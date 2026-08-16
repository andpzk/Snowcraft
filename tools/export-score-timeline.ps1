param(
  [string]$ScoreResource = "reverse\resources\VWSC\0007_VWSC_rel-1539A_size-141029.bin",
  [string]$LabelsResource = "reverse\resources\VWLB\0514_VWLB_rel-37A88_size-73.bin",
  [string]$ResourceManifest = "reverse\resources\manifest.csv",
  [string]$CastIndex = "reverse\cast-index.csv",
  [string]$AssetCatalog = "reverse\asset-catalog.csv",
  [string]$SoundCatalog = "reverse\sound-cast-metadata.csv",
  [string]$SummaryOut = "reverse\score-summary.csv",
  [string]$LabelsOut = "reverse\score-labels.csv",
  [string]$FramesOut = "reverse\score-frame-summary.csv",
  [string]$SpritesOut = "reverse\score-frame-sprites.csv",
  [string]$ScriptDetailsOut = "reverse\score-script-details.csv",
  [string]$LingoScripts = "reverse\lingo-scripts.csv",
  [string]$SpriteBehaviorsOut = "reverse\score-sprite-behaviors.csv"
)

$ErrorActionPreference = "Stop"

function Read-U16BE {
  param([byte[]]$Bytes, [int]$Offset)
  return (([int]$Bytes[$Offset] -shl 8) -bor [int]$Bytes[$Offset + 1])
}

function Read-S16BE {
  param([byte[]]$Bytes, [int]$Offset)
  $value = Read-U16BE -Bytes $Bytes -Offset $Offset
  if ($value -ge 0x8000) {
    return $value - 0x10000
  }
  return $value
}

function Read-U32BE {
  param([byte[]]$Bytes, [int]$Offset)
  return (([uint32]$Bytes[$Offset] -shl 24) -bor
    ([uint32]$Bytes[$Offset + 1] -shl 16) -bor
    ([uint32]$Bytes[$Offset + 2] -shl 8) -bor
    [uint32]$Bytes[$Offset + 3])
}

function Read-U32LE {
  param([byte[]]$Bytes, [int]$Offset)
  return ([uint32]$Bytes[$Offset] -bor
    ([uint32]$Bytes[$Offset + 1] -shl 8) -bor
    ([uint32]$Bytes[$Offset + 2] -shl 16) -bor
    ([uint32]$Bytes[$Offset + 3] -shl 24))
}

function Read-Tag {
  param([byte[]]$Bytes)
  return [Text.Encoding]::ASCII.GetString($Bytes, 0, 4)
}

function Add-Name {
  param([hashtable]$Map, [string]$Index, [string]$Name)
  if (-not $Index -or -not $Name) {
    return
  }
  if (-not $Map.ContainsKey($Index)) {
    $Map[$Index] = $Name
    return
  }
  $names = @($Map[$Index] -split " \| ")
  if ($names -notcontains $Name) {
    $Map[$Index] = "$($Map[$Index]) | $Name"
  }
}

function Get-Name {
  param([hashtable]$Map, [object]$Index)
  $key = [string]$Index
  if ($Map.ContainsKey($key)) {
    return $Map[$key]
  }
  return ""
}

