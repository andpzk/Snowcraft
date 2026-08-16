param(
  [string]$ResourceManifest = "reverse\resources\manifest.csv",
  [string]$CastIndex = "reverse\cast-index.csv",
  [string]$KeyMap = "reverse\key-map.csv",
  [string]$AssetCatalog = "reverse\asset-catalog.csv",
  [string]$ScoreSprites = "reverse\score-frame-sprites.csv",
  [string]$OutPath = "reverse\cast-member-map.csv"
)

$ErrorActionPreference = "Stop"

function Read-U32BE {
  param([byte[]]$Bytes, [int]$Offset)
  return (([uint32]$Bytes[$Offset] -shl 24) -bor
    ([uint32]$Bytes[$Offset + 1] -shl 16) -bor
    ([uint32]$Bytes[$Offset + 2] -shl 8) -bor
    [uint32]$Bytes[$Offset + 3])
}

function Join-Unique {
  param([object[]]$Values)

  $items = @($Values | Where-Object { $_ -ne $null -and "$_" -ne "" } | Select-Object -Unique)
  return ($items -join " | ")
}

if (-not (Test-Path -LiteralPath $ResourceManifest)) {
  throw "Resource manifest not found: $ResourceManifest"
}
if (-not (Test-Path -LiteralPath $CastIndex)) {
  throw "Cast index not found: $CastIndex. Run tools\export-cast-index.ps1 first."
}

$resources = @(Import-Csv -LiteralPath $ResourceManifest)
$casts = @(Import-Csv -LiteralPath $CastIndex)

$castByIndex = @{}
foreach ($cast in $casts) {
  if ($cast.Index -ne "") {
    $castByIndex[[int]$cast.Index] = $cast
  }
}

$resourceByIndex = @{}
foreach ($resource in $resources) {
  if ($resource.Index -ne "") {
    $resourceByIndex[[int]$resource.Index] = $resource
  }
}

$bitdByCastIndex = @{}
if (Test-Path -LiteralPath $KeyMap) {
  foreach ($key in @(Import-Csv -LiteralPath $KeyMap)) {
    if ($key.CastIndex -eq "" -or $key.ChildType -ne "BITD") {
      continue
    }

    $castKey = [int]$key.CastIndex
    if (-not $bitdByCastIndex.ContainsKey($castKey)) {
      $bitdByCastIndex[$castKey] = [System.Collections.Generic.List[object]]::new()
    }
    $bitdByCastIndex[$castKey].Add($key)
  }
}

$assetsByCastIndex = @{}
$assetsByDimensions = @{}
if (Test-Path -LiteralPath $AssetCatalog) {
  foreach ($asset in @(Import-Csv -LiteralPath $AssetCatalog)) {
    if ($asset.CastIndex -eq "") {
      continue
    }

    $castKey = [int]$asset.CastIndex
    if (-not $assetsByCastIndex.ContainsKey($castKey)) {
      $assetsByCastIndex[$castKey] = [System.Collections.Generic.List[object]]::new()
    }
    $assetsByCastIndex[$castKey].Add($asset)

    if ($asset.Width -ne "" -and $asset.Height -ne "") {
      $dimensionKey = "$($asset.Width)x$($asset.Height)"
      if (-not $assetsByDimensions.ContainsKey($dimensionKey)) {
        $assetsByDimensions[$dimensionKey] = [System.Collections.Generic.List[object]]::new()
      }
      $assetsByDimensions[$dimensionKey].Add($asset)
    }
  }
}

$scoreUsageByMember = @{}
if (Test-Path -LiteralPath $ScoreSprites) {
  foreach ($sprite in @(Import-Csv -LiteralPath $ScoreSprites)) {
    if ($sprite.CastIndex -eq "") {
      continue
    }

    $memberId = [int]$sprite.CastIndex
    if (-not $scoreUsageByMember.ContainsKey($memberId)) {
      $scoreUsageByMember[$memberId] = @{
        Count = 0
        FirstFrame = [int]$sprite.Frame
        LastFrame = [int]$sprite.Frame
        Dimensions = @{}
      }
    }

    $usage = $scoreUsageByMember[$memberId]
    $usage.Count++
    $frame = [int]$sprite.Frame
    if ($frame -lt $usage.FirstFrame) {
      $usage.FirstFrame = $frame
    }
    if ($frame -gt $usage.LastFrame) {
      $usage.LastFrame = $frame
    }

    if ($sprite.Width -ne "" -and $sprite.Height -ne "") {
      $dimensionKey = "$($sprite.Width)x$($sprite.Height)"
      if (-not $usage.Dimensions.ContainsKey($dimensionKey)) {
        $usage.Dimensions[$dimensionKey] = 0
      }
      $usage.Dimensions[$dimensionKey]++
    }
  }
}

$rows = [System.Collections.Generic.List[object]]::new()
$casResources = @($resources | Where-Object Type -eq "CAS*" | Sort-Object {[int]$_.Index})

