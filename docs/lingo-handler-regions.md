# Lingo handler regions

This document is a manual control-flow annotation of the gameplay handlers most relevant to a later port. It is derived only from:

- `reverse/lingo-structured-pseudocode/*.txt`;
- `reverse/lingo-state-transitions.csv`;
- `reverse/lingo-basic-blocks.csv`;
- `reverse/lingo-control-flow-edges.csv`.

It is not reconstructed Lingo source. A block identifier has the form `script-resource:handler-ordinal:start-offset`; ranges are half-open bytecode ranges `[StartOffset, EndOffsetExclusive)`. Calls rendered as `nothing()` and stack-cleanup statements such as `drop 1` are preserved as exporter observations and are not assigned source-level meaning here.

Across the handlers below, all CFG targets are resolved. The edge table reports no unresolved target for these handlers.

## `0579.prepareFrame`

Entry block: `579:1:0xC0` `[0xC0, 0xCD)`.

### Entry gates

1. `579:1:0xC0` `[0xC0, 0xCD)` tests `the timer > myClock + myTempo`. False goes directly to the terminal block `579:1:0x6BF`; true enters the update at `579:1:0xCD`.
2. `579:1:0xCD` `[0xCD, 0xD4)` tests `myMove > 0`. The true arm decrements it in `579:1:0xD4` `[0xD4, 0xDB)`; both arms join at `579:1:0xDB`.
3. `579:1:0xDB` `[0xDB, 0xEC)` stores `myClock = the timer` and requires `sprite(sp).memberNum > 0`. False returns at `579:1:0xFD` `[0xFD, 0xFE)`; true snapshots the current member into `mn` at `579:1:0xEC` `[0xEC, 0xFD)`.
4. `579:1:0xFE` `[0xFE, 0x10C)` compares `myDirection` with `point(3, 6)`. The true arm replaces it with that point in `579:1:0x10C` `[0x10C, 0x116)`; both arms enter the state dispatch at `579:1:0x116`.
5. `579:1:0x116` `[0x116, 0x12F)` first copies `sprite(sp).loc` to `sprite(sp - 15).loc`, then tests the first state, `mn = "G ready"`.

### State-dispatch chain

Every matched state region converges through `579:1:0x6BD` `[0x6BD, 0x6BF)`, whose only visible operation is `drop 1`, and then returns at `579:1:0x6BF` `[0x6BF, 0x6C0)`. The one exception is successful projectile allocation, which returns inside `579:1:0x24B`.

