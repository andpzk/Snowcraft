param(
  [string]$BasicBlocksPath = "reverse\lingo-basic-blocks.csv",
  [string]$EdgesPath = "reverse\lingo-control-flow-edges.csv",
  [string]$OutputDirectory = "reverse\lingo-structured-pseudocode",
  [string[]]$FocusHandlers = @()
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $BasicBlocksPath)) {
  throw "Missing basic block CSV: $BasicBlocksPath"
}

if (-not (Test-Path -LiteralPath $EdgesPath)) {
  throw "Missing control-flow edge CSV: $EdgesPath"
}

function Get-HandlerKey {
  param($Row)

  return "{0}:{1}:{2}" -f $Row.ScriptResourceIndex, $Row.HandlerOrdinal, $Row.Handler
}

function Get-OffsetValue {
  param([string]$Offset)

  if (-not $Offset -or -not $Offset.StartsWith("0x")) {
    return [int]::MaxValue
  }

  return [Convert]::ToInt32($Offset.Substring(2), 16)
}

function Get-BlockLabel {
  param([string]$BlockId)

  $parts = $BlockId.Split(":")
  return "block_$($parts[$parts.Count - 1])"
}

function Get-SafeFileName {
  param(
    [string]$ScriptResourceIndex,
    [string]$HandlerOrdinal,
    [string]$Handler
  )

  $name = "{0}_{1}_{2}.txt" -f $ScriptResourceIndex.PadLeft(4, "0"), $HandlerOrdinal.PadLeft(2, "0"), $Handler
  foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
    $name = $name.Replace($char, "_")
  }

  return $name
}

function Get-Statements {
  param([string]$PseudoStatements)

  if (-not $PseudoStatements) {
    return @()
  }

  return @($PseudoStatements -split " \| ")
}

function Get-BranchCondition {
  param([string]$Statement)

  if ($Statement -match '^if not \((.*)\) jump -?\d+$') {
    return $Matches[1]
  }

  return ""
}

$blocks = @(Import-Csv -LiteralPath $BasicBlocksPath)
$edges = @(Import-Csv -LiteralPath $EdgesPath)

if ($FocusHandlers.Count -gt 0) {
  $wanted = @{}
  foreach ($handler in $FocusHandlers) {
    $wanted[$handler] = $true
  }

  $blocks = @($blocks | Where-Object {
    $wanted.ContainsKey($_.Handler) -or $wanted.ContainsKey((Get-HandlerKey $_))
  })
  $edges = @($edges | Where-Object {
    $wanted.ContainsKey($_.Handler) -or $wanted.ContainsKey((Get-HandlerKey $_))
  })
}

