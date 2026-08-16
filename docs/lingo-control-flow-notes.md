# Lingo Control Flow Notes

Scope: recovered control-flow structure from the generated Lingo bytecode
exports. This is a bridge between raw opcode rows and future gameplay
reimplementation.

Primary generated inputs:

- `reverse/lingo-disassembly.csv`
- `reverse/lingo-pseudocode.csv`
- `reverse/lingo-basic-blocks.csv`
- `reverse/lingo-control-flow-edges.csv`
- `reverse/lingo-control-flow-analysis.csv`
- `reverse/lingo-natural-loops.csv`
- `reverse/lingo-control-flow-analysis-manifest.csv`
- `reverse/lingo-state-transitions.csv`
- `reverse/lingo-structured-pseudocode/*.txt`
- `reverse/lingo-member-assignments.csv`
- `reverse/control-flow-graphs/*.dot`

## Current Export

`tools/export-lingo-bytecode-summary.ps1` now derives basic blocks and
control-flow edges after disassembly and stack-simulated pseudo-code generation.

Current counts:

| Output | Rows |
| --- | ---: |
| `lingo-basic-blocks.csv` | 320 |
| `lingo-control-flow-edges.csv` | 451 |
| `lingo-control-flow-analysis.csv` | 320 |
| `lingo-natural-loops.csv` | 16 |
| `lingo-control-flow-analysis-manifest.csv` | 23 |

All current control-flow targets resolve to a recovered block:

| Edge kind | Count |
| --- | ---: |
| `conditional-false` | 131 |
| `conditional-true` | 131 |
| `fallthrough` | 74 |
| `jump` | 67 |
| `loop-back` | 16 |
| `return` | 32 |

The jump target rule for this Director bytecode is:

```text
forward target = instruction offset + operand
backward target = instruction offset - operand
```

This matches the observed `jump16`, `jump-if-zero16`, and `jump-back` rows in
Snowcraft. Using the next-instruction offset was off by the opcode size and left
many targets unresolved.

## Useful Handler Shapes

`0579.prepareFrame` has the densest recovered control flow. It contains a timer
gate, state-name comparisons against the current sprite member, random movement
choices, movement updates, throw states, hit/down/recover states, and a final
return. Its basic blocks expose state names such as:

```text
G Walk V1
G Walk H1
G Walk H2
G Walk V2
G windup
G cock
G toss
G ow
G down
G recover
G ready
shadow
nothing
```

`0445.mouseDown` has two loop-back edges. This matches its role as a red
opponent click/throw handler: it scans or waits through related state/power
conditions before setting `R cock`, `R toss`, `power 0`, and cleanup states.

`0318.prepareFrame` and `0341.prepareFrame` each have a compact projectile
state graph: create/show `snowball`, move via `sprite.loc`, trigger hit states,
set `drop`, then progress the sprite member number dynamically for later impact
frames.

`0257.exitFrame` has a smaller level-flow graph:

- branch on the red-dead/global-win condition;
- loop through sprite ranges to set `G yea` and later `nothing`;
- call `ridicule()` twice;
- `go("GreenWin")`;
- branch through `nextLevel()` and `go(("Level" && (level + 1)))`.

## How To Use This For A Web Port

The block and edge CSVs now feed two port-facing views:

- use `BlockId`, `StateNames`, and `PseudoStatements` from
  `lingo-basic-blocks.csv` to identify state transitions;
- use `lingo-control-flow-edges.csv` to connect those transitions under
  conditional true/false paths;
- use `lingo-member-assignments.csv` for the concrete sprite state names;
- use `lingo-pseudocode.csv` for readable movement, sound, timer, and level
  transition statements.
- use `lingo-state-transitions.csv` for one deterministic table of state
  conditions, assigned states, sounds, globals, locations, and edge targets;
- use `lingo-structured-pseudocode/*.txt` for exact handler flow expressed as
  labeled blocks with explicit `if/else/goto`, loop-back, and return edges.
- use `docs/lingo-handler-regions.md` for the manual high-level regions of the
  gameplay-critical handlers, while retaining the generated CFG as the oracle.
- use `docs/director-runtime-semantics.md` for the runtime operations that the
  recovered Lingo expects from a future implementation.

The structured export currently emits all `23` handlers with `0` unparsed
branch conditions. The state-transition export currently emits `203` relevant
blocks.

## Dominators And Natural Loops

`tools/export-lingo-control-flow-analysis.ps1` computes reachability,
dominators, post-dominators, conditional merge blocks, and natural loops from
the exact block/edge CSVs. It validates that every reachable non-entry block
has an immediate dominator and that each natural-loop header dominates every
member of that loop.

All current `320` blocks are reachable. The `16` dominance-derived back edges
match the `16` previously classified `loop-back` edges. Important loops are:

| Handler | Header | Latch | Blocks | Role |
| --- | --- | --- | ---: | --- |
| `0579.prepareFrame` | `0x232` | `0x291` | 3 | Search green projectile pool `40..49`. |
| `0445.mouseDown` | `0x329` | `0x3DB` | 10 | Drag and charge while `the stillDown`. |
| `0445.mouseDown` | `0x3E1` | `0x448` | 3 | Search red projectile pool `50..59`. |
| `0318.prepareFrame` | `0x122` | `0x173` | 6 | Scan green targets `18..29`. |
| `0341.prepareFrame` | `0x111` | `0x192` | 8 | Scan red targets `30..32`. |
| `0257.exitFrame` | `0x68` | `0x95` | 5 | Apply `G yea` to green channels. |
| `0257.exitFrame` | `0xA6` | `0xAE` | 2 | Clear runtime/effect channels. |

The analysis currently finds `112` conditional blocks with a concrete
post-dominator merge and `19` whose branches terminate through different exits.
This is enough structure to lift many regions into `if`, `while`, and counted
loop constructs while retaining the block IR as the behavioral oracle.

## Graphviz Export

`tools/export-lingo-control-flow-graphs.ps1` converts the block and edge CSVs
into one Graphviz/DOT graph per Lingo handler. The full reverse pipeline now
runs it after `tools/export-lingo-bytecode-summary.ps1`.

Generated files are ignored under `reverse/control-flow-graphs/`. The manifest
lists script id, handler ordinal, handler name, block count, edge count, and dot
file path:

```text
reverse/control-flow-graphs/manifest.csv
```

This makes the high-branching handlers easier to inspect visually without
checking generated graph files into git.

## Structured Exports

`tools/export-lingo-structured-pseudocode.ps1` preserves every recovered CFG
edge in readable block IR. It deliberately keeps labels and gotos instead of
guessing high-level source constructs that could change behavior.

`tools/export-lingo-state-transitions.ps1` produces
`reverse/lingo-state-transitions.csv`. It extracts state conditions and
assignments plus sound, global, and location effects while retaining all true,
false, fallthrough, jump, loop-back, and return targets.