| State predicate block | High-level region and exact blocks | Observed result |
| --- | --- | --- |
| `579:1:0x116` `[0x116,0x12F)` — `G ready` | Random dispatch `0x12F`, `0x13D`, `0x15E`, `0x16B`, `0x177`, `0x17A`, `0x182`, `0x19F`, `0x1AC`, `0x1B8`, `0x1BB`, `0x1C3`, `0x1D7`, `0x1DF`, joining at `579:1:0x1F0` `[0x1F0,0x1F5)` | May enter `G Walk V1`, `G Walk H1`, or `G windup`; otherwise remains ready. Direction and `myMove` are initialized on the selected arms. Each displayed `random(10)` is a separate call in the IR. |
| `579:1:0x1F5` `[0x1F5,0x1FD)` — `G windup` | `579:1:0x1FD` tests `myMove = 0`; `579:1:0x204` `[0x204,0x21C)` performs the transition; join `579:1:0x21C` | On zero, state becomes `G cock` and `myMove = random(10) + 5`. |
| `579:1:0x21F` `[0x21F,0x227)` — `G cock` | Zero gate `579:1:0x227`; initialize `n = 40` at `579:1:0x22E`; pool loop header/body/increment at `579:1:0x232`, `0x23A`, `0x24B`, `0x291`; exhausted/nonzero join `579:1:0x29A` | On a free sprite, state becomes `G toss`, projectile member becomes `"sb" && random(4)+4`, projectile location copies the thrower, and `579:1:0x24B` returns. |
| `579:1:0x29D` `[0x29D,0x2A5)` — `G toss` | Zero gate `579:1:0x2A5`; assignment `579:1:0x2AC`; join `579:1:0x2B9` | On zero, returns to `G ready`. |
| `579:1:0x2BC` `[0x2BC,0x2C4)` — `G Walk H1` | Animation gate `0x2C4` with arms `0x2CB`/`0x2DB`; boundary corrections `0x2E8`/`0x2F4` and `0x2FE`/`0x30A`; movement `0x314`; diagonal-limit arm `0x33A`; sound gate/arms `0x347`, `0x350`, `0x357`; join `0x35D` | Alternates to `G Walk H2` while moving, or `G ready` when `myMove = 0`; may force `G windup` after the diagonal boundary test; plays `step` only when channel 1 is not busy. |
| `579:1:0x360` `[0x360,0x368)` — `G Walk H2` | Corresponding blocks `0x368`, `0x36F`, `0x37F`, `0x38C`, `0x398`, `0x3A2`, `0x3AE`, `0x3B8`, `0x3DE`, `0x3EB`, `0x3F4`, `0x3FB`, `0x401` | Same movement region, alternating back to `G Walk H1` or ending at `G ready`. |
| `579:1:0x404` `[0x404,0x40C)` — `G Walk V1` | Corresponding blocks `0x40C`, `0x413`, `0x423`, `0x430`, `0x43C`, `0x446`, `0x452`, `0x45C`, `0x482`, `0x48F`, `0x498`, `0x49F`, `0x4A6` | Alternates to `G Walk V2`; unlike the H pair, `myMove = 0` selects `G windup`. Movement, boundary, and sound logic otherwise has the same shape. |
| `579:1:0x4A9` `[0x4A9,0x4B2)` — `G Walk V2` | Corresponding blocks `0x4B2`, `0x4B9`, `0x4CA`, `0x4D8`, `0x4E4`, `0x4EE`, `0x4FA`, `0x504`, `0x52A`, `0x538`, `0x541`, `0x548`, `0x54F` | Alternates back to `G Walk V1`; `myMove = 0` selects `G windup`. |
| `579:1:0x552` `[0x552,0x55B)` — `G Hit` | Body `579:1:0x55B` `[0x55B,0x571)` | Sets `myMove = 1` and advances `memberNum` by one. The transition table records the target as the numeric expression, not a resolved cast name. |
| `579:1:0x571` `[0x571,0x57A)` — `G Hit2` | Zero gate `0x57A`; hit count and branches `0x581`, `0x590`, `0x5A5`, `0x5AD`, `0x5DA`, `0x5E2`; join `0x631` | On timer zero increments `myHits`: 1 -> `G ow`; 2 -> `G down`, hides companion/shadow and plays `hit2`; 3 -> hides main sprite, places a random death member on `sp-15`, plays `kids1..3`, and increments `gGdead`. Other counts only join. |
| `579:1:0x634` `[0x634,0x63D)` — `G dead` | Body `579:1:0x63D` `[0x63D,0x644)` | Calls the rendered `nothing()` operation and joins. |
| `579:1:0x644` `[0x644,0x64D)` — `G down` | Zero gate `0x64D`; body `0x654`; join `0x677` | On zero changes main sprite to `G ow`, companion to `shadow`, and sets `myMove = 5`. |
| `579:1:0x67A` `[0x67A,0x683)` — `G ow` | Zero gate `0x683`; body `0x68A`; join `0x69C` | On zero changes to `G recover` and sets `myMove = 5`. |
| `579:1:0x69F` `[0x69F,0x6A8)` — `G recover` | Zero gate `0x6A8`; body `0x6AF` | On zero returns to `G ready`; an unmatched state follows the false edge of `0x69F` directly to the common join. |

### Loops and exits

- The only intra-invocation CFG cycle is the free-projectile scan: `579:1:0x232` tests `n <= 49`, `579:1:0x23A` tests for `nothing`, and `579:1:0x291` increments `n`; the exact loop-back edge is `579:1:0x291 -> 579:1:0x232`. Pool exhaustion joins at `579:1:0x29A`. A successful allocation returns from `579:1:0x24B`.
- The animation/state sequences are temporal loops across repeated `prepareFrame` calls, not CFG cycles in one invocation.
- Terminal return blocks are `579:1:0xFD`, `579:1:0x24B`, and `579:1:0x6BF`.

