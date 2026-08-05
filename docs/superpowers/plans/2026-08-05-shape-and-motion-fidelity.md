# The Island's Shape and Its Motion Implementation Plan (Plan 6.3, §5–§6 · §9.1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the island's shape and the way it moves match
`island-motion.html`, because right now **the drawer never gets wider and opening
it makes the island narrower.**

**Architecture:** Nothing new. `IslandGeometry.frames` computes
`width = leftFlank + notch.width + rightFlank` and lets `tier` touch only the
*height* — so a per-face width is the change, and everything else follows from it.
The motion work is replacing four hand-picked SwiftUI easings with the prototype's
own curves.

**Tech Stack:** Swift 6, SwiftUI with AppKit interop. **No package may be added.**

## Why this plan exists — measured, not felt

The owner used the app and reported that hover and the expansion do not match the
mockup and that the notch does not grow with the session list. An investigation
([`.superpowers/sdd/motion-fidelity-investigation.md`](../../../.superpowers/sdd/motion-fidelity-investigation.md))
found the reports were understatements:

| | prototype | ours |
|---|---|---|
| drawer width, 1 / 3 / 12 sessions | 560 / 560 / 560 | **273.1 / 273.1 / 281.2** |
| island on click-to-open | 273 → **560** (wider) | 423 → **273** (**narrower**) |
| hover, largest divergence | — | **38.1% behind at 75ms** |
| `--ease: cubic-bezier(.22,.9,.28,1)` | used in 12 places | **implemented nowhere** |

**The second row is the whole complaint.** Clicking always happens while hovering
(the `acceptsClicks` gate), so opening the drawer *loses* the 150pt hover reveal and
gains nothing — the island contracts by 150pt where the mockup expands by 287pt.
**The gesture runs backwards**, and that is what "doesn't match the mockup" felt
like.

And the width is the recorded root cause of a defect already in the register: the
session list's line 2 truncating to `As…`. Its ink saturates at 420pt; it is given
273.

## Global Constraints

- **No external dependencies.** Swift 6, macOS 14 floor.
- **The prototype is the authority on appearance and on motion.**
  [`island-motion.html`](../prototypes/island-motion.html). Its tokens, verbatim
  from lines 22–27:

  | token | value |
  |---|---|
  | `--spring-w` | `cubic-bezier(.32,1.5,.5,1)` |
  | `--spring-h` | `cubic-bezier(.34,1.22,.5,1)` |
  | `--ease` | `cubic-bezier(.22,.9,.28,1)` |
  | `--t-shape` | `440ms` |
  | `--t-hover` | `280ms` |
  | `--t-face` | `190ms` |

- **§6.3 was missing a *width* column, not heights. Corrected 2026-08-05 by Task 1.**
  An earlier draft of this plan said the spec gave two heights where the prototype
  had four. **That was wrong** — `DrawerFace` already carried all four (`question`
  288, `questionWithReply` **184**, `questionMulti` 300, `sessionList` 420), and
  `questionWithReply` is live at `QuestionModel.swift:43`. So the drawer *does*
  already shrink while a custom answer is being typed. What §6.3 never said was how
  wide any face is, and that silence was read as "whatever the collapsed island
  happens to be". Left visible because Tasks 2–6 would otherwise chase a height bug
  that does not exist.
- **`LW = 58pt` is constant (§5.3)** and that is what pins the island's left edge so
  the cat never walks sideways. **Every width change in this plan must leave the
  cat's painted left edge where it was** — Plan 6.1's Task 5 rasterised this across
  three right-flank values and it held. Do not lose it.
- **The notch is a hole (§5.1).** The black shape may span the cutout; **content may
  not.** Widening the drawer must not put anything inside the cutout.
- **A divergence from the prototype is either a fix or a written decision.** The
  `15pt` bottom radius against the prototype's `9px` is the model case: it matches
  measured hardware and the reason is written down. **This plan changes the *open*
  radius to the prototype's `20px`; do not touch the collapsed one.**
- **A test that cannot fail is not a test.** Across six plans: 6.4 shipped seven,
  6.5 caught three in its own new tests, 6.1's Task 3 found one that could not fail
  against the wiring beside it. **Name the production change that would break each
  assertion, and report a mutation that stays green rather than adjusting the test.**
- **Reading a property proves nothing about what was drawn.** Rasterise. **Count a
  colour inside a box you predicted, never across the render** — a mid-grey drew 111
  phantom hits. `Raster` is not `Equatable`. `ImageRenderer` cannot render a
  `ScrollView`; `rasteriseHosted` can, and is untrustworthy for flat backgrounds.
