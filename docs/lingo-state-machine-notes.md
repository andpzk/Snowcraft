# Lingo State Machine Notes

Scope: derived bytecode evidence for sprite property access and sprite member
state changes. This is not a full Lingo decompile yet; it is a repeatable map
from bytecode operations to likely runtime actor states.

Primary generated inputs:

- `reverse/lingo-disassembly.csv`
- `reverse/lingo-entity-ops.csv`
- `reverse/lingo-member-assignments.csv`
- `reverse/lingo-call-sites.csv`

`tools/export-lingo-bytecode-summary.ps1` now follows the ScummVM Director
bytecode table more closely for Director v4+ opcodes
(`engines/director/lingo/lingo-bytecode.cpp`) and exports:

- entity/property operations such as `the memberNum of sprite`,
  `the loc of sprite`, `the locH of sprite`, `the locV of sprite`, `the timer`,
  and `the number of cast`;
- derived member assignments of the common form
  `sprite.memberNum = cast("<state>").number`.

## Entity / Property Use

Current entity/property operation totals:

| Operation | Count | Meaning |
| --- | ---: | --- |
| `cast.number` push | 83 | Resolves a named cast member to a numeric member id. |
| `sprite.memberNum` assign | 78 | Changes a sprite's visible cast member/state. |
| `sprite.memberNum` push | 31 | Reads the current state of a sprite. |
| `sprite.loc` assign | 21 | Moves a sprite by assigning a point. |
| `sprite.loc` push | 19 | Reads current sprite position. |
| `sprite.locH` / `sprite.locV` push | 25 | Reads horizontal/vertical coordinates. |
| `timer` push | 12 | Reads Director timer state for wait/charge timing. |
| `sprite.blend` push/assign | 7 | Used by `0023.ridicule` visual fade/flash behavior. |

These rows are more reliable than raw string scanning because they come from
decoded bytecode operands plus the ScummVM `lingoV4TheEntity` mapping.

## Green / Player Behavior (`0579`)

`0579.prepareFrame` is now the richest state map. Confirmed state assignments
include:

| State | Evidence |
| --- | --- |
| `G Walk V1` | assigned at `0x150`, `0x4D6` |
| `G Walk H1` | assigned at `0x191`, `0x2B7`, `0x37A`, `0x38A` |
| `G Walk H2` | assigned at `0x2D6`, `0x2E6` |
| `G Walk V2` | assigned at `0x41E`, `0x42E` |
| `G windup` | assigned repeatedly at `0x1D2`, `0x1EE`, `0x345`, `0x3E9`, `0x48D`, `0x536` |
| `G cock` | assigned at `0x20F` |
| `G toss` | assigned at `0x25A` |
| `G Hit2` | assigned at `0x56C` |
| `G ow` | assigned at `0x5A0`, `0x660` |
| `G down` | assigned at `0x5C4` |
| `G recover` | assigned at `0x696` |
| `G ready` | assigned at `0x6BB`; also in `beginSprite` at `0x8D` |
| `shadow` | assigned in `beginSprite` at `0x9D` and later at `0x671` |
| `sb` / `nothing` | used around throw/hit cleanup blocks |

This supports the working model that `0579` is the green/player state machine:
walk direction, windup/cock/toss, hit/down/recover, and reset to ready all live
in this one behavior.

Sound evidence from `reverse/lingo-call-sites.csv` aligns with that role:
`0579.prepareFrame` calls `puppetSound("step")`, `puppetSound("hit2")`, and a
`kids` sound-selection path.

## Red / Opponent Behavior (`0445`)

`0445` assigns red state members across `beginSprite`, `prepareFrame`,
`mouseEnter`, `mouseLeave`, and `mouseDown`:

| Handler | State assignments |
| --- | --- |
| `beginSprite` | initializes related sprite/member state and position. |
| `prepareFrame` | `R hit2`, `R daze1`, `R daze2`, `R daze3`, repeated `nothing` cleanup. |
| `mouseEnter` | `R pop`, `power 0`, plus `short_chirps` sound call. |
| `mouseLeave` | clears three related member slots to `nothing`. |
| `mouseDown` | `R cock`, `R toss`, `power 0`, `sb`, and cleanup to `nothing`. |

This supports the working model that `0445` owns red target interaction:
hover/pop, click power/throw, hit/daze, and cleanup.

## Projectile Scripts (`0318` and `0341`)

Both projectile scripts change visible member state and position with the same
general pattern:

| Script | Likely side | State assignments |
| --- | --- | --- |
| `0318.prepareFrame` | green/projectile path | `snowball`, `hit1`, `splat`, `melt`, `nothing` |
| `0341.prepareFrame` | red/projectile path | `snowball`, `hit1`, `splat`, `melt`, `nothing` |

Both scripts also assign `sprite.loc`, so they are not just collision effects;
they update projectile position over time. Their `puppetSound` call sites align
with the state changes: `Whoosh`, `Whoosh Percusive`, `hit1`, and `splat`.

## Level / Transition Script Evidence

`0257.exitFrame` now has direct member assignment evidence:

- sets a range of sprites to `G yea` before `go("GreenWin")`;
- clears another range to `nothing`;
- branches on globals already identified in `docs/level-data-notes.md`.

`0023.nextLevel` assigns `R rest` during transition cleanup. `0023.ridicule`
assigns `G yea` and manipulates `sprite.blend`, consistent with a short visual
effect or taunt/victory animation.

## Current Limits

- `reverse/lingo-member-assignments.csv` uses a conservative nearby-string
  heuristic around `cast("<state>").number` patterns. It is repeatable and very
  useful, but it is not a stack-accurate AST.
- Target sprite identity is still a hint, not a final expression. The exporter
  preserves `TargetHints` such as `push-the-property:sp`,
  `push-the-property:spriteNum`, `push-local:0`, and `push-local:8`.
- The next decompiler step should add a small stack simulator for simple
  expressions so target sprite ids, `point(x,y)`, and `go("Level" & n)` can be
  emitted as structured pseudo-Lingo.
