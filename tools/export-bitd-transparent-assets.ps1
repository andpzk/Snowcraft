param(
  [string]$CandidateManifest = "reverse\bitd-previews\manifest.csv",
  [string]$ResourceManifest = "reverse\resources\manifest.csv",
  [string]$OutDir = "reverse\bitd-transparent",
  [int]$TransparentIndex = 0
)

$ErrorActionPreference = "Stop"

function Sanitize-Name {
  param([string]$Value)
  $safe = $Value -replace "[^A-Za-z0-9_. -]", "_"
  ($safe.Trim() -replace "\s+", "_")
}

function Read-Palette {
  param([string]$Path, [int]$TransparentIndex)

  $bytes = [IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 8 + (256 * 6)) {
    throw "CLUT resource is too small: $Path"
  }

  $palette = New-Object 'System.Drawing.Color[]' 256
  for ($i = 0; $i -lt 256; $i++) {
    $pos = 8 + ($i * 6)
    $alpha = if ($i -eq $TransparentIndex) { 0 } else { 255 }
    $palette[$i] = [System.Drawing.Color]::FromArgb($alpha, $bytes[$pos], $bytes[$pos + 2], $bytes[$pos + 4])
  }

  $palette
}

function Decode-Bitd {
  param([byte[]]$Bytes, [int]$Needed)

  $out = New-Object byte[] $Needed
  $inPos = 8
  $outPos = 0

  while ($inPos -lt $Bytes.Length -and $outPos -lt $Needed) {
    $control = $Bytes[$inPos]
    $inPos++

    if (($control -band 0x80) -ne 0) {
      if ($inPos -ge $Bytes.Length) {
        return $null
      }

      $count = (($control -bxor 0xFF) -band 0xFF) + 2
      $value = $Bytes[$inPos]
      $inPos++
      if ($outPos + $count -gt $Needed) {
        return $null
      }

      for ($i = 0; $i -lt $count; $i++) {
        $out[$outPos + $i] = $value
      }
      $outPos += $count
    } else {
      $count = $control + 1
      if ($inPos + $count -gt $Bytes.Length -or $outPos + $count -gt $Needed) {
        return $null
      }

      [Array]::Copy($Bytes, $inPos, $out, $outPos, $count)
      $inPos += $count
      $outPos += $count
    }
  }

  if ($outPos -ne $Needed) {
    return $null
  }

  $out
}

function Save-Png {
  param(
    [string]$Path,
    [byte[]]$Pixels,
    [int]$Width,
    [int]$Height,
    [int]$Pitch,
    [System.Drawing.Color[]]$Palette
  )

  $bitmap = New-Object System.Drawing.Bitmap $Width, $Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  try {
    for ($y = 0; $y -lt $Height; $y++) {
      $row = $y * $Pitch
      for ($x = 0; $x -lt $Width; $x++) {
        $bitmap.SetPixel($x, $y, $Palette[[int]$Pixels[$row + $x]])
      }
    }
    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $bitmap.Dispose()
  }
}

if (-not (Test-Path -LiteralPath $CandidateManifest)) {
  throw "Candidate manifest not found: $CandidateManifest. Run tools\export-bitd-previews.ps1 first."
}
if (-not (Test-Path -LiteralPath $ResourceManifest)) {
  throw "Resource manifest not found: $ResourceManifest. Run tools\export-director-resources.ps1 first."
}

Add-Type -AssemblyName System.Drawing

$candidates = @(Import-Csv -LiteralPath $CandidateManifest)
$resources = @(Import-Csv -LiteralPath $ResourceManifest)
$bitdByIndex = @{}
foreach ($bitd in ($resources | Where-Object Type -eq "BITD")) {
  $bitdByIndex[[int]$bitd.Index] = $bitd
}

$clut = $resources | Where-Object Type -eq "CLUT" | Select-Object -First 1
if (-not $clut) {
  throw "No CLUT resource found in $ResourceManifest"
}

$castCandidateCounts = @{}
$bitdCandidateCounts = @{}
foreach ($candidate in $candidates) {
  $castCandidateCounts[$candidate.CastIndex] = 1 + $castCandidateCounts[$candidate.CastIndex]
  $bitdCandidateCounts[$candidate.BitdIndex] = 1 + $bitdCandidateCounts[$candidate.BitdIndex]
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$palette = Read-Palette $clut.File $TransparentIndex
$rows = @()

foreach ($candidate in $candidates) {
  $width = [int]$candidate.Width
  $height = [int]$candidate.Height

  # Large 600x320 movie backgrounds use palette index 0 as real snow/white.
  if ($width -ge 300 -and $height -ge 200) {
    continue
  }

  $pitch = [int]$candidate.Pitch
  $needed = $pitch * $height
  $bitd = $bitdByIndex[[int]$candidate.BitdIndex]
  if (-not $bitd) {
    continue
  }

  $bytes = [IO.File]::ReadAllBytes($bitd.File)
  $pixels = Decode-Bitd $bytes $needed
  if (-not $pixels) {
    continue
  }

  $name = if ($candidate.Name) { $candidate.Name } else { "unnamed" }
  $safeName = Sanitize-Name $name
  if (-not $safeName) {
    $safeName = "unnamed"
  }

  $fileName = "cast-{0:D4}_bitd-{1:D4}_{2}_{3}x{4}_transparent.png" -f [int]$candidate.CastIndex, [int]$candidate.BitdIndex, $safeName, $width, $height
  $outPath = Join-Path $OutDir $fileName
  Save-Png $outPath $pixels $width $height $pitch $palette

  $rows += [pscustomobject]@{
    CastIndex = $candidate.CastIndex
    CastSlot = $candidate.CastSlot
    Name = $candidate.Name
    Width = $width
    Height = $height
    Pitch = $pitch
    BitdIndex = $candidate.BitdIndex
    CastCandidateCount = $castCandidateCounts[$candidate.CastIndex]
    BitdCandidateCount = $bitdCandidateCounts[$candidate.BitdIndex]
    TransparentIndex = $TransparentIndex
    Png = $outPath
  }
}

$manifestPath = Join-Path $OutDir "manifest.csv"
$rows | Export-Csv -LiteralPath $manifestPath -NoTypeInformation

"Transparent sprite candidates: $($rows.Count)"
"Output: $OutDir"
"Manifest: $manifestPath"
""
$rows | Sort-Object {[int]$_.CastIndex}, {[int]$_.BitdIndex} | Format-Table CastIndex,CastSlot,Name,Width,Height,BitdIndex,CastCandidateCount,BitdCandidateCount,Png -AutoSize
