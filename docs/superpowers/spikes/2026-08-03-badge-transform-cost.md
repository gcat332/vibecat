# Badge Transform Cost

**Date:** 2026-08-03
**Status:** Complete. The measurement `Badge.pulse` asked for. Probe kept in the tree as `Sources/VibeCatApp/BadgeCPUProbe.swift`.
**Purpose:** Settle the claim shipped in Plan 4.5's badge work — that a repeating SwiftUI transform animates for free — before Plans 5, 6 and 8 are designed around it.

**Hardware:** MacBook Pro 14″, built-in Liquid Retina XDR, 120 Hz. **OS:** Darwin 25.5.0. **Toolchain:** Swift 6.3.2.
**Method:** `getrusage(RUSAGE_SELF)`, three 3-second samples per row, wall clock measured rather than assumed. Never `ps %cpu`.

---

## The claim, and the verdict

`5b7c6f9` rewrote every badge to animate as a repeating `.scaleEffect`/`.opacity`
instead of by swapping cells, and recorded the reasoning honestly as unmeasured:

> **Not yet measured.** The claim that a repeating `.scaleEffect` does not
> re-invoke the `Canvas` renderer is reasoned from how SwiftUI composites, not
> from `getrusage`. Measure before relying on it.

**The claim is half right, and the half that is wrong is the half that mattered.**

| | claim | measured |
|---|---|---|
| Does a repeating transform re-invoke the `Canvas` renderer? | No | **No. Confirmed — 0.0 draws/s, every sample.** |
| Does it therefore cost nothing? | Yes | **No. +12% of a core.** |

The transform avoided the *redraw*. It did not avoid the *cost*. Skipping
SwiftUI's renderer is not the same as skipping per-frame work: the content is
cached, and something still ticks the animation every display frame.

## The numbers

Release build, each row adding exactly one mechanism to the row above it.

| what is running | draws/s | CPU (% of one core) | added by this row |
|---|---|---|---|
| floor: run loop only, no panel, no timer | 0.0 | 0.05 (0.03–0.07) | — |
| + `HoverMonitor` 30 Hz alone, no panel | 0.0 | 0.29 (0.28–0.30) | +0.24 |
| + dormant island composited (badge transform, no timeline) | 0.0 | **12.26 (11.46–12.70)** | **+11.97** |
| + running (12 fps timeline instead of no timeline) | 47.9 | 15.15 (14.82–15.42) | +2.89 |
| + dormant again, motion `.off` **and** system reduce-motion on | 0.0 | 11.83 (9.97–12.87) | **±0 — see §9.3 below** |

Debug build, same run order, for comparison: 0.03 · 0.31 · **10.63** · 13.27 ·
9.98. **Within noise of release.** This is not a debug artefact — which had to be
checked, because [the animation spike](2026-08-01-animation-spike.md)'s own
figures are release and comparing a debug number against them would have been
the same category of error as comparing `ps %cpu` against `getrusage`.

### This probe's noise floor, and what it can therefore prove

Across five runs the dormant row read **9.61, 10.63, 11.05, 11.47 and 12.26%**,
under varying background load (VS Code frontmost in some runs, Microsoft Teams in
others). So run-to-run variance is roughly ±1.5pp on that row, and one run's
`running` sample spread as wide as 10.00–16.87%.

That is worth stating precisely, because it sets what this instrument can and
cannot settle:

- **The regression is far outside it.** Every run puts dormant near 10–12%
  against a recorded 0.35%. Nothing about that conclusion depends on a single run.
- **Small optimisations are inside it, and therefore unmeasurable here.**
  `CatPalette`'s tone caching was measured before and after and moved the
  `running` − `dormant` delta from +2.89pp to +3.42pp — i.e. nominally the wrong
  direction, comfortably inside the spread. That change is kept on correctness
  grounds, not as a measured improvement, and the plans README says so. Anything
  claiming an effect below ~2pp needs many more samples on an idle machine.

### Against the recorded baseline

The animation spike measured, in release, on this same machine:

| | then | now |
|---|---|---|
| idle island, no timeline | **0.35%** | **12.26%** |
| dormant, 8 fps timeline | 3.61% | — |
| cell-swapping `zzz` (what the transform replaced) | 3.6–4.1% | — |
| panel + `NSHostingView`, no animation | 0.23% | — |
| 30 Hz hover timer | ~0.1–0.2% | 0.24% |

**A 35× regression on the island's resting cost, and about 3× worse than the
cell-swapping animation the rewrite existed to replace.** The hover timer
reproduces its old figure almost exactly, which is the cross-build check that the
instrument agrees with the earlier one.

### Why the cost is the transform and not something else

Nothing here is attributed by reasoning alone except the last line:

- **Not SwiftUI redrawing.** 0.0 `Canvas` draws per second, three samples, every
  dormant row. The counter is not broken: the `running` row reads 47.9/s, which
  is 12 fps × `squares`' four independently-delayed parts — the rate and the part
  count both come out exactly right, so the instrument registers redraws when
  there are redraws.
- **Not the hover monitor.** Measured standalone with no panel in existence:
  0.24%, matching its own earlier figure.
- **Not the aura.** `needsTimeline` is false in every dormant row (printed by an
  earlier revision of the probe), so no bloom is in flight during sampling.
- **Not compositing a SwiftUI window as such.** The earlier spike's own isolation
  sweep puts panel + `NSHostingView` with no animation at 0.23%. Cross-build, so
  this is the one link in the chain not closed by a same-run control — see the
  open item below, which closes it and fixes a bug at the same time.