- **Motion cannot be checked from one frame.** `Tests/VibeCatUITests/MotionFidelityProbe.swift`
  samples an animation's curve over time and is committed for this plan. The
  env-gated `VIBECAT_GIF` / `VIBECAT_FILMSTRIP` tools write real files — use them.
- **Run the suite with `Scripts/test.sh`** (`swift test --no-parallel`; its header
  says why). Current total is **706** after Task 2 (701 after Task 1), ~22s. Zero
  warnings in debug, `-c release` and `--build-tests`.
- **Measure cost with `getrusage(RUSAGE_SELF)`. Never `ps %cpu`.** Plan 6.1 measured
  motion `off` at 0.38% of a core against `full`'s ~12%; a wider, more animated
  island must not undo that. **Re-measure both.**
- Commit subjects state the insight. Trailer
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Never `git push`.** Ask, every time.

---

## Task 1: The drawer gets its own width

**Files:**
- Modify: `Sources/VibeCatUI/IslandGeometry.swift` (`frames(rightFlank:tier:)`),
  `Sources/VibeCatUI/IslandModel.swift` (`drawerWidth`), `IslandTier`
- Modify: `docs/superpowers/specs/2026-07-31-vibecat-design.md` — a dated §6.3
  correction block in §5.5's form
- Test: `Tests/VibeCatUITests/IslandGeometryTests.swift`, `IslandModelTests.swift`

**The defect, at the line.** `frames(rightFlank:tier:)` is
`width = Self.leftFlank + notch.width + right`, and `tier` reaches only
`height = notch.height + tier.extraHeight`. So **width is a function of the tally's
digit count and nothing else** — 1 and 3 sessions produce *identical* widths, and 12
gains 8.1pt only because the tally went from one digit to two. `IslandModel
.drawerWidth` then deliberately asks for `hovering: false, tier: .rest`.

**The fix is a per-face width, the way there is already a per-face height.** §6.3
fixes heights per face and says nothing about width; that silence is what this plan
reads as the gap, and the prototype answers it: **all three expanded states are
`560px`** (lines 162–168).

**Decide and record how 560 maps to our geometry.** The prototype's island is
`--lw 58 + notch 186 + --rw` collapsed, and a flat `560px` open. Ours has a real
`NSScreen` notch whose width is read at runtime, so 560 may be literal, or
`leftFlank + notch + 316`, or content-derived. **Whichever you choose, say why, and
say what happens on a notchless display** where §5.1 falls back to a floating pill.

**Also correct §6.3's height table** in the same pass — it has two rows where the
prototype has four, and the missing `Other`-open **184** is the one with
consequences.

- [ ] **Step 1: Write the failing tests**

Assert, at minimum: `frames` at `.drawer` is wider than at `.rest`; the width at 1,
3 and 12 sessions is the *same* when open (it is a face width, not a content
width); **the cat's painted left edge does not move** between closed and open
(rasterise — this is §5.3 and it is the thing most likely to break); and nothing is
drawn inside the cutout at the new width (§5.1).

- [ ] **Step 2–4:** implement, pass, and mutation-verify — make `tier` affect only
      height again (the width tests fail); shift the left flank to absorb the extra
      width (the cat test fails); use 560 for `.rest` too (the collapsed island's
      own golden tests fail).
- [ ] **Step 5:** `VIBECAT_LIST_SHOT=/tmp/list.png Scripts/test.sh --filter sessionListShot`,
      **open the PNG**, and confirm line 2 no longer truncates to `As…`. That
      truncation is a recorded defect whose root cause this task removes; if it is
      still there, the width did not reach the row.
- [ ] **Step 6:** full suite, commit.

---

## Task 2: Opening widens instead of narrowing

**Files:** `Sources/VibeCatUI/NotchController.swift`, `IslandModel.swift`
**Test:** `Tests/VibeCatUITests/NotchControllerTests.swift`

