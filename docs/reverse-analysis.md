# Snowcraft Reverse Analysis

This note captures the current evidence from the bundled Snowcraft Windows
projector.

## Source Artifact

- File: `EXE/Snowcraft.exe`
- Size: `2,071,847` bytes
- SHA-256: `93AD8B3AE0098063A59ECB9D4784D6222778E52C7C5F1D18238992842BA02ED6`
- Format: Windows PE executable
- Product metadata: `Macromedia Director`
- File description: `Projector Skeleton`
- File version: `6.5r1`
- Product version: `6.5`
- Original filename: `Projectr.skl`
- Copyright metadata: `Copyright (c) 1985-1997 Macromedia, Inc.`

## Director Evidence

The executable is a Macromedia Director 6.5 projector, not a Flash/SWF movie.
ASCII string extraction found Director resource names including:

- `Director 6.0 Movie`
- `Director 6.0 Script`
- `Director 6.0 Score`
- `Director 6.0 Cast`
- `Director 6.0 Sound`
- `Director 6.0 Bitmap Info`
- `Director 6.0 Xtra CastMember`
- `Projector`

The PE section table ends at offset `1,258,496`, while the file is `2,071,847`
bytes long. That leaves an appended overlay of `813,351` bytes.

Inside that overlay, a Director container starts at offset `0x16DD33`
(`1,498,419` decimal). Its length runs exactly to the end of the executable:

```text
0x16DD33 + 12 + 0x08BFE8 = 0x1F9D27
```

`0x1F9D27` is the full executable size, so this is the embedded movie payload.
Use `tools/extract-director-movie.ps1` to extract it reproducibly:

```powershell
powershell -ExecutionPolicy Bypass -File tools/extract-director-movie.ps1
```

Then inspect the Director resource map:

```powershell
powershell -ExecutionPolicy Bypass -File tools/inspect-director-resources.ps1
```

Run the full reproducible reverse-export pipeline:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run-reverse-pipeline.ps1
```

Or run individual export steps:

```powershell
powershell -ExecutionPolicy Bypass -File tools/export-director-resources.ps1
powershell -ExecutionPolicy Bypass -File tools/export-cast-index.ps1
powershell -ExecutionPolicy Bypass -File tools/export-bitmap-metadata.ps1
powershell -ExecutionPolicy Bypass -File tools/export-key-map.ps1
powershell -ExecutionPolicy Bypass -File tools/export-lingo-strings.ps1
powershell -ExecutionPolicy Bypass -File tools/export-lingo-bytecode-summary.ps1
powershell -ExecutionPolicy Bypass -File tools/export-director-sounds.ps1
powershell -ExecutionPolicy Bypass -File tools/export-sound-cast-metadata.ps1
powershell -ExecutionPolicy Bypass -File tools/export-sound-map.ps1
powershell -ExecutionPolicy Bypass -File tools/export-bitd-previews.ps1
powershell -ExecutionPolicy Bypass -File tools/export-bitd-transparent-assets.ps1
powershell -ExecutionPolicy Bypass -File tools/export-asset-catalog.ps1
powershell -ExecutionPolicy Bypass -File tools/export-score-timeline.ps1
powershell -ExecutionPolicy Bypass -File tools/export-cast-member-map.ps1
```

The generated `reverse/Snowcraft.embedded.dir` file is ignored by git because it
is derived from `EXE/Snowcraft.exe`.

Current extracted payload:

- Size: `573,428` bytes
- SHA-256: `DC4B8D8E2D6553B8B9658DB96485D5B4C70794F7CE1996D2A620AE81889A80D3`

## Initial Chunk Map

The embedded Director data uses little-endian/reversed FourCC markers. For
example, `XFIR` corresponds to `RIFX`, `pami` to `imap`, `pamm` to `mmap`, and
`*YEK` to `KEY*`.

The first visible chunks at `0x16DD33` are:

```text
Offset     Stored  Likely  Size
0x16DD3F   pami    imap    24
0x16DD5F   pamm    mmap    144
0x16DDF7   tsiL    List    28
0x16DE1B   tciD    Dict    122
0x16DE9D   XFIR    RIFX    573054
```

Another nested area around `0x17B565` contains markers such as `*YEK`, `FCRD`,
`pmXF`, and `LsCM`, which is consistent with Director resource-map data rather
than native Windows code.

## Resource Map

`tools/inspect-director-resources.ps1` parses the inner `pamm` resource map at
offset `0x1DE`. The current type summary is:

```text
107 CASt   cast member records
 75 BITD   bitmap data
 32 junk
 15 snd    sound records
 15 sndH   sound headers
 15 sndS   sound samples
 13 Lscr   Lingo script chunks
  1 KEY*   resource key
  1 Lnam   Lingo name table
  1 VWSC   score
  1 CLUT   palette
 1 STXT   styled text
