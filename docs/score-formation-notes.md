# Score Formation Notes

This note focuses only on level setup and formation evidence visible in the
Director score exports. It uses:

- `reverse/score-frame-sprites.csv`
- `reverse/score-frame-summary.csv`
- `reverse/score-labels.csv`
- `reverse/cast-member-map.csv`
- `reverse/asset-catalog.csv`
- `docs/reverse-analysis.md`
- `tools/export-score-timeline.ps1`

Coordinates below are raw Director score `X`/`Y` values from
`score-frame-sprites.csv`. They appear to be sprite registration-point
coordinates, not necessarily top-left bitmap coordinates.

## Score Labels

| Frame | Label |
| ---: | --- |
| 40 | GreenWin |
| 50 | Level 2 |
| 70 | Level 3 |
| 90 | Level 4 |
| 110 | Level 5 |
| 130 | Level 6 |

There is no explicit `Level 1` label, but frames `3-35` have the same formation
pattern as later playable blocks. Frame `35` has an action/behavior member
attached, matching the role that frames `65`, `85`, `105`, `125`, and `161`
play after later labels.

## Repeated Level Intro Walk-In

Frames `50-60`, `70-80`, `90-100`, and `110-120` are structurally identical.
They look like an entrance animation rather than final gameplay state: three
green-side character channels enter from the left/top-left, while red-side
channels are already on or near the right side.

| Role | Sprite channel | Shadow channel | Frame start | Frame end | Candidate visual evidence |
| --- | ---: | ---: | --- | --- | --- |
| green entrant A | 27 | 12 | `(56,-21)` | `(176,49)` | `G Walk H2 | G Walk V1` / `G Walk V2` |
| green entrant B | 28 | 13 | `(-41,-21)` | `(-41,-21)` | `G Walk V2` / `G windup` |
| green entrant C | 29 | 14 | `(-49,38)` | `(71,108)` | `G Walk H2 | G Walk V1` / `G Walk V2` |
| red entrant A | 30 | 15 | `(628,272)` | `(628,272)` | `R Auto walk_1`; sometimes dimension-resolved as `G windup` after setup |
| red entrant B | 31 | 16 | `(492,355)` | `(508,192)` | `R Auto walk_2` / `R Auto walk_1` |
| red entrant C | 32 | 17 | `(604,362)` | `(604,362)` | `R Auto walk_1`; often off-stage or near lower edge |

The score reuses the same channel layout for these four labeled blocks:
shadows on `12-17`, character bodies on `27-32`.

## Playable Setup Frames

The most likely setup frames are the frames where the intro block has settled
and an action/behavior member is attached:

| Setup frame | Related label/block | Active sprites | Action member | Behavior member | Notes |
| ---: | --- | ---: | ---: | ---: | --- |
| 35 | unlabeled first block, likely Level 1 | 16 | 98 | 98 | First playable-style setup |
| 65 | after `Level 2` | 18 | 98 | 98 | Same base formation plus two `G ready` entries |
| 85 | after `Level 3` | 20 | 98 | 98 | Same base formation plus four `G ready` entries |
| 105 | after `Level 4` | 22 | 98 | 98 | Same base formation plus six `G ready` entries |
| 125 | after `Level 5` | 22 | 98 | 98 | Same base formation plus six `G ready` entries in a wider spread |
| 161 | after `Level 6` | 33 | 98 | 98 | Large final setup or finale-style formation |

The score's level labels are probably entry points into short scripted score
segments. The gameplay state is more likely initialized at the later setup
frames above, not directly on the labeled frames.

## Common Base Formation

Frames `35`, `65`, `85`, `105`, and mostly `125` share this base formation.
The cast resolver is still imperfect for several channels, so the visual role is
based primarily on dimensions and `DimensionCandidateNames`.

| Channel | Shadow channel | Position | Candidate visual evidence | Interpretation |
| ---: | ---: | --- | --- | --- |
| 27 | 12 | `(176,49)` | `G Walk V2` | green-side active character |
| 28 | 13 | `(-41,-21)` | `G windup` | off-screen/top-left green-side slot |
| 29 | 14 | `(71,108)` | `G windup` / `G Walk V2` | green-side active character |
| 30 | 15 | `(628,272)` | `G windup` by dimensions, but red-side channel in walk-in | off-screen/right slot, unresolved team |
| 31 | 16 | `(508,192)` | `R rest` | red-side active character |
| 32 | 17 | `(604,362)` | `R rest` | off-screen/lower-right red-side slot |
| 33 | none observed in shadow block | `(73,46)` | `R rest` | extra red/rest-like slot present by frame `31+` and all setup frames |

The channel numbers strongly suggest a stable pairing model: shadows live in
`12-17`, bodies in `27-32`, with `33` as an extra body-only/rest-like channel.

## Added Ready Slots By Block

The number and placement of `G ready`-dimension slots increases with later
blocks. These slots are strong candidates for level-specific green/player
formation data or spawn markers. They are mostly off-screen or near the left/top
edge in earlier levels, then spread farther right in the later blocks.

