param(
  [string]$ResourceManifest = "reverse\resources\manifest.csv",
  [string]$OutPath = "reverse\lingo-strings.csv"
)

$ErrorActionPreference = "Stop"

function Get-AsciiStrings {
  param([byte[]]$Bytes)

  $text = [Text.Encoding]::ASCII.GetString($Bytes)
  [regex]::Matches($text, "[ -~]{3,}") | ForEach-Object {
    [pscustomobject]@{
      Offset = $_.Index
      Encoding = "ascii"
      Value = $_.Value
    }
  }
}

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
        Encoding = "pascal"
        Value = [Text.Encoding]::ASCII.GetString($Bytes, $pos + 1, $len)
      }
    }
  }
}

if (-not (Test-Path -LiteralPath $ResourceManifest)) {
  throw "Resource manifest not found: $ResourceManifest. Run tools\export-director-resources.ps1 first."
}

$resources = Import-Csv -LiteralPath $ResourceManifest
$scriptLike = @($resources | Where-Object { $_.Type -in @("Lnam", "Lctx", "Lscr", "STXT") } | Sort-Object {[int]$_.Index})
$rows = @()

foreach ($resource in $scriptLike) {
  $bytes = [IO.File]::ReadAllBytes($resource.File)
  $seen = @{}
  $items = @()
  $items += @(Get-AsciiStrings $bytes)
  $items += @(Get-PascalStrings $bytes)

  foreach ($item in ($items | Sort-Object Offset,Encoding,Value)) {
    $value = $item.Value.Trim()
    if (-not $value -or $value -match "^\?+$") {
      continue
    }

    $key = "{0}:{1}:{2}" -f $item.Offset, $item.Encoding, $value
    if ($seen.ContainsKey($key)) {
      continue
    }
    $seen[$key] = $true

    $rows += [pscustomobject]@{
      ResourceIndex = $resource.Index
      Type = $resource.Type
      Relative = $resource.Relative
      Offset = "0x{0:X}" -f $item.Offset
      Encoding = $item.Encoding
      Value = $value
      File = $resource.File
    }
  }
}

$rows | Export-Csv -LiteralPath $OutPath -NoTypeInformation

"Lingo/script string rows: $($rows.Count)"
"Output: $OutPath"
""
$rows | Sort-Object Type,{[int]$_.ResourceIndex},Value | Format-Table ResourceIndex,Type,Offset,Encoding,Value -AutoSize