### Side effects and ambiguities

Observed side effects are sprite-member changes, movement of `sp` and `sp-15`, projectile allocation in channels 40..49, sounds `step`, `hit2`, and `kids1..3`, and `gGdead += 1` at `579:1:0x5E2`.

- The IR displays `mn = member(memberNum)` but then compares `mn` with strings. Whether Director performs implicit member-to-name coercion or the exporter has collapsed a name lookup is unresolved.
- The ordering semantics of point comparison in `579:1:0xFE` are not established by these artifacts.
- `memberNum + 1` at `579:1:0x55B`, and the random member offset based on `G down` at `579:1:0x5E2`, rely on cast ordering. The CFG does not independently prove the symbolic identity of every resulting member.
- The threshold/boundary expression `locH > (320 - locV) * 2` and the low-coordinate corrections are exact; their intended geometric coordinate system is not documented by the bytecode.

## `0445.prepareFrame`

Entry block: `445:1:0x96` `[0x96, 0xA3)`.

### Entry gates

1. `445:1:0x96` applies the same timer gate; false returns at `445:1:0x1F4`.
2. `445:1:0xA3` tests `myMove > 0`; `445:1:0xAA` decrements it before the join at `445:1:0xB1`.
3. `445:1:0xB1` copies `sp.loc` to `(sp-15).loc`, stores `myClock`, and checks `memberNum > 0`. False returns at `445:1:0xE2`; true snapshots `mn` in `445:1:0xD1` and enters dispatch at `445:1:0xE3`.

### State-dispatch chain

| State predicate block | Region | Observed result |
| --- | --- | --- |
| `445:1:0xE3` `[0xE3,0xED)` — `R hit` | `445:1:0xED` `[0xED,0xFD)` | Immediate member change to `R hit2`. |
| `445:1:0xFD` `[0xFD,0x105)` — `R hit2` | `myMove=0` gate `0x105`; increment/test `0x10C`; death arm `0x11B`; daze arm `0x171`; join `0x18C` | On zero increments `myHits`. Exactly 2 produces `R dead` on `sp-15`, hides `sp`, 33, and 34, plays `Ahhhh!`, and increments `gRDead`; every non-2 value takes the `R daze1` arm with `mySteps=25`, `myMove=3`, and `bird_tweets`. |
| `445:1:0x18F` `[0x18F,0x197)` — `R daze1` | `445:1:0x197` | Advances to `R daze2`. |
| `445:1:0x1A7` `[0x1A7,0x1AF)` — `R daze2` | `445:1:0x1AF` | Advances to `R daze3`. |
| `445:1:0x1BF` `[0x1BF,0x1C7)` — `R daze3` | decrement/test `0x1C7`; zero arm `0x1D5`; nonzero arm `0x1E5` | Decrements `mySteps`; zero selects `R ready`, otherwise returns to `R daze1`. |

All matched and unmatched state paths converge at `445:1:0x1F2` `[0x1F2,0x1F4)`, which renders `drop 1`, then return at `445:1:0x1F4` `[0x1F4,0x1F5)`.

### Loops, exits, side effects, ambiguities

- There is no intra-invocation CFG loop. `R daze1 -> R daze2 -> R daze3 -> R daze1/R ready` is a temporal state cycle across frame calls.
- Terminal return blocks are `445:1:0xE2` and `445:1:0x1F4`.
- Side effects are companion location synchronization, red state changes, hiding sprites 33/34 on death, sounds, and `gRDead += 1` at `445:1:0x11B`.
- The non-2 branch after incrementing `myHits` includes values greater than 2; whether those are reachable under normal initialization is not proved here.
- As in script 579, `mn` member/string coercion and rendered `nothing()`/`drop 1` source semantics remain unresolved.

## `0445.mouseDown`

