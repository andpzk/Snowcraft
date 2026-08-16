param(
  [string]$ManifestPath = "reverse\resources\manifest.csv",
  [string]$OutDir = "reverse\sounds"
)

$ErrorActionPreference = "Stop"

function Read-BigU16 {
  param([byte[]]$Bytes, [int]$Offset)
  (([int]$Bytes[$Offset] -shl 8) -bor [int]$Bytes[$Offset + 1])
}

function Read-BigU32 {
  param([byte[]]$Bytes, [int]$Offset)
  (([int]$Bytes[$Offset] -shl 24) -bor ([int]$Bytes[$Offset + 1] -shl 16) -bor ([int]$Bytes[$Offset + 2] -shl 8) -bor [int]$Bytes[$Offset + 3])
}

function Write-Ascii {
  param([IO.BinaryWriter]$Writer, [string]$Value)
  $Writer.Write([Text.Encoding]::ASCII.GetBytes($Value))
}

function Write-Wav {
  param(
    [string]$Path,
    [byte[]]$Samples,
    [int]$SampleRate,
    [int]$Channels,
    [int]$BitsPerSample
  )

  $blockAlign = [int](($Channels * $BitsPerSample) / 8)
  $byteRate = $SampleRate * $blockAlign
  $dataSize = $Samples.Length

  $stream = [IO.File]::Create($Path)
  try {
    $writer = New-Object IO.BinaryWriter($stream)
    Write-Ascii $writer "RIFF"
    $writer.Write([uint32](36 + $dataSize))
    Write-Ascii $writer "WAVE"
    Write-Ascii $writer "fmt "
    $writer.Write([uint32]16)
    $writer.Write([uint16]1)
    $writer.Write([uint16]$Channels)
    $writer.Write([uint32]$SampleRate)
    $writer.Write([uint32]$byteRate)
    $writer.Write([uint16]$blockAlign)
    $writer.Write([uint16]$BitsPerSample)
    Write-Ascii $writer "data"
    $writer.Write([uint32]$dataSize)
    $writer.Write($Samples)
  } finally {
    $stream.Dispose()
  }
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw "Manifest not found: $ManifestPath. Run tools\export-director-resources.ps1 first."
}

$manifest = Import-Csv -LiteralPath $ManifestPath
$soundHeaders = @($manifest | Where-Object Type -eq "sndH" | Sort-Object {[Convert]::ToInt32($_.Relative.Substring(2), 16)})
$soundSamples = @($manifest | Where-Object Type -eq "sndS" | Sort-Object {[Convert]::ToInt32($_.Relative.Substring(2), 16)})

if ($soundHeaders.Count -ne $soundSamples.Count) {
  throw "Sound header/sample count mismatch: sndH=$($soundHeaders.Count), sndS=$($soundSamples.Count)"
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$exports = @()
for ($i = 0; $i -lt $soundHeaders.Count; $i++) {
  $headerEntry = $soundHeaders[$i]
  $sampleEntry = $soundSamples[$i]
  $headerBytes = [IO.File]::ReadAllBytes($headerEntry.File)
  $sampleBytes = [IO.File]::ReadAllBytes($sampleEntry.File)

  if ([Text.Encoding]::ASCII.GetString($headerBytes, 0, 4) -ne "Hdns") {
    throw "Unexpected sound header FourCC in $($headerEntry.File)"
  }
  if ([Text.Encoding]::ASCII.GetString($sampleBytes, 0, 4) -ne "Sdns") {
    throw "Unexpected sound sample FourCC in $($sampleEntry.File)"
  }

  $declaredSamples = Read-BigU16 $headerBytes 14
  $sampleRate = Read-BigU16 $headerBytes 54
  $bitsPerSample = $headerBytes[79]
  $channels = [Math]::Max(1, $headerBytes[83])

  if ($sampleRate -le 0 -or $sampleRate -gt 96000) {
    $sampleRate = 11025
  }
  if ($bitsPerSample -ne 8 -and $bitsPerSample -ne 16) {
    $bitsPerSample = 8
  }

  $dataOffset = 8
  $available = $sampleBytes.Length - $dataOffset
  $sampleCount = [Math]::Min([int]$declaredSamples, $available)
  if ($sampleCount -le 0) {
    $sampleCount = $available
  }

  $samples = New-Object byte[] $sampleCount
  [Array]::Copy($sampleBytes, $dataOffset, $samples, 0, $sampleCount)

  $outPath = Join-Path $OutDir ("{0:D2}_idx-{1}_rate-{2}_bytes-{3}.wav" -f $i, $sampleEntry.Index, $sampleRate, $sampleCount)
  Write-Wav $outPath $samples $sampleRate $channels $bitsPerSample

  $exports += [pscustomobject]@{
    Sound = $i
    HeaderIndex = $headerEntry.Index
    SampleIndex = $sampleEntry.Index
    SampleRate = $sampleRate
    Channels = $channels
    Bits = $bitsPerSample
    DeclaredSamples = $declaredSamples
    ExportedBytes = $sampleCount
    Seconds = [Math]::Round($sampleCount / [double]($sampleRate * $channels * ($bitsPerSample / 8)), 3)
    File = $outPath
  }
}

$summaryPath = Join-Path $OutDir "manifest.csv"
$exports | Export-Csv -LiteralPath $summaryPath -NoTypeInformation
$exports | Format-Table -AutoSize
