# Lingo Bytecode Notes

Scope: this note only covers the Director Lingo resources currently extracted
under `reverse/resources/Lscr`, `reverse/resources/Lnam`, `reverse/resources/Lctx`,
the generated `reverse/lingo-strings.csv`, and the existing
`tools/export-lingo-strings.ps1`.

The current goal is repeatable extraction without a full Lingo decompiler.

## External Format References

The most useful primary reference is ScummVM's Director engine:

- `engines/director/lingo/lingo-bytecode.cpp`
  - https://raw.githubusercontent.com/scummvm/scummvm/master/engines/director/lingo/lingo-bytecode.cpp
  - Contains the Director 4+ Lingo bytecode opcode table.
  - Documents `Lscr` header fields, constants, function tables, and bytecode
    argument decoding.
- ScummVM's 2026 Director debugger notes also confirm the practical model:
  - https://blogs.scummvm.org/ramyak/2026/07/09/inside-dt-scummvms-director-debugger/
  Director movies store compiled Lingo bytecode, and readable Lingo requires a
  decompiler such as LingoDec.

This Snowcraft build is Director 6.5, so the Director 5+ constant table layout
applies: 8-byte constant index entries made of `uint32 type` and `uint32 value`.

## Resource Inventory

Local Lingo-facing resources:

- `Lnam`: 1 resource, 61 names.
- `Lctx`: 1 resource, 288-byte body, not fully decoded yet.
- `Lscr`: 13 resources.
- `STXT`: already handled by `export-lingo-strings.ps1`, but this note focuses
  on bytecode-bearing Lingo chunks.

Each exported resource file includes the 8-byte resource chunk header. All
offsets below are relative to the `Lscr` or `Lnam` body after that 8-byte header.
The resource type tag itself is stored reversed in the extracted files, e.g.
`rcsL` for `Lscr`, `manL` for `Lnam`, and `xtcL` for `Lctx`.

## Lnam

`Lnam` has a stable, easy parse:

- Body offset `0x10`: names offset, `0x0014`.
- Body offset `0x12`: names count, `0x003D` / 61.
- Body offset `0x14`: Pascal string table.

Decoded names:

```text
exitFrame, preLoad, mouseDown, clearGlobals, go,
getPropertyDescriptionList, gRDead, nothing, updateStage, soundBusy, ridicule,
gGdead, nextLevel, frame, n, format, integer, default, comment, addProp, gd,
level, return, tempList, propList, beginSprite, prepareFrame, spriteNum,
myMove, random, myTempo, myClock, me, myDirection, sp, point, puppetSound,
myHits, mySteps, mn, mouseEnter, mouseLeave, oH, oV, mouseH, mouseV,
stillDown, powerTime, power, myRange, greenDead, redDead, startMovie,
step, cursor, startTimer, put, gotoNetPage, open
```

The existing string extractor finds these names, but with duplicate ASCII and
Pascal hits. A future structured extractor should parse `Lnam` directly instead
of relying on regex string scanning.

## Lscr Header Layout

The following fields decoded cleanly using the ScummVM layout and big-endian
reads. This is enough to build a repeatable `Lscr` summary tool.

```text
0x08 uint32 length
0x0C uint32 lengthAgain
0x10 uint16 codeStoreOffset
0x12 uint16 lctxIdOrScriptId
0x16 int16  parentNumber
0x24 uint16 unknown
0x26 uint32 scriptFlags
0x2E int16  assemblyId
0x30 int16  factoryNameId
0x32 uint16 eventMapCount
0x34 uint32 eventMapOffset
0x38 uint32 eventMapFlags
0x3C uint16 propertiesCount
0x3E uint32 propertiesOffset
0x42 uint16 globalsCount
0x44 uint32 globalsOffset
0x48 uint16 functionsCount
0x4A uint32 functionsOffset
0x4E uint16 constantsCount
0x50 uint32 constantsOffset
0x54 uint32 constantsStoreCount
0x58 uint32 constantsStoreOffset
```

Function table entries are 42 bytes each:

```text
0x00 int16  handlerNameIndex
0x02 uint16 unknown
0x04 uint32 bytecodeLength
0x08 uint32 bytecodeStartOffset
0x0C uint16 argCount
0x0E uint32 argNameOffset
0x12 uint16 varCount
0x14 uint32 varNameOffset
0x18..0x29 unknown/reserved
```

Argument and local variable name lists are arrays of big-endian `int16` indexes
into `Lnam`.

## Handler Table

Decoded handlers:

| Lscr | Lctx id | Assembly | Properties | Globals | Handlers |
| --- | ---: | ---: | --- | --- | --- |
| 0023 | 8 | 104 |  |  | `startMovie`, `step(sp,myDirection)`, `nextLevel(n)`, `ridicule(n)` |
| 0146 | 0 | 96 |  |  | `exitFrame` |
| 0210 | 10 | 106 |  |  | `exitFrame` |
| 0224 | 14 | 95 |  |  | `exitFrame` |
| 0257 | 2 | 98 | `gd,level` |  | `exitFrame(n)`, `getPropertyDescriptionList(propList,tempList)` |
| 0283 | 15 | 76 |  |  | `mouseDown` |
| 0308 | 9 | 105 |  |  | `exitFrame` |
| 0318 | 5 | 101 | `sp,myClock,myTempo,myRange` |  | `beginSprite(me)`, `prepareFrame(me; mn,n)` |
| 0341 | 6 | 102 | `myClock,myTempo,myRange` | `greenDead,redDead` | `prepareFrame(me; sp,mn,n)` |
| 0344 | 7 | 103 |  |  | `exitFrame` |
| 0445 | 4 | 100 | `sp,myClock,myTempo,myDirection,myMove,mySteps,myHits` | `gRDead,gGdead` | `beginSprite(me)`, `prepareFrame(me; mn)`, `mouseEnter`, `mouseLeave`, `mouseDown(oH,oV,powerTime,power,n)` |
| 0573 | 1 | 97 |  |  | `mouseDown` |
| 0579 | 3 | 99 | `sp,myClock,myTempo,myDirection,myMove,mySteps,myHits` | `gRDead,gGdead` | `beginSprite(me)`, `prepareFrame(me; mn,n)` |

Interpretive notes:

- `0579` is very likely the green player-character behavior script.
- `0445` is very likely the red opponent/target behavior script.
- `0318` and `0341` are likely projectile/collision/impact behavior scripts.
- `0257` is likely the score/level data script because it owns `gd` and `level`.
- `0023` is a movie-level script containing startup, level advance, and ridicule
  behavior.

## Constants

The structured constants table is much cleaner than regex string scanning. It
removes bytecode-looking false positives such as `A#]`, `W%Q`, and similar
ASCII fragments.

Key constants by script:

```text
0023:
  G windup, step, nothing, R rest, ugly, laugh, G yea

0257:
  nothing, G yea, GreenWin, Level, Number of Green:, Level:

0283:
  mailto:wells@nny.com

0318:
  nothing, sb, snowball, Whoosh, Whoosh Percusive, G recover, G hit,
  hit1, drop, splat, melt

0341:
  sb, snowball, Whoosh, Whoosh Percusive, R dead, R hit,
  hit1, drop, splat, melt

0445:
  shadow, R hit, R hit2, Ahhhh!, R dead, bird_tweets,
  R daze1, R daze2, R daze3, R ready, R pop, power 0,
  short_chirps, R cock, R toss, sb, integer 100000

0579:
  nothing, G ready, shadow, G Walk V1, G Walk H1, G Walk H2, G Walk V2,
  G windup, G cock, G toss, step, G Hit, G Hit2, G ow, hit2,
  G down, kids, G dead, G recover, sb, integer 100000
```

The repeated `sb` constant is probably a variable/member name or short logical
name for snowball state. It appears in projectile-related scripts and both main
actor behavior scripts.

## Opcode Evidence

ScummVM's opcode table gives a practical non-decompiler disassembly path.
Important opcodes already observed:

```text
0x01 / 0x02  return
0x03         push zero
0x04..0x14   arithmetic/comparison/logical operators
0x41 / 0x81  push int8 / int16
0x42 / 0x82  push argument count for a no-return call
0x43 / 0x83  push argument count for a returning call
0x44 / 0x84  push constant by constant-table byte offset
0x49 / 0x89  push global
0x4A / 0x8A  push `the` property
0x4B / 0x8B  push argument/property-like variable
0x4C / 0x8C  push local variable
0x4F / 0x8F  assign global
0x50 / 0x90  assign `the` property
0x51 / 0x91  assign argument/property-like variable
0x52 / 0x92  assign local variable
0x53 / 0x93  jump
0x54 / 0x94  negative jump
0x55 / 0x95  jump if zero
0x56 / 0x96  local handler call
0x57 / 0x97  named call
0x5C / 0x9C  push Director entity/property
0x5D / 0x9D  assign Director entity/property
```

This explains why the current `lingo-strings.csv` contains many fake ASCII
strings: bytecode sequences containing opcodes like `0x41`, `0x5C`, and `0x5D`
look printable when scanned as plain ASCII.

## Behavioral Snippets

Approximate bytecode disassembly gives useful behavior without reconstructing
full Lingo source.

`0023.startMovie`:

```text
push -1
call cursor(1 arg)
call clearGlobals(0 args)
return
```

`0573.mouseDown`:

```text
call clearGlobals(0 args)
push 1
call go(1 arg)
return
```

`0283.mouseDown`:

```text
push constant "mailto:wells@nny.com"
call gotoNetPage(1 arg)
return
```

`0146.exitFrame`:

```text
push 1
push 77
call preLoad(2 args)
return
```

These simple handlers are good smoke tests for any future disassembly exporter.

## Repeatable Extraction We Can Add Next

Without a full decompiler, `tools/export-lingo-bytecode-summary.ps1` now
generates these ignored CSVs:

- `reverse/lingo-names.csv`
  - Direct parse of `Lnam`, no regex duplicates.
- `reverse/lingo-scripts.csv`
  - One row per `Lscr`: resource index, Lctx id, assembly id, script flags,
    event map flags, table offsets, property/global names, counts.
- `reverse/lingo-handlers.csv`
  - One row per handler: handler name, bytecode start, bytecode length,
    argument names, local variable names.
- `reverse/lingo-constants.csv`
  - One row per constant: script, constant index, type, exact value.
- `reverse/lingo-disassembly.csv`
  - One row per opcode: script, handler, byte offset, opcode, mnemonic,
    raw operands, resolved name/constant when possible.
- `reverse/lingo-call-sites.csv`
  - One row per local/named call, with nearby pushed constants and the last
    nearby constant. This is especially useful for `puppetSound`.
- `reverse/lingo-entity-ops.csv`
  - One row per decoded Director entity/property access, including
    `sprite.memberNum`, `sprite.loc`, `sprite.locH`, `sprite.locV`, `timer`,
    and `cast.number`.
- `reverse/lingo-member-assignments.csv`
  - Derived rows for common `sprite.memberNum = cast("<state>").number`
    patterns, useful for actor state-machine reconstruction.

The disassembly does not need AST reconstruction to be valuable. Resolved
constants, globals, calls, property assignments, jumps, and `the sprite`
property access should be enough to build a state-machine map for the green and
red actors.

See `docs/lingo-state-machine-notes.md` for the current derived state map.

## Open Questions

- Decode `Lctx` fully. It likely maps context/script ids to `Lscr` resources and
  contains extra context metadata, but the exact entry format has not been
  confirmed here.
- Correlate `assemblyId` values with script cast members in `cast-index.csv`.
- Map event flags to Director events. Current evidence suggests:
  - `0x1` appears with `mouseDown`.
  - `0x20` appears with sprite `beginSprite`/`prepareFrame` behavior scripts.
  - `0x8000` appears with single `exitFrame` handlers.
  - `0x800` appears on the movie-level script containing `startMovie`.
- Decode Director entity/property operands for `0x5C/0x5D/0x9C/0x9D` so we can
  label expressions like `the locH of sprite sp`, `the member of sprite sp`,
  etc.
- Use jump targets plus constants to split `0579.prepareFrame` and
  `0445.prepareFrame` into actor state-machine blocks.
