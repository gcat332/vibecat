# Plan 4.5 — The Prototype Diff

**Date:** 2026-08-03
**Status:** Colour, radius, type scale, motion and the face crossfade all closed. Two deliberate divergences recorded. Nothing left open on this plan's own list.
**Reference:** [`island-motion.html`](../prototypes/island-motion.html) — the design's own, named in the [spec](../specs/2026-07-31-vibecat-design.md) header.

Plan 4.5 exists because across four plans nobody diffed the implementation
against the prototype. **The deliverable is as much this written record as the
fixes** — a divergence nobody wrote down gets re-introduced or re-removed by the
next person who notices it.

## Method

Every CSS custom property, every `color:` declaration and every `font-size` in
`island-motion.html`, extracted mechanically rather than read for impressions,
then matched against its counterpart in `Sources/`. Quoted values are the
prototype's own text, with line numbers where a claim rests on one.

---

## Closed

### The island's body colour was the sprite's mix base — fixed

The prototype: `.island { background: var(--void) }` with `--void: #07080A`
(line 83). Ours was `#05070B`, whose doc comment cited "Design §7.1: the sprite
ground colour" — and that is precisely the error. §7.1 names `#05070B` as the base
the **sprite's** outline and shadow composite the accent over (`O = accent 20%
over #05070B`), which `CatPalette` uses correctly and still does. In the whole
prototype `#05070B` appears exactly twice, both inside `color-mix` for
`--sp-out`/`--sp-sh`. **Nothing in the spec names a colour for the island body**,
so the prototype is the only authority, and it says `#07080A`.

Two levels a channel, on the largest area of colour on screen, for four plans.

**Why every test agreed with it, which is the more useful half.** Two levels is
under `Raster.pixelCount(near:)`'s default tolerance of 6, so no tolerance-based
assertion could see it. And the four assertions that *were* exact each hardcoded
`Raster.Pixel(r: 5, g: 7, b: 11, a: 255)` with `// islandGroundColour` in a
comment beside it. They pinned the value we happened to choose, precisely, and so
locked the wrong one in. **A test that restates a constant is not evidence about
that constant.** All four now derive from it via `Raster.Pixel(_ colour: RGBA)`,
and `theIslandGroundIsThePrototypesVoidNotTheSpritesMixBase` pins it against the
prototype's literal instead.

### The corner radius was never a divergence — claim withdrawn

`plans/README.md` recorded this as a deliberate divergence to be justified: "The
prototype uses `9px` (`--fillet`, six occurrences). We use `bottomRadius = 15`.
**Keep 15. Record why**".

**The prototype's island uses 15px, the same as ours.** Line 83, literally:

```css
.island{ background:var(--void); border-radius:0 0 15px 15px; … }
```

`--fillet: 9px` is a different feature: the size of the two concave radial
gradients welding the island to the bezel (`.island::before` / `::after`, lines
98–100). §5.5 removed those on 2026-08-01 as measured-wrong — the flare "read as a
hook the real notch does not have". So there is no radius divergence to justify,
and the thing 9px belonged to no longer exists.

**Where the prototype and the spec disagree, the spec's dated correction wins.**
The prototype still carries the claim §5.5 struck out, in a comment above those
fillets: "Apple's own cutout does not meet the bezel at a right angle, so neither
does this." §5.5 measured that on the running app and recorded it as wrong. The
prototype is stale on this point; do not re-derive the fillets from it.

### Already confirmed matching, not re-litigated

All four state colours (`#3FD99B`, `#5B9DF9`, `#FFA63C`, `#FF5C5C`), dormant's
`--dim: #5A6273`, and — exactly — all five accent-derived sprite tones against
`CatPalette`'s `.body/.highlight/.lightest/.outline/.shadow`.

---

## Closed, continued

### Every piece of text in the drawer was the wrong colour family — fixed

The prototype has two named text greys and uses them 32 times between them:

| token | value | uses |
|---|---|---|
| `--bone` | `#EDEFF4` | 16 |
| `--haze` | `#8A93A6` | 16 |
| `--dim` | `#5A6273` | 12 |

