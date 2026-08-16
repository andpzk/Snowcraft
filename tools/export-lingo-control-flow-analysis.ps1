param(
  [string]$BasicBlocksPath = "reverse\lingo-basic-blocks.csv",
  [string]$EdgesPath = "reverse\lingo-control-flow-edges.csv",
  [string]$AnalysisOut = "reverse\lingo-control-flow-analysis.csv",
  [string]$LoopsOut = "reverse\lingo-natural-loops.csv",
  [string]$ManifestOut = "reverse\lingo-control-flow-analysis-manifest.csv",
  [string[]]$FocusHandlers = @()
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
  $missing = @($RequiredColumns | Where-Object { $_ -notin $columns })
  if ($missing.Count -gt 0) {
    throw "$Description CSV is missing required columns ($($missing -join ', ')): $Path"
  }

  return $rows
}

function Convert-HexOffset {
  param([string]$Value)

  if (-not $Value) {
    return [int64]::MaxValue
  }

  if ($Value.StartsWith("0x", [System.StringComparison]::OrdinalIgnoreCase)) {
    return [Convert]::ToInt64($Value.Substring(2), 16)
  }

  return [int64]$Value
}

function Get-HandlerKey {
  param($Row)

  return "{0}:{1}:{2}" -f $Row.ScriptResourceIndex, $Row.HandlerOrdinal, $Row.Handler
}

function New-StringSet {
  param([string[]]$Values = @())

  $set = @{}
  foreach ($value in $Values) {
    $set[$value] = $true
  }
  return $set
}

function Copy-StringSet {
  param([hashtable]$Set)

  return New-StringSet @($Set.Keys)
}

function Test-SetEqual {
  param([hashtable]$Left, [hashtable]$Right)

  if ($Left.Count -ne $Right.Count) {
    return $false
  }
  foreach ($key in $Left.Keys) {
    if (-not $Right.ContainsKey($key)) {
      return $false
    }
  }
  return $true
}

function Intersect-Sets {
  param([hashtable[]]$Sets, [string[]]$Universe)

  if ($Sets.Count -eq 0) {
    return New-StringSet
  }

  $result = New-StringSet $Universe
  foreach ($set in $Sets) {
    foreach ($key in @($result.Keys)) {
      if (-not $set.ContainsKey($key)) {
        $result.Remove($key)
      }
    }
  }
  return $result
}

function Join-SortedIds {
  param([string[]]$Ids, [hashtable]$BlocksById)

  return (@($Ids | Sort-Object { Convert-HexOffset $BlocksById[$_].StartOffset }) -join " | ")
}

function Write-DeterministicCsv {
  param([object[]]$Rows, [string]$Path)

  $directory = Split-Path -Parent $Path
  if ($directory -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
  }

  $lines = @($Rows | ConvertTo-Csv -NoTypeInformation)
  [System.IO.File]::WriteAllLines(
    [System.IO.Path]::GetFullPath($Path),
    $lines,
    [System.Text.UTF8Encoding]::new($false)
  )
}

$requiredBlockColumns = @(
  "BlockId", "ScriptResourceIndex", "ScriptOrdinal", "LctxId", "AssemblyId",
  "Handler", "HandlerOrdinal", "StartOffset", "EndOffsetExclusive", "StateNames", "File"
)
$requiredEdgeColumns = @(
  "FromBlockId", "ToBlockId", "ScriptResourceIndex", "HandlerOrdinal", "Handler", "EdgeKind"
)

$blocks = @(Assert-CsvInput -Path $BasicBlocksPath -Description "basic block" -RequiredColumns $requiredBlockColumns)
$edges = @(Assert-CsvInput -Path $EdgesPath -Description "control-flow edge" -RequiredColumns $requiredEdgeColumns)

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

$analysisRows = [System.Collections.Generic.List[object]]::new()
$loopRows = [System.Collections.Generic.List[object]]::new()
$manifestRows = [System.Collections.Generic.List[object]]::new()