Entry block: `445:4:0x2DA` `[0x2DA, 0x30B)`.

### Entry gates and drag/charge region

1. `445:4:0x2DA` computes mouse offsets `oH/oV`, stores `powerTime`, and tests `sprite(sp).memberNum < cast("R hit")`. False returns at `445:4:0x328`; true changes both `sp` and sprite 33 to `R cock` in `445:4:0x30B`.
2. The held-mouse loop header `445:4:0x329` `[0x329,0x330)` tests `the stillDown`. False exits charging at `445:4:0x3DD`; true rechecks the same numeric state threshold at `445:4:0x330`.
3. A failed recheck returns at `445:4:0x3DA`. A successful recheck enters `445:4:0x341`, which moves `sp` with the mouse. `445:4:0x341` also tests `locH < (320-locV)*2`; true clamps `locH` to that expression in `445:4:0x372`.
4. `445:4:0x385` copies `sp.loc` to sprites 33 and 34 and computes `power = (timer-powerTime)/5`. `445:4:0x3B1` clamps values above 8; `445:4:0x3B8` and `0x3BF` clamp values below 0. `445:4:0x3C2` assigns sprite 34 to `cast("power 0") + power`, calls `updateStage()`, and reaches the loop-back block `445:4:0x3DB`.

### Projectile allocation region

After release, `445:4:0x3DD` initializes `n=50`. `445:4:0x3E1` tests `n <= 59`; `445:4:0x3E9` tests whether the slot is `nothing`. A free slot enters `445:4:0x3FB`, which changes `sp` and sprite 33 to `R toss`, hides sprite 34, assigns projectile member `"sb" && power`, copies the thrower location to the projectile, and returns. An occupied slot increments in `445:4:0x448` and loops.

There is no state-dispatch chain by `mn`; the two numeric comparisons against `cast("R hit")` are action-eligibility gates.

### Loops and exits

- Held-mouse loop: exact back edge `445:4:0x3DB -> 445:4:0x329`.
- Projectile-pool loop: exact back edge `445:4:0x448 -> 445:4:0x3E1`.
- Terminal return blocks are `445:4:0x328`, `445:4:0x3DA`, `445:4:0x3FB`, and exhausted-pool return `445:4:0x451` `[0x451,0x452)`.

### Side effects and ambiguities

The handler moves the red sprite during charging, mirrors location/state through sprites 33/34, updates the stage on each held iteration, and allocates a red projectile in channels 50..59.

- Eligibility depends on numeric cast ordering (`memberNum < number of cast "R hit"`), but the intended set of allowed symbolic states is not recoverable from CFG alone.
- The IR preserves division by 5 but does not establish whether Director stores `power` as an integer at this point. The subsequent cast-number addition and projectile name concatenation consume that value; rounding/coercion must be verified in a runtime implementation.
- Setting `n=100000` immediately before the return in `445:4:0x3FB` has no observable CFG role in this handler.

## `0318.prepareFrame`

Entry block: `318:1:0x6C` `[0x6C, 0x79)`.

### Entry gates and state dispatch

1. Timer gate `318:1:0x6C`: false returns at `318:1:0x216`; true checks `memberNum < 1` in `318:1:0x79`. True returns at `318:1:0x85`.
2. `318:1:0x86` snapshots `mn`, stores `myClock`, and returns at `318:1:0xA2` when `mn = "nothing"`.
3. `318:1:0xA3` tests `word 1 of mn = "sb"`. Initialization body `318:1:0xB5` sets `myRange = integer(word 2 of mn)*2` and state `snowball`; `318:1:0xDF` plays `Whoosh` when range is 16, otherwise `318:1:0xE8` plays `Whoosh Percusive`. Both join at `318:1:0xEE` and return through `0x216`.
4. `318:1:0xF1` dispatches `snowball`. `318:1:0xF9` moves by `point(-20,-10)`, decrements range, and either scans targets (`0x11E`) or changes to `drop` (`318:1:0x17F`); both outcomes converge through `318:1:0x18C` `[0x18C,0x18F)`.
5. Remaining chain: `318:1:0x18F` tests `nothing`; `318:1:0x19E` tests `drop` and body `0x1A6` moves by `point(-10,-5)` plus `memberNum+1`; `318:1:0x1CF` tests `splat`, sound gate/arms `0x1D7`, `0x1E0`, `0x1E7`, then advances in `0x1ED`; `318:1:0x1FF` tests `melt`, then advances in `0x207`. All paths return at `318:1:0x216`.