We use neither. Every label in `QuestionFace` and `ChoiceRow` is `Color.white` or
`Color.white.opacity(…)`, which is a different family, not a near miss:

| ours | renders as, over `--void` | prototype's intent | gap |
|---|---|---|---|
| `Color.white` | `#FFFFFF` | `--bone` `#EDEFF4` | 18/16/11 levels too bright |
| `.white.opacity(0.65)` | ≈ `(168,169,169)` | `--haze` `(138,147,166)` | ~30 levels too light, **and neutral where the prototype is cool** |
| `.white.opacity(0.55)`, `0.5`, `0.35` | neutral greys | `--haze` / `--dim` | same shape of error |

The systematic part is the last column. `--haze` has `b − r = 28`; white-over-void
has `b − r = 1`. The prototype's secondary text is a deliberate cool blue-grey and
ours is dead neutral, so no opacity value can reach it — this needs the tokens,
not a tuning pass.

**Fixed 2026-08-03.** `boneColour`, `hazeColour` and `hairlineOpacity` now sit
beside `islandGroundColour`, and which tone each label takes is read off the
prototype's own markup rather than guessed: `.ask-q` → `--bone`; `.detail.mono` →
`--haze`; `.choice` → `--bone` on the recommended row and `--haze` on the rest,
which is the prototype's `.choice` against `.choice.alt`; `.confirm .tally` →
`--haze`; Send's label → the prototype's own `#0A0B0D` on the accent.

The assertion that catches a regression is the **absence of pure white**: 437
white glyph pixels before, 0 after. A bare "is there any `--bone`" check would
*not* have caught it — antialiasing white text over a near-black ground
incidentally produces pixels within tolerance of `--bone`, so that assertion
passed before the tones existed. Recorded in the test, because it is the same trap
as the four hardcoded ground pixels above.

### The type scale has now been compared — and aligned

The prototype runs a dense ten-step ladder: **9, 9.5, 10, 10.5, 11, 11.5, 12,
12.5, 13, 14.5px**, with `12.5px` (9 uses) and `11px` (8 uses) dominant.

We used **10, 11, 12, 13** and `RightFlankFont.size = 12`, with nothing at 12.5 —
the prototype's most common size.

**Aligned 2026-08-03** for the drawer, which is where the ladder actually applies:
the question title 14.5 (`.ask-q`, and it was borrowing `RightFlankFont`, the
*collapsed island's* count font, which was never chosen for it and would have
dragged the island along if tuned there); the command body 11.5 mono
(`.detail.mono`); choice labels 12.5 (`.choice`); the tally and the reply label
11.5 (`.confirm .tally`).

Deliberately **not** touched: `RightFlankFont.size = 12` itself. It is measured
against a real digit advance for `CollapsedLayout.Metrics.standard`, so changing it
moves the island's geometry, not just its type — that belongs with a geometry pass,
not a type pass.

### `--t-face: 190ms`, the face crossfade — implemented

§9.1 specifies it ("Face crossfade `190ms`, fade up 5pt with a 3pt blur"), the
prototype declares it, and it had been recorded as unassigned twice — Plan 3's
follow-ups and then this document.

`FaceCrossfade` carries all three of §9.1's numbers, and applies them to a face's
own *content* rather than to the drawer's frame, because §9.1's rule is that
"faces never slide in from outside; they fade in **inside** a shape that is
already the right size". `DrawerView` still sizes itself from
`question.face.height`; the height spring remains the only thing that moves the
shape. Today's one face swap is rows ↔ the reply field; Plan 5's session list gets
it free by being another branch.

**One measured `ImageRenderer` quirk found writing the test, worth knowing before
anyone tests opacity again:** `.opacity(0)` is *ignored* — a label at opacity 0
rendered the same 372 opaque pixels as one at full opacity, while `.offset` and
`.blur` applied normally. And `opaquePixelCount` cannot see opacity in between
either, since a half-alpha pixel still has `a > 0`. So the test asserts mid-flight
against rest, which is both robust and the state a person actually sees.

---

## Motion: the cost decision is taken, so this is unblocked