| Setup frame | Extra `G ready`-dimension channels | Positions |
| ---: | --- | --- |
| 35 | none in the final setup rows; prior frames briefly use channels `25-26` | n/a |
| 65 | `25`, `26` | `(-7,-34)`, `(-9,28)` |
| 85 | `23`, `24`, `25`, `26` | `(53,-14)`, `(-39,48)`, `(153,-14)`, `(-49,108)` |
| 105 | `21`, `22`, `23`, `24`, `25`, `26` | `(68,-21)`, `(-7,33)`, `(109,-21)`, `(-8,96)`, `(36,-18)`, `(-3,172)` |
| 125 | `19`, `21`, `22`, `23`, `25`, `26` | `(138,-21)`, `(234,-6)`, `(3,183)`, `(307,-11)`, `(391,-6)`, `(-2,152)` |

This is one of the clearest score-side formation signals found so far. It also
lines up with the Lingo string evidence that level data carries increasing
`gd` values (`3`, `5`, `7`, `9`, `12`), though the exact mapping between
`gd`, on-score placeholders, and live game actors still needs bytecode
confirmation.

## Level 6 / Final Formation Candidate

After the `Level 6` label, frames `130-161` do not match the shorter repeated
intro pattern. The block gradually fills many more channels. Frame `161` is the
clearest settled state because it has action/behavior member `98` attached and
`33` active sprites.

Likely actor/body positions at frame `161`:

| Channel | Position | Candidate visual evidence | Notes |
| ---: | --- | --- | --- |
| 18 | `(380,-38)` | `R rest` | off-screen/top |
| 19 | `(470,62)` | `G windup` | on-stage/right |
| 20 | `(260,-18)` | `G windup` | top edge |
| 21 | `(350,147)` | `G windup` | on-stage |
| 22 | `(140,-18)` | `G windup` | top edge |
| 23 | `(230,227)` | `G windup` | on-stage |
| 24 | `(-17,67)` | `G windup` | left edge |
| 25 | `(520,107)` | `G windup` | on-stage/right |
| 26 | `(460,147)` | `G windup` | on-stage/right |
| 27 | `(400,187)` | `G windup` | on-stage |
| 28 | `(340,227)` | `G windup` | on-stage |
| 29 | `(280,267)` | `G windup` | on-stage |
| 30 | `(220,272)` | `G windup` | on-stage/lower |
| 31 | `(508,192)` | `R rest` | red/rest-like slot |
| 32 | `(604,362)` | `R rest` | off-screen/lower-right |
| 33 | `(73,46)` | `R rest` | left/top rest-like slot |

Frame `161` also has a large shadow field across channels `4-17`, including
positions such as `(320,-20)`, `(410,107)`, `(200,-18)`, `(290,187)`,
`(80,-18)`, `(170,267)`, `(520,107)`, `(460,147)`, `(400,187)`, `(340,227)`,
`(280,267)`, and `(220,192)`. That looks like a dense final-stage/finale
formation rather than the smaller six-character entrance pattern.

## UI And Background Slots

| Channel | Common position | Candidate visual evidence | Notes |
| ---: | --- | --- | --- |
| 1 | `(296,160)`, `600x320` | `ground | snowcraft_256` | persistent background |
| 2 | `(296,160)` | `snowcraft_key` or level title/large strip by dimensions | changes by label/setup block |
| 3 | `(176,49)`, `374x28` in setup frames | unnamed strip / `R rest` dimension ambiguity | likely title/instruction/status strip or hidden marker |

The label frames use channel `2` as a level-title-like strip:

| Label frame | Channel 2 cast index | Dimensions | Candidate |
| ---: | ---: | --- | --- |
| 50 | 73 | `86x22` | unnamed level title strip |
| 70 | 74 | `86x22` | unnamed level title strip |
| 90 | 75 | `87x22` | unnamed level title strip |
| 110 | 78 | `158x23` | unnamed level title strip |

The unlabeled first setup frame `35` uses channel `2` as `snowcraft_key`
(`203x31`), while later setup frames show channel `2` as a wider `374x28`
strip. This area needs visual confirmation against previews before naming the
asset.

## Ambiguities

- `CastIndex` alone is not enough to name several score sprites. Some channels
  resolve through `CAS*`, but their score dimensions point at a different visual
  asset. Formation inference here uses dimensions and repeated channel roles
  when `CastName` is misleading or empty.
- The score can show off-screen placeholders and transition actors. A position
  in these tables is evidence that the Director score contains a sprite at that
  coordinate, not proof that the gameplay engine treats it as a live actor.
- The exact team semantics for channels `30`, `31`, `32`, and `33` still need
  Lingo bytecode confirmation. Their positions and walk-in behavior make them
  red-side/rest-like, but the cast resolver sometimes reports green assets.
- Level numbering may be offset by the Director labels. The script string data
  has level records up to `#level: 5`, while the score labels include
  `Level 6`. The `Level 6` label may be a final/win/finale block rather than a
  normal sixth gameplay level.

## Working Hypothesis

The Director score stores reusable entrance and setup formations, while Lingo
probably activates and drives the real gameplay actors. For Level 2-5, the
score repeats a fixed six-character walk-in, then adds progressively more
`G ready`-dimension placeholders. For the `Level 6` block, the score builds a
larger dense formation that likely represents the final setup or a finale after
the main five gameplay levels.