## §9.3 is not merely unwired for badges — it is bypassed

The last row sets motion to `.off` *and* system reduce-motion on, the strongest
suppression §9.3 can express. The cost does not move: 11.83% against 12.26%,
inside the spread of either. `BadgeCanvas` never consults `MotionPreference` at
all, so **every badge animates in the configuration the design says must not
animate, and nothing a person can choose turns this 12% off.**

This was already recorded for `IslandBody.phase` and assigned to Plan 6. The
badges are a second, independent instance of the same bypass, introduced after
that note was written.

## Two wrong turns, kept because they were instructive

**A single "dormant costs 9.63%" figure, attributed to nothing.** The first run
measured only dormant and running. It established the regression and could not
say what caused it, which makes it useless for deciding what to change.

**An isolation that did not isolate.** The second run tried to separate the hover
monitor by calling `present()` and then `panel.orderOut(nil)`, assuming an
off-screen window cannot animate. It reported 10.88% for that row against 11.05%
with the panel shown — apparently pinning the entire cost on a `Timer` whose body
is `frame.contains(NSEvent.mouseLocation)`, about 3.6 ms of CPU per sample. That
absurdity is what exposed the error: `orderOut` does not stop a
`.repeatForever` animation ticking, so the row already contained the mechanism it
was meant to exclude. **The check that caught it was asking whether the number
was physically plausible for the mechanism it was being assigned to** — the same
question the animation spike's `ps %cpu` correction turned on.

## The decision: 12% is accepted, deliberately

**Taken by the owner on 2026-08-03, with these numbers in front of them.** The
options were: revert to still badges and lose the fidelity; gate them on
`MotionPreference` so the cost is at least a choice; hunt for a mechanism that is
genuinely render-server-only; or accept the cost and record it. **Accepted.**

Recorded as a **deliberate divergence from the 0.35% figure**, not as a defect
left unfixed — the distinction this project cares about. What that means
concretely:

- The island's resting cost is **~12% of one core**, and that is now the intended
  figure. The animation spike's 0.35% describes a build whose badges did not move
  and no longer describes this product.
- **Nobody should "fix" this back** by reverting the transforms. The motion is the
  design (§9, and the prototype the spec header names); the cost is what it costs.
- **The rest of Plan 4.5's motion is unblocked by this.** `trot`'s `translateY(-2px)`,
  `call`'s `scale(1.09)`, `happy`'s pop and `dead`'s rotate may now be matched with
  view transforms, at a cost of the same order per animation.

### What is still owed, given that choice

Accepting a cost is not the same as knowing its consequences, and three things
were explicitly not measured here:

- **Battery.** Every figure on this project, this spike included, was taken on
  mains power. 12% of a core sustained is a real drain claim and has never been
  checked unplugged.
- **Several sprites at once.** Plan 5 is the first thing that puts more than one
  cat on screen. If the cost is per-animation rather than per-island, the resting
  figure scales with the session count — which would change this decision.

  **Partly answered 2026-08-03, and the answer is per-island.** Plan 4.5 moved the
  cat's `trot` from a cell-swap to a view transform, putting *two* continuous
  transforms on the `running` island where there had been one. The within-run
  `running − dormant` delta — which cancels the 12 fps timeline, present in both —
  moved from **+2.89pp to +3.64pp**. So the second whole animation cost about
  **+0.75pp against roughly 10pp for the first.** Adding `sleep`'s drowse to
  dormant then took it from 10.16% to **11.59%** (spread 11.31–11.78), the same
  order again rather than another 10.

  So the ~10–12% is a fixed charge for animating at all, not a per-animation fee.
  Two consequences: matching more of the prototype's motion is nearly free once
  anything is moving, and **Plan 5's several sprites are much less alarming than
  this section originally assumed** — though several *separate* animating islands
  is still not the same experiment as several sprites inside one, and has not been
  run.
- **Thermals under load.** A dev machine running several agents is not idle. This
  probe measured an otherwise quiet system.

**Revisit the decision if any of those three comes back badly**, and re-run this
probe rather than re-reasoning about it.
- **Plan 8 is reframed again.** Not "match frame rate to distinct frames", and
  not "transforms are free" either. The correct framing is that *continuous
  animation of any kind on this sprite architecture costs about 3% (timeline) to
  12% (transform) of a core*, and the transform is the more expensive of the two.
- **`CatPalette`'s uncached tones drop in priority.** The fix-now list justifies
  it as "210 cells a frame" — but dormant draws zero frames per second, so the
  palette is not being touched at rest at all. It is real work for the `running`
  row's 47.9 draws/s and nothing else.
- **Plan 4.5's remaining cat-motion question is answered before it was asked.**
  `call`'s `scale(1.09)`, `happy`'s pop and `dead`'s rotate were held back
  because whole-cell movement protects the pixel grid. Whether to accept
  interpolation is now the *second* question; the first is that a repeating
  transform on this architecture costs 12% of a core, so adding three more is not
  a fidelity decision taken in isolation.

## Open, and the experiment that closes it

The one unclosed link is a same-run control for "composited island, no animation
at all". **The fix and the control are the same work:** make `BadgeCanvas`
consult `MotionPreference` — which §9.3 requires regardless — and the motion
`.off` row above becomes that control. If it drops to ~0.3%, the attribution is
closed by measurement rather than by the earlier spike's cross-build figure, and
a §9.3 bug is fixed in the same change.
