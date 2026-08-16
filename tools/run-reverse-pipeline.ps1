param(
  [string]$ExePath = "EXE\Snowcraft.exe"
)

$ErrorActionPreference = "Stop"

$steps = @(
  @{ Name = "Extract embedded Director movie"; Script = "tools\extract-director-movie.ps1"; UseExePath = $true },
  @{ Name = "Inspect Director resource map"; Script = "tools\inspect-director-resources.ps1" },
  @{ Name = "Export raw Director resources"; Script = "tools\export-director-resources.ps1" },
  @{ Name = "Export cast index"; Script = "tools\export-cast-index.ps1" },
  @{ Name = "Export bitmap metadata"; Script = "tools\export-bitmap-metadata.ps1" },
  @{ Name = "Export key map"; Script = "tools\export-key-map.ps1" },
  @{ Name = "Export Lingo strings"; Script = "tools\export-lingo-strings.ps1" },
  @{ Name = "Export Lingo bytecode summary"; Script = "tools\export-lingo-bytecode-summary.ps1" },
  @{ Name = "Analyze Lingo control flow"; Script = "tools\export-lingo-control-flow-analysis.ps1" },
  @{ Name = "Export Lingo control-flow graphs"; Script = "tools\export-lingo-control-flow-graphs.ps1" },
  @{ Name = "Export structured Lingo pseudocode"; Script = "tools\export-lingo-structured-pseudocode.ps1" },
  @{ Name = "Export Lingo state transitions"; Script = "tools\export-lingo-state-transitions.ps1" },
  @{ Name = "Export raw sound WAVs"; Script = "tools\export-director-sounds.ps1" },
  @{ Name = "Export sound cast metadata"; Script = "tools\export-sound-cast-metadata.ps1" },
  @{ Name = "Export sound map"; Script = "tools\export-sound-map.ps1" },
  @{ Name = "Export bitmap preview PNGs"; Script = "tools\export-bitd-previews.ps1" },
  @{ Name = "Export transparent sprite PNGs"; Script = "tools\export-bitd-transparent-assets.ps1" },
  @{ Name = "Export asset catalog"; Script = "tools\export-asset-catalog.ps1" },
  @{ Name = "Export score timeline"; Script = "tools\export-score-timeline.ps1" },
  @{ Name = "Export cast member map"; Script = "tools\export-cast-member-map.ps1" }
)

foreach ($step in $steps) {
  if (-not (Test-Path -LiteralPath $step.Script)) {
    throw "Missing pipeline step script: $($step.Script)"
  }

  ""
  "== $($step.Name) =="
  if ($step.UseExePath) {
    & $step.Script -ExePath $ExePath
  } else {
    & $step.Script
  }
}

""
"Reverse pipeline complete."
"Generated outputs are under reverse\ and are ignored by git."