function Parse-Labels {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Labels resource not found: $Path. Run tools\export-director-resources.ps1 first."
  }

  $bytes = [IO.File]::ReadAllBytes($Path)
  if ((Read-Tag -Bytes $bytes) -ne "BLWV") {
    throw "Unexpected labels resource tag in $Path"
  }

  $body = 8
  $count = (Read-U16BE -Bytes $bytes -Offset $body) + 1
  $stringBase = $count * 4 + 2
  $frame = Read-U16BE -Bytes $bytes -Offset ($body + 2)
  $stringPos = (Read-U16BE -Bytes $bytes -Offset ($body + 4)) + $stringBase
  $entryOffset = $body + 6
  $labels = [System.Collections.Generic.List[object]]::new()

  for ($i = 1; $i -lt $count; $i++) {
    $nextFrame = Read-U16BE -Bytes $bytes -Offset $entryOffset
    $nextStringPos = (Read-U16BE -Bytes $bytes -Offset ($entryOffset + 2)) + $stringBase
    $entryOffset += 4

    $textBytes = $bytes[($body + $stringPos)..($body + $nextStringPos - 1)]
    $text = [Text.Encoding]::ASCII.GetString($textBytes)
    $parts = @($text -split "`r", 2)
    $label = $parts[0]
    $comment = if ($parts.Count -gt 1) { $parts[1] -replace "`r", "`n" } else { "" }

    $labels.Add([pscustomobject]@{
      Frame = $frame
      Label = $label
      Comment = $comment
    })

    $frame = $nextFrame
    $stringPos = $nextStringPos
  }

  return $labels
}

function Get-DetailBounds {
  param([int]$DetailIndex)

  if ($DetailIndex -lt 0 -or $DetailIndex -ge ([int]$detailCount - 1)) {
    return $null
  }

  $start = $frameDataOffset + [int](Read-U32BE -Bytes $bytes -Offset ($indexStart + $DetailIndex * 4))
  $end = $frameDataOffset + [int](Read-U32BE -Bytes $bytes -Offset ($indexStart + ($DetailIndex + 1) * 4))
  return [pscustomobject]@{
    Start = $start
    End = $end
    Size = $end - $start
  }
}

function Get-HexPreview {
  param([int]$Start, [int]$Size, [int]$MaxBytes = 24)

  if ($Size -le 0) {
    return ""
  }
  $take = [Math]::Min($Size, $MaxBytes)
  return ($bytes[$Start..($Start + $take - 1)] | ForEach-Object { "{0:X2}" -f $_ }) -join " "
}

function Get-InitializerInfo {
  param([uint32]$DetailIndex)

  $result = [ordered]@{
    Size = ""
    HexPreview = ""
    Text = ""
    Gd = ""
    Level = ""
  }
  if ($DetailIndex -eq 0) {
    return [pscustomobject]$result
  }

  $bounds = Get-DetailBounds -DetailIndex $DetailIndex
  if (-not $bounds) {
    return [pscustomobject]$result
  }

  $result.Size = $bounds.Size
  $result.HexPreview = Get-HexPreview -Start $bounds.Start -Size $bounds.Size
  if ($bounds.Size -le 0) {
    return [pscustomobject]$result
  }

  $initializerBytes = @($bytes[$bounds.Start..($bounds.End - 1)])
  $nonAsciiBytes = @($initializerBytes | Where-Object {
    $_ -ne 0 -and ($_ -lt 0x20 -or $_ -gt 0x7E)
  })
  if ($nonAsciiBytes.Count -gt 0) {
    return [pscustomobject]$result
  }

  $result.Text = [Text.Encoding]::ASCII.GetString(
    $bytes,
    $bounds.Start,
    $bounds.Size
  ) -replace "`0+$", ""
  if ($result.Text -match '^\[#gd:\s*(-?\d+),\s*#level:\s*(-?\d+)\]$') {
    $result.Gd = [int]$Matches[1]
    $result.Level = [int]$Matches[2]
  }

  return [pscustomobject]$result
}

if (-not (Test-Path -LiteralPath $ScoreResource)) {
  throw "Score resource not found: $ScoreResource. Run tools\export-director-resources.ps1 first."
}

$assetNames = @{}
$assetClasses = @{}
$assetPreviews = @{}
$assetTransparent = @{}
$assetDimensionNames = @{}
if (Test-Path -LiteralPath $AssetCatalog) {
  foreach ($asset in @(Import-Csv -LiteralPath $AssetCatalog)) {
    Add-Name -Map $assetNames -Index $asset.CastIndex -Name $asset.Name
    Add-Name -Map $assetClasses -Index $asset.CastIndex -Name $asset.AssetClass
    Add-Name -Map $assetDimensionNames -Index "$($asset.Width)x$($asset.Height)" -Name $asset.Name
    if ($asset.PreviewPng -and -not $assetPreviews.ContainsKey($asset.CastIndex)) {
      $assetPreviews[$asset.CastIndex] = $asset.PreviewPng
    }
    if ($asset.TransparentPng -and -not $assetTransparent.ContainsKey($asset.CastIndex)) {
      $assetTransparent[$asset.CastIndex] = $asset.TransparentPng
    }
  }
}

