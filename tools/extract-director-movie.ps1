param(
  [string]$ExePath = "EXE\Snowcraft.exe",
  [string]$OutPath = "reverse\Snowcraft.embedded.dir"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ExePath)) {
  throw "Input file not found: $ExePath"
}

$bytes = [IO.File]::ReadAllBytes($ExePath)
$needle = [Text.Encoding]::ASCII.GetBytes("XFIR")
$candidateOffset = $null
$candidateSize = $null

for ($i = 0; $i -le $bytes.Length - $needle.Length - 8; $i++) {
  $matches = $true
  for ($j = 0; $j -lt $needle.Length; $j++) {
    if ($bytes[$i + $j] -ne $needle[$j]) {
      $matches = $false
      break
    }
  }

  if (-not $matches) {
    continue
  }

  $size = [BitConverter]::ToUInt32($bytes, $i + 4)
  if (($i + 12 + $size) -eq $bytes.Length) {
    $candidateOffset = $i
    $candidateSize = $size
    break
  }
}

if ($null -eq $candidateOffset) {
  throw "Could not find an XFIR Director payload that ends at EOF."
}

$outDir = Split-Path -Parent $OutPath
if ($outDir) {
  New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$payload = New-Object byte[] ($bytes.Length - $candidateOffset)
[Array]::Copy($bytes, $candidateOffset, $payload, 0, $payload.Length)
[IO.File]::WriteAllBytes($OutPath, $payload)

[pscustomobject]@{
  Input = $ExePath
  Output = $OutPath
  OffsetDecimal = $candidateOffset
  OffsetHex = "0x{0:X}" -f $candidateOffset
  PayloadSize = $payload.Length
  DirectorPayloadSize = $candidateSize
  Sha256 = (Get-FileHash -LiteralPath $OutPath -Algorithm SHA256).Hash
}
