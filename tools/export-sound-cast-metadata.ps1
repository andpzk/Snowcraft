param(
  [string]$CastIndex = "reverse\cast-index.csv",
  [string]$OutPath = "reverse\sound-cast-metadata.csv"
)

$ErrorActionPreference = "Stop"

function Get-PascalStrings {
  param([byte[]]$Bytes)

  for ($pos = 0; $pos -lt $Bytes.Length; $pos++) {
    $len = $Bytes[$pos]
    if ($len -lt 3 -or $len -gt 80 -or $pos + 1 + $len -gt $Bytes.Length) {
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
      [pscustomobject]@{
        Offset = $pos
        Value = [Text.Encoding]::ASCII.GetString($Bytes, $pos + 1, $len)
      }
    }
  }
}

function Read-BigU16 {
  param([byte[]]$Bytes, [int]$Offset)
  (([int]$Bytes[$Offset] -shl 8) -bor [int]$Bytes[$Offset + 1])
}

if (-not (Test-Path -LiteralPath $CastIndex)) {
  throw "Cast index not found: $CastIndex. Run tools\export-cast-index.ps1 first."
}

$casts = @(Import-Csv -LiteralPath $CastIndex | Where-Object Kind -eq "sound")
$rows = @()

foreach ($cast in $casts) {
  $bytes = [IO.File]::ReadAllBytes($cast.File)
  $strings = @(Get-PascalStrings $bytes | Select-Object -ExpandProperty Value)
  $format = ($strings | Where-Object { $_ -match "^kMoaCfFormat_" } | Select-Object -First 1)
  $names = @($strings | Where-Object { $_ -notmatch "^kMoaCfFormat_" -and $_ -ne "tSAC" })
  $displayName = if ($names.Count) { $names[0] } else { $cast.Name }

  $nameMetricValues = @()
  for ($offset = 0x40; $offset + 2 -le $bytes.Length -and $offset -le 0x74; $offset += 4) {
    $nameMetricValues += Read-BigU16 $bytes $offset
  }
  $nameMetric = ""
  if ($nameMetricValues.Count) {
    $nameMetric = ($nameMetricValues | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name
  }

  $rows += [pscustomobject]@{
    CastIndex = $cast.Index
    CastSlot = $cast.CastSlot
    Name = $displayName
    Format = $format
    NameMetric = $nameMetric
    NameLength = if ($displayName) { $displayName.Length } else { "" }
    Names = ($strings -join " | ")
    Relative = $cast.Relative
    File = $cast.File
  }
}

$rows | Export-Csv -LiteralPath $OutPath -NoTypeInformation

"Sound cast rows: $($rows.Count)"
"Output: $OutPath"
""
$rows | Sort-Object Name,CastIndex | Format-Table CastIndex,CastSlot,Name,Format,NameMetric,NameLength,Relative -AutoSize
