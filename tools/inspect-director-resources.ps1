param(
  [string]$DirPath = "reverse\Snowcraft.embedded.dir",
  [Nullable[int]]$OriginalOffset = $null,
  [int]$FirstEntries = 40,
  [int]$FirstNames = 120
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

function Get-LengthPrefixedNames {
  param([byte[]]$Bytes, [int]$Start, [int]$End)

  $best = @()
  $bestStart = $Start
  $maxProbe = [Math]::Min($Start + 96, $End)

  for ($probe = $Start; $probe -lt $maxProbe; $probe++) {
    $pos = $probe
    $names = @()

    while ($pos -lt $End) {
      $len = $Bytes[$pos]
      if ($len -lt 1 -or $len -gt 40 -or $pos + 1 + $len -gt $End) {
        break
      }

      $ok = $true
      for ($i = 0; $i -lt $len; $i++) {
        $code = $Bytes[$pos + 1 + $i]
        if ($code -lt 32 -or $code -gt 126) {
          $ok = $false
          break
        }
      }
      if (-not $ok) {
        break
      }

      $names += [Text.Encoding]::ASCII.GetString($Bytes, $pos + 1, $len)
      $pos += 1 + $len
    }

    if ($names.Count -gt $best.Count) {
      $best = $names
      $bestStart = $probe
    }
  }

  [pscustomobject]@{
    Offset = $bestStart
    Names = $best
  }
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

function Read-ResourceEntries {
  param([pscustomobject]$MapChunk)

  $entryStart = $MapChunk.Offset + 8 + 12
  $parsed = @()

  for ($pos = $entryStart; $pos + 20 -le $MapChunk.End; $pos += 20) {
    $stored = Read-FourCC $bytes $pos
    if (-not (Test-PrintableFourCC $stored)) {
      continue
    }

    $type = Reverse-FourCC $stored
    $size = Read-U32 $bytes ($pos + 4)
    $absolute = Read-U32 $bytes ($pos + 8)
    $relative = [int64]$absolute - [int64]$OriginalOffset

    if ($relative -lt 0 -or $relative -ge $bytes.Length) {
      continue
    }

    $parsed += [pscustomobject]@{
      Index = (($pos - $entryStart) / 20)
      Stored = $stored
      Type = $type
      Size = $size
      Absolute = "0x{0:X}" -f $absolute
      Relative = "0x{0:X}" -f $relative
      RelativeDecimal = $relative
    }
  }

  return $parsed
}

$mapCandidates = @()
foreach ($candidate in $pammChunks) {
  $candidateEntries = @(Read-ResourceEntries $candidate)
  $mapCandidates += [pscustomobject]@{
    Chunk = $candidate
    Entries = $candidateEntries
    Count = $candidateEntries.Count
  }
}

$selected = $mapCandidates | Sort-Object Count -Descending | Select-Object -First 1
$resourceMap = $selected.Chunk
$entries = $selected.Entries

"Director payload: $DirPath"
"Original offset: 0x{0:X}" -f $OriginalOffset
"Resource pamm: offset 0x{0:X}, size {1}" -f $resourceMap.Offset, $resourceMap.Size
""
"Resource type summary"
$entries | Group-Object Type | Sort-Object Count -Descending | Select-Object Count,Name | Format-Table -AutoSize

"First resource entries"
$entries | Sort-Object RelativeDecimal | Select-Object -First $FirstEntries Index,Stored,Type,Size,Absolute,Relative | Format-Table -AutoSize

$key = $entries | Where-Object Type -eq "KEY*" | Select-Object -First 1
if ($key) {
  $keyOffset = [Convert]::ToInt32($key.Relative.Substring(2), 16)
  $keySize = Read-U32 $bytes ($keyOffset + 4)
  $keyData = $keyOffset + 8
  $keyEntryStart = $keyData + 20
  $keyEnd = $keyOffset + 8 + $keySize
  $keyEntries = @()

  for ($pos = $keyEntryStart; $pos + 12 -le $keyEnd; $pos += 12) {
    $stored = Read-FourCC $bytes $pos
    if (-not (Test-PrintableFourCC $stored)) {
      continue
    }
    $keyEntries += [pscustomobject]@{
      Stored = $stored
      Type = Reverse-FourCC $stored
      ResourceId = Read-U32 $bytes ($pos + 4)
      CastId = Read-U32 $bytes ($pos + 8)
    }
  }

  ""
  "KEY* summary"
  $keyEntries | Group-Object Type | Sort-Object Count -Descending | Select-Object Count,Name | Format-Table -AutoSize
}

$lnam = $entries | Where-Object Type -eq "Lnam" | Select-Object -First 1
if ($lnam) {
  $lnamOffset = [Convert]::ToInt32($lnam.Relative.Substring(2), 16)
  $lnamSize = Read-U32 $bytes ($lnamOffset + 4)
  $namesResult = Get-LengthPrefixedNames $bytes ($lnamOffset + 8) ($lnamOffset + 8 + $lnamSize)

  ""
  "Lnam names (start 0x{0:X}, count {1})" -f $namesResult.Offset, $namesResult.Names.Count
  $namesResult.Names | Select-Object -First $FirstNames
}

$scripts = $entries | Where-Object Type -eq "Lscr" | Sort-Object RelativeDecimal
if ($scripts.Count) {
  ""
  "Lscr string hints"
  $scriptSummaries = @()
  $scriptIndex = 0
  foreach ($script in $scripts) {
    $scriptOffset = [Convert]::ToInt32($script.Relative.Substring(2), 16)
    $strings = @(Get-AsciiStrings $bytes $scriptOffset ([int]$script.Size + 8) | Select-Object -First 16)
    $scriptSummaries += [pscustomobject]@{
      Script = $scriptIndex
      Size = $script.Size
      Relative = $script.Relative
      Strings = ($strings -join " | ")
    }
    $scriptIndex++
  }
  $scriptSummaries | Format-List
}

$castRecords = $entries | Where-Object Type -eq "CASt" | Sort-Object RelativeDecimal
if ($castRecords.Count) {
  ""
  "CASt string hints"
  $castHints = @()
  foreach ($cast in $castRecords) {
    $castOffset = [Convert]::ToInt32($cast.Relative.Substring(2), 16)
    $strings = @(Get-AsciiStrings $bytes $castOffset ([int]$cast.Size + 8) |
      Where-Object {
        $_ -match "kids|snow|hit|Level|Green|red|wind|rest|dead|Whoosh|drop|splat|SCRIPT|Palette|palatte"
      } |
      Select-Object -First 8)

    if ($strings.Count) {
      $castHints += [pscustomobject]@{
        Index = $cast.Index
        Size = $cast.Size
        Relative = $cast.Relative
        Strings = ($strings -join " | ")
      }
    }
  }
  $castHints | Select-Object -First 80 | Format-List
}
