# Gameplay State Map

Scope: working gameplay reconstruction from bytecode-derived pseudo-Lingo,
basic blocks, control-flow edges, call sites, cast names, and sprite member
assignments. This is a porting map, not a complete decompile.

Primary generated inputs:

- `reverse/lingo-pseudocode.csv`
- `reverse/lingo-basic-blocks.csv`
- `reverse/lingo-control-flow-edges.csv`
- `reverse/lingo-member-assignments.csv`
- `reverse/lingo-call-sites.csv`
- `reverse/control-flow-graphs/*.dot`

## Main Runtime Scripts

| Script | Main role | Important handlers |
| --- | --- | --- |
| `0579` | green character behavior | `beginSprite`, `prepareFrame` |
| `0445` | red target/opponent behavior | `beginSprite`, `prepareFrame`, `mouseEnter`, `mouseLeave`, `mouseDown` |
| `0318` | red-to-green projectile behavior | `beginSprite`, `prepareFrame` |
| `0341` | green-to-red projectile behavior | `prepareFrame` |
| `0257` | level/controller behavior | `exitFrame`, `getPropertyDescriptionList` |
| `0023` | movie/global flow helpers | `startMovie`, `step`, `nextLevel`, `ridicule` |

The largest recovered handler graphs are:

| Script.handler | Blocks | Edges | Graph |
| --- | ---: | ---: | --- |
| `0579.prepareFrame` | 122 | 178 | `reverse/control-flow-graphs/0579_01_prepareFrame.dot` |
| `0318.prepareFrame` | 34 | 49 | `reverse/control-flow-graphs/0318_01_prepareFrame.dot` |
| `0341.prepareFrame` | 34 | 49 | `reverse/control-flow-graphs/0341_00_prepareFrame.dot` |
| `0445.prepareFrame` | 24 | 35 | `reverse/control-flow-graphs/0445_01_prepareFrame.dot` |
| `0445.mouseDown` | 20 | 28 | `reverse/control-flow-graphs/0445_04_mouseDown.dot` |
| `0257.exitFrame` | 17 | 23 | `reverse/control-flow-graphs/0257_00_exitFrame.dot` |

## Green Character (`0579`)

`0579.beginSprite` initializes the actor:

- stores `sp`;
- sets `myMove = random(50)`;
- sets the green sprite to `G ready`;
- sets companion sprite `sp - 15` to `shadow`;
- sets `myTempo = 5`.

`0579.prepareFrame` is timer-gated:

```text
if the timer <= myClock + myTempo then return
```

The current state is read through the sprite member:

```text
member(the memberNum of sprite sp)
```

The working state machine:

| State | Observed behavior |
| --- | --- |
| `G ready` | Randomly chooses vertical walk, horizontal walk, or throw windup. |
| `G Walk V1` / `G Walk V2` | Alternates vertical walk frames, moves by `myDirection`, plays `step`, and can end in `G windup`. |
| `G Walk H1` / `G Walk H2` | Alternates horizontal walk frames, moves by `myDirection`, plays `step`, and returns to `G ready`. |
| `G windup` | Waits for `myMove` to expire, then enters `G cock`. |
| `G cock` | Searches projectile slots `40..49`; when a free `nothing` slot is found, creates `sb4..sb8` at the green location and enters `G toss`. |
| `G toss` | Returns to `G ready` after its move timer expires. |
| `G Hit` / `G Hit2` | Hit animation path; `G Hit` advances by `memberNum + 1`, then hit count logic runs in `G Hit2`. |
| `G ow` | Short hurt state before recovery. |
| `G down` | Knockdown state; shadow is hidden while down. |
| `G recover` | Returns to `G ready`. |
| `G dead` | Appears terminal or no-op in the current pseudo-code layer. |

Boundary logic forces movement back into the play area:

- if `locH < 40`, force direction to `point(4, 1)`;
- if `locV < 40`, force direction to `point(1, 4)`;
- if `locH > ((320 - locV) * 2)`, transition toward `G windup`.

Hit progression:

- first hit: `G ow`, `myMove = 10`;
- second hit: `hit2` sound, `G down`, `myMove = 25`, shadow becomes `nothing`;
- third hit: `kids1..kids3` sound path, green sprite becomes `nothing`,
  companion/shadow sprite gets a dynamic `G down + random(3)` member, and a
  global death/count value is incremented.

## Red Opponent (`0445`)

`0445.beginSprite` initializes:

