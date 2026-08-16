param(
  [string]$KeyMap = "reverse\key-map.csv",
  [string]$SoundCastMetadata = "reverse\sound-cast-metadata.csv",
  [string]$SoundManifest = "reverse\sounds\manifest.csv",
  [string]$OutPath = "reverse\sound-map.csv"
)

$ErrorActionPreference = "Stop"

function Get-EventHint {
  param([string]$Name)

  switch -Regex ($Name) {
    "^step$" { return "walking/movement step" }
    "^Whoosh" { return "snowball throw/flight" }
    "^hit1$" { return "snowball impact/drop/splat" }
    "^hit2$" { return "green/player hit reaction" }
    "^splat$" { return "snowball impact/splat" }
    "^kids" { return "kids/ridicule/victory flavor" }
    "^laugh$" { return "ridicule/victory flavor" }
    "^ugly$" { return "ridicule/victory flavor" }
    "^Ahhhh!$" { return "red/opponent hit or death" }
    "^bird_tweets$|^short_chirps$" { return "red/opponent ambient/state flavor" }
    default { return "" }
  }
}

if (-not (Test-Path -LiteralPath $KeyMap)) {
  throw "Key map not found: $KeyMap. Run tools\export-key-map.ps1 first."
}
if (-not (Test-Path -LiteralPath $SoundCastMetadata)) {
  throw "Sound cast metadata not found: $SoundCastMetadata. Run tools\export-sound-cast-metadata.ps1 first."
}
if (-not (Test-Path -LiteralPath $SoundManifest)) {
  throw "Sound manifest not found: $SoundManifest. Run tools\export-director-sounds.ps1 first."
}

$keys = @(Import-Csv -LiteralPath $KeyMap)
$casts = @(Import-Csv -LiteralPath $SoundCastMetadata)
$sounds = @(Import-Csv -LiteralPath $SoundManifest)

$soundsByHeaderAndSample = @{}
$soundsBySample = @{}
foreach ($sound in $sounds) {
  $soundsByHeaderAndSample["$($sound.HeaderIndex):$($sound.SampleIndex)"] = $sound
  $soundsBySample[$sound.SampleIndex] = $sound
}

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($cast in $casts) {
  $castIndex = [int]$cast.CastIndex
  $keyParentIndex = $castIndex + 3
  $related = @($keys | Where-Object { $_.ParentIndex -eq [string]$keyParentIndex })
  $headerRows = @($related | Where-Object { $_.ChildType -eq "sndH" })
  $sampleRows = @($related | Where-Object { $_.ChildType -eq "sndS" })
  $headerIndex = ""
  $sampleIndex = ""

  if ($headerRows.Count -gt 0) {
    $headerIndex = [int]$headerRows[0].ChildIndex - 3
  }
  if ($sampleRows.Count -gt 0) {
    $sampleIndex = [int]$sampleRows[0].ChildIndex - 3
  }

  $sound = $null
  $headerSampleKey = "{0}:{1}" -f $headerIndex, $sampleIndex
  if ($headerIndex -ne "" -and $sampleIndex -ne "" -and $soundsByHeaderAndSample.ContainsKey($headerSampleKey)) {
    $sound = $soundsByHeaderAndSample[$headerSampleKey]
  } elseif ($sampleIndex -ne "" -and $soundsBySample.ContainsKey([string]$sampleIndex)) {
    $sound = $soundsBySample[[string]$sampleIndex]
  }

  $status = if ($sound) {
    "mapped"
  } elseif ($headerIndex -ne "" -or $sampleIndex -ne "") {
    "key-without-exported-wav"
  } else {
    "no-key-sound-link"
  }

  $rows.Add([pscustomobject]@{
    Status = $status
    SoundCastIndex = $castIndex
    SoundName = $cast.Name
    Format = $cast.Format
    Names = $cast.Names
    KeyParentIndex = $keyParentIndex
    SndHIndex = $headerIndex
    SndSIndex = $sampleIndex
    WavSoundOrdinal = if ($sound) { $sound.Sound } else { "" }
    SampleRate = if ($sound) { $sound.SampleRate } else { "" }
    Channels = if ($sound) { $sound.Channels } else { "" }
    Bits = if ($sound) { $sound.Bits } else { "" }
    ExportedBytes = if ($sound) { $sound.ExportedBytes } else { "" }
    Seconds = if ($sound) { $sound.Seconds } else { "" }
    WavFile = if ($sound) { $sound.File } else { "" }
    LikelyEventHint = Get-EventHint -Name $cast.Name
    CastFile = $cast.File
  })
}

$rows | Export-Csv -LiteralPath $OutPath -NoTypeInformation

"Sound map rows: $($rows.Count)"
"Mapped WAV rows: $(($rows | Where-Object { $_.Status -eq 'mapped' }).Count)"
"Output: $OutPath"
""
$rows | Sort-Object Status,SoundCastIndex | Format-Table Status,SoundCastIndex,SoundName,SndHIndex,SndSIndex,Seconds,LikelyEventHint,WavFile -AutoSize
