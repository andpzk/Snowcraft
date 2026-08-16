# Director 6.5 Runtime Semantics for Snowcraft

This document defines the compatibility behavior needed by a Snowcraft web
runtime. It is intentionally limited to semantics that affect recovered
Snowcraft Lingo. It does not describe a complete Director emulator.

## Evidence labels

- **Confirmed / source-backed** means the behavior is directly implemented in
  current ScummVM Director source, documented by Director material, or both.
  ScummVM source is still an implementation reference, not automatic proof of
  every historical Director 6.5 edge case.
- **Snowcraft-inferred** means the behavior follows from the recovered
  Snowcraft scripts, score, cast metadata, or their use of the confirmed
  runtime behavior.
- **Unresolved** means the original Director 6.5 behavior is not established
  strongly enough to require exact emulation. These cases should remain
  isolated and testable in the web runtime.

## Timer and `startTimer`

### Confirmed / source-backed

Director time is measured in ticks at 60 ticks per second. ScummVM derives its
Mac ticks from monotonic milliseconds as `millis * 60 / 1000`, then subtracts a
baseline:

- [`DirectorEngine::getMacTicks()`](https://github.com/scummvm/scummvm/blob/master/engines/director/events.cpp#L44)
- [`LB::b_startTimer()`](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-builtins.cpp#L2365-L2367)
- [`the timer` getter](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-the.cpp#L1173-L1175)
- [`the timer` setter](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-the.cpp#L1518-L1520)
- [Movie timer initialization](https://github.com/scummvm/scummvm/blob/master/engines/director/movie.cpp#L43-L60)

`startTimer` stores the current tick as the movie's last reset and therefore
makes `the timer` read zero. Setting `the timer` to `v` moves the reset baseline
so that the next read is approximately `v`; it is not just a read-only clock.
The timer belongs to the movie runtime, not to an individual sprite or handler.

Director documentation also describes a tick as 1/60 second and `startTimer`
as resetting `the timer` to zero:

- [Macromedia Director MX Lingo Dictionary](https://www.manualshelf.com/manual/macromedia/director-mx-lingo-dictionary/user-guide-english.html)
- [Director in a Nutshell, time chapter](https://www.oreilly.com/library/view/lingo-in-a/9781565924932/ch11.html)

### Snowcraft-inferred

The main prepare-frame clock checks `the timer <= myClock + myTempo`, with
`myTempo = 5`. Five ticks are about 83.33 ms. The throw-power handler records
`powerTime = the timer` and computes `(the timer - powerTime) / 5`, clamped to
0 through 8.

### Web runtime consequence

- Use a monotonic clock such as `performance.now()`, never wall-clock time.
- Convert elapsed milliseconds to integer ticks with truncation:
  `floor(elapsedMs * 60 / 1000)` for nonnegative elapsed time.
- Do not increment the timer once per rendered frame. It must continue across
  missed frames, throttling, and variable refresh rates.
- Keep a per-movie reset baseline. Implement both `startTimer` and assignment
  to `the timer`, even if the recovered game currently uses only reads.
- Snowcraft's five-tick cadence and throw-power steps must be based on these
  integer ticks.

### Unresolved

Browser background tabs heavily throttle execution. The timer should still
advance according to monotonic elapsed time, but catching up every missed game
step could diverge from Director's visible behavior. The scheduler policy
should be tested separately from timer units and reset semantics.

## `random(n)`

### Confirmed / source-backed

For positive `n`, ScummVM implements Director `random(n)` as an integer in the
inclusive range **1 through n**. It obtains a zero-based value and adds one:

- [`LB::b_random()`](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-builtins.cpp#L669-L679)
- [`RandomState::getRandom()`](https://github.com/scummvm/scummvm/blob/master/engines/director/util.cpp#L1233-L1244)

Current ScummVM clamps positive values above 65535 to 65535. For `n <= 0`, it
returns 1 through 65535. Those compatibility limits are not needed by the
known Snowcraft calls.

### Snowcraft-inferred

- `random(4) + 4` produces 5 through 8, not 4 through 7.
- `random(3)` produces 1 through 3.
- `base + random(3) - 1` produces `base`, `base + 1`, or `base + 2`.
- Movement code using `random(50)` receives 1 through 50 and never zero.

### Web runtime consequence

For positive `n`, implement `1 + floor(rng() * n)`. Keep the random-number
provider injectable so deterministic traces can use a seeded generator. Do not
use a zero-based helper directly at Lingo call sites.

### Unresolved

The exact Director 6.5 pseudo-random algorithm and seed lifecycle have not been
established. Range semantics are required; bit-identical random sequences are
not currently required for Snowcraft gameplay.

## Integer conversion and arithmetic

### Confirmed / source-backed

Current ScummVM has two relevant conversion paths:

- The `integer()` builtin rounds a floating-point argument to the nearest
  integer in Director 5 and later. C `round()` behavior makes exact halves move
  away from zero. Decimal strings are parsed as integers with version-specific
  compatibility checks.
- General `Datum::asInt()` coercion parses strings numerically and truncates a
  floating-point value toward zero in Director 4 and later.

Sources:

- [`LB::b_integer()`](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-builtins.cpp#L616-L648)
- [`Datum::asInt()`](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo.cpp#L1100-L1135)

For Director 4 and later, division of two integer Datums remains integer
division in ScummVM; mixed or floating operands use floating-point division:

- [Lingo division implementation](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-code.cpp#L859-L890)

For Snowcraft's nonnegative timer differences, integer division by 5 is
equivalent to floor division.

### Snowcraft-inferred

Projectile selection uses `integer(word 2 of mn) * 2`. The observed source
value is a single decimal digit in a name such as `"sb N"`, so neither float
rounding nor partial-string parsing affects the result. Throw power is
quantized because both timer operands and the divisor are integers.

### Web runtime consequence

- Represent Director integers distinctly enough that `int / int` can retain
  integer semantics.
- Implement `integer(float)` as nearest integer with ties away from zero.
- Implement ordinary float-to-int coercion as truncation toward zero.
- Do not replace all Lingo numeric operations with undifferentiated JavaScript
  `number` behavior; `/` in particular would otherwise produce fractions.

### Unresolved

Director 6.5 parsing of malformed or partially numeric strings has not been
verified independently from ScummVM. It is outside the observed Snowcraft
input domain and should not drive the first web implementation.

## Points, sprite locations, and comparison

### Confirmed / source-backed

`point(x, y)` coerces both coordinates to integers. ScummVM applies supported
binary arithmetic element by element, preserving a point result when the
operands are compatible. Thus point addition and subtraction are coordinate
operations, not string concatenation or vector magnitude operations:

- [`LB::b_point()`](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-builtins.cpp#L3759-L3771)
- [Array/point binary-operation mapping](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-code.cpp#L702-L767)
- [Addition and subtraction](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-code.cpp#L769-L826)

In current ScummVM's Director 6 path, point-to-point equality requires equal
length and equal components. Relational comparison is component-wise and all
compared components must satisfy the operator. A direct relational comparison
between a scalar and a point is false in Director 6 and later:

- [Array/point comparison helper](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-code.cpp#L1370-L1432)
- [Equality implementation](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-code.cpp#L1435-L1459)
- [Relational operators](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-code.cpp#L1498-L1549)

The `loc` of a sprite is its **registration point** in Stage coordinates, not
the top-left corner of its image:

- [`loc` getter](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-the.cpp#L1705-L1718)
- [`loc` setter](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-the.cpp#L2019-L2039)

### Snowcraft-inferred

Snowcraft uses point arithmetic for offsets such as `sprite.loc + point(...)`.
No gameplay-critical direct comparison between two points has been identified
in the recovered scripts. Recovered cast registration points are therefore
more important than the unexercised relational operators.

### Web runtime consequence

- Store a point as two integer components.
- Implement point addition and subtraction component-wise.
- Treat `sprite.loc` as the registration anchor everywhere: drawing, dragging,
  collision-mask placement, and scripted offsets.
- Do not silently reinterpret a location as a bitmap's top-left coordinate.
- Keep comparison logic in a dedicated compatibility helper so it can be
  corrected without changing gameplay code.

### Unresolved

The point-comparison rules above are confirmed as current ScummVM behavior but
have not been independently verified against native Director 6.5. Because
Snowcraft does not appear to depend on them, exact relational comparison should
remain a compatibility test rather than a launch blocker.

## Rectangles, registration, `intersects`, and `within`

### Confirmed / source-backed

ScummVM's `intersects` implementation contains behavior explicitly noted as
tested in Director 6:

- Two bitmap sprites using matte ink: matte-pixel against matte-pixel.
- Only the first sprite using matte ink: bounding box against bounding box.
- Only the second sprite using matte ink: first bounding box against the
  second sprite's matte pixels.
- Neither using matte ink: bounding box against bounding box.
- Non-bitmap cast types use bounding boxes even if their ink is matte.

The operand order therefore matters when only one bitmap sprite is matte:

- [`c_intersects`](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-code.cpp#L1015-L1057)
- [Pixel collision implementation](https://github.com/scummvm/scummvm/blob/master/engines/director/channel.cpp#L360-L444)

For `a within b`, current ScummVM tests whether the first sprite is wholly
inside the second. If both are eligible matte bitmaps, it uses matte containment;
otherwise it tests bounding-rectangle containment:

- [`c_within`](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-code.cpp#L1059-L1088)

A sprite bounding box is derived from the cast member rectangle, offset by the
cast registration point, and translated to the sprite's `loc`:

- [`Sprite::getBbox()`](https://github.com/scummvm/scummvm/blob/master/engines/director/sprite.cpp#L512-L524)
- [Base cast-member bounding box](https://github.com/scummvm/scummvm/blob/master/engines/director/castmember/castmember.cpp#L106-L117)
- [Bitmap registration initialization](https://github.com/scummvm/scummvm/blob/master/engines/director/castmember/bitmap.cpp#L75-L88)
- [Scaled registration offset](https://github.com/scummvm/scummvm/blob/master/engines/director/castmember/bitmap.cpp#L910-L916)

ScummVM rectangles are left/top inclusive and right/bottom exclusive. Merely
touching edges is not an intersection:

- [`Common::Rect` coordinate convention](https://github.com/scummvm/scummvm/blob/master/common/rect.h#L151-L171)
- [`contains` and `intersects`](https://github.com/scummvm/scummvm/blob/master/common/rect.h#L261-L306)

Director matte transparency is not simply "every white pixel is transparent."
ScummVM flood-fills white pixels connected to an image edge as transparent;
enclosed white regions remain opaque:

- [Bitmap matte-mask construction](https://github.com/scummvm/scummvm/blob/master/engines/director/castmember/bitmap.cpp#L551-L623)

Ink value 8 is matte in ScummVM's Director ink enumeration:

- [`InkType` values](https://github.com/scummvm/scummvm/blob/master/engines/director/types.h#L176-L196)

### Snowcraft-inferred

Recovered score data marks actor sprites 18 through 33 with ink 8, so their
bitmap pixels participate in matte collision. Projectile scripts use
`sp intersects n`, with the projectile as the first operand and the target
actor as the second. Consequently:

- If the projectile is also a matte bitmap, collision is matte against matte.
- If the projectile is not matte, its bounding box is tested against the
  target actor's matte pixels.

The projectile channels' ink metadata has not yet been recovered strongly
enough to choose between those two paths. A plain bounding-box-only port is
incorrect in either case because the second operand is a matte bitmap.
Snowcraft does not appear to call `within` in recovered gameplay scripts.

### Web runtime consequence

- Compute an unscaled bitmap box as
  `[locX - regX, locY - regY, locX - regX + width, locY - regY + height)`.
- Apply Director scaling to both dimensions and registration offsets before
  translating the box to `loc`.
- Use half-open rectangle tests so edge contact alone is not a hit.
- Build matte masks by edge-connected-white flood fill, then align each mask
  to the registration-derived bounding box.
- Preserve operand order in `intersects`; do not replace it with one symmetric
  generic overlap helper.
- Implement `within` as full containment, not any overlap, even though it is
  not currently exercised by Snowcraft.

### Unresolved

- The projectile cast members' effective ink and mask path need confirmation
  from score/cast decoding or a native runtime trace.
- Exact matte white matching under the original color depth and palette may
  differ from decoded RGBA assets. Mask generation should be cached separately
  so its threshold/palette interpretation can be corrected later.
- Rotation, skew, and nonuniform scaling edge cases are outside the recovered
  Snowcraft collision surface.

## Mouse coordinates and `stillDown`

### Confirmed / source-backed

ScummVM exposes `mouseH` and `mouseV` from the current Director window's mouse
position. The window implementation converts system coordinates to coordinates
relative to the inner movie window. `stillDown` reads the window manager's
current mouse-button-down state and returns false while input is ignored:

- [`mouseH`](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-the.cpp#L879-L881)
- [`mouseV`](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-the.cpp#L923-L925)
- [`stillDown`](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-the.cpp#L1135-L1140)
- [Window-relative mouse conversion](https://github.com/scummvm/scummvm/blob/master/engines/director/window.cpp#L479-L485)

Director reference material describes `mouseH`/`mouseV` in pixels relative to
the Stage's upper-left corner and permits negative values outside the Stage. It
also describes sprite `loc` as the registration point:

- [Learning Lingo: mouse and sprite coordinates](https://casadebender.com/reference/prog/lingo/ch06b.html)

### Snowcraft-inferred

The throw handler stores the grab offset as
`mouseH - sprite.locH`, `mouseV - sprite.locV`, then updates the sprite while
`stillDown` remains true. The offset is relative to the registration point,
not the bitmap corner. Release duration drives throw power.

### Web runtime consequence

- Convert Pointer Event client coordinates through the canvas CSS transform
  into integer logical Stage coordinates.
- Keep coordinates in the movie's coordinate system regardless of fullscreen
  or browser scaling; never feed CSS pixels directly to Lingo logic.
- Use pointer capture after `pointerdown` so drag and release continue when the
  pointer leaves the canvas.
- Keep `stillDown` true until the matching `pointerup`, `pointercancel`, lost
  capture, or window blur. Handle one active gameplay pointer initially.
- Preserve the grab offset to `sprite.loc`. Do not snap the bitmap corner or
  registration point directly to the pointer.
- Do not clamp raw `mouseH`/`mouseV` to the Stage bounds. Apply only the
  sprite constraint behavior requested by the game.

### Unresolved

Native Director behavior for multiple mouse buttons and interrupted drags is
not material to the original single-pointer game and has not been established.
The web runtime should define deterministic cancellation behavior.

## Sprite `blend`

### Confirmed / source-backed

Director-facing blend values are percentages from 0 through 100: 0 is fully
transparent and 100 is fully opaque. Current ScummVM clamps assignments to that
range and converts them to an inverted internal 0-through-255 value:

- [`blend` getter](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-the.cpp#L1647-L1649)
- [`blend` setter](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-the.cpp#L1867-L1884)
- [Macromedia Director blend discussion](https://groups.google.com/g/macromedia.director.lingo/c/VvT9tpYUwew)
- [Director 6-era Lingo sprite reference](https://www.c3.hu/docs/lingo/Ldoc_Sprites.html)

### Snowcraft-inferred

The ridicule/level-transition scripts animate sprite blend. Their integer
sequence should be preserved; opacity must not be inverted in the web port.

### Web runtime consequence

Clamp a Director blend value to 0 through 100 and render with
`globalAlpha = blend / 100` (or the equivalent CSS/WebGL alpha). Keep blend as
sprite state, independent of the decoded bitmap and cast member.

### Unresolved

Director 6-era references report color-depth-dependent quantization and unusual
out-of-range behavior in some configurations. ScummVM deliberately clamps.
Snowcraft's observed values do not require palette-era quantization, so the web
runtime should use the clamped percentage model unless native comparison shows
a visible discrepancy.

## `soundBusy(channel)` and `puppetSound`

### Confirmed / source-backed

`soundBusy(channel)` returns integer 1 or 0 based on whether the mixer handle
for that channel is actively playing. A sound merely queued for later playback
is not yet active:

- [`LB::b_soundBusy()`](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-builtins.cpp#L4072-L4088)
- [`DirectorSound::isChannelActive()`](https://github.com/scummvm/scummvm/blob/master/engines/director/sound.cpp#L352-L364)

In current ScummVM, one-argument `puppetSound member` targets channel 1 and
queues the member. A Director 4+ two-argument form supplies channel and member
and is committed immediately. A zero member stops the channel and removes its
puppet state:

- [`LB::b_puppetSound()`](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-builtins.cpp#L3182-L3252)
- [`setPuppetSound()` and `playPuppetSound()`](https://github.com/scummvm/scummvm/blob/master/engines/director/sound.cpp#L577-L612)
- [Cast-member playback and channel replacement](https://github.com/scummvm/scummvm/blob/master/engines/director/sound.cpp#L161-L234)
- [Score sound-channel commit](https://github.com/scummvm/scummvm/blob/master/engines/director/score.cpp#L1854-L1895)

Director reference material likewise states that the one-argument form uses
channel 1 and waits for the playback head to advance, loop, or `updateStage`,
whereas an explicit channel starts immediately; zero stops and unpuppets:

- [Director in a Nutshell PDF](https://elhacker.info/manuales/OReilly%204%20GB%20Collection/O%27Reilly%20-%20Macromedia%20Director%20in%20a%20Nutshell.pdf)

### Snowcraft-inferred

All recovered Snowcraft `puppetSound` calls use the one-argument form. They
therefore target channel 1 and are queued until a Stage/frame update commits
them. Snowcraft checks `soundBusy(1)`, which must reflect actual playback after
that commit rather than the existence of a pending sound request.

### Web runtime consequence

- Model at least four Director sound channels, with channel 1 fully supported.
- Separate `pendingPuppetMember` from the currently playing Web Audio source.
- One-argument `puppetSound` replaces the pending channel-1 request; commit it
  on `updateStage` or the normal score-render boundary.
- Explicit-channel `puppetSound` should commit immediately.
- `puppetSound 0` must stop playback, clear pending sound, and disable puppet
  ownership for that channel.
- `soundBusy` must inspect actual active playback and return Director integer
  1 or 0, not a JavaScript boolean and not the pending queue state.
- Starting a new committed sound on a channel replaces the previous source.

### Unresolved

ScummVM treats some looped sounds as no longer busy after the first iteration
as a game-compatibility workaround. This should not be generalized as Director
6.5 truth. The recovered Snowcraft sounds appear non-looping; any looped member
must be identified before choosing loop-specific `soundBusy` behavior.

## `updateStage`

### Confirmed / source-backed

Current ScummVM's `updateStage` refreshes sprite widgets, applies a pending
transition or renders the Stage, commits pending puppet sounds, updates the
cursor, and draws the window immediately:

- [`LB::b_updateStage()`](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-builtins.cpp#L3675-L3725)

ScummVM suppresses `go`, `play`, and `updateStage` while broadcasting a
Director 6 `prepareFrame` event:

- [`prepareFrame` dispatch guard](https://github.com/scummvm/scummvm/blob/master/engines/director/score.cpp#L760-L779)

Later Macromedia documentation describes `updateStage` as forcing an immediate
Stage update rather than waiting for the interval between frames, including
transition/sound processing:

- [Macromedia Director MX Lingo Dictionary](https://www.manualshelf.com/manual/macromedia/director-mx-lingo-dictionary/user-guide-english.html)

### Snowcraft-inferred

Snowcraft calls `updateStage` in projectile-hit and level/ridicule flows. Its
essential effects are immediate visual presentation of the current sprite
state and commitment of queued one-argument `puppetSound` audio. At least one
call can occur from prepare-frame-driven gameplay.

### Web runtime consequence

Implement a synchronous logical `flushStage()` operation that:

1. Recomputes the renderable sprite state.
2. Commits queued puppet sounds.
3. Draws the current Stage without advancing the score frame.
4. Does not recursively dispatch `prepareFrame` while already handling it.

Browser painting may physically appear on the next animation frame, but the
runtime's render snapshot and audio commit must occur at the `updateStage` call.

### Unresolved

Some Director documentation associates additional `prepareFrame`/`stepFrame`
event behavior with a Stage update, while the current ScummVM builtin does not
directly dispatch those events and explicitly guards calls during
`prepareFrame`. Exact native Director 6.5 reentrancy and event order remain
unresolved. The nonrecursive Snowcraft contract above is a deliberate,
source-informed compatibility choice until a native trace is available.

## `go` and `the frame`

### Confirmed / source-backed

ScummVM accepts frame numbers, frame-label strings, and symbols such as `loop`,
`next`, and `previous`. A string is resolved as a frame label; an integer is a
frame number:

- [`LB::b_go()`](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-builtins.cpp#L1999-L2063)

Navigation sets a skip-frame-advance flag and queues a target rather than
mutating the score frame inline. ScummVM freezes the current Lingo execution
state around navigation and resumes it after the destination frame is entered:

- [`Lingo::func_goto()`](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-funcs.cpp#L42-L117)
- [Queued current-frame update](https://github.com/scummvm/scummvm/blob/master/engines/director/score.cpp#L396-L460)

An explicit `go` suppresses normal automatic frame advance. ScummVM's score
loop also avoids sending a second `exitFrame` for the same current frame during
that explicit jump:

- [Score frame-advance and explicit-goto handling](https://github.com/scummvm/scummvm/blob/master/engines/director/score.cpp#L646-L708)

`the frame` reads the current score frame number:

- [`the frame` getter](https://github.com/scummvm/scummvm/blob/master/engines/director/lingo/lingo-the.cpp#L638-L640)

### Snowcraft-inferred

Calls such as `go("GreenWin")` and `go("Level" && (level + 1))` target score
labels. They are not URLs, DOM routes, or movie names. `go(1)` targets Director
frame 1. Snowcraft frame identifiers must remain 1-based.

### Web runtime consequence

- Build an exact label-to-frame map from the score and resolve concatenated
  strings before queuing navigation.
- Keep `currentFrame` 1-based at the Lingo boundary.
- Queue a requested destination and apply it at the score update boundary.
  Do not change `the frame` halfway through the invoking handler.
- Suppress automatic `currentFrame + 1` when an explicit destination exists.
- Avoid duplicate `exitFrame` dispatch for the frame that initiated a jump.
- A complete interpreter should suspend and resume handler execution around
  `go`. The recovered Snowcraft jump sites should still be audited for code
  following `go` before a simpler terminal-jump optimization is adopted.

### Unresolved

Cross-movie `go` forms and exact continuation behavior after a navigation are
not yet needed by the recovered Snowcraft scripts. They should not be guessed
into the game-specific runtime.

## Minimum web runtime contract

The first faithful runtime should lock in these observable rules:

1. A monotonic, per-movie, 60 Hz integer timer with reset-baseline semantics.
2. Inclusive `random(1..n)` with an injectable generator.
3. Distinct integer arithmetic, integer division, and Director conversion
   helpers.
4. Integer point arithmetic and registration-point-based sprite locations.
5. Half-open, registration-aware rectangles plus Director matte masks and
   operand-sensitive collision dispatch.
6. Logical Stage mouse coordinates, pointer capture, and persistent
   `stillDown` state through a drag.
7. Blend as clamped 0-through-100 opacity.
8. Queued one-argument channel-1 puppet audio, active-playback `soundBusy`, and
   audio commit during frame rendering or `updateStage`.
9. A nonrecursive immediate Stage flush that does not advance the score.
10. Deferred, 1-based, label-aware score navigation that suppresses automatic
    frame advance.

## Remaining native verification targets

These questions should be answered with focused Director 6.5 test movies or a
trace from the original Snowcraft executable, not by broad changes to the web
runtime:

1. Determine the projectile sprites' effective ink and confirm whether
   Snowcraft uses matte-vs-matte or box-vs-matte projectile collision.
2. Capture `updateStage` event order when called from `prepareFrame`, including
   sound start, render timing, and any recursive event dispatch.
3. Probe point relational comparisons if later recovered code depends on them.
4. Check whether any Snowcraft sound member loops and, if so, observe native
   `soundBusy(1)` across loop boundaries.
5. Compare generated matte masks against the original palette-indexed bitmaps,
   especially enclosed white regions and scaled sprites.
6. Audit every `go` site for executable statements after navigation to decide
   whether handler continuation must be implemented immediately.
