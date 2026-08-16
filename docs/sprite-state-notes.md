# Sprite State Notes

Scope: Windows/Macromedia Director asset and score evidence only. This note is
for rebuilding the actor state map before any web-port work.

Inputs checked:

- `reverse/asset-catalog.csv`
- `reverse/cast-index.csv`
- `reverse/cast-member-map.csv`
- `reverse/score-frame-sprites.csv`
- `reverse/bitmap-metadata.csv`
- Existing notes in `docs/reverse-analysis.md`,
  `docs/lingo-bytecode-notes.md`, and `docs/score-formation-notes.md`

Coordinates in score files are Director registration-point positions. Bitmap
anchors below are local anchors computed as `RegX - InitialLeft`,
`RegY - InitialTop`. Score `CastIndex` values are Director cast-member numbers,
not raw resource indexes; the current join is `ScoreCastIndex N -> CAS*[N - 1]
-> CASt resource`.

## Confidence Legend

| Level | Meaning |
| --- | --- |
| `score-confirmed` | The score resolves the cast member through `CAS*` or a single dimension candidate. |
| `asset-confirmed` | `asset-catalog.csv` and/or `bitmap-metadata.csv` exposes a named bitmap state, but static score placement does not directly prove runtime use. |
| `lingo-confirmed-name` | Existing Lingo notes show the state name appears in behavior/projectile scripts. |
| `ambiguous` | Multiple same-size or same-hash bitmap candidates exist, or a score slot is reused with mixed dimensions. |

## Score-Side Sprite Roles

| Role | Score evidence | Current interpretation | Confidence |
| --- | --- | --- | --- |
| Background | `ScoreCastIndex 69`, channel `1`, frames `1-166`, `600x320` | Persistent snowfield. Dimension candidates are `ground` and `snowcraft_256`. | `score-confirmed`, name `ambiguous` |
| Key/title strip | `ScoreCastIndex 71`, frames `10-34`, `203x31`; `ScoreCastIndex 70`, frame `35` as `203x31`, later `374x28` | UI/instruction strip or hidden level marker. | `score-confirmed`, name partly `ambiguous` |
| Level title strips | `ScoreCastIndex 73`, `74`, `75`, `78` on frames `50-60`, `70-80`, `90-100`, `110-120` | Level intro title strips. `73/74` are `86x22`, `75` is `87x22`, `78` is `158x23`. | `score-confirmed`, unnamed |
| Shadows | Normal setup uses channels `12-17`; Level 6/final block expands shadows across channels `3-17` | Shadow bitmap is likely the named `shadow` state (`36x21`), but `ScoreCastIndex 1` is mixed and also carries body-like `24x31` rows. | `score-confirmed`, mixed slot |
| Normal actor bodies | Channels `27-32`, paired with shadows `12-17`; channel `33` is an extra body-only/rest-like slot | Reused six-body formation. Channels `27-29` behave green-side; `30-32` behave red-side by formation, though the resolver can report green states. | `score-confirmed`, team partly `ambiguous` |
| Green ready placeholders | `ScoreCastIndex 24`, `25x36`, frames `61-125`; channels grow by level | Strong marker for extra green/player formation slots. | `dimension-single-candidate` |
| Direct green cast rows | `ScoreCastIndex 4 -> G cock`, frames `25-161`; `ScoreCastIndex 18 -> G ready`, frames `150-156` | Only narrow, direct score-to-named-green joins. Score dimensions are often smaller than bitmap dimensions, so treat them as placement/state placeholders. | `score-confirmed` |
| Dynamic projectile/power states | No static score usage for `snowball`, `R hit`, `R dead`, `G yea`, or power cast slots in current score rows | These states are likely switched by Lingo at runtime via sprite member changes. | `asset-confirmed`, `lingo-confirmed-name` where present |

## Green Actor States

These are the useful green/player visual states exposed by the bitmap/cast
catalog. `CASt` is the raw cast resource index; `BITD` is the bitmap data index.