> **Corrected 2026-08-05 by Task 2 itself. The contraction below no longer
> happens.** Re-measured on Task 1's commit before any Task 2 change, painted
> columns on `mbp14` / 3 sessions: hover+closed **423**, hover+open **560**. Task
> 1's `DrawerFace.width` fixed the endpoints, exactly as its own report predicted.
> The 423 → 273 figures in the paragraph below are the **historical** record of
> what the owner saw, kept because that is what the plan exists to explain — they
> are not a live defect, and Tasks 3–6 must not read them as one. What Task 2
> actually delivered: the rule stated once (`IslandTier.takesHoverReveal`), and
> the two things the investigation could not determine — **the §9.1 width spring
> carries the morph**, keyed to `IslandBody.restingWidth`, which moves on the click
> only because Task 1 made that property tier-aware; and **the width never moves
> backwards mid-morph** (lowest sample 423.10pt from a 423.10pt start; the only
> reversal is the settle from a 571.4pt overshoot peak, which is §9.1's own rule).
> Files touched were `IslandGeometry.swift` and `IslandView.swift`, not the two
> named above. See `.superpowers/sdd/2026-08-05-shape-and-motion-fidelity/task-2-report.md`.

Measured: hover+closed paints **423** columns, hover+open paints **273**. Clicking
always happens while hovering, so opening throws away the 150pt hover reveal and —
before Task 1 — gained nothing. **The island contracts on the gesture that should
expand it.**

The register already records the related fact: **`model.hovering` stays true for the
whole life of an open drawer**, because `click()` never clears the hover tier. So
the reveal is *notionally* still on while the width behaves as if it were off.

**Work out what should actually be true and say it, rather than patching a symptom.**
The prototype's answer is in its own CSS: the expanded states set `width:560px`
outright, and `.detail`'s `max-width` reveal is a separate transition on a separate
clock — so in the prototype the open width **does not depend on hover at all.**
That is probably our rule too, and it is worth stating in one place instead of being
an emergent property of three.

- [x] Tests first: opening never reduces the painted width, from both hovered and
      unhovered starts; and the width while open is the same either way.
      (`openingTheDrawerWidensThePaintedIslandFromEitherStart`,
      `hoveringChangesNothingAboutTheOpenIslandsPaintedExtent`.)
- [x] Mutation-verify: make the open width hover-dependent again → the "same either
      way" test must fail. (Mutation B, `revealWidth` losing its gate: it does. The
      weaker spelling — `openWidth` maxed against the collapsed width — does **not**
      bind at any realistic flank and only Task 1's `rightFlank: 5000` test sees it.)
- [x] **Then look at it in motion**: `VIBECAT_GIF=/tmp/open.gif` over the
      collapsed→open transition, and report whether the width ever moves *backwards*
      mid-animation. The investigation could not determine which curve carries
      423→273 today, because both inner `.animation(value:)` keys are unchanged when
      `drawerOpen` flips — so it may be a snap or it may ride the height spring.
      **Find out; a backwards step mid-morph would be visible and is not fixed by the
      endpoints being right.**
      Answered: the §9.1 **width** spring, and only because Task 1 made
      `IslandBody.restingWidth` tier-aware — before that neither `.animation(value:)`
      key moved, which is exactly why a static render could not see it. No backwards
      step. `/tmp/vibecat-open.gif`, 15 frames, our left edge at column 156 in every
      one of them.
- [x] Full suite, commit.

---

## Task 3: `--ease` exists in the prototype and nowhere in our code

**Files:** `Sources/VibeCatUI/IslandMotion.swift` and the four call sites
**Test:** `Tests/VibeCatUITests/IslandMotionTests.swift`

`--ease: cubic-bezier(.22,.9,.28,1)` is used **12 times** in the prototype. We use
`.easeOut` and `.easeInOut` in four places instead, which are not that curve.

SwiftUI has `Animation.timingCurve(0.22, 0.9, 0.28, 1, duration:)` — the same
four control points. **One named constant in `IslandMotion` replaces all four
sites**, which is also what stops the next divergence: the reason the shape springs
went unchecked for four plans was that they were two inline literals 350 lines apart.

- [ ] Add the curve beside the two springs, with the prototype's line number.
- [ ] Replace all four sites. **List them in the report** — if there are more or
      fewer than four, say so; the investigation counted four and may have missed
      one.
- [ ] Sample the curve with `MotionFidelityProbe` at ~10 points against the bezier
      evaluated directly, and assert they agree. **That is a real test**: `.easeOut`
      differs from this curve by a measurable amount at every interior point.
- [ ] Mutation-verify: restore `.easeOut` at any one site → the sampling test fails.
- [ ] Full suite, commit.

---

## Task 4: Hover is three clocks, not one

**Files:** `Sources/VibeCatUI/IslandView.swift` (around line 725), `IslandMotion.swift`
**Test:** `Tests/VibeCatUITests/HoverMotionTests.swift`

**Ours is one `.easeOut(0.28)` modifier covering the frame width, the reveal width
and the opacity together.** The prototype uses three clocks and two curves:

| what | duration | curve | line |
|---|---|---|---|
| `.island` `width` + `transform` | `440ms` | `--spring-w` | 84–85 |
| `.detail` `max-width` + `margin` | `280ms` | `--ease` | 125 |
| `.detail` `opacity` | `160ms` | `--ease` | 125 |

So the shape moves on the **shape** clock — the same 440ms spring as the expand —
while the revealed text has its own shorter, non-overshooting clock, and its fade is
shorter still. Ours collapses all three into 280ms with no overshoot, which is why
it reads as a different gesture: measured, **we are 38.1% behind the prototype at
75ms** on the content curve and 29.1% behind on the shape curve, and the prototype
overshoots to 107.9% at 240ms where we never exceed 100%.

**§9.1's own rule is at stake.** It says width overshoots more than height so the
island reads as one body with mass — and hover is a width change that currently has
no overshoot at all.

- [x] Tests first: sample each of the three with `MotionFidelityProbe` against the
      prototype's curve; assert the shape curve **exceeds 100%** during the hover
      (that single assertion is what the current code cannot pass); assert the
      opacity finishes before the width does.
- [x] Mutation-verify: collapse the three back onto one clock → at least two tests
      must fail, and say which.
- [x] **`VIBECAT_GIF=/tmp/hover.gif`**, and put the artefact path in the report so
      the owner can compare it against the prototype in a browser. **You cannot see;
      do not report an impression.**
- [x] Full suite, commit.

**Done, commit below. `.superpowers/sdd/2026-08-05-shape-and-motion-fidelity/task-4-report.md`.**
Three clocks: shape on `IslandMotion.widthSpring` (108.4% peak at 268ms against the
prototype's 108.0% at 230ms, +12.5pt past the hovered width), reveal width on
`--ease`/280ms, reveal opacity on `--ease`/160ms — the last two now 0.0% from the
prototype. **The plan's two headline gaps were stale**: the 38.1% content gap was
already closed by Task 3 (identical curve *and* duration) and the 29.1% shape gap had
halved to 14.7% and changed sign. What was real, and what nobody had isolated: the
opacity ran 23.6% behind, and the overshoot was **absent** rather than approximate.
The collapse-to-one-clock mutation fails **four** tests. Two green mutations reported
rather than patched — deleting `.clipped()` from the reveal leaves all 721 green
(redundant against the enclosing `.clipShape`, and `content(cell:)`'s comment calling
it load-bearing is wrong), and a `--bone`-span assertion could not fail and was
removed. §9.1 gained a correction block: its damping figures were stale since Plan
4.5 and its "Hover reveal | 280ms" row is one row where the prototype has three.
Cost unmeasured by design — Task 6 owns it.

---

## Task 5: The radius morphs, and the height lags the width

**Files:** `Sources/VibeCatUI/IslandView.swift`, `IslandShape.swift`, `IslandMotion.swift`
**Test:** `Tests/VibeCatUITests/IslandShapeTests.swift`

Two smaller prototype behaviours, both currently absent:

1. **The bottom radius morphs `15pt → 20pt` when open** — prototype lines 162 and
   164, `border-radius: 0 0 20px 20px`, transitioned over `440ms` on **`--ease`**,
   not on the spring (line 86). Ours is fixed at 15. **Keep 15 collapsed** — that
   value matches measured hardware and its divergence from the prototype's 9px is a
   written decision that must not be "corrected".
2. **The drawer's height runs `440ms + 30ms = 470ms`** (line 132,
   `calc(var(--t-shape) + 30ms)`), so the height deliberately trails the width by
   30ms. Ours shares one response. That lag is what makes the shape read as the
   width leading and the body following.

- [x] Tests: the open radius differs from the closed one, asserted on the rendered
      corner rather than a property; the height animation's duration exceeds the
      width's by 30ms.
- [x] Mutation-verify: equalise the durations → the lag test fails. Morph the
      *collapsed* radius too → an existing collapsed golden must fail, which is the
      guard that the written 15pt decision survives.
- [x] Full suite, commit.
- [x] **Carried, as the third item:** §9.3 now reaches the island's own six shape
      and hover clocks (`IslandMotion.gated`), the fourth bypass of the kind Plan
      6.1's Task 2 closed three of.

---

## Task 6: The list at one session and at twelve, then the whole thing in motion

**Files:** `Sources/VibeCatUI/Drawer/SessionListFace.swift` and whatever Task 1
touched
**Test:** `Tests/VibeCatUITests/SessionListFaceTests.swift`

§6.3's `420pt` with rows scrolling is **correct and stays** — the prototype agrees
exactly (line 168). But the fixed height has two measured consequences:

- **One session leaves 367pt of empty black.** The prototype has the same fixed
  height, so check what *it* shows there before changing anything — if it also shows
  empty space, ours is right and this is a written decision, not a defect.
- **Twelve sessions measure 625pt of content in 420pt, and the fold lands ≈5pt into
  row 8**, shearing a text line horizontally. That reads as a rendering bug rather
  than as "there is more below". The register already assigns the *choice* of
  overflow cue here: a bottom fade, an explicit "+N more", or row-granular snapping
  so the fold never lands inside a row.

**Pick one, implement it, and say why.** Row-granular snapping is the only option
that removes the sheared glyph rather than decorating it.

- [ ] Tests: the fold never lands inside a row's glyphs at 12 sessions; the cue is
      present when content overflows and absent when it does not.
- [ ] **The closing artefact.** With everything in place, render the full
      collapsed → hover → open sequence with `VIBECAT_GIF`, and **open
      `island-motion.html` in a real browser** and compare element by element the way
      Plan 6.4 and 6.5 did — that is what found two bugs no assertion would have
      caught, twice. **Report which elements you compared and every difference.**
- [ ] **Re-measure with `getrusage`**: dormant at motion `full` and at `off`, and the
      island while open. Plan 6.1 measured `off` at 0.38% of a core and `full` at
      ~12%; a wider, more animated island must not undo that. **If it does, say so** —
      that is a finding for Plan 8, not something to hide.
- [ ] Full suite three times, zero warnings in debug and release, commit.

---

## Out of scope, deliberately

- **The Settings controls for any of this.** Plan 6.6's Display page owns "Panel
  size", the motion picker and the right-flank picker. **This plan makes the island
  match the mockup; 6.6 lets a person change it.**
- **`.agentIcon`'s empty rounded square.** Plan 6.1 left it selectable and blank;
  the marks exist in the prototype's `MARKS` and belong with whoever ships the
  picker.
- **Re-centring the island when it expands.** The prototype does; **we deliberately
  do not**, because §5.3 pins the left edge so the cat never walks sideways. Task 1
  confirmed the cat holds across all four hover × open combinations, measured on the
  cat's own face colours rather than the silhouette edge. **Task 2 must not "fix"
  this** — it is the invariant, not a divergence.
- **The right flank's content while expanded.** The prototype right-aligns it and
  shows a label where we show a number (`island-motion.html:115–118, 474–476`). Found
  by Task 1, out of its scope; belongs with Task 6's browser diff or a
  `prototype-fidelity` pass.
- **Plan 6.2's four audible checks.** Still open, still need a person's ears.

## Self-review

**Coverage of the owner's report.** "Hover doesn't match" → Tasks 3 and 4, with the
measured 38.1% gap and the missing overshoot named. "The expansion doesn't match" →
Tasks 1, 2 and 5. "The notch doesn't grow with the list" → Task 1 for the width and
Task 6 for the fixed height's consequences, **with the finding that not growing in
height is correct per both spec and prototype** so the fix is the width and the
overflow cue rather than the height.

**Placeholders.** None, but Tasks 1 and 6 deliberately ask for a *decision* rather
than prescribing one — how 560 maps onto a runtime-measured notch, and which
overflow cue. Both are design choices the spec does not settle, and inventing an
answer in a plan is how Plan 6.5 ended up with four written decisions it had to
defend.

**Type consistency.** `IslandGeometry.frames(rightFlank:tier:)`, `IslandTier`,
`IslandModel.drawerWidth`, `IslandMotion` (gaining the `--ease` curve beside its two
springs), `MotionFidelityProbe`. Task 1 changes the first three; Tasks 3–5 extend
`IslandMotion`; Tasks 3, 4 and 6 use the probe.

**What I expect to be wrong.** Task 1's mapping of `560px` onto a runtime notch
width is the load-bearing guess in this plan. The prototype hardcodes a `186px`
notch and a flat `560px` open width; a real MacBook's cutout is measured, not
assumed, and §5.1 has a notchless fallback. **If those numbers cannot be reconciled
into one rule, the honest outcome is two rules with the reason written down** — not a
magic constant that happens to look right on one machine.
