# Plan 4.5 — The Prototype Diff

**Date:** 2026-08-03
**Status:** In progress. Colour partly closed, radius resolved, motion blocked on a cost decision.
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

## Open defects

### Every piece of text in the drawer is the wrong colour family

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

**Not yet fixed** because it is more than a constant swap: it needs `--bone` /
`--haze` / `--hairline` (`rgba(255,255,255,.09)`) introduced as named tones beside
`islandGroundColour`, and a judgement per label about which role it plays, read off
the prototype's own drawer markup rather than guessed.

### The type scale has still never been compared

The prototype runs a dense ten-step ladder: **9, 9.5, 10, 10.5, 11, 11.5, 12,
12.5, 13, 14.5px**, with `12.5px` (9 uses) and `11px` (8 uses) dominant.

We use **10, 11, 12, 13** and `RightFlankFont.size = 12`. Nothing at 12.5, which is
the prototype's single most common size. Whether the half-steps matter at these
sizes is a real question — SF at 12 vs 12.5 differs by less than a pixel of cap
height — but it has not been asked, let alone answered.

### `--t-face: 190ms`, the face crossfade, is still not implemented

§9.1 specifies it ("Face crossfade `190ms`, fade up 5pt with a 3pt blur") and the
prototype declares it. Already recorded as never assigned to a task in Plan 3's
follow-ups; still true.

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

### The motion curves are the one motion item that is not cost-blocked

`--spring-w: cubic-bezier(.32,1.5,.5,1)` and `--spring-h: cubic-bezier(.34,1.22,.5,1)`
over `--t-shape: 440ms`, against our `.spring(response: 0.42, dampingFraction:
0.72)` and `0.42/0.78`. The intent translated — 0.42 ≈ 420ms against 440, and
width overshoots more than height in both — but a spring settles asymptotically
where a bezier lands exactly, so this is where the feel diverges most and it will
not be settled by matching numbers. These fire on a state change and then stop, so
they are not part of the resting cost. **Render or record both and compare with an
eye**; `VIBECAT_GIF=…` exists for exactly this.

---

## Also found, unlisted anywhere before

- **`--ease: cubic-bezier(.22,.9,.28,1)`** is the prototype's general-purpose
  curve, used for the hover reveal, the debug ghost's fade and the island's own
  `border-radius` transition. Never compared against anything of ours.
- **`--carbon: #14161B`** and **`--hairline: rgba(255,255,255,.09)`** have no
  counterpart in `Sources/` at all. `--hairline` is the likely intent behind our
  `Color.white.opacity(0.05)`/`(0.06)`/`(0.08)` divider fills, which are three
  different values for what the prototype treats as one token.