| State | CASt / BITD | Size | Anchor | Evidence | Notes |
| --- | --- | --- | --- | --- | --- |
| `G ready` | `372 / 348` | `25x36` | `(11,29)` | `score-confirmed`, `lingo-confirmed-name` | Direct score cast index `18`; dimension slot `24` is also a single candidate for this state. |
| `G cock` | `358 / 361` | `34x35` | `(22,26)` | `score-confirmed`, `lingo-confirmed-name` | Direct score cast index `4`; used as a static placeholder in many setup frames. |
| `G windup` | `357 / 352` | `24x31` | `(7,23)` | `asset-confirmed`, `lingo-confirmed-name` | Common dimension candidate for mixed score slots and Level 6 body rows. |
| `G toss` | `243 / 230` | `24x34` | `(8,26)` | `asset-confirmed`, `lingo-confirmed-name` | Throw release state. |
| `G Walk H1` | `273 / 512` | `32x36` | `(13,29)` | `asset-confirmed`, `lingo-confirmed-name` | Horizontal walk frame. |
| `G Walk H2` | `515 / 376 or 432` | `30x36` | `(12,29)` | `ambiguous`, `lingo-confirmed-name` | Two same-size bitmap candidates. |
| `G Walk V1` | `389 / 376 or 432` | `30x36` | `(13,29)` | `ambiguous`, `lingo-confirmed-name` | Shares candidates with `G Walk H2`; visual selection needs preview/manual confirmation. |
| `G Walk V2` | `390 / 136` | `27x34` | `(11,28)` | `asset-confirmed`, `lingo-confirmed-name` | Also appears as score cast index `33` in `cast-member-map`, but with no static score usage under that index. |
| `G Hit` | `41 / 46 or 425` | `25x35` | `(13,28)` | `reused-identical`, `lingo-confirmed-name` | Shares identical bitmap candidates with `G Hit2`. |
| `G Hit2` | `422 / 46 or 425` | `25x35` | `(13,28)` | `reused-identical`, `lingo-confirmed-name` | Name distinction is meaningful in Lingo even if bitmap data is reused. |
| `G ow` | `35 / 37 or 156` | `29x35` | `(12,28)` | `ambiguous`, `lingo-confirmed-name` | Same dimensions and likely same visual pool as `G recover`. |
| `G recover` | `251 / 37 or 156` | `29x35` | `(12,28)` | `ambiguous`, `lingo-confirmed-name` | Needs runtime ordering from Lingo to separate from `G ow`. |
| `G down` | `226 / 104` | `35x34` | `(33,29)` | `asset-confirmed`, `lingo-confirmed-name` | Green downed/intermediate hit state. |
| `G dead` | `81 / 90`, `92 / 97`, `238 / 125`, `387 / 386` | `69x42`, `49x38`, `54x46`, `66x42` | anchors outside/right-heavy | `asset-confirmed`, `lingo-confirmed-name` | Multiple death/fall variants; select by Lingo transition order, not by score. |
| `G yea` | `369 / 334`, `441 / 359`, `469 / 426` | `40x37`, `42x37`, `42x35` | about `(20-22,26-29)` | `asset-confirmed`, `lingo-confirmed-name` | Celebration/win states. `ScoreCastIndex 111 -> G yea`, but no static score usage in current rows. |

## Red Actor States

The red/opponent catalog is complete enough for reconstruction, but static score
rows mostly identify red-side roles by channel and dimensions rather than named
red cast joins.

