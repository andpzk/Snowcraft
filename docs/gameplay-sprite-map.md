# Gameplay Sprite Channel and Cast Ordering Map

This document records the runtime sprite-channel layout and the cast-member
ordering constraints that are recoverable from the generated reverse CSVs. It
deliberately separates bytecode-proven relationships from score/cast resolver
inferences.

Primary evidence:

- `reverse/lingo-pseudocode.csv`
- `reverse/lingo-member-assignments.csv`
- `reverse/lingo-entity-ops.csv`
- `reverse/score-frame-sprites.csv`
- `reverse/score-summary.csv`
- `reverse/cast-index.csv`
- `reverse/cast-member-map.csv`
- `reverse/asset-catalog.csv`
- `reverse/bitmap-metadata.csv`

## Sprite Channels 18..59

| Channels | Runtime role | Companion / related channels | Confidence and bytecode evidence |
| --- | --- | --- | --- |
| `18..29` | Green actor body slots | `3..14`, using `body - 15` | Confirmed. `0318.prepareFrame` scans `18..29` for green targets (`0x120`, `0x127`); `0257.exitFrame` changes `18..29` to `G yea` (`0x66` through `0x9A`). All twelve channels occur as active score rows by the final setup block. |
| `30..32` | Red actor body slots | `15..17`, using `body - 15` | Confirmed. `0341.prepareFrame` scans `30..32` for red targets (`0x10F`, `0x116`); `0023.nextLevel` resets exactly `30..32` to `R rest` (`0xFB`, `0x102`, `0x128`). |
| `33` | Shared red interaction/animation overlay | Follows the selected red body `sp` | Confirmed runtime use. `0445.mouseEnter` assigns `R pop`; `mouseDown` assigns `R cock` and `R toss`; its location is copied from `sp`. Projectile hits and red death/leave paths clear it to `nothing`. The score also has an active channel-33 row from frames `31..161`, usually at `(73,46)`, so its static setup role is not fully explained. |
| `34` | Red power meter | Follows the selected red body `sp` | Confirmed. `0445.mouseEnter` assigns `power 0`; `mouseDown` assigns `number(cast "power 0") + power` after clamping `power` to `0..8`; throw/leave/hit paths clear it. No active channel-34 row exists in the exported score timeline. |
| `35..39` | Reserved runtime/scratch or effect slots | Included in the global runtime cleanup | Unconfirmed exact purpose. No direct assignment or active score row was found. `0257.exitFrame` clears the inclusive range `35..59` to `nothing` after a green win (`0xA4`, `0xAB`, `0xB9`). These channels must remain allocated even though their producer is not yet recovered. |
| `40..49` | Green-owned projectile pool | Projectile behavior is the green-to-red path (`0341`) | Confirmed pool, inferred behavior attachment. `0579.prepareFrame` searches `40..49` (`0x230`, `0x237`), requires a `nothing` member, assigns `cast("sb" && (random(4) + 4))`, and copies the green actor location. `0341` moves by `point(20,10)` and targets `30..32`, matching this pool's owner/direction. |
| `50..59` | Red-owned projectile pool | Projectile behavior is the red-to-green path (`0318`) | Confirmed pool, inferred behavior attachment. `0445.mouseDown` searches `50..59` (`0x3DF`, `0x3E6`), requires `nothing`, assigns `cast("sb" && power)`, and copies the red actor location. `0318` moves by `point(-20,-10)` and targets `18..29`, matching this pool's owner/direction. |

There are zero active `score-frame-sprites.csv` rows for channels `34..59`.
This is not evidence that the channels do not exist: `score-summary.csv` reports
`126` channels, `120` displayed channels, and a maximum touched sprite channel
of `60`. The score exporter emits active sprite rows; Lingo activates the power
and projectile slots at runtime.

### Green Actor Allocation

Channels `18..29` are a twelve-slot maximum allocation, not twelve actors in
every level. The score gradually introduces more of these slots in later setup
blocks. At frame `161`, all channels `18..29` have active rows. The level
controller compares `gGdead` with the per-level `gd` property, so the live
subset is level-dependent.