### Collision loop

`318:1:0x11E` initializes `n=18`; header `318:1:0x122` tests through 29. `318:1:0x12A` tests intersection. On intersection, `318:1:0x132` skips the target when its member number is greater than `cast("G recover")`; the skip arm is the rendered `nothing()` block `318:1:0x143` `[0x143,0x14A)`. Otherwise `318:1:0x14A` sets target to `G hit`, projectile to `nothing`, plays `hit1`, calls `updateStage()`, and sets `n=10000`. `318:1:0x173` increments and has the exact back edge `318:1:0x173 -> 318:1:0x122`; scan exhaustion joins through `318:1:0x17C`.

### Exits, side effects, ambiguities

- Terminal returns are `318:1:0x85`, `318:1:0xA2`, and `318:1:0x216`.
- Side effects are projectile movement/state progression, green hit assignment, `Whoosh`/`Whoosh Percusive`/`hit1`/`splat` sounds, and an immediate `updateStage()` on hit.
- The collision exclusion is a numeric member threshold, not an explicitly recovered symbolic state set.
- Because `mn` is an entry snapshot and `nothing` already returned at `0xA2`, the later `nothing` arm at `318:1:0x197` appears unreachable for an unchanged `mn`; dynamic coercion or side effects of `member()` are not proved, so it is retained rather than removed.
- The symbolic targets of each `memberNum+1` operation are inferred only as cast-order progression; the transition CSV deliberately records the numeric expression.
- This handler assigns the literal `"G hit"`, while `0579.prepareFrame` tests `"G Hit"`. Whether string/member-name comparison is case-insensitive is not established by these artifacts.

## `0341.prepareFrame`

Entry block: `341:0:0x5C` `[0x5C, 0x6E)`.

### Entry gates and state dispatch

1. `341:0:0x5C` stores `sp=me` and tests `memberNum < 1`; true returns at `341:0:0x6E`.
2. `341:0:0x6F` snapshots `mn`, sets `myTempo=2`, and applies the timer gate. False returns at `341:0:0x233`; true stores `myClock` and begins dispatch at `341:0:0x8E`.
3. `341:0:0x8E` tests `word 1 of mn = "sb"`. `341:0:0xA6` initializes `myRange` and `snowball`; `0xD0`/`0xD9` select `Whoosh` versus `Whoosh Percusive`, joining at `0xDF`.
4. `341:0:0xE2` tests `snowball`. Body `341:0:0xEA` moves by `point(20,10)`, decrements range, and either scans red targets or changes to `drop` at `341:0:0x19E`; both outcomes converge through `341:0:0x1AB` `[0x1AB,0x1AE)`.
5. Remaining chain: `341:0:0x1AE` tests `nothing`, whose true arm is rendered as `nothing()` in `341:0:0x1B6` `[0x1B6,0x1BD)`; `341:0:0x1BD` tests `drop` and body `0x1C5` moves by `point(10,5)` plus `memberNum+1`; `341:0:0x1EC` tests `splat`, sound gate/arms `0x1F4`, `0x1FD`, `0x204`, then advances in `0x20A`; `341:0:0x21C` tests `melt`, then advances in `0x224`. All converge at return `341:0:0x233`.

### Collision loop

`341:0:0x10D` initializes `n=30`; header `341:0:0x111` tests through 32. `341:0:0x119` tests intersection. Intersecting sprites are excluded when the resolved member equals `R dead` (`341:0:0x121`, with rendered `nothing()` arm `341:0:0x133` `[0x133,0x13A)`) or `nothing` (`341:0:0x13A`, with rendered `nothing()` arm `341:0:0x14C` `[0x14C,0x153)`). Hit body `341:0:0x153` sets the target to `R hit`, projectile and sprites 33/34 to `nothing`, plays `hit1`, and sets `n=10000`. Increment block `341:0:0x192` has the exact back edge `341:0:0x192 -> 341:0:0x111`; exhaustion joins through `341:0:0x19B`.

