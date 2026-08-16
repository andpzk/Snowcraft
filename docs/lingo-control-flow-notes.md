# Lingo Control Flow Notes

Scope: recovered control-flow structure from the generated Lingo bytecode
exports. This is a bridge between raw opcode rows and future gameplay
reimplementation.

Primary generated inputs:

- `reverse/lingo-disassembly.csv`
- `reverse/lingo-pseudocode.csv`
- `reverse/lingo-basic-blocks.csv`
- `reverse/lingo-control-flow-edges.csv`
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

The block and edge CSVs are not source code yet, but they define where the
future port should recover state machines:

- use `BlockId`, `StateNames`, and `PseudoStatements` from
  `lingo-basic-blocks.csv` to identify state transitions;
- use `lingo-control-flow-edges.csv` to connect those transitions under
  conditional true/false paths;
- use `lingo-member-assignments.csv` for the concrete sprite state names;
- use `lingo-pseudocode.csv` for readable movement, sound, timer, and level
  transition statements.

The next useful step is rendering and annotating the largest DOT graphs,
starting with `0579.prepareFrame`, `0445.prepareFrame`, `0445.mouseDown`,
`0318.prepareFrame`, `0341.prepareFrame`, and `0257.exitFrame`.

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