| State | CASt / BITD | Size | Anchor | Evidence | Notes |
| --- | --- | --- | --- | --- | --- |
| `R rest` | `355 / 64` | `24x33` | `(14,28)` | `asset-confirmed`, `lingo-confirmed-name` | Strong candidate for red idle/rest-like score body rows (`24x33`). |
| `R ready` | `298 / 366 or 492` | `26x34` | `(15,28)` | `ambiguous`, `lingo-confirmed-name` | Two bitmap candidates; likely shares visual pool with `R Auto walk_1`. |
| `R Auto walk_1` | `491 / 366 or 492` | `25x34` | `(15,28)` | `ambiguous` | Common dimension candidate for red-side entrance rows. |
| `R Auto walk_2` | `467 / 438` | `31x35` | `(19,28)` | `asset-confirmed` | Common dimension candidate for channel `31` during intro blocks. |
| `R cock` | `371 / 8 or 368` | `63x49` | `(33,29)` | `ambiguous`, `lingo-confirmed-name` | Red throw windup. |
| `R toss` | `379 / 339` | `63x51` | `(33,31)` | `asset-confirmed`, `lingo-confirmed-name` | Red throw release. |
| `R hit` | `316 / 32 or 336` | `46x33` | `(15,26)` | `reused-identical`, `lingo-confirmed-name` | `cast-member-map` has `ScoreCastIndex 94 -> R hit`, with no static score usage. |
| `R hit2` | `178 / 32 or 336` | `46x33` | `(15,26)` | `reused-identical`, `lingo-confirmed-name` | Bitmap data reused with `R hit`. |
| `R daze1` | `416 / 417` | `35x43` | `(21,37)` | `asset-confirmed`, `lingo-confirmed-name` | Dazed sequence frame. |
| `R daze2` | `420 / 424` | `36x44` | `(22,38)` | `asset-confirmed`, `lingo-confirmed-name` | Dazed sequence frame. |
| `R daze3` | `428 / 429` | `35x40` | `(21,34)` | `asset-confirmed`, `lingo-confirmed-name` | Dazed sequence frame. |
| `R pop` | `337 / 8 or 368` | `63x49` | `(33,29)` | `ambiguous`, `lingo-confirmed-name` | Shares candidate pool with `R cock`. |
| `R dead` | `19 / 250`, `400 / 203`, `490 / 86` | `71x33`, `51x53`, `68x49` | anchors around or outside the bitmap | `asset-confirmed`, `lingo-confirmed-name` | `ScoreCastIndex 105 -> R dead`, but no static score usage in current rows. |

## Snowball, Power, Shadow, Background

| State/object | CASt / BITD | Size | Anchor | Evidence | Notes |
| --- | --- | --- | --- | --- | --- |
| `shadow` | `442 / 443` | `36x21` | `(6,17)` | `score-confirmed by dimension`, `asset-confirmed` | Most `ScoreCastIndex 1` rows are `36x21` and align with body channels. |
| `snowball` | `186 / 188` | `11x42` | `(5,38)` | `asset-confirmed`, `lingo-confirmed-name` | `ScoreCastIndex 64 -> snowball`, but no static score usage; projectile scripts likely switch it dynamically. |
| `sb 0..9` | `66`, `177`, `481`, `71`, `76`, `83`, `99`, `123`, `138`, `151`, `159` | `1x1` | `(1,4)` | `bitmap-confirmed` | Tiny snowball-stage or hidden marker cast members. Their runtime role needs bytecode ordering. |
| `splat` | `133 / 134` | `16x7` | `(8,3)` | `asset-confirmed`, `lingo-confirmed-name` | Impact/melt effect candidate. There is also sound cast `313` named `splat`. |
| `power 0` | `95 / 95` | `4x3` | `(-27,-1)` | `bitmap-confirmed` | Present in `cast-index.csv` and `bitmap-metadata.csv`; currently missing `ui-power` classification in `asset-catalog.csv`. |
| `power 1` | `98 / 102` | `9x9` | `(-27,5)` | `asset-confirmed` | Score cast slot exists, no static usage. |
| `power 2` | `105 / 106` | `9x12` | `(-27,8)` | `asset-confirmed` |  |
| `power 3` | `110 / 111` | `9x15` | `(-27,11)` | `asset-confirmed` | `ScoreCastIndex 44 -> power 3`, no static usage. |
| `power 4` | `113 / 116` | `9x18` | `(-27,14)` | `reused-identical` | `ScoreCastIndex 40 -> power 4`, no static usage. |
| `power 5` | `118 / 119` | `9x21` | `(-27,17)` | `asset-confirmed` |  |
| `power 6` | `121 / 122` | `9x24` | `(-27,20)` | `asset-confirmed` | `ScoreCastIndex 42 -> power 6`, no static usage. |
| `power 7` | `107 / 145 or 174` | `9x27` | `(-27,23)` | `ambiguous` | Two same-size candidates. |
| `power 8` | `117 / 142` | `9x30` | `(-27,26)` | `asset-confirmed` | `ScoreCastIndex 68 -> power 8`, no static usage. |
| `ground` | `155 / 157 or 409` | `600x320` | `(300,160)` | `ambiguous` | Same dimensions as `snowcraft_256`; likely one of the persistent backgrounds. |
| `snowcraft_256` | `408 / 157 or 409` | `600x320` | `(300,160)` | `ambiguous` | Visual preview notes identify one `snowfield background` and one `snowfield with mounds`; score does not distinguish them by name. |
| `snowcraft_key` | `12 / 351` | `203x31` | `(111,14)` | `score-confirmed by dimension` | Appears in score channel `2` during early frames/key screen. |
| `snowcraft_palatte` | `510 / 511` | `84x22` | `(-216,-138)` | `score-confirmed by dimension` | Appears near `GreenWin` frames via `ScoreCastIndex 72`. Name spelling is from source. |