The motion half of this plan collided with
[the badge transform spike](../spikes/2026-08-03-badge-transform-cost.md) measured
the same day. **Resolved 2026-08-03: the owner accepted ~12% of a core as the
island's intended resting cost**, recorded there as a deliberate divergence from
the old 0.35% figure rather than a defect left unfixed. The motion is the design;
the cost is what it costs.

So everything below may now be matched with view transforms. What follows is still
the accounting of *what* has to change and why the plan file's own description of
it was wrong — the price is simply no longer a blocker.

### Done: four of the five moods now carry the prototype's own motion

Implemented 2026-08-03 as `CatMood.pulse`, a view-level transform applied by
`CatCanvas` — the same mechanism the badges use, so no `TimelineView` tick is
needed to move the cat.

| mood | prototype | ours | verdict |
|---|---|---|---|
| `trot` | `translateY(-2px)` 1s | `-2pt`, 1s | **matched exactly** |
| `sleep` | `translateY(2px)` 3s | `+2pt`, 3s | **matched exactly** |
| `happy` | `scale(.6→1.12→1)` 540ms `--spring-w` | one-shot spring overshoot | **matched in figure** |
| `call` | `scale(1.09)` 1.1s | `-3pt` translate, 1.1s | **deliberate divergence** |
| `dead` | `rotate(±4deg)` 2.4s | `±1pt` sway, 2.4s | **deliberate divergence** |

**The blur claim this all turned on was backwards.** `ResolvedCat.verticalOffset`
asserted for three plans that "a fractional offset would blur the grid", and it was
never measured. Measured now
(`theCatsGridSurvivesATranslateButNotAScale`): a translate leaves the sprite at
**9 distinct colours** at every offset tried, whole *or* fractional, at 1× and 2×.
`.scaleEffect(1.09)` — the prototype's own `callout` — takes it to **95 colours at
1×, 130 at 2×**. Translation is exact; scaling is what dissolves the grid.

So the whole-cell rule was guarding the wrong thing, and the two divergences above
are the honest consequence: `call` and `dead` cannot match the prototype without a
permanently soft sprite in the two states where the cat matters most. `happy` is
the one scale we do match, because a 540ms blur ends.

`call` is `-3pt` rather than `-2pt` for a reason worth keeping: §7.2 names two
*different* motions, a "quick bob" and an "attention pulse", and the prototype
carried that distinction in the transform *kind*. Collapsing both to translates
would have made them the same motion at slightly different speeds, so the
distinction moved into the amplitude.

### And the cost turned out to be per-island, not per-animation

Adding `trot`'s transform put two continuous animations on the `running` island.
The within-run `running − dormant` delta — the 12 fps timeline cancels, being in
both — moved from **+2.89pp to +3.64pp**: about **+0.75pp for a whole second
animation**, against ~10pp for the first. Adding `sleep`'s drowse to dormant then
took it 10.16% → **11.59%**, the same order again.

That is what unblocked `sleep`. Plan 3 made it still on a real measurement, but
that measurement priced the cell-swapping mechanism at 3.6–4.1%; a transform on an
island already animating is under a point. **The reasoning was sound and the number
it assumed was wrong** — which is the third time on this project that a genuine
measurement turned out to have priced the wrong mechanism.

### The trot amplitude is not the one-line fix it was recorded as

`plans/README.md` says: "`trot`'s amplitude is simply halved, … `trot`'s missing
pixel is a one-line fix and should not wait for that decision."

It is not, and `CatMood.offset`'s own comment already says why: "a step stays one
cell, because two would carry the ear tips off the top of the canvas." The sprite
is 18×14 with the ear tips on row 0, and our motion shifts *cells within the
grid*, so a two-cell rise clips them. **Both documents are right about their own
subject and the plan file drew the wrong conclusion from it.**

The prototype does not shift cells. It does `translateY(-2px)` on the whole
element, inside a container with room, so nothing clips. Matching it means moving
the cat's motion from cell-shifting to a **view transform** — which is not a
one-line change, and:

### …a view transform is now known to be the expensive option

The spike measured a repeating SwiftUI transform on the badge at **+12% of a core**
in release, against 0.35% for the pre-transform island and ~3% for a 12fps
timeline. It never re-invokes the `Canvas` renderer — 0.0 draws/s — but the
content being cached is not the same as the animation being free.