```

`tools/export-director-resources.ps1` exports the parsed resources to
`reverse/resources/` and writes `reverse/resources/manifest.csv`. The current
export contains `287` resources.

The first resource entries include:

```text
Stored  Type  Size    Relative
*YEK    KEY*  9096    0xB516
FCRD    DRCF  84      0xD8A6
droS    Sord  448     0xD902
pmXF    FXmp  6847    0xDACA
LsCM    MCsL  58      0xF592
*SAC    CAS*  444     0xF5D4
```

The `KEY*` chunk uses a 12-byte body header after the 8-byte Director resource
header:

```text
entrySize:        12
entrySize2:       12
declared entries: 757
used entries:     133
```

`tools/export-key-map.ps1` writes those `133` used entries to
`reverse/key-map.csv` as `ChildIndex`, `ParentIndex`, and `ChildType`.
The table is useful, but it is not a complete one-to-one bitmap join for this
movie: several rows point at cast/resource ids that need Director-specific
interpretation. Treat it as relationship evidence, not as the final asset map.

## Bitmap Resources

`tools/export-bitmap-metadata.ps1` parses Director 6 bitmap `CASt` metadata and
writes `reverse/bitmap-metadata.csv`. Current bitmap metadata:

```text
75 bitmap cast members
75 BITD pixel-data resources
1 CLUT palette resource
8 bits per pixel
shared palette id 80
largest frames: 600x320
```

Important decoded bitmap names and dimensions:

```text
snowcraft_256       600x320
ground              600x320
snowcraft_key       203x31
G ready              25x36
G Walk H1            32x36
G Walk H2            30x36
G Walk V1            30x36
G Walk V2            27x34
G cock               34x35
G windup             24x31
G toss               24x34
R ready              26x34
R rest               24x33
R Auto walk_1        25x34
R Auto walk_2        31x35
R cock               63x49
R toss               63x51
snowball             11x42
shadow               36x21
power 0..8        up to 9x30
```

`tools/export-bitd-previews.ps1` decodes Director `BITD` RLE data with the CLUT
palette and writes PNG candidates to `reverse/bitd-previews/`. The current run
exports `87` candidate PNGs because some cast members share dimensions and have
ambiguous matches. Visual checks confirmed that these are valid:

```text
cast-0408_bitd-0409_snowcraft_256_600x320.png  snowfield background
cast-0408_bitd-0157_snowcraft_256_600x320.png  snowfield with mounds
cast-0372_bitd-0348_G_ready_25x36.png          green ready sprite
cast-0379_bitd-0339_R_toss_63x51.png           red toss sprite
cast-0186_bitd-0188_snowball_11x42.png         snowball plus shadow
cast-0117_bitd-0142_power_8_9x30.png           power meter frame
```

For sprite-like assets, palette index `0` behaves like the transparent matte:
green/red character frames, `snowball`, and `shadow` all have `0` in their four
corners and as the dominant border index. `tools/export-bitd-transparent-assets.ps1`
therefore writes transparent PNG sprite candidates to `reverse/bitd-transparent/`,
skipping the large `600x320` backgrounds where index `0` is real snow/white.

`tools/export-asset-catalog.ps1` joins bitmap metadata, preview PNGs, transparent
PNGs, hashes, dimensions, and Director registration points into
`reverse/asset-catalog.csv`. It computes local sprite anchors as:

```text
AnchorX = RegX - InitialLeft
AnchorY = RegY - InitialTop
```

This matters for any reconstruction because many sprites are not centered in
their bitmap rectangle. For example, `G ready` is `25x36` with anchor `(11,29)`,
placing the registration point near the feet rather than the visual center.
The catalog labels candidates as `unambiguous`, `reused-identical`, or
`ambiguous`; repeated same-size frames such as `G Hit`/`G Hit2` and
`R hit`/`R hit2` currently hash to identical PNG data, while some walk/ready
frames have multiple distinct candidates.

Detailed sprite/state mapping notes are tracked in
`docs/sprite-state-notes.md`.

The generated bitmap CSVs and PNGs are derived from `EXE/Snowcraft.exe` and are
ignored by git.

## Score Timeline

`tools/export-score-timeline.ps1` parses the Director 6 `VWSC` score resource
using the same high-level structure as ScummVM's Director engine: a D6 detail
index followed by frame records, where each frame applies partial channel
updates. It writes:

```text
reverse/score-summary.csv
reverse/score-labels.csv
reverse/score-frame-summary.csv
reverse/score-frame-sprites.csv
reverse/score-script-details.csv
reverse/cast-member-map.csv
```

Current score summary:

```text
Frames resource size:      141029
Score version raw:         0xFFFFFFFD
Detail entries:            9609
Detail list size:          9610
Frames stream size:        40782
Header frame count:        0
Parsed frame count:        166
Frames version:            11
Sprite record size:        24
Director channels:         126
Displayed sprite channels: 120
Max touched sprite channel: 60
```

Director stores `HeaderFrameCount` as `0` here, so the exporter follows the
actual frame stream and stops when the frame data ends. This matches ScummVM's
approach of precomputing the frame count because Director score headers are not
always reliable.

The `VWLB` label resource resolves to these frame markers:

```text
Frame 40   GreenWin
Frame 50   Level 2
Frame 70   Level 3
Frame 90   Level 4
Frame 110  Level 5
Frame 130  Level 6
```

The score data makes the movie structure clearer:

- The large `600x320` background is active across the parsed timeline.
- Early frames build up active sprite channels from a small intro/state setup
  into groups of green/red character sprites and shadows.
- Level markers are spaced roughly every 20 frames from `Level 2` onward.
- `score-frame-summary.csv` shows frame-level tempo/action/sound channel state.
- `score-frame-sprites.csv` shows per-frame active sprites with channel,
  cast member id, position, size, ink data, and sprite list id.
- `score-script-details.csv` joins frame action members to the D6 sprite detail
  table, exposing the frame script behavior member and initializer index.
- `cast-member-map.csv` parses `CAS*` as a Director cast slot table and helps
  distinguish score cast slots from raw resource indexes.

Detailed level/formation notes are tracked in
`docs/score-formation-notes.md`.

Current frame-script evidence:

```text
Frame 35   ActionMember 98   BehaviorMember 98   Initializer 7105
Frame 45   ActionMember 105  BehaviorMember 105  Initializer 0
Frame 50   ActionMember 95   BehaviorMember 95   Initializer 0   Level 2
Frame 65   ActionMember 98   BehaviorMember 98   Initializer 7106
Frame 70   ActionMember 95   BehaviorMember 95   Initializer 0   Level 3
Frame 85   ActionMember 98   BehaviorMember 98   Initializer 8280
Frame 90   ActionMember 95   BehaviorMember 95   Initializer 0   Level 4
Frame 105  ActionMember 98   BehaviorMember 98   Initializer 8290
Frame 110  ActionMember 95   BehaviorMember 95   Initializer 0   Level 5
Frame 125  ActionMember 98   BehaviorMember 98   Initializer 8300
Frame 130  ActionMember 95   BehaviorMember 95   Initializer 0   Level 6
Frame 161  ActionMember 98   BehaviorMember 98   Initializer 9020
```

The behavior members above should be treated as Director/Lingo cast-member
numbers, not raw `CASt` resource indexes. Several numeric values collide with
bitmap resource indexes such as `power 0`, so naming them by resource index
would be misleading.

Important caveat: the score stores Director cast member numbers, while the raw
resource files are numbered by Director resource index. The `CAS*` resource is
a 1-based Director member slot table:

```text
Score cast index N -> CAS*[N - 1] -> resource index
```

This direct mapping is useful but not complete: many score-used member slots
point at non-`CASt` resources such as `Lscr`, `junk`, `snd`, or `STXT`, or at
missing/empty slots. Therefore `score-frame-sprites.csv` keeps separate kinds
of naming evidence:

- `CastResolvedBy = cas-slot` means `CAS*` pointed to a named `CASt` resource.
- `DimensionCandidateNames` is only a size-based hint, useful for investigation
  but not proof. For example, many `36x21` score rows point at `shadow` by size,
  but that is not as strong as a cast-member-id join.
- `LegacyCastMemberIdHint` and `LegacyResourceIndexHint` are kept only as
  diagnostic hints; they should not be treated as proof.

Current reliable score sprite joins from `CAS*` are narrow but useful:

```text
Score cast index 4   -> CASt 358 -> G cock
Score cast index 18  -> CASt 372 -> G ready
```

Other important score-used slots currently resolve by dimension hints:

```text
Score cast index 1   mostly 36x21 -> shadow, but mixed/ambiguous
Score cast index 24  25x36        -> G ready
Score cast index 69  600x320      -> ground | snowcraft_256
Score cast index 71  203x31       -> snowcraft_key
```

## Visible Game Data

ASCII string extraction from `reverse/Snowcraft.embedded.dir` found useful
Director/Lingo-facing names:

```text
C:\WINNT\Profiles\wells\Desktop\snowcraft98\sc98_13.dir
snowball
snowcraft_key
snowcraft_palatte
snowcraft_256
snowcraft_256 Palette
kids3
kids2
kids1
repeat While soundBusy(1)
Snowball red
Snowballs Green
GreenWin
Level
Level:
kids
mailto:wells@nny.com
soundBusy
nextLevel
level
puppetSound
myHits
startMovie
C:\WINNT\Profiles\wells\Desktop\snowcraft98
[#gd: 3, #level: 1]
[#gd: 5, #level: 2]
[#gd: 7, #level: 3]
[#gd: 9, #level: 4]
[#gd: 12, #level: 5]
GreenWinLevel 2Level 3Level 4Level 5Level 6
```

These names suggest the original game is level-driven:

- Level 1 starts with `gd: 3`.
- Level 2 uses `gd: 5`.
- Level 3 uses `gd: 7`.
- Level 4 uses `gd: 9`.
- Level 5 uses `gd: 12`.

The exact meaning of `gd` still needs confirmation from the Lingo scripts and
runtime behavior, but it is likely tied to opponent count, difficulty, or a
spawn/formation table.

Detailed level-flow notes are tracked in `docs/level-data-notes.md`.

The `Lnam` Lingo name table contains 61 identifiers. Important names found so
far:

```text
exitFrame
preLoad
mouseDown
clearGlobals
gRDead
updateStage
soundBusy
gGdead
nextLevel
gd
level
beginSprite
prepareFrame
spriteNum
myMove
random
myTempo
myClock
member
name
myDirection
point
puppetSound
myHits
mySteps
mouseEnter
mouseLeave
mouseH
mouseV
stillDown
powerTime
power
myRange
greenDead
redDead
startMovie
startTimer
gotoNetPage
open
```

`tools/export-lingo-strings.ps1` writes script-facing string evidence to
`reverse/lingo-strings.csv` from `Lnam`, `Lctx`, `Lscr`, and `STXT` resources.
This is not a bytecode decompiler, but it makes the visible script vocabulary
repeatable and easier to diff while reconstructing gameplay.

More structured Lingo notes are in `docs/lingo-bytecode-notes.md`. Current
bytecode-level findings are now exported by
`tools/export-lingo-bytecode-summary.ps1` to:

```text
reverse/lingo-names.csv
reverse/lingo-scripts.csv
reverse/lingo-handlers.csv
reverse/lingo-constants.csv
reverse/lingo-disassembly.csv
reverse/lingo-call-sites.csv
```

Current script role findings:

```text
0579  likely green character behavior
0445  likely red character behavior
0318  likely green snowball/projectile behavior
0341  likely red snowball/projectile behavior
0257  likely level/state data; owns gd and level properties
0023  movie startup / level flow / ridicule behavior
```

Some small handlers already disassemble clearly without a full decompiler:

```text
0023.startMovie  cursor(-1), clearGlobals()
0573.mouseDown   clearGlobals(), go(1)
0283.mouseDown   gotoNetPage("mailto:wells@nny.com")
0146.exitFrame   preLoad(1, 77)
```

The `lingo-call-sites.csv` output currently finds `20` `puppetSound` call sites.
The nearest resolved pushed constants give useful sound/action evidence:

```text
0023.step          puppetSound("step")
0023.nextLevel     puppetSound("ugly")
0023.ridicule      puppetSound("laugh")
0318.prepareFrame  puppetSound("Whoosh" | "Whoosh Percusive" | "hit1" | "splat")
0341.prepareFrame  puppetSound("Whoosh" | "Whoosh Percusive" | "hit1" | "splat")
0445.prepareFrame  puppetSound("Ahhhh!" | "bird_tweets")
0445.mouseEnter    puppetSound("short_chirps")
0579.prepareFrame  puppetSound("step" | "hit2" | "kids")
```

`Lscr` script chunks are still bytecode, but their embedded strings already map
some gameplay behavior:

```text
0x12984  GreenWin, Level, Number of Green:, Level:
0x140C2  snowball, Whoosh, G recover, G hit, hit1, drop, splat
0x144C4  snowball, Whoosh, R dead, R hit
0x1499A  G windup, step, R rest, ugly, laugh, G yea
0x14F70  mailto:wells@nny.com
```

Useful `CASt` record names found so far:

```text
GREEN DUDES SCRIPT
RED DUDES SCRIPT
R rest
R hit
R hit2
R dead
G windup
G Hit
G Hit2
G dead
drop
splat
snowball
Snowball red
Snowballs Green
Whoosh
Whoosh Percusive
kids1
kids2
kids3
hit1
hit2
snowcraft_256
snowcraft_256 Palette
snowcraft_key
snowcraft_palatte
```

`tools/export-cast-index.ps1` writes `reverse/cast-index.csv`. The current cast
index exposes the likely gameplay model:

```text
Green character states:
G ready
G Walk H1
G Walk H2
G Walk V1
G Walk V2
G cock
G windup
G toss
G recover
G Hit
G Hit2
G dead
G down
G ow
G yea

Red character states:
R rest
R ready
R Auto walk_1
R Auto walk_2
R cock
R toss
R pop
R daze1
R daze2
R daze3
R hit
R hit2
R dead

Snowball/power objects:
snowball
Snowball red
Snowballs Green
sb 0
sb 1
sb 2
sb 3
sb 4
sb 5
sb 6
sb 7
sb 8
sb 9
shadow
ground
power 0
power 1
power 2
power 3
power 4
power 5
power 6
power 7
power 8

Script cast members:
GREEN DUDES SCRIPT
RED DUDES SCRIPT
movie script
Event Loop
```

Sound cast names found so far:

```text
Whoosh
Whoosh Percusive
kids1
kids2
kids3
hit1
hit2
splat
laugh
Ahhhh!
bird_tweets
short_chirps
```

`tools/export-director-sounds.ps1` currently emits `15` provisional WAV files to
`reverse/sounds/`. The Director sound headers indicate 8-bit mono sample data,
mostly around `11025 Hz`, with some legacy rates near `11127 Hz` and `22254 Hz`.

`tools/export-sound-cast-metadata.ps1` writes `reverse/sound-cast-metadata.csv`
from sound `CASt` records. It captures sound cast names and embedded media
format labels such as `kMoaCfFormat_snd`, `kMoaCfFormat_WAVE`, and
`kMoaCfFormat_AIFF`. This is separate from the raw `sndH/sndS` WAV export, so
`tools/export-sound-map.ps1` performs the repeatable join.

`tools/export-sound-map.ps1` now formalizes the stronger `KEY*` relationship
found during reverse engineering:

```text
ParentIndex - 3 == sound CASt resource index
ChildIndex  - 3 == sndH/sndS resource index
```

It writes `reverse/sound-map.csv`, mapping `15` of `16` sound cast rows directly
to exported WAV files. The unresolved row is `CASt 133 splat`, which has no
current `KEY*` sound link; `CASt 313 splat` is the mapped audio version.

Detailed sound/action notes are tracked in `docs/sound-action-notes.md`.

`tools/export-key-map.ps1` is still partially interpretive. It now parses the
correct `KEY*` body header and used-entry count, but the exact Director key
semantics still need more work where rows do not join cleanly to `CASt` or
`BITD`.

## Tools To Try Next

- ProjectorRays or equivalent Director projector tooling to split the projector
  and inspect the embedded movie data.
- ScummVM Director runtime as a compatibility reference.
- Ghidra, IDA, or radare2 only if the projector wrapper itself becomes relevant;
  most gameplay logic is expected to live in Director data rather than native PE
  code.

## Constraints

This repository mirrors an old game artifact. Keep licensing and rights in mind
when redistributing extracted or derived assets.