## Practical Reconstruction Map

For a first actor reconstruction pass:

| Runtime role | Use these states first | Hold back / ambiguous |
| --- | --- | --- |
| Green idle/aim/throw | `G ready`, `G cock`, `G windup`, `G toss` | `G Walk H2` vs `G Walk V1` candidates need preview/runtime confirmation. |
| Green movement | `G Walk H1`, `G Walk H2`, `G Walk V1`, `G Walk V2` | Same-size `30x36` candidates may be reused or misjoined. |
| Green hit/death | `G Hit`, `G Hit2`, `G ow`, `G recover`, `G down`, `G dead` variants | `G Hit/G Hit2` and `G ow/G recover` share candidate pools; final sequencing needs Lingo. |
| Red idle/aim/throw | `R rest`, `R ready`, `R cock`, `R toss` | `R ready/R Auto walk_1` and `R cock/R pop` have ambiguous candidate pairs. |
| Red movement | `R Auto walk_1`, `R Auto walk_2` | Static score channels imply red-side roles, but cast names are often dimension-derived. |
| Red hit/death | `R hit`, `R hit2`, `R daze1`, `R daze2`, `R daze3`, `R pop`, `R dead` variants | Hit pair reuses identical bitmap data; death ordering needs behavior bytecode. |
| Projectile | `snowball`, `splat`, `sb 0..9` | `sb` states are only `1x1`; they may be hidden markers rather than visible animation frames. |
| UI/power | `power 0..8`, `snowcraft_key`, level strips | `power 0` needs asset catalog classification cleanup later. |
| Scene | `ground` / `snowcraft_256`, `shadow` | Background name is ambiguous because both candidates are `600x320`; shadow is strong by dimensions but mixed in score slot `1`. |

## Main Ambiguities To Preserve

- `ScoreCastIndex 1` is overloaded: it is mostly `36x21` shadow, but also has
  `24x31`, `24x33`, `25x34`, and `31x35` body-like rows.
- `ScoreCastIndex 4` directly resolves to `G cock`, yet score dimensions under
  this index include `24x31`, `24x33`, `25x34`, `27x34`, `30x36`, and `31x35`.
  Treat this as a static score placeholder, not proof every row is visually
  `G cock` at runtime.
- Several same-size bitmap pairs exist:
  `G Hit/G Hit2`, `G ow/G recover`, `G Walk H2/G Walk V1`,
  `R hit/R hit2`, `R ready/R Auto walk_1`, `R cock/R pop`, and `power 7`.
- The score formation suggests teams by channel geography: green-side bodies
  are mostly `27-29` plus added `G ready` placeholders, while red-side bodies
  are mostly `30-33`. This is formation evidence, not final gameplay logic.
- Static score rows do not place most projectile, power, hit, or death states.
  The existing Lingo notes indicate these are probably assigned dynamically with
  sprite member changes inside behavior scripts.