foreach ($cas in $casResources) {
  $bytes = [IO.File]::ReadAllBytes($cas.File)
  $entryCount = [Math]::Floor(([int]$cas.Size) / 4)

  for ($zeroSlot = 0; $zeroSlot -lt $entryCount; $zeroSlot++) {
    $entryOffset = 8 + ($zeroSlot * 4)
    if ($entryOffset + 4 -gt $bytes.Length) {
      break
    }

    $resourceIndex = [int](Read-U32BE -Bytes $bytes -Offset $entryOffset)
    $scoreCastIndex = $zeroSlot + 1
    $resource = if ($resourceByIndex.ContainsKey($resourceIndex)) { $resourceByIndex[$resourceIndex] } else { $null }
    $cast = if ($castByIndex.ContainsKey($resourceIndex)) { $castByIndex[$resourceIndex] } else { $null }
    $assets = if ($assetsByCastIndex.ContainsKey($resourceIndex)) { @($assetsByCastIndex[$resourceIndex]) } else { @() }
    $bitdLinks = if ($bitdByCastIndex.ContainsKey($resourceIndex)) { @($bitdByCastIndex[$resourceIndex]) } else { @() }
    $usage = if ($scoreUsageByMember.ContainsKey($scoreCastIndex)) { $scoreUsageByMember[$scoreCastIndex] } else { $null }
    $scoreDimensions = @()
    $dimensionCandidateAssets = @()
    if ($usage) {
      $scoreDimensions = @($usage.Dimensions.Keys | Sort-Object | ForEach-Object {
        "${_}:$($usage.Dimensions[$_])"
      })
      foreach ($dimensionKey in @($usage.Dimensions.Keys)) {
        if ($assetsByDimensions.ContainsKey($dimensionKey)) {
          $dimensionCandidateAssets += @($assetsByDimensions[$dimensionKey])
        }
      }
    }

    $resolutionHint = ""
    if ($cast -and $assets.Count -gt 0) {
      $resolutionHint = "cas-cast-asset"
    } elseif ($cast) {
      $resolutionHint = "cas-cast"
    } elseif ($dimensionCandidateAssets.Count -eq 1) {
      $resolutionHint = "dimension-single-candidate"
    } elseif ($dimensionCandidateAssets.Count -gt 1) {
      $resolutionHint = "dimension-ambiguous"
    } elseif ($resource) {
      $resolutionHint = "cas-non-cast-resource"
    } elseif ($resourceIndex -ne 0) {
      $resolutionHint = "cas-missing-resource"
    }

    $rows.Add([pscustomobject]@{
      ScoreCastIndex = $scoreCastIndex
      DirectorZeroSlot = $zeroSlot
      ResolutionHint = $resolutionHint
      CastResourceIndex = if ($resourceIndex -ne 0) { $resourceIndex } else { "" }
      ResourceType = if ($resource) { $resource.Type } else { "" }
      CastResourceFound = [bool]$cast
      Kind = if ($cast) { $cast.Kind } else { "" }
      Name = if ($cast) { $cast.Name } else { "" }
      Names = if ($cast) { $cast.Names } else { "" }
      AssetClass = Join-Unique @($assets.AssetClass)
      AssetStatus = Join-Unique @($assets.Status)
      Widths = Join-Unique @($assets.Width)
      Heights = Join-Unique @($assets.Height)
      BitdIndexes = Join-Unique (@($assets.BitdIndex) + @($bitdLinks.ChildIndex))
      PreviewPngs = Join-Unique @($assets.PreviewPng)
      TransparentPngs = Join-Unique @($assets.TransparentPng)
      KeyRelations = Join-Unique @($bitdLinks.Relation)
      ScoreUsageCount = if ($usage) { $usage.Count } else { 0 }
      FirstScoreFrame = if ($usage) { $usage.FirstFrame } else { "" }
      LastScoreFrame = if ($usage) { $usage.LastFrame } else { "" }
      ScoreDimensions = Join-Unique $scoreDimensions
      DimensionCandidateCastIndexes = Join-Unique @($dimensionCandidateAssets.CastIndex)
      DimensionCandidateNames = Join-Unique @($dimensionCandidateAssets.Name)
      DimensionCandidateClasses = Join-Unique @($dimensionCandidateAssets.AssetClass)
      DimensionCandidateStatuses = Join-Unique @($dimensionCandidateAssets.Status)
      DimensionCandidatePreviewPngs = Join-Unique @($dimensionCandidateAssets.PreviewPng)
      ResourceRelative = if ($resource) { $resource.Relative } else { "" }
      ResourceFile = if ($resource) { $resource.File } else { "" }
      CastRelative = if ($cast) { $cast.Relative } else { "" }
      CastFile = if ($cast) { $cast.File } else { "" }
      CasResourceIndex = $cas.Index
      CasFile = $cas.File
    })
  }
}

$rows | Export-Csv -LiteralPath $OutPath -NoTypeInformation

"Cast member rows: $($rows.Count)"
"Output: $OutPath"
""
"Score-used cast members"
$rows |
  Where-Object { $_.ScoreUsageCount -gt 0 } |
  Sort-Object {[int]$_.ScoreCastIndex} |
  Format-Table ScoreCastIndex,ResolutionHint,CastResourceIndex,ResourceType,Kind,Name,AssetClass,ScoreUsageCount,ScoreDimensions,DimensionCandidateNames -AutoSize