if ($blocks.Count -eq 0) {
  throw "No basic blocks matched the requested handlers."
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$edgesByBlock = @{}
foreach ($edge in $edges) {
  if (-not $edgesByBlock.ContainsKey($edge.FromBlockId)) {
    $edgesByBlock[$edge.FromBlockId] = [System.Collections.Generic.List[object]]::new()
  }
  $edgesByBlock[$edge.FromBlockId].Add($edge)
}

$manifestRows = [System.Collections.Generic.List[object]]::new()

foreach ($group in ($blocks | Group-Object -Property ScriptResourceIndex, HandlerOrdinal, Handler)) {
  $orderedBlocks = @($group.Group | Sort-Object { Get-OffsetValue $_.StartOffset })
  $first = $orderedBlocks[0]
  $handlerEdges = @($edges | Where-Object {
    $_.ScriptResourceIndex -eq $first.ScriptResourceIndex -and
    $_.HandlerOrdinal -eq $first.HandlerOrdinal -and
    $_.Handler -eq $first.Handler
  })

  $fileName = Get-SafeFileName `
    -ScriptResourceIndex $first.ScriptResourceIndex `
    -HandlerOrdinal $first.HandlerOrdinal `
    -Handler $first.Handler
  $outputPath = Join-Path $OutputDirectory $fileName
  $lines = [System.Collections.Generic.List[string]]::new()
  $unparsedConditions = 0

  $lines.Add("-- Recovered control-flow IR; generated from Director Lingo bytecode.")
  $lines.Add("-- Script $($first.ScriptResourceIndex), handler $($first.Handler), ordinal $($first.HandlerOrdinal)")
  $lines.Add("-- Entry: $(Get-BlockLabel $first.BlockId)")
  $lines.Add("")
  $lines.Add("on $($first.Handler)")
  $lines.Add("  goto $(Get-BlockLabel $first.BlockId)")
  $lines.Add("")

  foreach ($block in $orderedBlocks) {
    $blockEdges = @()
    if ($edgesByBlock.ContainsKey($block.BlockId)) {
      $blockEdges = @($edgesByBlock[$block.BlockId])
    }

    $statements = @(Get-Statements $block.PseudoStatements)
    $trueEdge = $blockEdges | Where-Object { $_.EdgeKind -eq "conditional-true" } | Select-Object -First 1
    $falseEdge = $blockEdges | Where-Object { $_.EdgeKind -eq "conditional-false" } | Select-Object -First 1
    $jumpEdge = $blockEdges | Where-Object { $_.EdgeKind -eq "jump" -or $_.EdgeKind -eq "loop-back" } | Select-Object -First 1
    $fallthroughEdge = $blockEdges | Where-Object { $_.EdgeKind -eq "fallthrough" } | Select-Object -First 1
    $returnEdge = $blockEdges | Where-Object { $_.EdgeKind -eq "return" } | Select-Object -First 1

    $lines.Add("$(Get-BlockLabel $block.BlockId):")
    $lines.Add("  -- bytecode $($block.StartOffset)..$($block.EndOffsetExclusive); $($block.InstructionCount) instructions")
    if ($block.StateNames) {
      $lines.Add("  -- cast states: $($block.StateNames)")
    }

    $condition = ""
    if ($trueEdge -and $falseEdge -and $statements.Count -gt 0) {
      $condition = Get-BranchCondition $statements[-1]
      if ($condition) {
        if ($statements.Count -eq 1) {
          $statements = @()
        } else {
          $statements = @($statements[0..($statements.Count - 2)])
        }
      } else {
        $unparsedConditions++
      }
    } elseif ($jumpEdge -and $statements.Count -gt 0 -and $statements[-1] -match '^jump -?\d+$') {
      if ($statements.Count -eq 1) {
        $statements = @()
      } else {
        $statements = @($statements[0..($statements.Count - 2)])
      }
    } elseif ($returnEdge -and $statements.Count -gt 0 -and $statements[-1] -eq "return") {
      if ($statements.Count -eq 1) {
        $statements = @()
      } else {
        $statements = @($statements[0..($statements.Count - 2)])
      }
    }

    foreach ($statement in $statements) {
      $lines.Add("  $statement")
    }

    if ($trueEdge -and $falseEdge) {
      if (-not $condition) {
        $condition = "UNPARSED_CONDITION_AT_$($block.StartOffset)"
      }
      $lines.Add("  if $condition then")
      $lines.Add("    goto $(Get-BlockLabel $trueEdge.ToBlockId)")
      $lines.Add("  else")
      $lines.Add("    goto $(Get-BlockLabel $falseEdge.ToBlockId)")
      $lines.Add("  end if")
    } elseif ($jumpEdge) {
      $suffix = ""
      if ($jumpEdge.EdgeKind -eq "loop-back") {
        $suffix = " -- loop back"
      }
      $lines.Add("  goto $(Get-BlockLabel $jumpEdge.ToBlockId)$suffix")
    } elseif ($fallthroughEdge) {
      $lines.Add("  goto $(Get-BlockLabel $fallthroughEdge.ToBlockId)")
    } elseif ($returnEdge) {
      $lines.Add("  return")
    } elseif ($blockEdges.Count -eq 0) {
      $lines.Add("  -- no recovered outgoing edge")
    } else {
      $lines.Add("  -- unresolved outgoing edge")
    }

    $lines.Add("")
  }

  $lines.Add("end")
  $lines | Set-Content -LiteralPath $outputPath -Encoding ascii

  $manifestRows.Add([pscustomobject]@{
    ScriptResourceIndex = $first.ScriptResourceIndex
    HandlerOrdinal = $first.HandlerOrdinal
    Handler = $first.Handler
    Blocks = $orderedBlocks.Count
    Edges = $handlerEdges.Count
    ConditionalBlocks = @($handlerEdges | Where-Object { $_.EdgeKind -eq "conditional-true" }).Count
    LoopBackEdges = @($handlerEdges | Where-Object { $_.EdgeKind -eq "loop-back" }).Count
    UnparsedConditions = $unparsedConditions
    Output = $outputPath
  })
}

$manifestPath = Join-Path $OutputDirectory "manifest.csv"
$manifestRows |
  Sort-Object { [int]$_.ScriptResourceIndex }, { [int]$_.HandlerOrdinal }, Handler |
  Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding UTF8

"Structured Lingo handlers: $($manifestRows.Count) -> $OutputDirectory"
"Structured Lingo manifest: $manifestPath"
