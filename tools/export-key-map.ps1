param(
  [string]$ResourceManifest = "reverse\resources\manifest.csv",
  [string]$CastIndex = "reverse\cast-index.csv",
  [string]$OutPath = "reverse\key-map.csv"
)

$ErrorActionPreference = "Stop"

function Read-U32 {
  param([byte[]]$Bytes, [int]$Offset)
  [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Read-FourCC {
  param([byte[]]$Bytes, [int]$Offset)
  [Text.Encoding]::ASCII.GetString($Bytes, $Offset, 4)
}

function Reverse-FourCC {
  param([string]$Stored)
  if ($Stored.Length -ne 4) {
    return $Stored
  }
  -join @($Stored[3], $Stored[2], $Stored[1], $Stored[0])
}

function Test-PrintableFourCC {
  param([string]$Value)
  if ($Value.Length -ne 4) {
    return $false
  }
  foreach ($ch in $Value.ToCharArray()) {
    $code = [int][char]$ch
    if ($code -lt 32 -or $code -gt 126) {
      return $false
    }
  }
  return $true
}

if (-not (Test-Path -LiteralPath $ResourceManifest)) {
  throw "Resource manifest not found: $ResourceManifest"
}
if (-not (Test-Path -LiteralPath $CastIndex)) {
  throw "Cast index not found: $CastIndex. Run tools\export-cast-index.ps1 first."
}

$resources = Import-Csv -LiteralPath $ResourceManifest
$casts = Import-Csv -LiteralPath $CastIndex
$key = $resources | Where-Object Type -eq "KEY*" | Select-Object -First 1
if (-not $key) {
  throw "No KEY* resource found in $ResourceManifest"
}

$resourceByIndex = @{}
foreach ($resource in $resources) {
  $resourceByIndex[[int]$resource.Index] = $resource
}

$castByResourceIndex = @{}
foreach ($cast in $casts) {
  if ($cast.Index -ne "") {
    $castByResourceIndex[[int]$cast.Index] = $cast
  }
}

$bytes = [IO.File]::ReadAllBytes($key.File)
$rows = @()

# Resource dumps include the 8-byte KEY* resource header. The KEY* body then
# starts with 2 uint16 sizes and 2 uint32 counts; entries begin at byte 20.
$entrySize = [BitConverter]::ToUInt16($bytes, 8)
$entrySize2 = [BitConverter]::ToUInt16($bytes, 10)
$entryCount = Read-U32 $bytes 12
$usedCount = Read-U32 $bytes 16

if ($entrySize -lt 12) {
  throw "Unexpected KEY* entry size: $entrySize"
}

for ($entry = 0; $entry -lt $usedCount; $entry++) {
  $pos = 20 + ($entry * $entrySize)
  if ($pos + 12 -gt $bytes.Length) {
    break
  }

  $childIndex = [int](Read-U32 $bytes $pos)
  $parentIndex = [int](Read-U32 $bytes ($pos + 4))
  $stored = Read-FourCC $bytes ($pos + 8)
  if (-not (Test-PrintableFourCC $stored)) {
    continue
  }

  $type = Reverse-FourCC $stored
  $childResource = $resourceByIndex[$childIndex]
  $parentCast = $castByResourceIndex[$parentIndex]
  $reversedParentCast = $castByResourceIndex[$childIndex]

  $relation = "none"
  $cast = $null
  if ($parentCast) {
    $relation = "parent-is-CASt"
    $cast = $parentCast
  } elseif ($reversedParentCast) {
    $relation = "child-is-CASt"
    $cast = $reversedParentCast
  }

  $rows += [pscustomobject]@{
    Entry = $entry
    ChildType = $type
    ChildIndex = $childIndex
    ParentIndex = $parentIndex
    ChildResourceType = if ($childResource) { $childResource.Type } else { "" }
    ChildResourceRelative = if ($childResource) { $childResource.Relative } else { "" }
    ChildResourceSize = if ($childResource) { $childResource.Size } else { "" }
    ChildResourceFile = if ($childResource) { $childResource.File } else { "" }
    Relation = $relation
    CastIndex = if ($cast) { $cast.Index } else { "" }
    CastSlot = if ($cast) { $cast.CastSlot } else { "" }
    CastKind = if ($cast) { $cast.Kind } else { "" }
    CastName = if ($cast) { $cast.Name } else { "" }
    CastRelative = if ($cast) { $cast.Relative } else { "" }
  }
}

$rows | Export-Csv -LiteralPath $OutPath -NoTypeInformation

"KEY entries: $($rows.Count)"
"Entry size: $entrySize / $entrySize2"
"Declared entries: $entryCount"
"Used entries: $usedCount"
"Output: $OutPath"
""
"Named mappings"
$rows | Where-Object CastName | Sort-Object CastKind,CastName,ChildType | Format-Table ChildType,ChildIndex,ParentIndex,Relation,CastIndex,CastSlot,CastKind,CastName -AutoSize
