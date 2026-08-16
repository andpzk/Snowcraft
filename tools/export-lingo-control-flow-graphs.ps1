param(
  [string]$BasicBlocksPath = "reverse\lingo-basic-blocks.csv",
  [string]$EdgesPath = "reverse\lingo-control-flow-edges.csv",
  [string]$OutputDirectory = "reverse\control-flow-graphs",
  [string[]]$FocusHandlers = @()
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $BasicBlocksPath)) {
  throw "Missing basic block CSV: $BasicBlocksPath"
}

if (-not (Test-Path -LiteralPath $EdgesPath)) {
  throw "Missing control-flow edge CSV: $EdgesPath"
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

function Escape-DotLabel {
  param([string]$Value)

  if ($null -eq $Value) {
    return ""
  }

  return ($Value `
    -replace "\\", "\\" `
    -replace '"', '\"' `
    -replace "`r`n", "\n" `
    -replace "`n", "\n")
}

function Get-SafeFileName {
  param(
    [string]$ScriptResourceIndex,
    [string]$HandlerOrdinal,
    [string]$Handler
  )

  $name = "{0}_{1}_{2}.dot" -f $ScriptResourceIndex.PadLeft(4, "0"), $HandlerOrdinal.PadLeft(2, "0"), $Handler
  foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
    $name = $name.Replace($char, "_")
  }

  return $name
}

function Get-HandlerKey {
  param($Row)

  return "{0}:{1}:{2}" -f $Row.ScriptResourceIndex, $Row.HandlerOrdinal, $Row.Handler
}

$blocks = Import-Csv -LiteralPath $BasicBlocksPath
$edges = Import-Csv -LiteralPath $EdgesPath

if ($FocusHandlers.Count -gt 0) {
  $wanted = @{}
  foreach ($handler in $FocusHandlers) {
    $wanted[$handler] = $true
  }

  $blocks = @($blocks | Where-Object { $wanted.ContainsKey($_.Handler) -or $wanted.ContainsKey((Get-HandlerKey $_)) })
  $edges = @($edges | Where-Object { $wanted.ContainsKey($_.Handler) -or $wanted.ContainsKey((Get-HandlerKey $_)) })
}

$edgesByHandler = $edges | Group-Object -Property ScriptResourceIndex, HandlerOrdinal, Handler -AsHashTable -AsString
$graphRows = @()

foreach ($group in ($blocks | Group-Object -Property ScriptResourceIndex, HandlerOrdinal, Handler)) {
  $first = $group.Group | Select-Object -First 1
  $handlerEdges = @()
  $edgeKey = "{0}, {1}, {2}" -f $first.ScriptResourceIndex, $first.HandlerOrdinal, $first.Handler
  if ($edgesByHandler.ContainsKey($edgeKey)) {
    $handlerEdges = @($edgesByHandler[$edgeKey])
  }

  $fileName = Get-SafeFileName `
    -ScriptResourceIndex $first.ScriptResourceIndex `
    -HandlerOrdinal $first.HandlerOrdinal `
    -Handler $first.Handler
  $outputPath = Join-Path $OutputDirectory $fileName

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("digraph ""script_$($first.ScriptResourceIndex)_$($first.HandlerOrdinal)_$($first.Handler)"" {")
  $lines.Add("  graph [rankdir=TB, bgcolor=""white"", pad=0.2];")
  $lines.Add("  node [shape=box, style=""rounded,filled"", fillcolor=""#f8fafc"", color=""#334155"", fontname=""Consolas"", fontsize=10];")
  $lines.Add("  edge [color=""#475569"", fontname=""Consolas"", fontsize=9];")
  $lines.Add("  label=""Lingo CFG: script $($first.ScriptResourceIndex) / $($first.Handler)"";")
  $lines.Add("  labelloc=""t"";")
  $lines.Add("")

  foreach ($block in ($group.Group | Sort-Object { [Convert]::ToInt32($_.StartOffset.Substring(2), 16) })) {
    $labelParts = @(
      $block.BlockId,
      "$($block.StartOffset)-$($block.EndOffsetExclusive)",
      "$($block.InstructionCount) instructions"
    )

    if ($block.StateNames) {
      $labelParts += "states: $($block.StateNames)"
    }

    if ($block.PseudoStatements) {
      $statements = $block.PseudoStatements -replace " \| ", "`n"
      $labelParts += $statements
    }

    $label = Escape-DotLabel ($labelParts -join "`n")
    $lines.Add("  ""$($block.BlockId)"" [label=""$label""];")
  }

  $lines.Add("")

  foreach ($edge in ($handlerEdges | Sort-Object FromOffset, EdgeKind, TargetOffset)) {
    if ($edge.EdgeKind -eq "return") {
      $terminalId = "$($edge.FromBlockId):return"
      $lines.Add("  ""$terminalId"" [label=""return"", shape=oval, fillcolor=""#fee2e2"", color=""#991b1b""];")
      $lines.Add("  ""$($edge.FromBlockId)"" -> ""$terminalId"" [label=""return""];")
      continue
    }

    if (-not $edge.ToBlockId) {
      $unresolvedId = "$($edge.FromBlockId):unresolved:$($edge.TargetOffset)"
      $lines.Add("  ""$unresolvedId"" [label=""unresolved $($edge.TargetOffset)"", shape=oval, fillcolor=""#fef3c7"", color=""#92400e""];")
      $lines.Add("  ""$($edge.FromBlockId)"" -> ""$unresolvedId"" [label=""$($edge.EdgeKind)"", color=""#92400e""];")
      continue
    }

    $edgeColor = "#475569"
    if ($edge.EdgeKind -eq "conditional-true") {
      $edgeColor = "#15803d"
    } elseif ($edge.EdgeKind -eq "conditional-false") {
      $edgeColor = "#b91c1c"
    } elseif ($edge.EdgeKind -eq "loop-back") {
      $edgeColor = "#7c3aed"
    }

    $lines.Add("  ""$($edge.FromBlockId)"" -> ""$($edge.ToBlockId)"" [label=""$($edge.EdgeKind)"", color=""$edgeColor""];")
  }

  $lines.Add("}")
  $lines | Set-Content -LiteralPath $outputPath -Encoding ascii

  $graphRows += [pscustomobject]@{
    ScriptResourceIndex = $first.ScriptResourceIndex
    HandlerOrdinal = $first.HandlerOrdinal
    Handler = $first.Handler
    Blocks = $group.Count
    Edges = $handlerEdges.Count
    Output = $outputPath
  }
}

$manifestPath = Join-Path $OutputDirectory "manifest.csv"
$graphRows |
  Sort-Object ScriptResourceIndex, HandlerOrdinal, Handler |
  Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding UTF8

"Lingo control-flow graphs: $($graphRows.Count) -> $OutputDirectory"
"Graph manifest: $manifestPath"