- `sp`;
- helper/shadow sprite `sp - 15`;
- Director `constraint = 1`;
- `myTempo = 5`.

`0445.prepareFrame` is the red hit/daze/death state machine:

| State | Observed behavior |
| --- | --- |
| `R hit` | Advances to `R hit2`. |
| `R hit2` | On timer expiry, increments `myHits`. |
| `R daze1` / `R daze2` / `R daze3` | Daze loop after a non-lethal hit, then returns to `R ready`. |
| `R ready` | Idle target state. |
| `R dead` | Death state assigned to helper/shadow before cleanup. |
| `nothing` | Cleanup for dead/hidden red and UI sprites. |

At `myHits = 2`, the red actor dies:

- helper/shadow sprite becomes `R dead`;
- main red sprite becomes `nothing`;
- sprites `33` and `34` are cleared;
- a global red-dead counter is incremented;
- `Ahhhh!` sound is played.

Otherwise, it plays `bird_tweets`, enters `R daze1`, sets `mySteps = 25`, and
sets `myMove = 3`.

Mouse handlers:

- `mouseEnter`: if not hit/dead, sets `R pop`, displays `power 0` on sprite
  `34`, aligns helper sprites, and plays `short_chirps`.
- `mouseLeave`: returns to `R ready` and clears sprites `33`/`34`.
- `mouseDown`: charges throw power, updates `power 0..8`, then searches
  projectile slots `50..59` and spawns `sb0..sb8` at the red location.

The current pseudo-code has a suspicious `if not (0)` in `0445.mouseDown`;
this likely hides a Director mouse-state expression such as `stillDown`.

## Projectiles (`0318` and `0341`)

Projectile members start as `sbN`, where `N` controls range/power. Both scripts
convert an `sbN` marker into visible `snowball`, set `myRange = N * 2`, and
play either `Whoosh` or `Whoosh Percusive`.

`0318.prepareFrame` appears to move red snowballs toward green sprites:

- `snowball` moves by `point(-20, -10)`;
- scans target sprites `18..29`;
- on hit, target becomes `G hit`, projectile becomes `nothing`, `hit1` plays,
  and `updateStage()` runs;
- when range expires, projectile becomes `drop`;
- `drop`, `splat`, and `melt` progress with dynamic `memberNum + 1`.

`0341.prepareFrame` is the mirrored green snowball path:

- `snowball` moves by `point(20, 10)`;
- scans red target sprites `30..32`;
- ignores targets already in `R dead` or `nothing`;
- on hit, target becomes `R hit`, projectile becomes `nothing`, sprites `33`
  and `34` are cleared, and `hit1` plays;
- `drop`, `splat`, and `melt` then progress by dynamic member increments.

## Level Flow (`0257` and `0023`)

`0257.exitFrame` is the level controller:

- if the red-dead/global-win counter reaches `3`, sprites `18..29` become
  `G yea`, sprites `35..59` become `nothing`, `ridicule()` runs twice,
  globals are cleared, and the movie jumps to `GreenWin`;
- another branch compares a green-dead or level counter global to `gd`, then
  clears globals, calls `nextLevel()`, and goes to `"Level" && (level + 1)`;
- `getPropertyDescriptionList` exposes `gd` as `Number of Green:` and `level`
  as `Level:`.

`0023` contains global helpers:

- `startMovie`: hides cursor and clears globals;
- `step(sp, myDirection)`: applies diagonal motion, boundary changes, and
  `step` sound;
- `nextLevel`: resets red sprites `30..32` to `R rest`, updates the stage,
  waits on the timer, and plays `ugly`;
- `ridicule`: plays `laugh`, assigns random `G yea` frames to sprites `21..29`,
  and manipulates `sprite.blend` for a fade/flash effect.

## Porting Gaps

Important items still needed before a faithful web runtime:

- name unresolved globals such as `global[6]` and `global[11]`;
- decode constant/member expressions that still appear as `<constant>`,
  `0 of local[0]`, or `0 of local[8]`;
- confirm Director `timer` units and map `myTempo` into a browser game loop;
- confirm Director `point` comparison semantics;
- implement Director-like `intersects`, `soundBusy`, `startTimer`, sprite
  registration points, and cast-member lookup;
- map dynamic animation sequences driven by `memberNum + 1`, including
  `drop -> splat -> melt`, `G Hit -> G Hit2`, and red hit frames;
- finish naming projectile `sbN` power/range and the two projectile sprite slot
  pools: green uses `40..49`, red uses `50..59`.
