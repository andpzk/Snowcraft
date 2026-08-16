# Snowcraft Sound/Action Notes

Scope: sound cast members, exported WAV samples, score sound channels, and
Lingo call-site evidence. The repeatable mapping is implemented in
`tools/export-sound-map.ps1`.

## Confirmed Cast-to-WAV Mapping

The repeatable join is through `KEY*`, not through score sound channels.

For sound resources, `reverse/key-map.csv` stores indexes with an observed
`+3` offset:

```text
ParentIndex - 3 == sound CASt resource index
ChildIndex  - 3 == sndH or sndS resource index
```

This maps the named sound cast members to the exported WAV files:

| Sound cast | CASt | sndH | sndS | WAV | Seconds |
| --- | ---: | ---: | ---: | --- | ---: |
| short_chirps | 77 | 80 | 82 | `reverse/sounds/05_idx-82_rate-22254_bytes-12672.wav` | 0.569 |
| step | 196 | 401 | 363 | `reverse/sounds/00_idx-363_rate-22254_bytes-7285.wav` | 0.327 |
| laugh | 239 | 244 | 245 | `reverse/sounds/02_idx-245_rate-11025_bytes-28913.wav` | 2.622 |
| ugly | 247 | 255 | 256 | `reverse/sounds/04_idx-256_rate-11127_bytes-20665.wav` | 1.857 |
| Whoosh | 263 | 267 | 268 | `reverse/sounds/06_idx-268_rate-11127_bytes-10112.wav` | 0.909 |
| kids3 | 269 | 274 | 275 | `reverse/sounds/07_idx-275_rate-11025_bytes-9088.wav` | 0.824 |
| kids2 | 276 | 280 | 281 | `reverse/sounds/08_idx-281_rate-11025_bytes-6422.wav` | 0.582 |
| kids1 | 282 | 286 | 287 | `reverse/sounds/09_idx-287_rate-11025_bytes-5638.wav` | 0.511 |
| hit1 | 288 | 292 | 293 | `reverse/sounds/10_idx-293_rate-11025_bytes-4445.wav` | 0.403 |
| Whoosh Percusive | 294 | 299 | 304 | `reverse/sounds/11_idx-304_rate-11127_bytes-2135.wav` | 0.192 |
| unnamed `kMoaCfFormat_snd` | 305 | 309 | 312 | `reverse/sounds/12_idx-312_rate-11025_bytes-1784.wav` | 0.162 |
| splat | 313 | 317 | 319 | `reverse/sounds/13_idx-319_rate-11025_bytes-1159.wav` | 0.105 |
| Ahhhh! | 396 | 402 | 403 | `reverse/sounds/03_idx-403_rate-11025_bytes-13172.wav` | 1.195 |
| bird_tweets | 434 | 439 | 440 | `reverse/sounds/01_idx-440_rate-11025_bytes-13568.wav` | 1.231 |
| hit2 | 466 | 167 | 576 | `reverse/sounds/14_idx-576_rate-11025_bytes-3264.wav` | 0.296 |

`CASt 133` is also named `splat`, but it has no current `KEY*` join to `sndH`
or `sndS` and no `kMoaCfFormat_*` string. Treat it as a likely non-audio cast
member or unresolved false positive until the cast parser is stronger.

`tools/export-sound-map.ps1` emits this join to `reverse/sound-map.csv` as part
of the full reverse pipeline.

## Score Sound Channel Evidence

`reverse/score-frame-summary.csv` does not contain useful named gameplay SFX.
Only two score sound states appear:

```text
142 frames: Sound1CastIndex 0, Sound2CastIndex 0
 24 frames: Sound1CastIndex 0, Sound2CastIndex 88
```

`ScoreCastIndex 88` resolves through current `CAS*` parsing to missing resource
`199`, not to a named sound cast. This means the visible gameplay sounds are
probably driven by Lingo calls such as `puppetSound`, not by static score sound
channels.

## Gameplay Event Evidence

This is not a full decompile yet, but `reverse/lingo-call-sites.csv` now gives
repeatable handler-level context for sound/action grouping.

| Script | Likely role | Sound/action strings |
| --- | --- | --- |
| `0023` | movie startup, level flow, ridicule | `G windup`, `step`, `R rest`, `ugly`, `laugh`, `G yea` |
| `0318` | projectile/snowball behavior | `snowball`, `Whoosh`, `Whoosh Percusive`, `G recover`, `G hit`, `hit1`, `drop`, `splat`, `melt` |
| `0341` | projectile/snowball behavior, opposite direction/target | `snowball`, `Whoosh`, `Whoosh Percusive`, `R dead`, `R hit`, `hit1`, `drop`, `splat`, `melt` |
| `0445` | red opponent behavior | `R hit`, `R hit2`, `Ahhhh!`, `R dead`, `bird_tweets`, `short_chirps`, `R cock`, `R toss` |
| `0579` | green player behavior | `step`, `G Hit`, `G Hit2`, `G ow`, `hit2`, `G down`, `kids`, `G dead`, `G recover` |

Likely action mapping from the current evidence:

| Event/action | Sound evidence | Confidence |
| --- | --- | --- |
| walking/step movement | `0579` repeats `step`; `0023` also has `step(sp,myDirection)` | high |
| snowball throw/flight | `0318` and `0341` combine `snowball`, `Whoosh`, `Whoosh Percusive` | medium |
| snowball impact on red/green target | `0318` and `0341` combine `G hit`/`R hit`, `hit1`, `drop`, `splat` | medium |
| green/player being hit | `0579` combines `G Hit`, `G Hit2`, `G ow`, `hit2` | medium |
| red/opponent being hit or dying | `0445` combines `R hit`, `R hit2`, `Ahhhh!`, `R dead` | medium |
| idle/ambient after red state changes | `0445` contains `bird_tweets` and `short_chirps` near red behavior constants | low-medium |
| ridicule or victory flavor | `0023` contains `ridicule(n)` plus `ugly` and `laugh`; `0579` contains grouped `kids` | medium |

The `kids` string in `0579` is not itself a sound cast name, but there are
three concrete sound cast members: `kids1`, `kids2`, and `kids3`. The likely
implementation is a random or indexed selection among those three, but that
needs bytecode call-site decoding to confirm.

## Next Tooling Ideas

1. Extend the Lingo structured extractor to export constants per handler, not
   just per script. That should separate `beginSprite`, `prepareFrame`,
   `mouseDown`, `ridicule`, and `step`.
2. Improve the partial `puppetSound` call-site scanner so it can distinguish
   call arguments from nearby constants more reliably.
3. Verify `CASt 133` by improving sound cast classification. It should not be
   treated as confirmed audio unless a `KEY*` sndH/sndS relationship appears.