$castMemberNames = @{}
$castMemberClasses = @{}
$castMemberPreviews = @{}
$castMemberTransparent = @{}
$resourceCastNames = @{}
$resourceCastKinds = @{}
$resourceCastClasses = @{}
$resourceCastPreviews = @{}
$resourceCastTransparent = @{}
if (Test-Path -LiteralPath $CastIndex) {
  foreach ($cast in @(Import-Csv -LiteralPath $CastIndex)) {
    Add-Name -Map $resourceCastNames -Index $cast.Index -Name $cast.Name
    Add-Name -Map $resourceCastKinds -Index $cast.Index -Name $cast.Kind
    if ($assetClasses.ContainsKey($cast.Index)) {
      Add-Name -Map $resourceCastClasses -Index $cast.Index -Name $assetClasses[$cast.Index]
    }
    if ($assetPreviews.ContainsKey($cast.Index) -and -not $resourceCastPreviews.ContainsKey($cast.Index)) {
      $resourceCastPreviews[$cast.Index] = $assetPreviews[$cast.Index]
    }
    if ($assetTransparent.ContainsKey($cast.Index) -and -not $resourceCastTransparent.ContainsKey($cast.Index)) {
      $resourceCastTransparent[$cast.Index] = $assetTransparent[$cast.Index]
    }

    if (-not $cast.CastMemberId) {
      continue
    }

    Add-Name -Map $castMemberNames -Index $cast.CastMemberId -Name $cast.Name
    if ($assetClasses.ContainsKey($cast.Index)) {
      Add-Name -Map $castMemberClasses -Index $cast.CastMemberId -Name $assetClasses[$cast.Index]
    }
    if ($assetPreviews.ContainsKey($cast.Index) -and -not $castMemberPreviews.ContainsKey($cast.CastMemberId)) {
      $castMemberPreviews[$cast.CastMemberId] = $assetPreviews[$cast.Index]
    }
    if ($assetTransparent.ContainsKey($cast.Index) -and -not $castMemberTransparent.ContainsKey($cast.CastMemberId)) {
      $castMemberTransparent[$cast.CastMemberId] = $assetTransparent[$cast.Index]
    }
  }
}

$scoreCastToResource = @{}
if (Test-Path -LiteralPath $ResourceManifest) {
  $cas = @(Import-Csv -LiteralPath $ResourceManifest | Where-Object { $_.Type -eq "CAS*" } | Select-Object -First 1)
  if ($cas.Count -gt 0 -and (Test-Path -LiteralPath $cas[0].File)) {
    $casBytes = [IO.File]::ReadAllBytes($cas[0].File)
    $entryCount = [Math]::Floor(([int]$cas[0].Size) / 4)
    for ($zeroSlot = 0; $zeroSlot -lt $entryCount; $zeroSlot++) {
      $entryOffset = 8 + ($zeroSlot * 4)
      if ($entryOffset + 4 -gt $casBytes.Length) {
        break
      }
      $scoreCastToResource[[string]($zeroSlot + 1)] = [int](Read-U32BE -Bytes $casBytes -Offset $entryOffset)
    }
  }
}

$soundNames = @{}
if (Test-Path -LiteralPath $SoundCatalog) {
  foreach ($sound in @(Import-Csv -LiteralPath $SoundCatalog)) {
    Add-Name -Map $soundNames -Index $sound.CastIndex -Name $sound.Name
  }
}

