param(
  [string]$ManifestPath = "reverse\resources\manifest.csv",
  [string]$OutPath = "reverse\cast-index.csv"
)

$ErrorActionPreference = "Stop"

function Get-PascalStrings {
  param([byte[]]$Bytes)

  $items = @()
  for ($pos = 0; $pos -lt $Bytes.Length; $pos++) {
    $len = $Bytes[$pos]
    if ($len -lt 3 -or $len -gt 40 -or $pos + 1 + $len -gt $Bytes.Length) {
      continue
    }

    $ok = $true
    for ($i = 0; $i -lt $len; $i++) {
      $code = $Bytes[$pos + 1 + $i]
      if ($code -lt 32 -or $code -gt 126) {
        $ok = $false
        break
      }
    }

    if ($ok) {
      $items += [pscustomobject]@{
        Offset = $pos
        Value = [Text.Encoding]::ASCII.GetString($Bytes, $pos + 1, $len)
      }
    }
  }

  $items
}

function Read-BigU32 {
  param([byte[]]$Bytes, [int]$Offset)
  (([int]$Bytes[$Offset] -shl 24) -bor ([int]$Bytes[$Offset + 1] -shl 16) -bor ([int]$Bytes[$Offset + 2] -shl 8) -bor [int]$Bytes[$Offset + 3])
}

function Guess-CastKind {
  param([string[]]$Names)

  $joined = $Names -join " "
  if ($joined -match "kMoaCfFormat_snd|kMoaCfFormat_AIFF") {
    return "sound"
  }
  foreach ($name in $Names) {
    if ($name -in @("Whoosh", "Whoosh Percusive", "kids1", "kids2", "kids3", "hit1", "hit2", "splat", "laugh", "Ahhhh!", "bird_tweets", "short_chirps")) {
      return "sound"
    }
  }
  if ($joined -match "SCRIPT|movie script") {
    return "script"
  }
  if ($joined -match "Palette|palatte|snowcraft_256|Snowball|snowball|G Hit|R hit|dead|windup|rest|drop") {
    return "visual"
  }
  return "unknown"
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw "Manifest not found: $ManifestPath. Run tools\export-director-resources.ps1 first."
}

$manifest = Import-Csv -LiteralPath $ManifestPath
$castSlotByResourceIndex = @{}
$casRows = @($manifest | Where-Object Type -eq "CAS*" | Sort-Object {[int]$_.Index})

foreach ($cas in $casRows) {
  $bytes = [IO.File]::ReadAllBytes($cas.File)
  $count = [Math]::Floor(([int]$cas.Size) / 4)
  for ($slot = 0; $slot -lt $count; $slot++) {
    $offset = 8 + ($slot * 4)
    if ($offset + 4 -gt $bytes.Length) {
      break
    }

    $castResourceIndex = Read-BigU32 $bytes $offset
    if ($castResourceIndex -ne 0 -and -not $castSlotByResourceIndex.ContainsKey([int]$castResourceIndex)) {
      $castSlotByResourceIndex[[int]$castResourceIndex] = $slot
    }
  }
}

$castRows = @($manifest | Where-Object Type -eq "CASt" | Sort-Object {[int]$_.Index})
$index = @()

foreach ($row in $castRows) {
  $bytes = [IO.File]::ReadAllBytes($row.File)
  $resourceIndex = [int]$row.Index
  $castMemberId = if ($castSlotByResourceIndex.ContainsKey($resourceIndex)) { $castSlotByResourceIndex[$resourceIndex] } else { "" }
  $pascal = @(Get-PascalStrings $bytes)
  $names = @($pascal.Value | Where-Object {
    $_ -notmatch "^tSAC" -and
    $_ -notmatch "^[A-Za-z]{4}$" -and
    $_ -notmatch "^\?+$"
  } | Select-Object -Unique)

  $displayName = ""
  if ($names.Count) {
    $displayName = ($names | Where-Object { $_ -ne "kMoaCfFormat_snd" } | Select-Object -First 1)
    if (-not $displayName) {
      $displayName = $names[0]
    }
  }

  $index += [pscustomobject]@{
    Index = $row.Index
    CastMemberId = $castMemberId
    CastSlot = $castMemberId
    Kind = Guess-CastKind $names
    Name = $displayName
    Names = ($names -join " | ")
    Size = $row.Size
    Relative = $row.Relative
    File = $row.File
  }
}

$index | Export-Csv -LiteralPath $OutPath -NoTypeInformation

"Cast entries: $($index.Count)"
"Output: $OutPath"
""
"Named cast members"
$index | Where-Object Name | Sort-Object Kind,Name | Format-Table Index,CastSlot,Kind,Name,Relative -AutoSize
