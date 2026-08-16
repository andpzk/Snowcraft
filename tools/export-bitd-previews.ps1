param(
  [string]$BitmapMetadata = "reverse\bitmap-metadata.csv",
  [string]$ResourceManifest = "reverse\resources\manifest.csv",
  [string]$OutDir = "reverse\bitd-previews"
)

$ErrorActionPreference = "Stop"

function Sanitize-Name {
  param([string]$Value)
  $safe = $Value -replace "[^A-Za-z0-9_. -]", "_"
  ($safe.Trim() -replace "\s+", "_")
}

function Read-Palette {
  param([string]$Path)

  $bytes = [IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 8 + (256 * 6)) {
    throw "CLUT resource is too small: $Path"
  }

  $palette = New-Object 'System.Drawing.Color[]' 256
  for ($i = 0; $i -lt 256; $i++) {
    $pos = 8 + ($i * 6)
    $palette[$i] = [System.Drawing.Color]::FromArgb(255, $bytes[$pos], $bytes[$pos + 2], $bytes[$pos + 4])
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

  [pscustomobject]@{
    Pixels = $out
    Consumed = $inPos
  }
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

if (-not (Test-Path -LiteralPath $BitmapMetadata)) {
  throw "Bitmap metadata not found: $BitmapMetadata. Run tools\export-bitmap-metadata.ps1 first."
}
if (-not (Test-Path -LiteralPath $ResourceManifest)) {
  throw "Resource manifest not found: $ResourceManifest. Run tools\export-director-resources.ps1 first."
}

Add-Type -AssemblyName System.Drawing

$metadata = @(Import-Csv -LiteralPath $BitmapMetadata)
$resources = @(Import-Csv -LiteralPath $ResourceManifest)
$bitds = @($resources | Where-Object Type -eq "BITD" | Sort-Object {[int]$_.Index})
$clut = $resources | Where-Object Type -eq "CLUT" | Select-Object -First 1
if (-not $clut) {
  throw "No CLUT resource found in $ResourceManifest"
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$palette = Read-Palette $clut.File
$rows = @()

foreach ($meta in $metadata) {
  $width = [int]$meta.Width
  $height = [int]$meta.Height
  $pitch = [int]$meta.Pitch
  $needed = $pitch * $height

  foreach ($bitd in $bitds) {
    $bytes = [IO.File]::ReadAllBytes($bitd.File)
    $decoded = Decode-Bitd $bytes $needed
    if (-not $decoded -or $decoded.Consumed -ne $bytes.Length) {
      continue
    }

    $name = if ($meta.Name) { $meta.Name } else { "unnamed" }
    $safeName = Sanitize-Name $name
    if (-not $safeName) {
      $safeName = "unnamed"
    }

    $fileName = "cast-{0:D4}_bitd-{1:D4}_{2}_{3}x{4}.png" -f [int]$meta.Index, [int]$bitd.Index, $safeName, $width, $height
    $outPath = Join-Path $OutDir $fileName
    Save-Png $outPath $decoded.Pixels $width $height $pitch $palette

    $rows += [pscustomobject]@{
      CastIndex = $meta.Index
      CastSlot = $meta.CastMemberId
      Name = $meta.Name
      Width = $width
      Height = $height
      Pitch = $pitch
      BitdIndex = $bitd.Index
      BitdSize = $bitd.Size
      Consumed = $decoded.Consumed
      Png = $outPath
    }
  }
}

$manifestPath = Join-Path $OutDir "manifest.csv"
$rows | Export-Csv -LiteralPath $manifestPath -NoTypeInformation

"BITD preview candidates: $($rows.Count)"
"Output: $OutDir"
"Manifest: $manifestPath"
""
$rows | Sort-Object {[int]$_.CastIndex}, {[int]$_.BitdIndex} | Format-Table CastIndex,CastSlot,Name,Width,Height,BitdIndex,BitdSize,Png -AutoSize