$lingoByAssemblyId = @{}
if (Test-Path -LiteralPath $LingoScripts) {
  foreach ($script in @(Import-Csv -LiteralPath $LingoScripts)) {
    if ($script.AssemblyId) {
      $lingoByAssemblyId[[string]$script.AssemblyId] = $script
    }
  }
}

$labels = Parse-Labels -Path $LabelsResource
$labelByFrame = @{}
foreach ($label in $labels) {
  $labelByFrame[[int]$label.Frame] = $label.Label
}
$labels | Export-Csv -LiteralPath $LabelsOut -NoTypeInformation

$bytes = [IO.File]::ReadAllBytes($ScoreResource)
if ((Read-Tag -Bytes $bytes) -ne "CSWV") {
  throw "Unexpected score resource tag in $ScoreResource"
}

$body = 8
$chunkBodySize = Read-U32LE -Bytes $bytes -Offset 4
$framesResourceSize = Read-U32BE -Bytes $bytes -Offset $body
$scoreVersionRaw = Read-U32BE -Bytes $bytes -Offset ($body + 4)
$listStart = Read-U32BE -Bytes $bytes -Offset ($body + 8)
$listAbs = $body + [int]$listStart
$detailCount = Read-U32BE -Bytes $bytes -Offset $listAbs
$detailListSize = Read-U32BE -Bytes $bytes -Offset ($listAbs + 4)
$maxDetailLength = Read-U32BE -Bytes $bytes -Offset ($listAbs + 8)
$indexStart = $listAbs + 12
$frameDataOffset = $indexStart + ([int]$detailListSize * 4)
$scoreHeaderOffset = $frameDataOffset + [int](Read-U32BE -Bytes $bytes -Offset $indexStart)

$framesStreamSize = Read-U32BE -Bytes $bytes -Offset $scoreHeaderOffset
$frame1Offset = Read-U32BE -Bytes $bytes -Offset ($scoreHeaderOffset + 4)
$headerFrameCount = Read-U32BE -Bytes $bytes -Offset ($scoreHeaderOffset + 8)
$framesVersion = Read-U16BE -Bytes $bytes -Offset ($scoreHeaderOffset + 12)
$spriteRecordSize = Read-U16BE -Bytes $bytes -Offset ($scoreHeaderOffset + 14)
$numChannels = Read-U16BE -Bytes $bytes -Offset ($scoreHeaderOffset + 16)
$displayedOrReserved = Read-U16BE -Bytes $bytes -Offset ($scoreHeaderOffset + 18)
$numChannelsDisplayed = if ($framesVersion -gt 13) { $displayedOrReserved } else { 120 }
$firstFramePosition = $scoreHeaderOffset + 20

$mainChannel = New-Object byte[] 144
$spriteChannels = @{}
$frameRows = [System.Collections.Generic.List[object]]::new()
$spriteRows = [System.Collections.Generic.List[object]]::new()
$scriptDetailRows = [System.Collections.Generic.List[object]]::new()
$spriteBehaviorRowsByKey = @{}
$position = $firstFramePosition
$frameNumber = 1
$maxTouchedChannel = 0