foreach ($group in ($blocks | Group-Object ScriptResourceIndex, HandlerOrdinal, Handler)) {
  $orderedBlocks = @($group.Group | Sort-Object { Convert-HexOffset $_.StartOffset })
  $first = $orderedBlocks[0]
  $handlerEdges = @($edges | Where-Object {
    $_.ScriptResourceIndex -eq $first.ScriptResourceIndex -and
    $_.HandlerOrdinal -eq $first.HandlerOrdinal -and
    $_.Handler -eq $first.Handler
  })

  $blocksById = @{}
  $successors = @{}
  $predecessors = @{}
  $edgesByBlock = @{}
  foreach ($block in $orderedBlocks) {
    $blocksById[$block.BlockId] = $block
    $successors[$block.BlockId] = [System.Collections.Generic.List[string]]::new()
    $predecessors[$block.BlockId] = [System.Collections.Generic.List[string]]::new()
    $edgesByBlock[$block.BlockId] = [System.Collections.Generic.List[object]]::new()
  }

  foreach ($edge in $handlerEdges) {
    if (-not $blocksById.ContainsKey($edge.FromBlockId)) {
      throw "Edge references unknown source block $($edge.FromBlockId)"
    }
    $edgesByBlock[$edge.FromBlockId].Add($edge)
    if ($edge.ToBlockId) {
      if (-not $blocksById.ContainsKey($edge.ToBlockId)) {
        throw "Edge references unknown target block $($edge.ToBlockId)"
      }
      if (-not $successors[$edge.FromBlockId].Contains($edge.ToBlockId)) {
        $successors[$edge.FromBlockId].Add($edge.ToBlockId)
      }
      if (-not $predecessors[$edge.ToBlockId].Contains($edge.FromBlockId)) {
        $predecessors[$edge.ToBlockId].Add($edge.FromBlockId)
      }
    }
  }

  $entryId = $first.BlockId
  $reachable = New-StringSet
  $queue = [System.Collections.Generic.Queue[string]]::new()
  $queue.Enqueue($entryId)
  while ($queue.Count -gt 0) {
    $node = $queue.Dequeue()
    if ($reachable.ContainsKey($node)) {
      continue
    }
    $reachable[$node] = $true
    foreach ($successor in $successors[$node]) {
      if (-not $reachable.ContainsKey($successor)) {
        $queue.Enqueue($successor)
      }
    }
  }

  $reachableIds = @($orderedBlocks | Where-Object { $reachable.ContainsKey($_.BlockId) } | ForEach-Object BlockId)
  $dom = @{}
  foreach ($node in $reachableIds) {
    $dom[$node] = if ($node -eq $entryId) { New-StringSet @($node) } else { New-StringSet $reachableIds }
  }

  $changed = $true
  while ($changed) {
    $changed = $false
    foreach ($node in $reachableIds) {
      if ($node -eq $entryId) {
        continue
      }
      $predSets = @($predecessors[$node] | Where-Object { $reachable.ContainsKey($_) } | ForEach-Object { $dom[$_] })
      $next = Intersect-Sets -Sets $predSets -Universe $reachableIds
      $next[$node] = $true
      if (-not (Test-SetEqual $dom[$node] $next)) {
        $dom[$node] = $next
        $changed = $true
      }
    }
  }

  $idom = @{}
  $idom[$entryId] = ""
  foreach ($node in $reachableIds) {
    if ($node -eq $entryId) {
      continue
    }
    $strict = @($dom[$node].Keys | Where-Object { $_ -ne $node })
    $candidate = $strict | Sort-Object { $dom[$_].Count } -Descending | Select-Object -First 1
    $idom[$node] = if ($candidate) { $candidate } else { "" }
  }

  $missingImmediateDominators = @($reachableIds | Where-Object {
    $_ -ne $entryId -and -not $idom[$_]
  })
  if ($missingImmediateDominators.Count -gt 0) {
    throw "Reachable non-entry blocks are missing immediate dominators in $(Get-HandlerKey $first): $($missingImmediateDominators -join ', ')"
  }

  $terminalIds = @($reachableIds | Where-Object { $successors[$_].Count -eq 0 })
  $postDom = @{}
  foreach ($node in $reachableIds) {
    $postDom[$node] = if ($node -in $terminalIds) { New-StringSet @($node) } else { New-StringSet $reachableIds }
  }

  $changed = $true
  while ($changed) {
    $changed = $false
    foreach ($node in $reachableIds) {
      if ($node -in $terminalIds) {
        continue
      }
      $succSets = @($successors[$node] | Where-Object { $reachable.ContainsKey($_) } | ForEach-Object { $postDom[$_] })
      $next = Intersect-Sets -Sets $succSets -Universe $reachableIds
      $next[$node] = $true
      if (-not (Test-SetEqual $postDom[$node] $next)) {
        $postDom[$node] = $next
        $changed = $true
      }
    }
  }

  $ipdom = @{}
  foreach ($node in $reachableIds) {
    $strict = @($postDom[$node].Keys | Where-Object { $_ -ne $node })
    $candidate = $strict | Sort-Object { $postDom[$_].Count } -Descending | Select-Object -First 1
    $ipdom[$node] = if ($candidate) { $candidate } else { "" }
  }

  $loops = [System.Collections.Generic.List[object]]::new()
  $backEdges = @($handlerEdges | Where-Object {
    $_.ToBlockId -and $reachable.ContainsKey($_.FromBlockId) -and
    $reachable.ContainsKey($_.ToBlockId) -and $dom[$_.FromBlockId].ContainsKey($_.ToBlockId)
  } | Sort-Object { Convert-HexOffset $blocksById[$_.ToBlockId].StartOffset }, { Convert-HexOffset $blocksById[$_.FromBlockId].StartOffset })

  $loopOrdinal = 0
  foreach ($backEdge in $backEdges) {
    $header = $backEdge.ToBlockId
    $latch = $backEdge.FromBlockId
    $members = New-StringSet @($header, $latch)
    $work = [System.Collections.Generic.Stack[string]]::new()
    if ($latch -ne $header) {
      $work.Push($latch)
    }
    while ($work.Count -gt 0) {
      $node = $work.Pop()
      foreach ($predecessor in $predecessors[$node]) {
        if ($reachable.ContainsKey($predecessor) -and -not $members.ContainsKey($predecessor)) {
          $members[$predecessor] = $true
          if ($predecessor -ne $header) {
            $work.Push($predecessor)
          }
        }
      }
    }

    $outsideHeaderDominance = @($members.Keys | Where-Object {
      -not $dom[$_].ContainsKey($header)
    })
    if ($outsideHeaderDominance.Count -gt 0) {
      throw "Back edge $latch -> $header does not form a natural loop; header does not dominate: $($outsideHeaderDominance -join ', ')"
    }

    $loopId = "{0}:{1}:L{2}" -f $first.ScriptResourceIndex, $first.HandlerOrdinal, $loopOrdinal
    $exitEdges = @($handlerEdges | Where-Object {
      $members.ContainsKey($_.FromBlockId) -and ($_.ToBlockId -eq "" -or -not $members.ContainsKey($_.ToBlockId))
    })
    $exitTargets = @($exitEdges | ForEach-Object {
      if ($_.ToBlockId) { $_.ToBlockId } else { "terminal" }
    } | Select-Object -Unique)
    $stateNames = @($members.Keys | ForEach-Object { $blocksById[$_].StateNames -split "," } | Where-Object { $_ } | Select-Object -Unique)

    $loop = [pscustomobject]@{
      LoopId = $loopId
      Header = $header
      Latch = $latch
      Members = $members
    }
    $loops.Add($loop)
    $loopRows.Add([pscustomobject][ordered]@{
      LoopId = $loopId
      ScriptResourceIndex = $first.ScriptResourceIndex
      ScriptOrdinal = $first.ScriptOrdinal
      LctxId = $first.LctxId
      AssemblyId = $first.AssemblyId
      Handler = $first.Handler
      HandlerOrdinal = $first.HandlerOrdinal
      HeaderBlockId = $header
      HeaderOffset = $blocksById[$header].StartOffset
      LatchBlockId = $latch
      LatchOffset = $blocksById[$latch].StartOffset
      MemberCount = $members.Count
      MemberBlockIds = Join-SortedIds @($members.Keys) $blocksById
      ExitEdgeCount = $exitEdges.Count
      ExitTargets = Join-SortedIds @($exitTargets | Where-Object { $_ -ne "terminal" }) $blocksById
      HasTerminalExit = if ("terminal" -in $exitTargets) { "yes" } else { "no" }
      StateNames = ($stateNames -join " | ")
      File = $first.File
    })
    $loopOrdinal++
  }

  foreach ($block in $orderedBlocks) {
    $node = $block.BlockId
    $isReachable = $reachable.ContainsKey($node)
    $nodeLoops = @($loops | Where-Object { $_.Members.ContainsKey($node) })
    $edgeKinds = @($edgesByBlock[$node] | ForEach-Object EdgeKind | Select-Object -Unique)
    $trueTarget = $edgesByBlock[$node] | Where-Object EdgeKind -eq "conditional-true" | Select-Object -ExpandProperty ToBlockId -First 1
    $falseTarget = $edgesByBlock[$node] | Where-Object EdgeKind -eq "conditional-false" | Select-Object -ExpandProperty ToBlockId -First 1
    $domIds = if ($isReachable) { @($dom[$node].Keys) } else { @() }
    $postDomIds = if ($isReachable) { @($postDom[$node].Keys) } else { @() }

    $analysisRows.Add([pscustomobject][ordered]@{
      ScriptResourceIndex = $block.ScriptResourceIndex
      ScriptOrdinal = $block.ScriptOrdinal
      LctxId = $block.LctxId
      AssemblyId = $block.AssemblyId
      Handler = $block.Handler
      HandlerOrdinal = $block.HandlerOrdinal
      BlockId = $node
      StartOffset = $block.StartOffset
      EndOffsetExclusive = $block.EndOffsetExclusive
      Reachable = if ($isReachable) { "yes" } else { "no" }
      PredecessorCount = $predecessors[$node].Count
      SuccessorCount = $successors[$node].Count
      EdgeKinds = ($edgeKinds -join " | ")
      ImmediateDominator = if ($isReachable) { $idom[$node] } else { "" }
      DominatorDepth = if ($isReachable) { $dom[$node].Count - 1 } else { "" }
      Dominators = if ($isReachable) { Join-SortedIds $domIds $blocksById } else { "" }
      ImmediatePostDominator = if ($isReachable) { $ipdom[$node] } else { "" }
      PostDominators = if ($isReachable) { Join-SortedIds $postDomIds $blocksById } else { "" }
      ConditionalTrueTarget = $trueTarget
      ConditionalFalseTarget = $falseTarget
      ConditionalMergeBlock = if ($trueTarget -and $falseTarget -and $isReachable) { $ipdom[$node] } else { "" }
      IsLoopHeader = if (@($loops | Where-Object Header -eq $node).Count -gt 0) { "yes" } else { "no" }
      IsLoopLatch = if (@($loops | Where-Object Latch -eq $node).Count -gt 0) { "yes" } else { "no" }
      NaturalLoopDepth = $nodeLoops.Count
      NaturalLoopIds = (@($nodeLoops | ForEach-Object LoopId) -join " | ")
      IsTerminal = if ($successors[$node].Count -eq 0) { "yes" } else { "no" }
      StateNames = $block.StateNames
      File = $block.File
    })
  }

  $manifestRows.Add([pscustomobject][ordered]@{
    ScriptResourceIndex = $first.ScriptResourceIndex
    HandlerOrdinal = $first.HandlerOrdinal
    Handler = $first.Handler
    Blocks = $orderedBlocks.Count
    ReachableBlocks = $reachableIds.Count
    Edges = $handlerEdges.Count
    ConditionalBlocks = @($handlerEdges | Where-Object EdgeKind -eq "conditional-true").Count
    NaturalLoops = $loops.Count
    BackEdges = $backEdges.Count
    MaxLoopDepth = if ($loops.Count -gt 0) {
      @($orderedBlocks | ForEach-Object {
        $id = $_.BlockId
        @($loops | Where-Object { $_.Members.ContainsKey($id) }).Count
      } | Measure-Object -Maximum).Maximum
    } else { 0 }
    TerminalBlocks = $terminalIds.Count
    EntryBlockId = $entryId
    File = $first.File
  })
}

Write-DeterministicCsv @($analysisRows) $AnalysisOut
Write-DeterministicCsv @($loopRows) $LoopsOut
Write-DeterministicCsv @($manifestRows) $ManifestOut

"Lingo control-flow analysis: $($analysisRows.Count) blocks -> $AnalysisOut"
"Lingo natural loops: $($loopRows.Count) -> $LoopsOut"
"Lingo control-flow manifest: $($manifestRows.Count) handlers -> $ManifestOut"