`0023.ridicule` operates on `21..29`, while the win controller operates on the
full `18..29` range. This narrower celebration loop should not be interpreted
as a different team boundary.

### Companion Offset

Both actor behaviors use a fixed `sp - 15` companion channel:

| Body range | Companion range | Runtime states |
| --- | --- | --- |
| Green `18..29` | `3..14` | Normally `shadow`; hidden during part of the hit path; on the third hit receives `number(cast "G down") + random(3)` while the body becomes `nothing`. |
| Red `30..32` | `15..17` | Normally `shadow`; on final defeat receives `R dead` while the body becomes `nothing`. |

The score supports this pairing. Channels `3..17` and `18..32` form matching
15-channel ranges, and repeated setup formations place shadow-sized `36x21`
sprites in the lower range. In the settled frame-161 rows, several pairs have
identical coordinates, including `10/25`, `11/26`, `12/27`, `13/28`, and
`14/29`. Other pairs are still in entrance/off-screen positions in that score
frame; at runtime both actor scripts repeatedly copy `loc(sp)` to
`loc(sp - 15)`.

The raw `beginSprite` bytecode at `0445:0x7F` and `0579:0xAC` genuinely reads
`loc(sp - 15) = memberNum(sp)`: it pushes sprite field `35` (`memberNum`) and
assigns sprite field `33` (`loc`). This is type-inconsistent but is not a
decompiler artifact. It is likely an original script mistake; the later
`prepareFrame` assignments (`0445:0xBE`, `0579:0x123`) correctly copy location
to location. A web port should initialize the companion from `loc(sp)`.

## Cast Member Ordering Constraints

Director code performs arithmetic on member numbers, so some ordering is a
runtime contract rather than a naming convention. These relationships must be
preserved in a compatible reconstruction, even if a web port later replaces
member numbers with explicit animation-state tables.

### Behaviorally Proven Relative Order

| Expression / transition | Required member order | Evidence |
| --- | --- | --- |
| `number(cast "power 0") + power`, `power = 0..8` | `power 0`, `power 1`, ..., `power 8` are nine consecutive members in numeric order. | `0445.mouseDown:0x3A7..0x3D1`. The resolver independently anchors `power 0` at one-based score member `36`, and correctly joins `power 1`, `power 4`, and `power 6` at the expected offsets. The required range is therefore most likely members `36..44`. |
| `G Hit` then `memberNum + 1` | The member immediately after `G Hit` is `G Hit2`. | `0579.prepareFrame:0x558..0x577`. The serialized CASt resources also place `G Hit` directly before `G Hit2`. |
| `drop` then `memberNum + 1` | The member immediately after `drop` is `splat`. | Both projectile handlers: `0318:0x1A3..0x1D4` and `0341:0x1C2..0x1F1`. |
| `splat` then `memberNum + 1` | The member immediately after `splat` is `melt`. | `0318:0x1D4..0x204` and `0341:0x1F1..0x221`. |
| `melt` then `memberNum + 1` | The next member must be an invisible/free terminal member, very likely one of the two members named `nothing`. | `0318:0x204..0x214` and `0341:0x221..0x231`. The next-frame early-out tests `nothing`, but the generated cast join does not identify which duplicate `nothing` member is reached. |
| `number(cast "G down") + random(3)` | Three consecutive members immediately after `G down` are selectable death/down variants. | `0579.prepareFrame:0x61A`. Four CASt resources are named `G dead`; the CSVs do not establish which three occupy these relative positions. |
| `(number(cast "G yea") + random(3)) - 1` | `G yea` plus its next two members form a three-frame celebration set. | `0023.ridicule:0x1AC`. Three serialized CASt resources are named `G yea`; `cast-member-map.csv` tentatively anchors one at score member `111`, suggesting `111..113`, but only the relative three-member requirement is certain. |

Under standard Director semantics, `random(4)` returns `1..4`, so green throws
select `sb 5..8` from the expression `random(4) + 4`. The bytecode expression
is certain; the numeric range should be rechecked against the target Director
runtime before hard-coding it in another engine.