while (($position -lt $bytes.Length) -and (($position - $firstFramePosition) -lt $framesStreamSize)) {
  $frameStart = $position
  $frameSize = Read-U16BE -Bytes $bytes -Offset $position
  if ($frameSize -le 0) {
    break
  }

  $position += 2
  $remaining = $frameSize - 2
  if ($position + $remaining -gt $bytes.Length) {
    throw "Frame $frameNumber declares data past end of file."
  }

  $changedChannels = @{}
  $changedMain = $false

  while ($remaining -gt 0) {
    $channelSize = Read-U16BE -Bytes $bytes -Offset $position
    $channelOffset = Read-U16BE -Bytes $bytes -Offset ($position + 2)
    $position += 4
    $remaining -= 4

    if ($channelSize -gt $remaining) {
      throw "Frame $frameNumber has channel chunk larger than remaining frame data."
    }

    $sourceOffset = 0
    while ($sourceOffset -lt $channelSize) {
      $absoluteOffset = $channelOffset + $sourceOffset
      if ($absoluteOffset -lt 144) {
        $copySize = [Math]::Min($channelSize - $sourceOffset, 144 - $absoluteOffset)
        [Array]::Copy($bytes, $position + $sourceOffset, $mainChannel, $absoluteOffset, $copySize)
        $sourceOffset += $copySize
        $changedMain = $true
      } else {
        $spriteIndex = [int](($absoluteOffset - 144) / 24) + 1
        $fieldOffset = [int](($absoluteOffset - 144) % 24)
        $copySize = [Math]::Min($channelSize - $sourceOffset, 24 - $fieldOffset)
        if (-not $spriteChannels.ContainsKey($spriteIndex)) {
          $spriteChannels[$spriteIndex] = New-Object byte[] 24
        }
        [Array]::Copy($bytes, $position + $sourceOffset, $spriteChannels[$spriteIndex], $fieldOffset, $copySize)
        $sourceOffset += $copySize
        $changedChannels[$spriteIndex] = $true
        if ($spriteIndex -gt $maxTouchedChannel) {
          $maxTouchedChannel = $spriteIndex
        }
      }
    }

    $position += $channelSize
    $remaining -= $channelSize
  }

  $activeCount = 0
  $label = if ($labelByFrame.ContainsKey($frameNumber)) { $labelByFrame[$frameNumber] } else { "" }

  foreach ($channel in @($spriteChannels.Keys | Sort-Object {[int]$_})) {
    $state = $spriteChannels[$channel]
    $castIndex = Read-U16BE -Bytes $state -Offset 6
    $width = Read-S16BE -Bytes $state -Offset 18
    $height = Read-S16BE -Bytes $state -Offset 16
    $spriteListIdx = Read-U32BE -Bytes $state -Offset 8

    if ($spriteListIdx -gt 0) {
      $spriteInfoBounds = Get-DetailBounds -DetailIndex $spriteListIdx
      $behaviorBounds = Get-DetailBounds -DetailIndex ($spriteListIdx + 1)
      if ($behaviorBounds -and $behaviorBounds.Size -gt 0) {
        if (($behaviorBounds.Size % 8) -ne 0) {
          throw "Sprite list $spriteListIdx on channel $channel has a behavior detail size not divisible by 8: $($behaviorBounds.Size)"
        }

        $spriteInfoStartFrame = ""
        $spriteInfoEndFrame = ""
        $spriteInfoSize = ""
        if ($spriteInfoBounds) {
          $spriteInfoSize = $spriteInfoBounds.Size
          if ($spriteInfoBounds.Size -ge 8) {
            $spriteInfoStartFrame = Read-U32BE -Bytes $bytes -Offset $spriteInfoBounds.Start
            $spriteInfoEndFrame = Read-U32BE -Bytes $bytes -Offset ($spriteInfoBounds.Start + 4)
          }
        }

        for ($behaviorOffset = 0; $behaviorOffset -lt $behaviorBounds.Size; $behaviorOffset += 8) {
          $behaviorOrdinal = [int]($behaviorOffset / 8)
          $recordStart = $behaviorBounds.Start + $behaviorOffset
          $behaviorCastLib = Read-U16BE -Bytes $bytes -Offset $recordStart
          $behaviorMember = Read-U16BE -Bytes $bytes -Offset ($recordStart + 2)
          $initializerIndex = Read-U32BE -Bytes $bytes -Offset ($recordStart + 4)
          $initializer = Get-InitializerInfo -DetailIndex $initializerIndex
          $lingoScript = if ($lingoByAssemblyId.ContainsKey([string]$behaviorMember)) {
            $lingoByAssemblyId[[string]$behaviorMember]
          } else {
            $null
          }
          $rowKey = "$spriteListIdx|$channel|$behaviorOrdinal"

          if ($spriteBehaviorRowsByKey.ContainsKey($rowKey)) {
            $spriteBehaviorRowsByKey[$rowKey].LastObservedFrame = $frameNumber
            if ($label) {
              $spriteBehaviorRowsByKey[$rowKey].LastObservedLabel = $label
            }
            continue
          }

          $spriteBehaviorRowsByKey[$rowKey] = [pscustomobject]@{
            SpriteListIdx = $spriteListIdx
            Channel = [int]$channel
            SpriteInfoSize = $spriteInfoSize
            SpriteInfoStartFrame = $spriteInfoStartFrame
            SpriteInfoEndFrame = $spriteInfoEndFrame
            FirstObservedFrame = $frameNumber
            LastObservedFrame = $frameNumber
            FirstObservedLabel = $label
            LastObservedLabel = $label
            BehaviorOrdinal = $behaviorOrdinal
            BehaviorCastLib = $behaviorCastLib
            BehaviorMember = $behaviorMember
            ScriptResourceIndex = if ($lingoScript) { $lingoScript.ResourceIndex } else { "" }
            ScriptProperties = if ($lingoScript) { $lingoScript.Properties } else { "" }
            ScriptGlobals = if ($lingoScript) { $lingoScript.Globals } else { "" }
            InitializerIndex = $initializerIndex
            InitializerSize = $initializer.Size
            InitializerHexPreview = $initializer.HexPreview
            InitializerText = $initializer.Text
            InitializerGd = $initializer.Gd
            InitializerLevel = $initializer.Level
          }
        }
      }
    }

    if ($castIndex -eq 0 -or $width -le 0 -or $height -le 0) {
      continue
    }

    $activeCount++
    $castResourceIndex = if ($scoreCastToResource.ContainsKey([string]$castIndex)) { $scoreCastToResource[[string]$castIndex] } else { "" }
    $castName = ""
    $assetClass = ""
    $preview = ""
    $transparent = ""
    $castResolvedBy = ""
    if ($castResourceIndex -ne "" -and $resourceCastNames.ContainsKey([string]$castResourceIndex)) {
      $castName = Get-Name -Map $resourceCastNames -Index $castResourceIndex
      $assetClass = Get-Name -Map $resourceCastClasses -Index $castResourceIndex
      $preview = if ($resourceCastPreviews.ContainsKey([string]$castResourceIndex)) { $resourceCastPreviews[[string]$castResourceIndex] } else { "" }
      $transparent = if ($resourceCastTransparent.ContainsKey([string]$castResourceIndex)) { $resourceCastTransparent[[string]$castResourceIndex] } else { "" }
      $castResolvedBy = "cas-slot"
    }
    $dimensionCandidateNames = Get-Name -Map $assetDimensionNames -Index "$($width)x$($height)"
    $legacyCastMemberIdHint = Get-Name -Map $castMemberNames -Index $castIndex
    $legacyResourceIndexHint = Get-Name -Map $assetNames -Index $castIndex

    $spriteRows.Add([pscustomobject]@{
      Frame = $frameNumber
      Label = $label
      Channel = [int]$channel
      ChangedThisFrame = [bool]$changedChannels.ContainsKey($channel)
      CastIndex = $castIndex
      CastResourceIndex = $castResourceIndex
      CastName = $castName
      CastResolvedBy = $castResolvedBy
      AssetClass = $assetClass
      DimensionCandidateNames = $dimensionCandidateNames
      LegacyCastMemberIdHint = $legacyCastMemberIdHint
      LegacyResourceIndexHint = $legacyResourceIndexHint
      SpriteType = [int]$state[0]
      InkData = [int]$state[1]
      Ink = ([int]$state[1] -band 0x3f)
      CastLib = (Read-S16BE -Bytes $state -Offset 4)
      SpriteListIdx = $spriteListIdx
      X = (Read-S16BE -Bytes $state -Offset 14)
      Y = (Read-S16BE -Bytes $state -Offset 12)
      Width = $width
      Height = $height
      ForeColor = [int]$state[2]
      BackColor = [int]$state[3]
      ColorCode = [int]$state[20]
      BlendAmount = [int]$state[21]
      Thickness = [int]$state[22]
      PreviewPng = $preview
      TransparentPng = $transparent
    })
  }

  $sound1 = Read-U16BE -Bytes $mainChannel -Offset 98
  $sound2 = Read-U16BE -Bytes $mainChannel -Offset 74
  $actionMember = Read-U16BE -Bytes $mainChannel -Offset 2
  $scriptSpriteListIdx = Read-U32BE -Bytes $mainChannel -Offset 4
  $scriptInfoSize = 0
  $scriptBehaviorSize = 0
  $scriptInfoStartFrame = ""
  $scriptInfoEndFrame = ""
  $scriptBehaviorCastLib = ""
  $scriptBehaviorMember = ""
  $scriptBehaviorInitializerIndex = ""
  $scriptBehaviorInitializerSize = ""
  $scriptBehaviorInitializerHex = ""
  $scriptBehaviorInitializerText = ""
  $scriptBehaviorInitializerGd = ""
  $scriptBehaviorInitializerLevel = ""
  $scriptBehaviorHex = ""
  $scriptBehaviorNameHint = ""

  if ($scriptSpriteListIdx -gt 0) {
    $infoBounds = Get-DetailBounds -DetailIndex $scriptSpriteListIdx
    $behaviorBounds = Get-DetailBounds -DetailIndex ($scriptSpriteListIdx + 1)

    if ($infoBounds) {
      $scriptInfoSize = $infoBounds.Size
      if ($scriptInfoSize -ge 8) {
        $scriptInfoStartFrame = Read-U32BE -Bytes $bytes -Offset $infoBounds.Start
        $scriptInfoEndFrame = Read-U32BE -Bytes $bytes -Offset ($infoBounds.Start + 4)
      }
    }
    if ($behaviorBounds) {
      $scriptBehaviorSize = $behaviorBounds.Size
      $scriptBehaviorHex = Get-HexPreview -Start $behaviorBounds.Start -Size $behaviorBounds.Size
      if ($scriptBehaviorSize -ge 8) {
        $scriptBehaviorCastLib = Read-U16BE -Bytes $bytes -Offset $behaviorBounds.Start
        $scriptBehaviorMember = Read-U16BE -Bytes $bytes -Offset ($behaviorBounds.Start + 2)
        $scriptBehaviorInitializerIndex = Read-U32BE -Bytes $bytes -Offset ($behaviorBounds.Start + 4)
        $scriptBehaviorNameHint = Get-Name -Map $assetNames -Index $scriptBehaviorMember
        $initializer = Get-InitializerInfo -DetailIndex $scriptBehaviorInitializerIndex
        $scriptBehaviorInitializerSize = $initializer.Size
        $scriptBehaviorInitializerHex = $initializer.HexPreview
        $scriptBehaviorInitializerText = $initializer.Text
        $scriptBehaviorInitializerGd = $initializer.Gd
        $scriptBehaviorInitializerLevel = $initializer.Level
      }
    }

    $scriptDetailRows.Add([pscustomobject]@{
      Frame = $frameNumber
      Label = $label
      ActionMember = $actionMember
      ScriptSpriteListIdx = $scriptSpriteListIdx
      ScriptInfoSize = $scriptInfoSize
      ScriptInfoStartFrame = $scriptInfoStartFrame
      ScriptInfoEndFrame = $scriptInfoEndFrame
      BehaviorSize = $scriptBehaviorSize
      BehaviorCastLib = $scriptBehaviorCastLib
      BehaviorMember = $scriptBehaviorMember
      BehaviorNameResourceIndexHint = $scriptBehaviorNameHint
      BehaviorInitializerIndex = $scriptBehaviorInitializerIndex
      BehaviorInitializerSize = $scriptBehaviorInitializerSize
      BehaviorInitializerHexPreview = $scriptBehaviorInitializerHex
      BehaviorInitializerText = $scriptBehaviorInitializerText
      InitializerGd = $scriptBehaviorInitializerGd
      InitializerLevel = $scriptBehaviorInitializerLevel
      BehaviorHexPreview = $scriptBehaviorHex
    })
  }

  $frameRows.Add([pscustomobject]@{
    Frame = $frameNumber
    Label = $label
    FrameOffset = ("0x{0:X}" -f $frameStart)
    FrameSize = $frameSize
    ChangedMainChannel = $changedMain
    ChangedSpriteChannelCount = $changedChannels.Count
    ActiveSpriteCount = $activeCount
    Tempo = [int]$mainChannel[30]
    ActionMember = $actionMember
    ScriptSpriteListIdx = $scriptSpriteListIdx
    ScriptInfoStartFrame = $scriptInfoStartFrame
    ScriptInfoEndFrame = $scriptInfoEndFrame
    BehaviorMember = $scriptBehaviorMember
    BehaviorInitializerIndex = $scriptBehaviorInitializerIndex
    BehaviorInitializerText = $scriptBehaviorInitializerText
    InitializerGd = $scriptBehaviorInitializerGd
    InitializerLevel = $scriptBehaviorInitializerLevel
    Sound1CastIndex = $sound1
    Sound1Name = (Get-Name -Map $soundNames -Index $sound1)
    Sound2CastIndex = $sound2
    Sound2Name = (Get-Name -Map $soundNames -Index $sound2)
  })

  $frameNumber++
}

