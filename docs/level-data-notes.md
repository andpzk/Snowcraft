# Level Data Notes

This note isolates the Director/Windows level-flow evidence from the generated
Lingo CSVs. It is intentionally scoped to level data and transition control, not
to actor movement, collision, or any web prototype.

## Source Files

- `reverse/lingo-handlers.csv`
- `reverse/lingo-constants.csv`
- `reverse/lingo-disassembly.csv`
- `reverse/lingo-call-sites.csv`
- `reverse/score-labels.csv`
- `reverse/score-script-details.csv`
- Existing context from `docs/reverse-analysis.md` and
  `docs/lingo-bytecode-notes.md`

## Relevant Names

The `Lnam` table gives these indexes used by the level scripts:

| Name index | Name |
| ---: | --- |
| 3 | `clearGlobals` |
| 4 | `go` |
| 6 | `gRDead` |
| 8 | `updateStage` |
| 9 | `soundBusy` |
| 10 | `ridicule` |
| 11 | `gGdead` |
| 12 | `nextLevel` |
| 20 | `gd` |
| 21 | `level` |
| 38 | `puppetSound` |
| 54 | `startMovie` |
| 56 | `cursor` |
| 57 | `startTimer` |

`gd` and `level` are behavior properties on script `0257`, not standalone
globals. `gRDead` and `gGdead` are globals used by the actor scripts and read by
the level controller.

## Handler Map

| Script | Assembly | Role | Handlers / properties |
| ---: | ---: | --- | --- |
| `0023` | 104 | Movie startup and transition helpers | `startMovie`, `nextLevel`, `ridicule`, `step` |
| `0257` | 98 | Level/state controller | properties `gd, level`; handlers `exitFrame(n)`, `getPropertyDescriptionList(propList,tempList)` |
| `0445` | 100 | Red/opponent behavior | globals `gRDead,gGdead`; writes `gRDead` in `prepareFrame` |
| `0579` | 99 | Green/player behavior | globals `gRDead,gGdead`; writes `gGdead` in `prepareFrame` |

Score action member `98` is the same assembly as script `0257`. It appears on
setup/play frames `35`, `65`, `85`, `105`, `125`, and `161`.

## Frame Labels

`reverse/score-labels.csv` resolves the Director score labels:

| Frame | Label |
| ---: | --- |
| 40 | `GreenWin` |
| 50 | `Level 2` |
| 70 | `Level 3` |
| 90 | `Level 4` |
| 110 | `Level 5` |
| 130 | `Level 6` |

`reverse/score-script-details.csv` places member `98` level-controller actions
between or after those labels:

| Frame | Action member | Behavior initializer | Note |
| ---: | ---: | ---: | --- |
| 35 | 98 | 7105 | First playable/setup frame before `GreenWin` / `Level 2` labels |
| 65 | 98 | 7106 | Setup/play frame after `Level 2` intro |
| 85 | 98 | 8280 | Setup/play frame after `Level 3` intro |
| 105 | 98 | 8290 | Setup/play frame after `Level 4` intro |
| 125 | 98 | 8300 | Setup/play frame after `Level 5` intro |
| 161 | 98 | 9020 | Later/final setup frame after `Level 6` intro |

The level intro labels themselves use action member `95` at frames `50`, `70`,
`90`, `110`, and `130`. The actual level-state properties are attached to
member `98`, not to member `95`.

## Level Property Data

String extraction in `docs/reverse-analysis.md` found these behavior initializer
property lists:

| Inferred level property | `gd` | Extracted property list |
| ---: | ---: | --- |
| 1 | 3 | `[#gd: 3, #level: 1]` |
| 2 | 5 | `[#gd: 5, #level: 2]` |
| 3 | 7 | `[#gd: 7, #level: 3]` |
| 4 | 9 | `[#gd: 9, #level: 4]` |
| 5 | 12 | `[#gd: 12, #level: 5]` |

`getPropertyDescriptionList` in script `0257` confirms the two author-facing
property labels:

- property `gd` is described with the string `Number of Green:`
- property `level` is described with the string `Level:`

