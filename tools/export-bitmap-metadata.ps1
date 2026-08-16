param(
  [string]$CastIndex = "reverse\cast-index.csv",
  [string]$OutPath = "reverse\bitmap-metadata.csv"
)

$ErrorActionPreference = "Stop"

function Read-BigU16 {
  param([byte[]]$Bytes, [int]$Offset)
  (([int]$Bytes[$Offset] -shl 8) -bor [int]$Bytes[$Offset + 1])
}

function Read-BigS16 {
  param([byte[]]$Bytes, [int]$Offset)
  $value = Read-BigU16 $Bytes $Offset
  if ($value -ge 0x8000) {
    return $value - 0x10000
  }
  return $value
}

function Read-BigU32 {
  param([byte[]]$Bytes, [int]$Offset)
  (([int]$Bytes[$Offset] -shl 24) -bor ([int]$Bytes[$Offset + 1] -shl 16) -bor ([int]$Bytes[$Offset + 2] -shl 8) -bor [int]$Bytes[$Offset + 3])
}

function Read-Rect {
  param([byte[]]$Bytes, [int]$Offset)
  $top = Read-BigS16 $Bytes $Offset
  $left = Read-BigS16 $Bytes ($Offset + 2)
  $bottom = Read-BigS16 $Bytes ($Offset + 4)
  $right = Read-BigS16 $Bytes ($Offset + 6)
  [pscustomobject]@{
    Top = $top
    Left = $left
    Bottom = $bottom
    Right = $right
    Width = $right - $left
    Height = $bottom - $top
  }
}

function Try-Parse-BitmapData {
  param([byte[]]$Bytes, [int]$Offset, [int]$Length)

  if ($Length -lt 22 -or $Offset + $Length -gt $Bytes.Length) {
    return $null
  }

  $pitchRaw = Read-BigU16 $Bytes $Offset
  $pitch = $pitchRaw -band 0x3fff
  $initial = Read-Rect $Bytes ($Offset + 2)
  $paddingOrAlpha = Read-BigU16 $Bytes ($Offset + 10)
  $editVersion = Read-BigU16 $Bytes ($Offset + 12)
  $scrollY = Read-BigS16 $Bytes ($Offset + 14)
  $scrollX = Read-BigS16 $Bytes ($Offset + 16)
  $regY = Read-BigU16 $Bytes ($Offset + 18)
  $regX = Read-BigU16 $Bytes ($Offset + 20)
  $updateFlags = if ($Length -gt 22) { $Bytes[$Offset + 22] } else { 0 }

  $bitsPerPixel = 1
  $clutCastLib = ""
  $clutId = ""
  if (($pitchRaw -band 0x8000) -ne 0 -and $Length -ge 28) {
    $bitsPerPixel = $Bytes[$Offset + 23]
    $clutCastLib = Read-BigS16 $Bytes ($Offset + 24)
    $clutId = Read-BigS16 $Bytes ($Offset + 26)
  }

  if ($initial.Width -le 0 -or $initial.Height -le 0 -or $initial.Width -gt 1000 -or $initial.Height -gt 1000) {
    return $null
  }

  [pscustomobject]@{
    PitchRaw = "0x{0:X4}" -f $pitchRaw
    Pitch = $pitch
    BitsPerPixel = $bitsPerPixel
    InitialLeft = $initial.Left
    InitialTop = $initial.Top
    InitialRight = $initial.Right
    InitialBottom = $initial.Bottom
    Width = $initial.Width
    Height = $initial.Height
    PaddingOrAlpha = $paddingOrAlpha
    EditVersion = $editVersion
    ScrollX = $scrollX
    ScrollY = $scrollY
    RegX = $regX
    RegY = $regY
    UpdateFlags = $updateFlags
    ClutCastLib = $clutCastLib
    ClutId = $clutId
  }
}

if (-not (Test-Path -LiteralPath $CastIndex)) {
  throw "Cast index not found: $CastIndex. Run tools\export-cast-index.ps1 first."
}

$casts = Import-Csv -LiteralPath $CastIndex
$rows = @()

foreach ($cast in $casts) {
  $bytes = [IO.File]::ReadAllBytes($cast.File)
  if ($bytes.Length -lt 20) {
    continue
  }

  $bodyOffset = 8
  $castType = Read-BigU32 $bytes $bodyOffset
  $castInfoSize = Read-BigU32 $bytes ($bodyOffset + 4)
  $castDataSize = Read-BigU32 $bytes ($bodyOffset + 8)
  $castDataOffset = $bodyOffset + 12 + $castInfoSize

  # Director 5+ bitmap cast type is 1 in the ScummVM loader path.
  if ($castType -ne 1) {
    continue
  }

  $meta = Try-Parse-BitmapData $bytes $castDataOffset $castDataSize
  if (-not $meta) {
    continue
  }

  $rows += [pscustomobject]@{
    Index = $cast.Index
    CastMemberId = $cast.CastMemberId
    Name = $cast.Name
    Kind = $cast.Kind
    Relative = $cast.Relative
    CastType = $castType
    CastInfoSize = $castInfoSize
    CastDataSize = $castDataSize
    DataOffset = "0x{0:X}" -f $castDataOffset
    PitchRaw = $meta.PitchRaw
    Pitch = $meta.Pitch
    BitsPerPixel = $meta.BitsPerPixel
    Width = $meta.Width
    Height = $meta.Height
    InitialLeft = $meta.InitialLeft
    InitialTop = $meta.InitialTop
    InitialRight = $meta.InitialRight
    InitialBottom = $meta.InitialBottom
    RegX = $meta.RegX
    RegY = $meta.RegY
    UpdateFlags = $meta.UpdateFlags
    ClutCastLib = $meta.ClutCastLib
    ClutId = $meta.ClutId
    File = $cast.File
  }
}

$rows | Export-Csv -LiteralPath $OutPath -NoTypeInformation

"Bitmap metadata rows: $($rows.Count)"
"Output: $OutPath"
""
$rows | Sort-Object Name,Index | Format-Table Index,CastMemberId,Name,Width,Height,Pitch,BitsPerPixel,RegX,RegY,ClutId -AutoSize