### Exits, side effects, ambiguities

- Terminal returns are `341:0:0x6E` and `341:0:0x233`.
- Side effects mirror script 318 in the opposite direction, plus cleanup of sprites 33/34 on a red hit.
- The later `nothing` branch is structurally present, unlike script 318's early return, and is therefore not marked unreachable.
- Cast-order and member/string-coercion ambiguities for `memberNum+1` and member comparisons remain unresolved.

## `0257.exitFrame`

Entry block: `257:0:0x5C` `[0x5C, 0x64)`. This handler is a priority chain: red-team defeat (`gRDead=3`) wins over the green-death test (`gGdead=gd`), and the fallback repeats the current frame.

### Win region (`gRDead = 3`)

1. `257:0:0x64` initializes `n=18`. Loop header `257:0:0x68` scans through 29; `257:0:0x70` preserves `nothing` through the rendered `nothing()` block `257:0:0x81` `[0x81,0x88)`, while `257:0:0x88` changes other sprites to `G yea`; increment `257:0:0x95` has exact back edge `257:0:0x95 -> 257:0:0x68`.
2. `257:0:0x9E` calls `updateStage()` and initializes `n=35`. Header `257:0:0xA6` scans through 59; `257:0:0xAE` hides each sprite, increments, and has exact back edge `257:0:0xAE -> 257:0:0xA6`.
3. `257:0:0xC4` polls `soundBusy(1)`. Busy reaches `257:0:0xCD`, whose exact back edge is `257:0:0xCD -> 257:0:0xC4`; not busy reaches `257:0:0xCF`.
4. `257:0:0xCF` calls `ridicule()` twice, `clearGlobals()`, and `go("GreenWin")`, then joins return block `257:0:0x10B`.

### Green-death and fallback regions

- `257:0:0xE4` tests `gGdead = gd`. True enters `257:0:0xEC`, which calls `clearGlobals()`, `nextLevel()`, and `go("Level" && level+1)`, then joins `0x10B`.
- False enters `257:0:0x103`, calls `go(the frame)`, and joins `0x10B`.

There is no member-state dispatch beyond the two sprite loops. Terminal return is `257:0:0x10B` `[0x10B,0x10C)`.

### Side effects and ambiguities

Side effects are bulk green celebration state, cleanup of channels 35..59, stage update, synchronous sound polling, two ridicule calls, global reset, and frame/movie navigation.

- The CFG proves call order but not whether `go(...)` transfers immediately or after the handler returns; both branches still have an explicit CFG edge to `0x10B`.
- Equality checks require exact counts (`3` and `gd`), not `>=`. Reachability when counters overshoot is not established.
- `soundBusy` polling has no yield visible in this handler. Whether Director pumps audio/events during the tight loop is a runtime-semantic question.

## `0023.step`

Entry block: `23:1:0x6A` `[0x6A, 0x76)`. There is no timer gate, state-dispatch chain, or CFG loop.

1. `23:1:0x6A` tests `sprite(sp).locH < 40`; true sets `myDirection=point(4,1)` in `23:1:0x76`.
2. `23:1:0x80` tests `locV < 40`; true overwrites direction with `point(1,4)` in `23:1:0x8C`.
3. `23:1:0x96` adds `myDirection` to sprite location and tests `locH > (320-locV)*2`; true sets state `G windup` in `23:1:0xBC`.
4. `23:1:0xC9` checks `soundBusy(1)`. Busy calls the rendered `nothing()` in `23:1:0xD2`; not busy plays `step` in `23:1:0xD9`. Both return at `23:1:0xDF` `[0xDF,0xE0)`.