The score has a `Level 6` label and a later member `98` initializer at frame
`161`, but the simple string extraction currently exposes only the five
property-list strings above. Treat the frame `161` / initializer `9020` data as
not fully resolved yet.

## Script `0023.startMovie`

Disassembly and call-site rows show a very small startup handler:

```text
push -1
call cursor(1 arg)
call clearGlobals(0 args)
return
```

Interpretation: the movie hides/sets the cursor with `cursor(-1)`, clears global
state, and returns. This is the clean boot/reset entry point for level counters.

## Script `0257.exitFrame`

`0257.exitFrame` is the central level-state frame script. Important confirmed
constants in this script are:

```text
nothing
G yea
GreenWin
Level
Number of Green:
Level:
```

High-level flow from `reverse/lingo-disassembly.csv`:

```text
if gRDead == 3 then
  for sprite-like slots 18..29:
    if member is "nothing" then
      nothing()
    else
      set member to "G yea"
  updateStage()

  for sprite-like slots 35..59:
    set member to "nothing"

  wait while soundBusy(1)
  ridicule()
  ridicule()
  clearGlobals()
  go("GreenWin")

else if gGdead == gd then
  clearGlobals()
  nextLevel()
  go("Level" joined with an expression based on level and 1)

else
  go(<unresolved expression>)
end if
```

Evidence for the first branch:

- `0x5C..0x60`: `push-global 6` (`gRDead`), `push-int8 3`, `equal`
- `0x8A`: pushes constant `G yea`
- `0xA0`: calls `updateStage`
- `0xB0`: pushes constant `nothing`
- `0xC8`: calls `soundBusy(1)`
- `0xD1` and `0xD5`: calls `ridicule`
- `0xD9`: calls `clearGlobals`
- `0xDB..0xDF`: pushes `GreenWin` and calls `go`

Evidence for the second branch:

- `0xE4..0xE8`: compares global `gGdead` to property `gd`
- `0xEE`: calls `clearGlobals`
- `0xF2`: calls `nextLevel`
- `0xF4..0xFE`: pushes `Level`, reads property `level`, combines it with an
  arithmetic expression involving `1`, and calls `go`

The exact target-label expression should be treated as not fully decompiled yet:
the current disassembler names the arithmetic opcode as `subtract`, but this
needs validation before turning it into final source-level Lingo. The important
confirmed fact is that the branch builds a label from the string `Level` and the
behavior property `level`, then passes it to `go`.

## Script `0023.nextLevel`

`0023.nextLevel` handles the visual/audio transition around level advance:

```text
updateStage()
if soundBusy(1) then
  for sprite-like slots 30..32:
    if member is "nothing" then
      nothing()
    else
      set member to "R rest"
  updateStage()
  startTimer()
  wait until a timer-like property reaches 8
  loop back while needed
end if
puppetSound("ugly")
return
```

Confirmed call-sites:

- `0xEE`: `updateStage`
- `0xF4`: `soundBusy(1)`
- `0x118`: `nothing`
- `0x135`: `updateStage`
- `0x139`: `startTimer`
- `0x14D`: `puppetSound("ugly")`

This makes `nextLevel` a transition helper, not the owner of the level property
data. The `gd` and `level` values live on script `0257`; `nextLevel` mainly
resets visible red/rest state, waits on sound/timer state, and plays the `ugly`
sound.

## Working Model

- Level configuration is behavior data on script `0257`: `gd` plus `level`.
- `gd` is author-labeled `Number of Green:` and is compared against global
  `gGdead` in `0257.exitFrame`.
- The `GreenWin` branch is triggered by global `gRDead == 3`, not by `gd == 3`.
- `startMovie` clears global state at movie startup.
- `nextLevel` is called by `0257.exitFrame` after `clearGlobals()` when the
  `gGdead == gd` branch fires.
- Score labels give the visible Director navigation points, while member `98`
  setup frames carry the level-controller behavior instances.

Open items for a later pass:

- Decode the exact `go("Level" ...)` arithmetic/string expression.
- Resolve the frame `161` member `98` initializer data for the `Level 6` path.
- Confirm the runtime meaning and initial values of `gRDead` and `gGdead` by
  decompiling the relevant parts of scripts `0445`, `0579`, and `clearGlobals`.
