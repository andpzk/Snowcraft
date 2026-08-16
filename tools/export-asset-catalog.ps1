param(
  [string]$BitmapMetadata = "reverse\bitmap-metadata.csv",
  [string]$PreviewManifest = "reverse\bitd-previews\manifest.csv",
  [string]$TransparentManifest = "reverse\bitd-transparent\manifest.csv",
  [string]$OutPath = "reverse\asset-catalog.csv"
)

$ErrorActionPreference = "Stop"

function Get-AssetClass {
  param([string]$Name, [int]$Width, [int]$Height)

  if ($Width -ge 300 -and $Height -ge 200) {
    return "background"
  }
  if ($Name -match "^G ") {
    return "green-sprite"
  }
  if ($Name -match "^R ") {
    return "red-sprite"
  }
  if ($Name -match "^power ") {
    return "ui-power"
  }
  if ($Name -match "^sb ") {
    return "snowball-state"
  }
  if ($Name -eq "snowball") {
    return "projectile"
  }
  if ($Name -eq "shadow") {
    return "shadow"
  }
  if ($Name -eq "splat") {
    return "effect"
  }
  if ($Name -match "^snowcraft_") {
    return "ui-or-background"
  }
  if (-not $Name) {
    return "unnamed"
  }
  return "visual"
}

function Get-CandidateStatus {
  param([int]$CastCandidateCount, [int]$BitdCandidateCount, [int]$CastUniqueHashCount)

  if ($CastCandidateCount -eq 1 -and $BitdCandidateCount -eq 1) {
    return "unambiguous"
  }
  if ($CastUniqueHashCount -eq 1) {
    return "reused-identical"
  }
  return "ambiguous"
}

if (-not (Test-Path -LiteralPath $BitmapMetadata)) {
  throw "Bitmap metadata not found: $BitmapMetadata. Run tools\export-bitmap-metadata.ps1 first."
}
if (-not (Test-Path -LiteralPath $PreviewManifest)) {
  throw "Preview manifest not found: $PreviewManifest. Run tools\export-bitd-previews.ps1 first."
}
if (-not (Test-Path -LiteralPath $TransparentManifest)) {
  throw "Transparent manifest not found: $TransparentManifest. Run tools\export-bitd-transparent-assets.ps1 first."
}

$metadata = @(Import-Csv -LiteralPath $BitmapMetadata)
$previews = @(Import-Csv -LiteralPath $PreviewManifest)
$transparent = @(Import-Csv -LiteralPath $TransparentManifest)

$metaByCast = @{}
foreach ($meta in $metadata) {
  $metaByCast[$meta.Index] = $meta
}

$transparentByKey = @{}
foreach ($asset in $transparent) {
  $transparentByKey["$($asset.CastIndex):$($asset.BitdIndex)"] = $asset.Png
}

$castCounts = @{}
$bitdCounts = @{}
$hashesByCast = @{}
$hashByPreviewKey = @{}

foreach ($preview in $previews) {
  $castCounts[$preview.CastIndex] = 1 + $castCounts[$preview.CastIndex]
  $bitdCounts[$preview.BitdIndex] = 1 + $bitdCounts[$preview.BitdIndex]

  $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $preview.Png).Hash
  $hashByPreviewKey["$($preview.CastIndex):$($preview.BitdIndex)"] = $hash

  if (-not $hashesByCast.ContainsKey($preview.CastIndex)) {
    $hashesByCast[$preview.CastIndex] = @{}
  }
  $hashesByCast[$preview.CastIndex][$hash] = $true
}

$rows = @()
foreach ($preview in $previews) {
  $meta = $metaByCast[$preview.CastIndex]
  $name = $preview.Name
  $width = [int]$preview.Width
  $height = [int]$preview.Height
  $bitdIndex = [int]$preview.BitdIndex
  $castIndex = [int]$preview.CastIndex
  $key = "$($preview.CastIndex):$($preview.BitdIndex)"
  $hash = $hashByPreviewKey[$key]
  $castUniqueHashCount = if ($hashesByCast.ContainsKey($preview.CastIndex)) { $hashesByCast[$preview.CastIndex].Count } else { 0 }
  $castCandidateCount = [int]$castCounts[$preview.CastIndex]
  $bitdCandidateCount = [int]$bitdCounts[$preview.BitdIndex]
  $transparentPng = if ($transparentByKey.ContainsKey($key)) { $transparentByKey[$key] } else { "" }

  $initialLeft = if ($meta) { [int]$meta.InitialLeft } else { 0 }
  $initialTop = if ($meta) { [int]$meta.InitialTop } else { 0 }
  $regX = if ($meta) { [int]$meta.RegX } else { 0 }
  $regY = if ($meta) { [int]$meta.RegY } else { 0 }

  $rows += [pscustomobject]@{
    AssetClass = Get-AssetClass $name $width $height
    Status = Get-CandidateStatus $castCandidateCount $bitdCandidateCount $castUniqueHashCount
    CastIndex = $castIndex
    CastSlot = $preview.CastSlot
    Name = $name
    Width = $width
    Height = $height
    Pitch = $preview.Pitch
    BitdIndex = $bitdIndex
    RegX = $regX
    RegY = $regY
    InitialLeft = $initialLeft
    InitialTop = $initialTop
    AnchorX = $regX - $initialLeft
    AnchorY = $regY - $initialTop
    CastCandidateCount = $castCandidateCount
    BitdCandidateCount = $bitdCandidateCount
    CastUniqueHashCount = $castUniqueHashCount
    PngSha256 = $hash
    PreviewPng = $preview.Png
    TransparentPng = $transparentPng
  }
}

$rows | Sort-Object AssetClass,Name,CastIndex,BitdIndex | Export-Csv -LiteralPath $OutPath -NoTypeInformation

"Asset catalog rows: $($rows.Count)"
"Output: $OutPath"
""
$rows |
  Group-Object AssetClass,Status |
  Sort-Object Name |
  Select-Object Name,Count |
  Format-Table -AutoSize

""
"Gameplay-facing assets"
$rows |
  Where-Object { $_.AssetClass -in @("green-sprite", "red-sprite", "projectile", "shadow", "effect", "ui-power", "background") } |
  Sort-Object AssetClass,Name,CastIndex,BitdIndex |
  Format-Table AssetClass,Status,CastIndex,Name,Width,Height,BitdIndex,AnchorX,AnchorY -AutoSize
