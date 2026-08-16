param(
  [string]$DirPath = "reverse\Snowcraft.embedded.dir",
  [string]$OutDir = "reverse\resources",
  [Nullable[int]]$OriginalOffset = $null
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

function Get-AsciiStrings {
  param([byte[]]$Bytes, [int]$Start, [int]$Count)

  $end = [Math]::Min($Start + $Count, $Bytes.Length)
  $slice = New-Object byte[] ($end - $Start)
  [Array]::Copy($Bytes, $Start, $slice, 0, $slice.Length)
  $text = [Text.Encoding]::ASCII.GetString($slice)

  [regex]::Matches($text, "[ -~]{4,}") |
    ForEach-Object { $_.Value } |
    Where-Object { $_ -notmatch "^\?+$" }
}

function Sanitize-Name {
  param([string]$Value)
  $safe = $Value -replace "[^A-Za-z0-9_. -]", "_"
  $safe.Trim() -replace "\s+", "_"
}

function Read-ResourceEntries {
  param([byte[]]$Bytes, [pscustomobject]$MapChunk, [int64]$BaseOffset)

  $entryStart = $MapChunk.Offset + 8 + 12
  $parsed = @()

  for ($pos = $entryStart; $pos + 20 -le $MapChunk.End; $pos += 20) {
    $stored = Read-FourCC $Bytes $pos
    if (-not (Test-PrintableFourCC $stored)) {
      continue
    }

    $type = Reverse-FourCC $stored
    $size = Read-U32 $Bytes ($pos + 4)
    $absolute = Read-U32 $Bytes ($pos + 8)
    $relative = [int64]$absolute - $BaseOffset

    if ($relative -lt 0 -or $relative -ge $Bytes.Length) {
      continue
    }

    $parsed += [pscustomobject]@{
      Index = [int](($pos - $entryStart) / 20)
      Stored = $stored
      Type = $type
      Size = $size
      AbsoluteDecimal = $absolute
      RelativeDecimal = $relative
    }
  }

  return $parsed
}

if (-not (Test-Path -LiteralPath $DirPath)) {
  throw "Input file not found: $DirPath. Run tools\extract-director-movie.ps1 first."
}

$bytes = [IO.File]::ReadAllBytes($DirPath)
if ($bytes.Length -lt 16 -or (Read-FourCC $bytes 0) -ne "XFIR") {
  throw "Expected an extracted little-endian Director XFIR payload."
}

if ($null -eq $OriginalOffset) {
  if ((Read-FourCC $bytes 12) -eq "pami") {
    $mmapAbsolute = Read-U32 $bytes 24
    $OriginalOffset = $mmapAbsolute - 0x2C
  } else {
    $OriginalOffset = 0
  }
}

$pammChunks = @()
for ($pos = 0; $pos + 8 -le $bytes.Length; $pos++) {
  if ((Read-FourCC $bytes $pos) -ne "pamm") {
    continue
  }
  $size = Read-U32 $bytes ($pos + 4)
  if ($size -gt 0 -and $pos + 8 + $size -le $bytes.Length) {
    $pammChunks += [pscustomobject]@{
      Offset = $pos
      Size = $size
      End = $pos + 8 + $size
    }
  }
}

if (-not $pammChunks.Count) {
  throw "No pamm/mmap chunks found."
}

$selected = $null
foreach ($candidate in $pammChunks) {
  $candidateEntries = @(Read-ResourceEntries $bytes $candidate $OriginalOffset)
  if ($null -eq $selected -or $candidateEntries.Count -gt $selected.Entries.Count) {
    $selected = [pscustomobject]@{
      Chunk = $candidate
      Entries = $candidateEntries
    }
  }
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$manifest = @()
foreach ($entry in ($selected.Entries | Sort-Object RelativeDecimal)) {
  $resourceStart = [int]$entry.RelativeDecimal
  $resourceLength = [Math]::Min([int]$entry.Size + 8, $bytes.Length - $resourceStart)
  if ($resourceLength -le 0) {
    continue
  }

  $typeDir = Join-Path $OutDir (Sanitize-Name $entry.Type)
  New-Item -ItemType Directory -Path $typeDir -Force | Out-Null

  $fileName = "{0:D4}_{1}_rel-{2:X}_size-{3}.bin" -f $entry.Index, (Sanitize-Name $entry.Type), $entry.RelativeDecimal, $entry.Size
  $filePath = Join-Path $typeDir $fileName

  $resourceBytes = New-Object byte[] $resourceLength
  [Array]::Copy($bytes, $resourceStart, $resourceBytes, 0, $resourceLength)
  [IO.File]::WriteAllBytes($filePath, $resourceBytes)

  $strings = @(Get-AsciiStrings $bytes $resourceStart $resourceLength | Select-Object -First 8)

  $manifest += [pscustomobject]@{
    Index = $entry.Index
    Type = $entry.Type
    Stored = $entry.Stored
    Size = $entry.Size
    Absolute = "0x{0:X}" -f $entry.AbsoluteDecimal
    Relative = "0x{0:X}" -f $entry.RelativeDecimal
    File = $filePath
    Strings = ($strings -join " | ")
  }
}

$manifestPath = Join-Path $OutDir "manifest.csv"
$manifest | Export-Csv -LiteralPath $manifestPath -NoTypeInformation

[pscustomobject]@{
  Input = $DirPath
  OutputDirectory = $OutDir
  Manifest = $manifestPath
  OriginalOffset = "0x{0:X}" -f $OriginalOffset
  ResourceMapOffset = "0x{0:X}" -f $selected.Chunk.Offset
  ResourceMapSize = $selected.Chunk.Size
  ExportedResources = $manifest.Count
}