$parsedFrames = $frameNumber - 1
$summary = [pscustomobject]@{
  ScoreResource = $ScoreResource
  ChunkBodySize = $chunkBodySize
  FramesResourceSize = $framesResourceSize
  ScoreVersionRaw = ("0x{0:X8}" -f $scoreVersionRaw)
  DetailCount = $detailCount
  DetailListSize = $detailListSize
  MaxDetailLength = $maxDetailLength
  IndexStart = ("0x{0:X}" -f $indexStart)
  FrameDataOffset = ("0x{0:X}" -f $frameDataOffset)
  ScoreHeaderOffset = ("0x{0:X}" -f $scoreHeaderOffset)
  FramesStreamSize = $framesStreamSize
  Frame1Offset = $frame1Offset
  HeaderFrameCount = $headerFrameCount
  ParsedFrameCount = $parsedFrames
  FramesVersion = $framesVersion
  SpriteRecordSize = $spriteRecordSize
  NumChannels = $numChannels
  NumChannelsDisplayed = $numChannelsDisplayed
  DisplayedOrReserved = $displayedOrReserved
  FirstFramePosition = ("0x{0:X}" -f $firstFramePosition)
  LastFrameEnd = ("0x{0:X}" -f $position)
  ExpectedFrameEnd = ("0x{0:X}" -f ($firstFramePosition + $framesStreamSize))
  MaxTouchedSpriteChannel = $maxTouchedChannel
  LabelCount = $labels.Count
  SpriteRowCount = $spriteRows.Count
  SpriteBehaviorRowCount = $spriteBehaviorRowsByKey.Count
}

$spriteBehaviorRows = @($spriteBehaviorRowsByKey.Values | Sort-Object SpriteInfoStartFrame, Channel, SpriteListIdx, BehaviorOrdinal)
$summary | Export-Csv -LiteralPath $SummaryOut -NoTypeInformation
$frameRows | Export-Csv -LiteralPath $FramesOut -NoTypeInformation
$spriteRows | Export-Csv -LiteralPath $SpritesOut -NoTypeInformation
$scriptDetailRows | Export-Csv -LiteralPath $ScriptDetailsOut -NoTypeInformation
$spriteBehaviorRows | Export-Csv -LiteralPath $SpriteBehaviorsOut -NoTypeInformation

"Exported score summary: $SummaryOut"
"Exported score labels: $LabelsOut"
"Exported frame summary: $FramesOut"
"Exported frame sprites: $SpritesOut"
"Exported score script details: $ScriptDetailsOut"
"Exported score sprite behaviors: $SpriteBehaviorsOut"