So every remaining motion item now carries a price, and the price runs the wrong
way from the intuition the badge rewrite was built on:

| item | prototype | matching it costs |
|---|---|---|
| `trot` amplitude | `translateY(-2px)` | a view transform on the cat |
| `call` | `scale(1.09)` | a view transform, plus accepting grid interpolation |
| `happy` | `scale(.6 → 1.12 → 1)` | same |
| `dead` | `rotate(±4deg)` | same |
| motion curves | explicit cubic-beziers over `--t-shape: 440ms` | nothing — see below |

**Answered 2026-08-03: the budget is whatever the design's motion costs, and ~12%
is accepted.** So these four are now ordinary work rather than a decision. Two
things follow from *how* the cost behaves, though, and they shape the order:

- **Do `trot` first and re-measure before the other three.** It is the one whose
  mechanism change (cells → view transform) is forced rather than chosen, and it
  answers the question the spike could not: whether the cost is per-animation or
  per-island. If four transforms cost 4× one, that is a fact the owner accepted
  12% without knowing.
- **`call`, `happy` and `dead` still carry the *other* decision**, which the cost
  decision did not touch: `scale` and `rotate` on an 18×14 sprite either
  interpolate — blurring the grid the whole-cell rule exists to protect — or need a
  second set of frames drawn at the larger size. That is a fidelity choice, not a
  budget one, and it is still open.

### The motion curves — measured, and retuned

`--spring-w: cubic-bezier(.32,1.5,.5,1)` and `--spring-h: cubic-bezier(.34,1.22,.5,1)`
over `--t-shape: 440ms`, against our `.spring(response: 0.42, dampingFraction:
0.72)` and `0.42/0.78`.

This document's own earlier note said the difference "will not be settled by
matching numbers", because a spring settles asymptotically where a bezier lands
exactly. **That is true about the curve shape and it was the wrong conclusion to
stop at.** `Spring` is evaluable (macOS 14+, this package's floor) and a
cubic-bezier is four control points, so both can be sampled and subtracted —
`MotionCurveComparison`, env-gated with `VIBECAT_MOTION_CURVES=1`.

What that turned up is not a matter of feel:

| | prototype | ours, before | ours, now |
|---|---|---|---|
| width overshoot | **8.0%** | 3.8% (`0.72`) | **8.3%** (`0.62`) |
| height overshoot | **1.5%** | 2.0% (`0.78`) | **1.5%** (`0.80`) |
| width ÷ height | **5.3×** | **1.9×** | **5.5×** |

**§9.1 states a rule — "width overshoots more than height, so the island reads as
one body with mass rather than a resizing box" — and the old values very nearly
erased it.** 1.9× against the prototype's 5.3×, and nothing anywhere asserted the
rule at all. It now has a test with a floor set from the prototype's own ratio, so
a later tuning pass that flattens it fails rather than passing on a technicality.
The two literals also moved into `IslandMotion`; they had been sitting ~350 lines
apart in `IslandView`, which is part of why the relationship between them went
unexamined.

**Still not matched, and permanently so:** the prototype's width curve is at 65.6%
of its travel by 75ms where ours is at 35.8% — worst deviation 29.8%, all of it
front-loading. A bezier can leap from rest; a spring accelerates. That is inherent
to the two mechanisms and no parameter closes it. Recorded here so nobody hunts for
one.

These fire on a state change and then stop, so none of it touches the resting cost.

---

## Also found, unlisted anywhere before

- **`--ease: cubic-bezier(.22,.9,.28,1)`** is the prototype's general-purpose
  curve, used for the hover reveal, the debug ghost's fade and the island's own
  `border-radius` transition. Never compared against anything of ours.
- **`--carbon: #14161B`** and **`--hairline: rgba(255,255,255,.09)`** have no
  counterpart in `Sources/` at all. `--hairline` is the likely intent behind our
  `Color.white.opacity(0.05)`/`(0.06)`/`(0.08)` divider fills, which are three
  different values for what the prototype treats as one token.