Side effects are direction correction, one movement, an optional `G windup` transition, and optional step sound. The structured export does not recover the handler's parameter list or variable bindings, so `sp` and `myDirection` are documented only as consumed names. Geometric intent and `nothing()` semantics remain unresolved.

## `0023.nextLevel`

Entry block: `23:2:0xEC` `[0xEC, 0xF0)`. There is no state-dispatch chain; the handler is a sound-duration loop with an inner sprite loop and timer wait.

1. `23:2:0xEC` calls `updateStage()`, then `23:2:0xF0` polls `soundBusy(1)`. Not busy exits to `23:2:0x149`; busy enters the body.
2. `23:2:0xF9` initializes `n=30`. Header `23:2:0xFD` scans through 32; `23:2:0x105` preserves `nothing` through rendered `nothing()` block `23:2:0x116` `[0x116,0x11D)`, while `23:2:0x11D` sets other sprites to `R rest`; increment `23:2:0x12A` has exact back edge `23:2:0x12A -> 23:2:0xFD`.
3. After the scan, `23:2:0x133` calls `updateStage()` and `startTimer()`. `23:2:0x13B` polls `the timer < 8`; true reaches `23:2:0x145`, whose exact back edge is `23:2:0x145 -> 23:2:0x13B`.
4. When the timer reaches 8, `23:2:0x147` has the exact outer back edge `23:2:0x147 -> 23:2:0xF0`, rechecking sound status.
5. Once sound is not busy, `23:2:0x149` plays `ugly` and returns (`[0x149,0x150)`).

Side effects are repeated red `R rest` assignment while sound remains busy, stage updates, timer resets, and the final sound. The tight timer loop has no visible yield. It is unresolved whether repeated member assignment is intended animation staging or merely idempotent waiting behavior.

## `0023.ridicule`

Entry block: `23:3:0x160` `[0x160, 0x16A)`. There is no state-dispatch chain; this is a sound-duration animation loop.

1. `23:3:0x160` plays `laugh` and calls `updateStage()`. Outer header `23:3:0x16A` polls `soundBusy(1)`; false returns at `23:3:0x222`, true enters the animation body.
2. `23:3:0x173` initializes `n=21`. Header `23:3:0x177` scans through 29; `23:3:0x17F` preserves `nothing` through rendered `nothing()` block `23:3:0x190` `[0x190,0x197)`, while `23:3:0x197` assigns `(cast("G yea") + random(3)) - 1`; increment `23:3:0x1AE` has exact back edge `23:3:0x1AE -> 23:3:0x177`.
3. `23:3:0x1B7` tests `sprite(2).blend < 99`; true increments it by 2 in `23:3:0x1C3`. Both arms continue at `23:3:0x1D2`.
4. `23:3:0x1D2` initializes `n=3`. Header `23:3:0x1D6` scans through 17; `23:3:0x1DE` tests blend > 5, with decrement arm `0x1EA` and clamp-to-zero arm `0x1FC`; increment `23:3:0x203` has exact back edge `23:3:0x203 -> 23:3:0x1D6`.
5. `23:3:0x20C` calls `updateStage()` and `startTimer()`. Timer header `23:3:0x214` waits while `< 8`; `23:3:0x21E` has exact back edge `23:3:0x21E -> 23:3:0x214`.
6. At timer completion, `23:3:0x220` has exact outer back edge `23:3:0x220 -> 23:3:0x16A`. When the laugh sound is no longer busy, terminal block `23:3:0x222` returns.

Side effects are `laugh`, randomized green celebration members, a gradual blend increase on sprite 2, gradual blend decrease/clamping on sprites 3..17, repeated stage updates, and timer resets.

- The expression based on `cast("G yea") + random(3) - 1` proves a three-member numeric range but does not independently name all three cast members.
- Blend arithmetic bounds are asymmetric: sprite 2 can be incremented from 98 to 100, because the test is `<99`; sprites 3..17 subtract 5 only when `>5`, otherwise clamp to zero.
- As in `nextLevel`, busy and timer polling are tight CFG loops with no explicit yield, so event/audio progression depends on Director runtime behavior not represented in these artifacts.
