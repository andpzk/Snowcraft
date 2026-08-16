param(
  [string]$BasicBlocksPath = "reverse\lingo-basic-blocks.csv",
  [string]$EdgesPath = "reverse\lingo-control-flow-edges.csv",
  [string]$OutputPath = "reverse\lingo-state-transitions.csv"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-CsvInput {
  param(
    [string]$Path,
    [string]$Description,
    [string[]]$RequiredColumns
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing $Description CSV: $Path"
  }

  $rows = @(Import-Csv -LiteralPath $Path)
  if ($rows.Count -eq 0) {
    throw "$Description CSV contains no data rows: $Path"
  }

  $columns = @($rows[0].PSObject.Properties.Name)
  $missingColumns = @($RequiredColumns | Where-Object { $_ -notin $columns })
  if ($missingColumns.Count -gt 0) {
    throw "$Description CSV is missing required columns ($($missingColumns -join ', ')): $Path"
  }

  return $rows
}

function Convert-HexOffset {
  param([string]$Value)

  if (-not $Value) {
    return [int64]::MaxValue
  }

  $text = $Value.Trim()
  if ($text.StartsWith("0x", [System.StringComparison]::OrdinalIgnoreCase)) {
    return [Convert]::ToInt64($text.Substring(2), 16)
  }

  return [int64]$text
}

function Join-UniqueStable {
  param([object[]]$Values)

  $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  $items = [System.Collections.Generic.List[string]]::new()
  foreach ($value in $Values) {
    if ($null -eq $value) {
      continue
    }

    $text = ([string]$value).Trim()
    if ($text -and $seen.Add($text)) {
      $items.Add($text)
    }
  }

  return ($items -join " | ")
}

function Get-Statements {
  param([string]$PseudoStatements)

  if (-not $PseudoStatements) {
    return @()
  }

  return @($PseudoStatements -split ' \| ' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-BranchCondition {
  param([string[]]$Statements)

  foreach ($statement in $Statements) {
    $match = [regex]::Match($statement, '^if not \((.*)\) jump -?\d+$')
    if ($match.Success) {
      return $match.Groups[1].Value
    }
  }

  return ""
}

function Get-StateConditions {
  param([string]$Condition)

  if (-not $Condition) {
    return ""
  }

  $states = [System.Collections.Generic.List[string]]::new()
  $quotedMatches = [regex]::Matches($Condition, '"([^"]+)"')
  foreach ($match in $quotedMatches) {
    $states.Add($match.Groups[1].Value)
  }

  return Join-UniqueStable $states
}

function Get-StateAssignments {
  param([string[]]$Statements)

  $assignments = [System.Collections.Generic.List[string]]::new()
  foreach ($statement in $Statements) {
    $match = [regex]::Match(
      $statement,
      '^set the memberNum of sprite (.+?) = (.+)$',
      [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    if ($match.Success) {
      $assignments.Add("sprite $($match.Groups[1].Value) => $($match.Groups[2].Value)")
    }
  }

  return Join-UniqueStable $assignments
}

function Get-NextStates {
  param([string[]]$Statements)

  $states = [System.Collections.Generic.List[string]]::new()
  foreach ($statement in $Statements) {
    $match = [regex]::Match($statement, '^set the memberNum of sprite .+? = (.+)$')
    if (-not $match.Success) {
      continue
    }

    $expression = $match.Groups[1].Value
    $castMatches = [regex]::Matches($expression, 'the number of cast ("[^"]+"|\(.+\))')
    if ($castMatches.Count -gt 0) {
      foreach ($castMatch in $castMatches) {
        $states.Add($castMatch.Groups[1].Value)
      }
    } else {
      $states.Add($expression)
    }
  }

  return Join-UniqueStable $states
}

function Get-Effects {
  param(
    [string[]]$Statements,
    [scriptblock]$Predicate
  )

  return Join-UniqueStable @($Statements | Where-Object $Predicate)
}

function Get-EdgeTargets {
  param(
    [object[]]$Edges,
    [string]$EdgeKind
  )

  $targets = @(
    $Edges |
      Where-Object { $_.EdgeKind -eq $EdgeKind } |
      Sort-Object @{ Expression = { Convert-HexOffset $_.TargetOffset } }, ToBlockId |
      ForEach-Object {
        if ($_.ToBlockId) {
          return $_.ToBlockId
        }
        if ($_.TargetOffset) {
          return "unresolved:$($_.TargetOffset)"
        }
        return "terminal"
      }
  )

  return Join-UniqueStable $targets
}

$requiredBlockColumns = @(
  "BlockId", "ScriptResourceIndex", "ScriptOrdinal", "LctxId", "AssemblyId",
  "Handler", "HandlerOrdinal", "StartOffset", "EndOffsetExclusive", "StateNames",
  "PseudoStatements", "File"
)
$requiredEdgeColumns = @(
  "FromBlockId", "ToBlockId", "ScriptResourceIndex", "HandlerOrdinal", "Handler",
  "EdgeKind", "TargetOffset", "Resolved"
)

$blocks = @(Assert-CsvInput -Path $BasicBlocksPath -Description "basic block" -RequiredColumns $requiredBlockColumns)
$edges = @(Assert-CsvInput -Path $EdgesPath -Description "control-flow edge" -RequiredColumns $requiredEdgeColumns)

$duplicateBlockIds = @($blocks | Group-Object BlockId | Where-Object Count -gt 1)
if ($duplicateBlockIds.Count -gt 0) {
  throw "Basic block CSV contains duplicate BlockId values: $((@($duplicateBlockIds | ForEach-Object Name) -join ', '))"
}

$knownBlockIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($block in $blocks) {
  [void]$knownBlockIds.Add($block.BlockId)
}

$orphanEdges = @($edges | Where-Object { -not $knownBlockIds.Contains($_.FromBlockId) })
if ($orphanEdges.Count -gt 0) {
  throw "Control-flow edge CSV references unknown FromBlockId values: $((@($orphanEdges | Select-Object -ExpandProperty FromBlockId -Unique) -join ', '))"
}

$edgesByBlock = @{}
foreach ($edge in $edges) {
  if (-not $edgesByBlock.ContainsKey($edge.FromBlockId)) {
    $edgesByBlock[$edge.FromBlockId] = [System.Collections.Generic.List[object]]::new()
  }
  $edgesByBlock[$edge.FromBlockId].Add($edge)
}

$rows = [System.Collections.Generic.List[object]]::new()
$sortedBlocks = @(
  $blocks | Sort-Object `
    @{ Expression = { [int]$_.ScriptResourceIndex } }, `
    @{ Expression = { [int]$_.HandlerOrdinal } }, `
    @{ Expression = { Convert-HexOffset $_.StartOffset } }, `
    BlockId
)

foreach ($block in $sortedBlocks) {
  $statements = @(Get-Statements $block.PseudoStatements)
  $condition = Get-BranchCondition $statements
  $stateAssignments = Get-StateAssignments $statements
  $nextStates = Get-NextStates $statements
  $soundEffects = Get-Effects $statements { $_ -match '^(puppetSound|sound|soundBusy)\(' -or $_ -match '^set the .+ of sound ' }
  $globalEffects = Get-Effects $statements { $_ -match '^set g[A-Za-z0-9_]*\s*=' -or $_ -eq 'clearGlobals()' }
  $locationEffects = Get-Effects $statements { $_ -match '^set the loc(H|V)? of sprite ' }

  $blockEdges = @()
  if ($edgesByBlock.ContainsKey($block.BlockId)) {
    $blockEdges = @($edgesByBlock[$block.BlockId])
  }

  $edgeTargets = @(
    $blockEdges |
      Sort-Object EdgeKind, @{ Expression = { Convert-HexOffset $_.TargetOffset } }, ToBlockId |
      ForEach-Object {
        $target = if ($_.ToBlockId) { $_.ToBlockId } elseif ($_.TargetOffset) { "unresolved:$($_.TargetOffset)" } else { "terminal" }
        "$($_.EdgeKind) => $target"
      }
  )

  $isRelevant = $condition -or $stateAssignments -or $soundEffects -or $globalEffects -or $locationEffects
  if (-not $isRelevant) {
    continue
  }

  $rows.Add([pscustomobject][ordered]@{
    ScriptResourceIndex = $block.ScriptResourceIndex
    ScriptOrdinal = $block.ScriptOrdinal
    LctxId = $block.LctxId
    AssemblyId = $block.AssemblyId
    Handler = $block.Handler
    HandlerOrdinal = $block.HandlerOrdinal
    BlockId = $block.BlockId
    StartOffset = $block.StartOffset
    EndOffsetExclusive = $block.EndOffsetExclusive
    Condition = $condition
    StateCondition = Get-StateConditions $condition
    AssignedNextStates = $nextStates
    StateAssignments = $stateAssignments
    SoundEffects = $soundEffects
    GlobalEffects = $globalEffects
    LocationEffects = $locationEffects
    TrueTargets = Get-EdgeTargets $blockEdges "conditional-true"
    FalseTargets = Get-EdgeTargets $blockEdges "conditional-false"
    FallthroughTargets = Get-EdgeTargets $blockEdges "fallthrough"
    JumpTargets = Get-EdgeTargets $blockEdges "jump"
    LoopBackTargets = Get-EdgeTargets $blockEdges "loop-back"
    ReturnTargets = Get-EdgeTargets $blockEdges "return"
    EdgeTargets = Join-UniqueStable $edgeTargets
    StateNames = $block.StateNames
    PseudoStatements = $block.PseudoStatements
    File = $block.File
  })
}

if ($rows.Count -eq 0) {
  throw "No state-transition rows were extracted from $BasicBlocksPath"
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
  New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$csvLines = @($rows | ConvertTo-Csv -NoTypeInformation)
[System.IO.File]::WriteAllLines(
  [System.IO.Path]::GetFullPath($OutputPath),
  $csvLines,
  [System.Text.UTF8Encoding]::new($false)
)

"Lingo state transitions: $($rows.Count) -> $OutputPath"