### Explicit State Sequences

These sequences are assigned by name and therefore do not require adjacency,
but they define the animation/state order used by gameplay:

- Green movement alternates `G Walk H1 <-> G Walk H2` and
  `G Walk V1 <-> G Walk V2`; boundary cases return to `G windup`.
- Green throw is `G ready -> G windup -> G cock -> G toss -> G ready`.
- Green hit progression is `G Hit -> G Hit2`, then branches through `G ow`,
  `G down`, `G recover`, or the companion death variants according to hit count.
- Red hit progression is `R hit -> R hit2`; a non-final hit enters
  `R daze1 -> R daze2 -> R daze3`, loops the daze frames while `mySteps`
  remains, then returns to `R ready`.
- Red interaction uses `R pop -> R cock -> R toss`, with channel `33`
  mirroring those visible states and channel `34` showing power.
- Projectile progression is `sb N -> snowball -> drop -> splat -> melt ->`
  terminal invisible/free state.

The red input guards compare `memberNum(sp) < number(cast "R hit")`, and one
hover path compares against `R dead`. This confirms that cast numeric ordering
also separates interactable red states from hit/death states; it does not by
itself recover every absolute member number.

### Serialized CASt Order

Sorting named `CASt` resources by file-relative offset produces the following
semantic run:

```text
shadow
R Auto walk_1, R Auto walk_2, R rest, R ready, R pop, R cock, R toss,
R hit, R hit2, R daze1, R daze2, R daze3, R dead x3,
G yea x3,
G Walk H2, G Walk H1, G Walk V1, G Walk V2, G ready, G windup,
G cock, G toss, G Hit, G Hit2, G ow, G recover, G down, G dead x4,
power 0..8,
sb 0..9, a second sb 0, snowball,
unnamed projectile/effect members, splat, more unnamed effect members,
nothing x2
```

This order strongly corroborates the animation groupings, but file-relative
resource order is not a substitute for Director member numbers. The partial
`CAS*` resolver has known wrong joins: for example it places `power 3` at score
member `44` and `power 8` at `68`, while the bytecode requires the complete
`power 0..8` run to be consecutive from the `power 0` base. Use the arithmetic
constraints above as authoritative and serialized order only as supporting
evidence.

## Unresolved Or Unconfirmed Areas

- The exact producers and intended visuals for channels `35..39` are unknown.
  They are only proven to be in the `35..59` win-cleanup range.
- The exact score-time role of channel `33` is unresolved. It has a static
  active row before gameplay but is definitely repurposed by Lingo as the red
  interaction overlay.
- Channels `34..59` have no active exported score rows. Their initial
  `nothing` state is required by Lingo searches but is not directly represented
  by those rows.
- The behavior-script attachment of `0341` to `40..49` and `0318` to `50..59`
  is inferred from owner, movement direction, and target ranges. The current
  generated CSVs do not expose a direct channel-to-Lscr attachment table.
- Absolute member numbers are incomplete outside a few resolver anchors.
  Relative arithmetic relationships (`+1`, `+power`, `+random`) are stronger
  evidence than `CastResourceIndex`, file-relative order, or a lone
  `CastSlot` join.
- `drop` and `melt` are present as Lingo names but remain unnamed in the asset
  catalog. Several adjacent unnamed projectile/effect bitmaps exist, so their
  exact CASt/BITD resource identities are not yet proven.
- `splat` has two named resources: visual/effect CASt `133` with BITD `134`,
  and sound CASt `313`. `bitmap-metadata.csv` labels CASt `133` as `sound`, but
  its `16x7` bitmap and `asset-catalog.csv` classification show that it is the
  visual effect; this metadata-kind field is unreliable here.
- Duplicate cast names remain significant: `R dead` x3, `G yea` x3,
  `G dead` x4, `sb 0` x2, and `nothing` x2. Name lookup alone cannot identify
  which duplicate member an arithmetic transition reaches.
