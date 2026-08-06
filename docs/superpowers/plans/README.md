# Which plan owns what

The plan boundaries were drawn in Plan 2 and have held since. This file exists
because the answer to "what is left" had to be re-derived from the spec and the
plan files twice; it is cheaper to keep it written down.

| Plan | Owns | Design | State |
|---|---|---|---|
| 1 | Socket, wire protocol, hook, Claude Code adapter, session store, the worst-state-wins rule | §2, §4 | done |
| 2 | Notch geometry, the panel, the collapsed island, hover, the aura | §5, §6.1–6.2, §9.2 | done |
| 3 | The cat, its moods and coats, badges, motion | §7, §8, §9.1, §9.3's rule | done |
| 4 | The drawer and answering — single and multi select, the destructive second ask, the reply round-trip | §6.3, §10 | done |
| 4.5 | Matching the prototype — one systematic diff of colour, radius, type scale, spacing and motion curve, and a written record of every deliberate divergence | the prototypes the spec header names | **done** — [the diff](2026-08-03-prototype-diff.md); two deliberate divergences recorded |
| 5 | The session list · plus the hover reveal's content and the sliver that shares its mechanism · plus a multi-sprite CPU measurement | §11, §9.1's reveal | **done** — [the plan](2026-08-03-session-list.md), 8 tasks; 419 tests after the raster and lapse fixes. Carried findings below |
| 6.2 | Sound — five synthesised cues, the trigger rule, Do Not Disturb | §12 | **done** — [the plan](2026-08-03-sound.md), 7 tasks plus a whole-branch review and one fix round; 509 tests. Five written decisions, and four things still needing an ear (see the plan's own closing section) |
| 6.4 | The Settings **shell** — persisted preferences, the drawer footer's mute and gear, the window the gear opens, its sidebar and the four panes' chrome · **mute wired end to end** | §14's layout, §6.4's footer | **done** — [the plan](2026-08-03-settings-shell.md), 6 tasks plus a whole-branch review and one fix round; 574 tests. **The first plan in this project's history to actually diff `settings.html`** |
| 6.5 | The Notifications page — the four alert switches, the Sound section that gives Plan 6.2's engine its sheet, stall detection, and the system-notification fallback | §14's Notifications | **done** — [the plan](2026-08-04-notifications-page.md), 7 tasks; 647 tests. The browser diff found the page did not fit its own window |
| 6.3 | The island's shape and its motion — a per-face width, opening that widens instead of narrowing, the prototype's own curves, the bezel fillets, and the list's overflow cue | §5–§6, §9.1 | **done** — [the plan](2026-08-05-shape-and-motion-fidelity.md), 6 tasks; 744 tests. Found that the drawer had no width of its own and that opening the island made it narrower |
| 6.6 | The Display page — every control whose behaviour exists: the motion picker, §11's eight session-card switches, §6.2's right flank with a real CLI mark, the coat, and a live preview that *is* `SessionRow` | §14's Display, §11, §9.3, §6.2 | **done** — [the plan](2026-08-05-display-page.md), 6 tasks; 788 tests |
| **6.8** | The Display controls with no behaviour anywhere — Clean/Detailed tiers, Meter/Dot, the four panel-size sliders, the two notch-tuning offsets, the display picker, editable state colours, Always/Never reveal | §14's Display | not written |
| **6.7** | The General and Integrations pages | §14 | not written |
| 6.1 | Keyboard answering, `Other…`, the three motion defects a motion switch exposes, the duplicate tier, and §6.2's choosable right flank | §10.1, §9.3, §6.2 | **done** — [the plan](2026-08-04-keyboard-and-switches.md), 6 tasks; 686 tests. Keyboard answering verified on hardware with a TextEdit witness, including all three key releases |
| **6** | Jump and §16's AppleScript hint — everything else that was gated on keyboard input is 6.1 | §13, §16 | not written |
| 7 | Generic adapter and custom sources — plus `SourceAdapter.icon`, so a source can point at its own icon file | §3 | **done** — [the plan](2026-08-05-generic-adapter.md), 6 tasks; 875 tests. Proved on hardware against **Codex CLI 0.145.0**, a CLI nobody wrote code for; found a main-thread hang reading an icon out of a TCC-protected directory. Carried findings below |
| **8** | Matching motion cost to motion content | §9.1's rates | not written |
| 9 | Parking a question in the session list — Escape sets it aside instead of giving up on it, and it renders as a `.rblock` under its own row | new; §11.1 + dated §2.3 and §14 corrections | **done** — [the plan](2026-08-06-parking-questions.md), 8 tasks; **936 tests**. Measured the hook protocol rather than reasoning from §2.3: the CLI blocks on a hook and prints nothing for the duration, so only one party can hold a question at a time and the answer deadline is the *hand-back*, not a safety net. Fixed two defects nobody asked about — two agents asking at once fail-opened the first, and Escape threw a question away. Carried findings below |

Everything that had no owner now has one. What follows is where each thing went
and why, so a later reader does not have to reconstruct the reasoning.

## Fix now — no plan, four small commits and one measurement

These need no design decision, so wrapping them in a plan would be ceremony.

- ~~**`.truncationMode(.middle)` on the drawer's command body.**~~ **Done
  2026-08-03.** Plan 4's `.lineLimit(1)` stopped the confirmation banner
  clipping, but SwiftUI's default `.tail` truncation ate the *destination* of a
  long command: `rm -rf /Users/dev/projects/vibe…`. Measured before the fix, at
  production width: `…/build/cache/tmp` and `…/build/cache/src` rendered with
  **exactly 0 differing pixels** — a person authorising `rm -rf` could not see
  what it was aimed at. Pinned by
  `aLongCommandBodyKeepsTheTargetBeingAuthorisedRatherThanItsHead`, which was
  watched failing at 0 first and now measures 154.
- ~~**`@MainActor` on `theConfirmationBannerNamesTheControlThatActuallyConfirms`**~~
  **Done 2026-08-03.** `QuestionFace` conforms to `View`, so even a pure static
  helper on it is main-actor isolated. The branch now builds with zero warnings.
- ~~**Cache `CatPalette`'s five accent-derived tones.**~~ **Done 2026-08-03, and
  it is not a measured win.** Two corrections to how this item was written:

  **It named the cheaper half.** The four *fixed facial* tones were built with
  `RGBA(hex: "#F08098")!` inside the subscript — parsing a **string** on every
  access, strictly more work than the three multiply-adds `over` does. Those are
  now `static let`; the accent-derived ramp is computed once in `init`. `body` is
  deliberately not stored, because it *is* the accent.

  **The justification does not survive the measurement.** "210 cells a frame"
  only applies where there are frames, and the [badge transform
  spike](../spikes/2026-08-03-badge-transform-cost.md) measured the dormant
  island at **zero** draws per second — the palette is untouched at rest. It is
  real work only for `running`'s 47.9 draws/s, and re-measuring before and after
  found **no effect above the probe's noise floor**: the `running` − `dormant`
  delta read +2.89pp before and +3.42pp after, inside a run whose own spread was
  ±3.4pp. Kept because removing per-access string parsing is obviously correct and
  all 375 tests hold, **not** because it was shown to be faster. Anyone citing
  this as a performance improvement should re-measure on a quiet machine first.
- ~~**Measure the badge transforms with `getrusage`.**~~ **Done 2026-08-03, and
  it failed.** [The spike](../spikes/2026-08-03-badge-transform-cost.md) has the
  numbers and the two wrong turns taken getting to them. Short version: the
  `Canvas` half of the claim held exactly (0.0 draws/s against 47.9/s with a
  timeline), and the cost half did not — **the dormant island measures 12.26% of
  a core in release against the 0.35% it used to cost, a 35× regression, and
  about 3× worse than the cell-swapping badges the transform replaced.** Not a
  debug artefact; the debug figure is 10.63%. Also found: `BadgeCanvas` never
  consults `MotionPreference`, so motion `.off` with system reduce-motion on
  changes the cost by nothing — §9.3 is bypassed, a second instance of the
  `IslandBody.phase` bypass already assigned to Plan 6. **What to do about it is
  a design decision and is deliberately not taken here** — see the spike's own
  "What this changes".
- ~~**Run `KeyDownProbe` on an unlocked machine.**~~ **Done 2026-08-03 — Path A.**
  [The spike](../spikes/2026-08-03-notch-panel-key-input.md) has the readings.
  The panel becomes key (`isKeyWindow true`, `.statusBar`), receives every
  keystroke, and `frontmostApplication` never changes. Verified beyond the
  proxies with a TextEdit witness and a control run: input is delivered
  **exclusively** to the panel — the other app receives nothing.

  **Two things came out of it that the brief did not ask for.** First, a hazard:
  because delivery is exclusive and `frontmost` never changes, a panel left key
  at rest would silently swallow everything the person types into a terminal that
  still looks focused — so key status must be taken only while a question is open
  and returned immediately after. **This is a Plan 6 constraint, not a
  preference.** Second, `NSApp.isActive` read `true` in every run and is not a
  usable proxy here; the Path B test is whether `frontmost after` names our own
  bundle id, and it never did.

  **Corrected 2026-08-03:** this line used to say `VIBECAT_KEYDOWN_PROBE=1`.
  No such environment variable exists in the source — `main.swift` gates the
  probe on the command-line argument `--keydown-probe`, under `#if DEBUG`. The
  full invocation, and why each part of it is load-bearing, is in
  [HANDOFF.md](../HANDOFF.md) and in `KeyDownProbe`'s own doc comment.

## Plan 4.5 — matching the prototype

**The gap this closes is not any one value. It is that nobody has ever diffed
the implementation against the prototype.** The spec header names
[`island-motion.html`](../prototypes/island-motion.html) and
[`settings.html`](../prototypes/settings.html) as the design's own reference,
and across four plans no task ever compared them. Ten minutes of reading the
prototype's CSS custom properties turned up five divergences; the honest
expectation is that there are more.

**It comes before Plan 5**, because Plans 5 and 6 build more surface on the same
foundations. Tuning after is tuning twice.

What is already known to match, so the diff does not re-litigate it: all four
state colours (`#3FD99B`, `#5B9DF9`, `#FFA63C`, `#FF5C5C`), dormant's
`--dim: #5A6273`, and — exactly — all five accent-derived sprite tones,
`--sp-body/hi/lt/out/sh` against `CatPalette`'s `.body/.highlight/.lightest/
.outline/.shadow`.

What is known to differ. **Start with the motion, because it is not a tuning
value — it is an architectural mismatch:**

- **Three of five moods animate with a transform our sprite architecture cannot
  do.** The box sizes match exactly (cat `18×14`, gap `4`, badge `14×14` on both
  sides), which is why this hides. The *motion* does not:

  | mood | prototype | ours |
  |---|---|---|
  | `trot` | `translateY(-2px)` over 1s | `-1pt`, two beats — **half the amplitude** |
  | `call` | **`scale(1.09)`** over 1.1s | a `-1pt` hop — **a different transform entirely** |
  | `happy` | `scale(.6 → 1.12 → 1)` over 540ms | nothing |
  | `dead` | `rotate(-4deg ↔ 4deg)` over 2.4s | nothing |
  | `sleep` | `translateY(2px)` over 3s | still |

  The last three were deliberate CPU decisions, recorded in Plan 3's follow-ups.
  The first two were not: `trot`'s amplitude is simply halved, and `call` uses a
  vertical hop where the prototype scales.

  **The root cause is a Plan 3 decision, not an oversight.** `ResolvedCat` moves
  in whole cells because "pixel art steps; a fractional offset would blur the
  grid." `scale(1.09)` on an 18×14 sprite either interpolates — blurring the grid
  that decision exists to protect — or needs a second set of sprite frames drawn
  at the larger size. Same for `rotate`. So matching `call`, `happy` and `dead`
  is a real design decision (accept interpolation, draw more frames, or diverge
  on purpose), not a constant to nudge. ~~`trot`'s missing pixel is a one-line fix
  and should not wait for that decision.~~

  **Withdrawn 2026-08-03 — see [the diff](2026-08-03-prototype-diff.md).** It is
  not a one-line fix, and `CatMood.offset`'s own comment already said why: "a step
  stays one cell, because two would carry the ear tips off the top of the canvas."
  The sprite is 18×14 with the ear tips on row 0 and our motion shifts *cells
  within the grid*, so a two-cell rise clips them. The prototype does not shift
  cells — it `translateY(-2px)`s the whole element inside a container with room.
  Matching it means moving the cat's motion to a **view transform**, which is the
  same mechanism [the badge spike](../spikes/2026-08-03-badge-transform-cost.md)
  measured at **+12% of a core**. So `trot` is in the same bucket as `call`,
  `happy` and `dead`, not ahead of it.

  **The cost is no longer a blocker: the owner accepted ~12% as the island's
  intended resting figure on 2026-08-03**, recorded in that spike as a deliberate
  divergence from the old 0.35%. `trot` should still go first of the four, because
  it is the one whose mechanism change is forced rather than chosen and it answers
  what the spike could not — whether the cost is per-animation or per-island.

> **The badge half of this is DONE** (`5b7c6f9`, `398082a`, `1cc5f40`). All five
> badges now animate as transforms on the mockup's own timings, `zzz`'s two z's
> and `squares`' four blocks stagger the way the mockup does, `squares`' blocks
> stopped resizing, and the three verdict badges share one pulse. **No badge
> needs a `TimelineView` any more** — `needsTimeline` depends only on the cat.
>
> **The one thing that must happen next:** measure it with `getrusage`. The claim
> that a repeating `.scaleEffect` does not re-invoke the `Canvas` renderer is now
> load-bearing in shipped code and is still only reasoned, not measured. If it is
> wrong, five animating badges cost five timelines and the idle island's 0.35%
> is gone. The source says so in `Badge.pulse`.
>
> The **cat** half is untouched and is the same question one layer down — see
> below.

- **All five badges animated in the prototype and three of ours were still —
  and the reason was a false economy.** Confirmed against the prototype's own CSS:

  | badge | prototype | ours |
  |---|---|---|
  | `zzz` | `zfloat 2.8s`, two z's staggered | still |
  | `check` | `twinkle 2.2s` — `scale(.62)` + `opacity(.55)` | still |
  | `squares` | `quad 1.15s` — `scale(.5→1.18)`, `opacity(.28→1)`, staggered per square | 12fps cell swap |
  | `bang` | `softpulse 1.1s` | 12fps cell swap |
  | `cross` | `shudder 2.4s` | still |

  `zzz`, `check` and `cross` were made still on a **measured** basis: a
  continuously drifting `zzz` cost 3.6–4.1% of a core against 0.35% with no
  timeline, for an animation that did not read as one. That measurement was
  honest and is not in dispute.

  **But it measured the wrong mechanism.** Every badge animation in the
  prototype is `scale` and/or `opacity` — and the badge is monochrome, so
  opacity is alpha on a single fill. In SwiftUI those are `.scaleEffect` and
  `.opacity` on the whole `BadgeCanvas`, declared once with
  `.repeatForever()`, and run by the render server. Our cost came from
  animating by *swapping cells*, which forces a `TimelineView` to re-evaluate
  the `Canvas` N times a second. A transform-based badge animation plausibly
  costs **no timeline at all** — meaning all five could animate for roughly
  what three still ones cost today.

  **This is a hypothesis, not a measurement.** Whether SwiftUI re-invokes a
  `Canvas` renderer during an implicit repeating transform is exactly the kind
  of thing this project has been wrong about before, in both directions. Measure
  it with `getrusage` before designing around it. If it holds, it is the single
  biggest visual-fidelity win available and it reframes Plan 8: not "match rate
  to distinct frames", but "the prototype's motion is transforms, and transforms
  are free".

- ~~**The island's ground colour.**~~ **Fixed 2026-08-03.** `islandGroundColour`
  is now the prototype's `--void: #07080A`; it was `#05070B`, the prototype's
  *sprite outline mix base*, which `CatPalette` uses correctly and still does.
  Two levels a channel, on the largest area of colour on screen. The more useful
  half is why four plans of green tests agreed with it — four assertions each
  hardcoded `Raster.Pixel(r: 5, g: 7, b: 11, a: 255)`, pinning the value we chose
  rather than checking it. See [the diff](2026-08-03-prototype-diff.md).
- ~~**The corner radius, and this one is not a defect.** The prototype uses `9px`
  (`--fillet`, six occurrences). We use `bottomRadius = 15`.~~ **Claim withdrawn
  2026-08-03: there is no divergence here at all.** The prototype's island is
  literally `border-radius: 0 0 15px 15px` (line 83) — the same 15 we use.
  `--fillet: 9px` sizes the two concave radial gradients welding the island to the
  bezel (`.island::before`/`::after`), and §5.5 removed those on 2026-08-01 as
  measured-wrong. So nothing needs justifying; the feature 9px belonged to no
  longer exists. Also noted: the prototype still carries the exact claim §5.5
  struck out, in a comment above those fillets — **where the prototype and a dated
  spec correction disagree, the correction wins.**

  **Reversed again 2026-08-05, and this time by the owner looking at the real app.**
  The fillets are back, at the prototype's own `9pt`, because the island met the
  bezel at a right angle and read wrong on hardware — which is the same kind of
  evidence §5.5 used to remove them. So the precedence rule above held only until
  newer evidence of the same kind arrived, which is what it should do.

  **Two things are worth carrying out of this, because the cost was four plans
  long.** First: `CLAUDE.md` went on citing the withdrawn claim as its *model case*
  for "a divergence is either a fix or a written decision" for two days after this
  entry withdrew it — a register is only as good as the documents that read it, so
  a withdrawal has to be pushed, not published. Second, and the reason the fillets
  were ever deleted: someone read `9px` as the bottom radius, found the fillets six
  lines away, and removed **them** rather than re-spelling a number that never
  needed changing. Cite the line, not the recollection.
- **The motion curves.** The prototype is explicit cubic-beziers over
  `--t-shape: 440ms` — `--spring-w: cubic-bezier(.32,1.5,.5,1)` (that `1.5` is
  real overshoot) and `--spring-h: cubic-bezier(.34,1.22,.5,1)`. We use SwiftUI
  `.spring(response: 0.42, dampingFraction: 0.72)` for width and `0.42/0.78` for
  height. The *intent* translated — 0.42 ≈ 420ms against 440, and width
  overshoots more than height in both — but a spring settles asymptotically where
  a bezier lands exactly, so this is where the feel diverges most and it will not
  be settled by matching numbers. Render or record both and compare.
- ~~**`--t-face: 190ms`, the face crossfade, was never implemented.** Already
  recorded in Plan 3's follow-ups as never assigned to a task.~~ **Done — Plan
  4.5 built it, Plan 5 finished wiring it.** `FaceCrossfade` / `AnyTransition
  .faceCrossfade` carry §9.1's own three numbers (190ms, 5pt rise, 3pt blur).
  Plan 4.5 applied it to `QuestionFace`'s rows ↔ reply-field swap but wired only
  its `duration`, leaving the transition itself with **no caller at all** — found
  by Plan 5's final whole-branch review as F7 and applied there to the drawer's
  first real face swap, `QuestionFace` ↔ `SessionListFace` (`011c277`).
- **The type scale has never been compared.** The prototype runs a dense ladder —
  9, 9.5, 10, 10.5, 11, 11.5, 12, 12.5, 13, 14.5px — across SF Pro Text and SF
  Mono. We have `RightFlankFont` and whatever Plan 4's drawer chose.

The deliverable is as much the **written record of deliberate divergences** as
the fixes. A divergence nobody wrote down gets re-introduced or re-removed by
the next person who notices it.

## Plan 5 also owns

Two items land here because they share a mechanism or a cause with the session
list, not because the list needs them.

- ~~**The hover sliver.** `IslandBody`'s silhouette is one shape spanning the whole
  body height at the hover-coupled width, while Plan 4 made the drawer's width
  hover-independent. The result is a 150pt-wide opaque rectangle covering ~92% of
  the drawer's height, appearing and disappearing with hover.~~ **Done — Plan 5
  Task 1**, `IslandBody` now paints two silhouette rects and drops the reveal
  entirely while a drawer is open, so the collapsed bar and the drawer share one
  width. One correction to how this was written: "appearing and disappearing with
  hover" understated it. `model.hovering` stays **true for the whole life of an
  open drawer** (`click()` never clears the controller's `.hover` tier, and
  `acceptsClicks` is gated on it), so the sliver stood there for as long as the
  question did.

  **And it cost a follow-on defect, which is the part worth remembering.** Task 1
  shrank the silhouette's `.frame` and left `content(cell:)` laying `RevealContent`
  out at the full 150pt, so the `HStack` overran its frame and SwiftUI squeezed
  §5.4's session-count `Text` — the count vanished from every open drawer. Task 1
  was the one task on the branch that never had an independent review, and no test
  in the suite looked at the collapsed bar's *content* while the drawer was open.
  Fixed in `6607728`; both call sites now read one `IslandBody.revealWidth`.
- ~~**`render()`'s unconditional writes.** It assigns `model.state` and
  `model.sessionCount` on every call, and `@Observable` notifies on the write
  rather than on a change, so every hook event invalidates the body two or three
  times when nothing differs.~~ **The premise is false — corrected 2026-08-03.**

  Measured on Swift 6.3.2: `@Observable` does **not** notify when an `Equatable`
  property is assigned an equal value. Verified four ways in one run and confirmed
  by mutation (guards added, then deleted, with the test passing either way). So
  there were never two or three spurious invalidations per hook event, and no
  guard is needed. Pinned by
  `anEqualWriteToAnObservablePropertyDoesNotNotify`.

  **This mattered far more than the item itself, because something else depended
  on the belief being true.** `NotchController`'s bloom-end nudge assigned
  `model.aura` its own value to force `IslandView.body` to re-evaluate and drop the
  `TimelineView` — and, notifying nothing, it ended no bloom. A still mood
  therefore kept a live 8fps timeline **forever** after the first state change:
  ~3.3% of a core permanently, against the animation spike's own 3.61%-vs-0.35%
  figures, in exactly the state §6.1 says must look idle. No probe caught it
  because `AuraTrigger.observe` never blooms on its first observation and
  `BadgeCPUProbe` sets the state once. Fixed by `AuraTrigger.endBloom()` —
  Plan 5's inserted Task 3.5.

  **Refined 2026-08-03, from `-dump-macro-expansions`:** the two call shapes are
  gated differently, and only one of them is gated at all. A plain **assignment**
  (`model.aura = …`) goes through the generated `set`, which *is* equality-gated —
  that is why the old nudge notified nothing. A **mutating call** through the
  property (`model.aura.endBloom()`) goes through `_modify`, which notifies
  **unconditionally**, whether or not the value ends up different. So the fix does
  not depend on `firedAt` changing; it works because it is a mutating call rather
  than an assignment. Worth knowing before anyone "optimises" a mutating call into
  an assignment, or writes another equal-value nudge expecting it to fire.
- ~~**A CPU measurement, as a task.** Plan 3's numbers are all single-sprite, on
  mains power, on a 120Hz built-in display. Plan 8 needs multi-sprite numbers to
  aim at, and Plan 5 is the first thing that produces several sprites.~~ **Done —
  Task 8**, in [the badge spike](../spikes/2026-08-03-badge-transform-cost.md).
  `getrusage(RUSAGE_SELF)`, never `ps %cpu` — that decaying average once produced
  a false failure costing most of a plan's investigation budget.

  **The result reopens the owner's accepted ~12%.** Opening the session list with
  12 sessions costs **+13.6pp of one core** on top of the running row (17.69% →
  31.28%), about 9× the ±1.5pp noise floor, with `draws/s` flat at 47.8 → 47.7 —
  so it is not extra badge redraws. That **revises** rather than extends the
  earlier "per-island, not per-animation" conclusion, which came from a second
  *animation* costing ~+0.75pp and does not carry to rows of content.

  **Two caveats a reader must not lose.** The run was on battery, ~48%
  discharging, with Low Power Mode **on** — every other figure in that spike is
  mains. Throttling scales both rows of a single run together, so the within-run
  +13.6pp stands; the cross-run comparison against the mains-taken +11.97pp badge
  figure does **not**, and which way throttling moves it is indeterminate rather
  than favourable (lower clocks inflate a share-of-core delta, a frame-rate cap
  compresses it). A mains re-measurement is owed and the spike records it as such.

## Plan 5's carried findings — what its final review deliberately did not close

- **NOBODY ON PLAN 5 OPENED THE MOCKUP, AND THE MOCKUP HAS THE SESSION LIST.** Added
  2026-08-03 after the owner asked. This is Plan 4.5's own failure — "nobody diffed the
  implementation against the prototype" — repeating one level down, and it is the most
  embarrassing finding on this list because a subagent was written at the start of the
  same session *specifically to prevent it* (`.claude/agents/prototype-fidelity.md`) and
  never used. Every Plan 5 dispatch pointed implementers at **§11's ASCII diagram** in
  the spec instead of at `island-motion.html`, which contains a fully worked session
  list: real session records (line 788+), a `card` options object (line 813), and the
  row rendering (line 846+).

  Concrete divergences, read off `renderRows()` (line 839+), `metaLine()` (816) and the
  `card` object (813). None of the eight task reviews could have caught any of these,
  because none was given the reference:

  | # | the mockup | ours |
  |---|---|---|
  | 1 | `markSVG(s.mark)` leads the row — a **per-CLI** mark | a state-coloured `Circle()`. §11's `✳` was read as a state marker |
  | 2 | state text carries a **`pip`**, class `live` while running | no pip; the dot moved to the front instead |
  | 3 | `${card.project ? s.proj : s.term}` — the project switch **substitutes the terminal name**, it does not blank the field | no project switch at all; line 1 declared non-switchable |
  | 4 | `${s.act} <em>${s.code}</em>` — sentence and command are **separate fields, the command emphasised** | one `session.activity` string, `"title body"` joined by `Session.activity(from:)`; the command no longer stands out |
  | 5 | `metaLine` = `term · model · effort`, model and effort **individually switchable** | the same three joined, none switchable |
  | 6 | running shows `state:'2m 14s'` — **elapsed time as the state** | `IslandState.label`, the word "Running" |
  | 7 | 8 switches: `project` `worktree` `model` `effort` `said` `tasks` `agents` `activity` | 5: `activity` `lastMessage` `tasks` `agents` `subagents` |

  **#1 is the one that matters beyond appearance.** §4.3 says which agent is speaking is
  carried by icon *shape*, never by hue — the mockup honours that by leading with the
  CLI's mark and putting state in a pip. Ours spends the row's leading position on a
  state-coloured dot and then repeats state in the label beside it, so a row cannot say
  *which* CLI it belongs to at all. That is a design-rule divergence, not a styling one.

  **#4 is a legibility regression** and the repo already knows why: the drawer's own
  command body gets `.truncationMode(.middle)` because the end of a command is its
  target. A row that merges the sentence into the command loses the emphasis the mockup
  gives it, in a list whose whole job is triage at a glance.

  §11 says "every line is individually switchable" and the mockup shows what that
  means. `SessionRow.Options` implements a different, smaller set, and the
  "line 1 is deliberately not switchable" ruling in the plan was a decision made
  without looking at the reference that contradicts it.

  **This is not closed and should not be treated as cosmetic.** The three §11-diagram
  divergences the final review found were caught only by the visual fixture, at the very
  end; the four above are against a *richer* reference nobody consulted at all, so the
  honest expectation is that there are more. The work is a Plan 4.5-style systematic
  diff of `SessionRow`/`SessionBlocks`/`SessionListFace` against `island-motion.html`,
  with every deliberate divergence written down — and the `prototype-fidelity` agent now
  exists to do it, in a session where it resolves.


The equivalent of Plan 4's follow-ups, recorded here because `.superpowers/` is
gitignored scratch and this file is the permanent register. Everything Plan 5's
final whole-branch review ruled *must fix* is fixed (`6607728`, `b907682`,
`011c277`, and the documentation-truth commit that carries this section). What
follows is what it deliberately left, with the reason.

**One item has a deadline attached, and it is the only one that does:**

- ~~**`aLapsedQuestionClosesTheDrawer` must be fixed before the next plan starts.**~~
  **Fixed 2026-08-03 (`94db7c5`), after this entry was written.** The diagnosis below
  was right about the mechanism and wrong about the remedy: the problem was not that
  the test failed to poll, but that its ceiling was denominated in **wall-clock
  seconds** while the thing it waits for needs **main-actor turns**. Full-suite runs
  hold the main actor synchronously for long stretches (every `rasterise` call), so a
  2-second ceiling could expire having granted the lapse `Task` almost no turns at
  all. It now counts turns instead. Mutation-verified: removing `dismissQuestion()`
  from the lapse `Task` reproduces the reported symptom exactly
  (`.drawer(height: 288.0)` != `.rest`) and gives up in 4.3s rather than hanging.

  Two honest caveats kept from the original entry, because they still apply: the fix
  rests on mutation evidence and an identified mechanism, **not** on a measured drop
  in flake rate — the test did not flake once in 60 runs while being fixed. And the
  raster fix in the same wave removed a great deal of synchronous main-actor work, so
  the two changes are not independent and credit cannot be apportioned between them.

  Original diagnosis, retained: it flaked under full-suite load — measured over 8 full-suite runs each, 2/8 on
  the commit before the fix wave and 3/8 with the wave's own tests added, which at
  that sample size says nothing about the difference. **Pre-existing, not Plan
  5's**: nothing in this plan touches the lapse path. The test already polls
  rather than sleeping, with a 2s ceiling, so the remaining failure mode is the
  lapse `Task`'s continuation being starved of main-actor turns for longer than
  that while other `@MainActor` tests hold it. The precedent to follow is
  `0ed9932`, which fixed two drawer golden tests of exactly this class with a
  condition-based wait. Two honest limits on calling it benign: single-digit run
  counts are weak evidence about a load-dependent flake, and this repo has a
  documented case where a "flake" turned out to be a real concurrency bug
  (`AppModel`'s `DispatchQueue.main.sync`).
- **A drawer-golden jitter reading nobody can account for.**
  `theDrawersContentDoesNotShiftWhenOnlyHoverChanges` asserts `differing == 0` and
  produced **72** on one full-suite run out of ~10 during the final fix wave,
  never reproducible under `--filter`. Every jitter magnitude previously recorded
  for this class is 4, 4, 8, 22. Not chased and deliberately not absorbed by
  loosening the assertion back to `<= 30` — the whole reason it is `== 0` is that
  the tolerance stopped absorbing anything once the sliver was split out. If it
  recurs, start here.
- **`ImageRenderer.cgImage` hands back a recycled backing store, and a view that
  paints nothing does not clear it. FIXED — and two of the four things this entry
  originally said about it were wrong.** Found while measuring the two above.
  `eachBlockOptionGatesOnlyItsOwnBlock` draws `SessionBlocks(options: [])` — an
  empty `VStack` in a fixed 388×80 frame — and asserts the two single-bit renders
  beat it. That render read 0 opaque pixels under `--filter` and **exactly 2287**
  on 4 of 18 full-suite runs, reproduced by three separate observers, and it later
  failed a real assertion: `(agentsOnly → 474) > (none → 2287)`.

  **What it actually is.** `ImageRenderer.cgImage`'s bitmap comes from a store
  that is reused across renderers, and a fully transparent render never writes to
  it, so the previous occupant's pixels are read back verbatim. Reproduced
  **deterministically, single-threaded, under `--filter`, with no concurrency
  anywhere**: render `SessionBlocks(options: .agents)` in a 388×80 frame (474
  opaque pixels), then the blank `options: []` render in the *identical* frame,
  and the blank one reads **474, twelve times out of twelve**. The first blank
  render in a fresh process reads 0, because nothing has occupied that block yet.
  Fixed by rendering through `ImageRenderer.render(rasterizationScale:renderer:)`
  into a bitmap context `rasterise` allocates and zeroes itself, so the shared
  store is never involved. **20 consecutive full-suite runs green afterwards,
  against 3 failures in 20 immediately before** — and pinned by
  `aViewThatPaintsNothingDoesNotInheritTheLastRender`, which fails 12 issues out
  of 12 against the old path.

  **Two claims this entry made that are now disproven, recorded because this
  register's rule is that a wrong measurement gets corrected loudly:**

  1. *"`--filter` is the only trustworthy mode for a golden result"* — **false, and
     it was the most damaging thing said here.** `--filter` is only ever *quieter*,
     because a filtered run has fewer prior renders to inherit. The deterministic
     reproduction above is a `--filter` run. Plan 5's mutation checks all used
     `--filter` and were called "unaffected" on that basis; that reasoning does not
     hold, though the mutations themselves stand, since every one of them asserted
     a *difference* between two renders taken the same way.
  2. *"the reasonable next step is to serialise the rasterising tests
     (`.serialized`, or one shared render queue)"* — **false.** There is no race to
     serialise. `.serialized` would have suppressed the full-suite symptom while
     leaving the bug entirely in place, and would have made it harder to find by
     removing the only signal anyone had.

  **And one claim it made that held:** the attribution to `ImageRenderer` was
  right. A competing diagnosis — that the escaping `CGContext(data: &bytes, …)` in
  `Raster.swift` was corrupting the destination buffer — was tested first and
  **falsified**: on a full-suite run that reproduced the bad reading, a correctly
  allocated buffer that provably outlived its context read the same wrong 474 as
  the `&bytes` version did, so the corruption was upstream of the buffer. That
  escaping-inout *is* real undefined behaviour and was fixed at all four sites in
  the same commit, on its own separately-measured evidence (a `let` copy of the
  array, taken before the draw, is mutated by the draw) — but it was never this
  bug, and fixing it alone does not fix this bug. **Two real defects sharing one
  symptom is exactly the shape that makes a plausible diagnosis dangerous.**
- **An unidentified Task 4 flake** whose data is unrecoverable. Recorded only so a
  future recurrence is not mistaken for something new.

**And one defect the fixture found and the fix wave closed**, noted here because
of *how* it was found: `SessionRow`'s project name had no `.lineLimit(1)`, so a
long one wrapped and §11's "three lines per row" became four — with line 1 going
visually crooked, because the state dot centres against the taller block while
the worktree and state label sit on the lower baseline. `project` is `cwd`'s last
path component, so its length is entirely the user's. Every other `Text` in the
row already had `.lineLimit(1)`; the row's most important field did not. Nothing
in 414 tests could see it, and nobody had ever looked at the assembled list —
which is the whole argument for keeping `VIBECAT_LIST_SHOT` in the suite. Pinned
now by `aLongProjectNameDoesNotAddAFourthLineToTheRow` (66pt against 51pt under
mutation).

Plan 6 items, deliberately left as behaviour rather than changed:

- **`IslandModel.revealed` is now redundant with `sessions.first`.** `render()`
  assigns both from the same `SessionStore.mostUrgentFirst` ordering, so
  `revealed` is `sessions.first` by construction. Not collapsed now for one
  reason: they are read by different surfaces with different lifetimes —
  `revealed` by the collapsed bar's hover reveal, `sessions` by §11's list — and
  Plan 6's Settings can make the list's contents configurable (§11: "every line is
  individually switchable"), at which point "the session the island's state
  summary is about" and "the first row of the list" stop being guaranteed to be
  the same session. Collapsing them first and re-splitting them later is the
  expensive order. If Plan 6 decides the two really are one thing, `revealed` is
  the one to delete.
- **`.scrollIndicators(.never)` on a face whose content genuinely overflows, and
  the fold cuts a line in half.** `SessionListFace` fixes at §6.3's 420pt (376pt
  of it usable above §6.4's footer reservation) while 20 sessions measure 699pt —
  measured, not assumed, by `twentySessionsGenuinelyOverflowTheFixedFace`. So rows
  continue below the fold with no cue that they do. **Seen for the first time in
  the `VIBECAT_LIST_SHOT` fixture, and it is worse than "no cue":** with four
  sessions, the boundary lands mid-row and clips the last agent line
  *horizontally through its glyphs*, leaving a half-height strip of text. That
  does not read as "there is more below", it reads as a rendering bug. Choosing
  an indicator is a design decision §11 does not settle — a permanently visible
  scrollbar on a 400pt-wide black panel is a real aesthetic cost — but "no cue
  plus a sheared line" was never chosen either; it fell out of one modifier and a
  fixed frame. Plan 6 owns picking one (a bottom-edge fade, an explicit "+N more"
  line, or row-granular snapping so the fold never lands inside a row), because
  Plan 6 is where the list gets its Settings and its footer.
- **Three divergences from §11's own diagram, all found by that same fixture, all
  cosmetic and none written down before now.** Recorded together because a
  divergence nobody wrote down gets re-introduced or re-removed by the next person
  who notices it — this file's own standing rule.
  - **Line 1's state marking is mirrored.** §11 draws `✳  api  ⑂ worktree … Needs
    you ●` — a glyph on the left, the word *and* a dot on the right. `SessionRow`
    draws the dot on the left and the word on the right, with no trailing dot and
    no `✳`. One accent mark instead of two, which Task 5's review approved on
    §4.3 grounds; it is still not the diagram.
  - **§11's `│` continuation bars are missing under the Tasks and Agents
    headers.** The diagram brackets each block — `┌ Tasks` then `│ ● …`, `│ ☐ …`.
    Ours draws the `┌` header and then flat, unprefixed items, so at a glance the
    task lines look like they belong to the row rather than to the block.
  - **Agent lines are missing §11's effort** (`8s · Sonnet 4.6 · High`; ours stops
    at the model). This one is a **model** gap, not a view gap: `AgentItem` has
    `name`/`elapsed`/`model`/`activity`/`finished` and no `effort` field at all,
    so it needs a wire-protocol change and belongs with whoever next touches
    `VibeEvent`.

  Everything else in §11's diagram is present and correct, verified line by line
  against the render: three lines per row in the specified order, the Tasks
  summary omitting zero counts, `●`/`☐`/`☑` markers with `done` struck through and
  dimmed, the nested `└ activity` line under a running subagent, one hairline
  divider between rows and none after the last, middle-truncation keeping both
  ends of a long worktree, and the collapse rule reporting the **running** count
  rather than the total. §4.3 holds: each row wears exactly one hue across its
  dot, its state label and its in-progress task marker, with no other state's
  accent anywhere in it.
- **`SessionRow.Options` has no production caller passing anything but `.all`.**
  Kept deliberately — it is §11's own "every line is individually switchable in
  Settings" switch point, and removing it means Plan 6 rewrites `SessionRow` and
  `SessionBlocks`. It is not untested: `sessionRowForwardsItsOptionsToSessionBlocks`
  pins the forwarding by mutation. **But `SessionListFace.options` was removed** in
  the final fix wave — nothing, test or production, ever passed it — so Plan 6 has
  to re-thread one parameter from Settings down to `SessionRow` when it wires the
  switches up. That is a deliberate one-line cost, not an oversight.
- **`Session.lastUserMessage` is rendered and never populated.** §11's line 3, and
  no adapter produces it. Already recorded out of scope with the check that would
  settle it.
- **`eachBlockOptionGatesOnlyItsOwnBlock` catches an asymmetric mis-gate but not a
  symmetric double swap.** With both guards swapped, both single-bit probes still
  draw non-empty, non-equal content and the test passes. Narrow — it needs a
  symmetric mistake rather than a typo — but real, and the fix is a third probe
  asserting *which* block drew rather than only that the heights differ.
- **A transition's *wiring* is not observable with the tools this project takes.**
  A `.transition` contributes nothing at identity, and identity is the only state a
  static `ImageRenderer` render can capture. So `FaceCrossfade`'s numbers and
  geometry are pinned, and that anything *applies* it is not — which is exactly how
  §9.1's crossfade sat with no caller from Plan 4.5 until Plan 5's final review
  found it by reading. Both of `DrawerView`'s and both of `QuestionFace`'s call
  sites are in this position today. Worth a `#if DEBUG` counter of the kind
  `IslandView.buildCount` already establishes, if Plan 6 adds a fourth face.

## Plan 6.2's carried findings — sound shipped, four things still need an ear

Full account: [the plan's closing section](2026-08-03-sound.md) and
[`.superpowers/sdd/2026-08-03-sound/final-review.md`](../../../.superpowers/sdd/2026-08-03-sound/final-review.md).
509 tests. What is here is owned elsewhere or unmeasurable without a person, not
skipped.

- **Nobody has heard it.** Every cue is verified by arithmetic — the note tables
  diffed against `island-motion.html:894-912` value by value, the durations
  checked against §12's own totals, the waveforms against their Fourier series.
  **No listening check has been performed and none is claimed anywhere in the
  source.** Four things need an ear: whether each cue matches the prototype's own
  sound buttons; whether there is a click at a note's release; whether `done`'s
  held G6 carries inharmonic hash, which would mean the band-limiting is not
  working; and whether `isQuiet` reads `true` during a real Focus session, which
  needs the system Focus toggled. **Compare at `volume: 1.0`** — the prototype has
  no master gain, so our default of `0.60` is 4.4 dB down and a like-for-like
  comparison at `0.60` will mislead.
- **Switching output device is handled defensively but was never reproduced.**
  `AVAudioEngineConfigurationChange` is observed and `connected` is reset while
  `attached` is not, because `attach` raises on a second call. Nobody unplugged a
  real device. Left as a labelled unknown rather than a claim.
- **`SoundPlayer` schedules serially where the prototype mixes overlapping cues**
  — written decision 5, not a gap. A burst is bounded by `maximumBacklog` (1.0 s,
  wall-clock so a missed callback cannot wedge it) and a cue that would start late
  is dropped rather than queued. If §12's character turns out to need the overlap,
  this is the one line to change.
- **`meow` fires from nothing and `SoundSettings` has no persistence** — both
  Plan 6.4's, both deliberate. §14's Sound section offers `meow` as a per-cue
  *alternative*, and choosing one is the sheet's job. 6.4 also has to clamp
  whatever it reads out of `UserDefaults`; `SoundSettings` clamps at its own two
  entry points, but the boundary is 6.4's to hold.
- **`Soft`, `System` and `Blip` are not implemented and must not be invented.**
  `settings.html` offers them; nothing in this repo defines what they sound like.
  Written decision 3. `SoundPack` is an enum, so adding one is additive.
- **Rendering is cached, and the cache is the thing to watch.** Keyed on
  `(settings, sampleRate)`, filled on a dedicated serial queue — not
  `Task.detached`, which draws on the same small cooperative pool this repo has
  already been burned by. Uncached, `error` cost **860 ms on the main actor in a
  debug build**, which is what `Scripts/build-app.sh` produces; cached it is
  ~1.1 ms, at the measurement floor. Measured with `getrusage`, never `ps %cpu`.
- **The lesson worth carrying forward, because it is about method not sound.**
  Executing this plan found **five tests that could not fail** and **two real
  bugs**, every one surfaced by an implementer reporting a mutation as green
  instead of adjusting the test until it went red. Two were load-bearing: an
  unreachable guard concealing a note shorter than 6 ms never releasing, and a
  prune test that pruned a *waiting* session — which is never removed — and so was
  blind to the defect it existed to catch. The plan's own self-review also
  reported a defect class as fixed having fixed one instance of it. **A mutation
  list in a plan is a prediction, and three of this plan's predictions were
  wrong** — which is the argument for writing them down, not against.

## Plan 6.4's carried findings — the shell, and the first real `settings.html` diff

574 tests. Full account: [the plan](2026-08-03-settings-shell.md) and
[`.superpowers/sdd/2026-08-03-settings-shell/final-review.md`](../../../.superpowers/sdd/2026-08-03-settings-shell/final-review.md).

- **`settings.html` was finally diffed, in a browser, and it found two bugs
  nothing else could.** Task 6 used `getBoundingClientRect` and
  `getComputedStyle` on every element plus screenshots at 4× against its own
  rasterised renders. It caught `.continuous` corners where every CSS radius is
  circular, and a note's 2pt blue rule that — being a doubly-flexible
  `Rectangle` — stretched to the pane's full height and dragged a 500pt card with
  it. Neither is visible to any assertion anyone had thought to write. Five
  further differences are recorded as written decisions. **§14 is four lines of
  prose over 640 lines of prototype; the prototype won every disagreement.**
- **Scope: the shell only.** 22 subsections and roughly 47 controls, counted.
  6.5 owns Notifications, 6.6 Display, 6.7 General and Integrations, and **every
  pane says so on its own face** — an empty pane that looks finished is worse than
  one that names its owner.
- **`--accent` means system blue in Settings and the current state's colour in the
  island.** §4.3 inverted. Verified: nothing in `Sources/VibeCatUI/Settings/`
  touches `IslandState` except doc comments, and the four state hues still agree
  where `settings.html` shares them for the island preview.
- **Two AppKit facts measured rather than reasoned about**, both because a
  documented contract pointed the wrong way. `isReleasedWhenClosed = false` leaked
  one `NSWindow` per open/close — `NSApp.windows` 0→10 across ten cycles, all
  still titled "VibeCat Settings" — and the comment defending it had the release
  order backwards, since `willCloseNotification` fires *before* the close. And a
  weak-reference test for it **cannot work**: AppKit finishes teardown inside
  `NSApplication.run()`, which `swift test` never calls, so the window sits at
  retain count 8 after 50 run-loop spins even when correct. The test asserts
  window-list membership by identity instead.
- **A symmetric `removePersistentDomain` does not clean up after a test.** The
  fixture this plan mandated leaked one plist per test into
  `~/Library/Preferences` — 175 files, 700 KB — and emptying the domain is not
  enough because `cfprefsd` rewrites it. Isolation now lives in `keyPrefix` on one
  fixed suite: one bounded file.
- **Un-muting used to re-pay the full render cost**, 859 ms for the `error` cue,
  because the cache key was the whole `SoundSettings` and `enabled` is in it —
  though `enabled` cannot change what a cue *sounds* like. Now 0.170 ms. Measured
  with `getrusage`, never `ps %cpu`. A **volume** change still re-renders at
  859 ms, which is correct and is 6.5's to think about when it ships the slider.
- **Three preferences were persisted and never read**, not one. The ledger caught
  `selectedPage`; the whole-branch review found `volume` and
  `quietDuringDoNotDisturb` in the same state, so a plist could say
  "don't respect Do Not Disturb" and suppression carried on. All three now round
  trip. **`save()` writes the whole struct, so it is a clobber hazard**: every
  writer must read-modify-write against the current value and never hold a
  snapshot. 6.5–6.7 add many more writers.
- **Seven tests that could not fail were found across this plan, four of them from
  premises its own author wrote.** The two worth remembering: "muted draws more
  ink than unmuted" is simply false — muting *hides* the two waves while adding the
  slash, measured 301 against 308 the wrong way — and a sidebar assertion that two
  renders *differ* passed happily with the selection inverted, because **"differs"
  is not "differs in the right direction"**.
- **Still not testable, and accepted rather than faked:** whether a real click
  reaches a closure, or which `Binding` a `body` wired. Three separate tasks hit it
  independently. It needs a ViewInspector-style dependency this project will not
  add. The *rendered* selection, by contrast, **is** testable and is now tested.
- **Carried out:** the titlebar's `#232326` is unverified because `cacheDisplay`
  is untrustworthy for flat fills, and no golden was built on it. Corner style and
  SVG stroke width remain uncaught by any mutation. **`PanelBar` moved the drawer's
  footer, so a `prototype-fidelity` dispatch over the whole drawer is worth doing
  before 6.5.**

## Plan 6.5's carried findings — the Notifications page, and a suite that only passes serially

647 tests. Full account: [the plan](2026-08-04-notifications-page.md) and
`.superpowers/sdd/2026-08-04-notifications-page/progress.md`.

- **The suite is run with `Scripts/test.sh`, which is `swift test --no-parallel`.**
  Decided 2026-08-04. In parallel it fails on nearly every run; serially it is
  647/647 in ~21s, and the failing tests pass alone in 0.11s — so **nothing in the
  product is broken**, what fails is scheduling latency. Across Plans 6.4 and 6.5
  the `@MainActor` count in `Tests/` went 264 → 375 (+42%) against 13% more tests,
  because a SwiftUI view can only be rasterised on the main actor, so a test that
  waits a bounded time for the main actor now contends with half again as many
  main-actor-bound tests as when its bound was chosen. **The better fix is to rework
  those polling tests so they do not depend on main-actor latency**; the flag buys a
  trustworthy result until someone does. Measured 0 failures in 8 serial runs.
  **And measure ten runs, not four, if you revisit it** — a four-run sample read 2
  failures where ten runs of the same tree read 10, and acting on the four would
  have meant reporting a regression that was not there.
- **The browser diff found the page did not fit its own window.** 771pt of content
  in 552pt: the `VStack` overflowed centred and the pane title **vanished entirely**,
  chip at zero pixels, taking three existing chip tests red with it. Fixed with a
  `ScrollView`. Also `.sel` had no dropdown arrow at all, because the browser draws
  one and the CSS does not. Two more bugs that only looking could find, after the
  two Plan 6.4 found the same way.
- **Deleting `.onAppear { notifier.refresh() }` is caught by nothing — but not for
  the reason first recorded.** Plan 6.5's Task 7 reported the cause as `onAppear`
  not firing under `ImageRenderer`. **Plan 6.1's Task 2 measured that and it is
  false: `onAppear` does fire.** The mutation survives for a duller reason — no test
  renders that view at all — which is a fixable gap rather than a platform limit,
  and the fix is a test, not a workaround. Corrected here because the wrong version
  would have told Plans 6.6 and 6.7 to stop trying.

  Still true and unchanged: no headless test can see which closure a `Button` was
  bound to. That one is a real limit, hit independently by three separate tasks.
- **Rows below the fold are unverifiable.** `ImageRenderer` cannot render a
  `ScrollView`, and the page now has one. `rasteriseHosted` is the path, and Plan
  6.4 measured it untrustworthy for flat background colours — so a golden over
  scrolled content needs care, not a copied helper.
- **`Notifier.automationTarget` is hardcoded to `com.apple.Terminal`.** Harmless
  today because §14's row only reports status and never prompts, and nothing uses
  Automation until jump ships — but the row's meaning changes the moment it does,
  and jump is Plan 6's.
- **The stall alert has no sound, deliberately.** §12 defines five cues and none is
  "stalled"; Plan 6.2's written decision 3 forbids inventing one. A stall posts a
  system notification and nothing else. Cost with the real consumer attached:
  58.36µs per tick, 0.000096% of a core at the 60s cadence, measured with
  `getrusage`.
- **`Soft`, `System`, `Blip` and `Buzz` still do not exist** and the pickers
  deliberately do not offer them. Plan 6.2's written decision 3, unchanged.

## Plan 6.3's carried findings — shape and motion

744 tests. Full account in the plan and
`.superpowers/sdd/2026-08-05-shape-and-motion-fidelity/`.

- **The drawer had no width of its own, and opening the island made it narrower.**
  `frames(rightFlank:tier:)` let `tier` touch only the height, so the open width was a
  function of how many digits were in the session tally: measured 273.1 / 273.1 /
  281.2pt at 1, 3 and 12 sessions against the prototype's flat 560. And because a
  click always happens while hovering, opening threw away the 150pt hover reveal —
  measured 423 painted columns hovered-and-closed against 273 hovered-and-open. It
  contracted by 150 where the mockup expands by 287. **That was the owner's whole
  complaint, and it also silently caused the recorded `As…` truncation**, because the
  row's ink saturates at 420pt and it was given 273.
- **`--ease` was used 35 times in the prototype and zero times in our code**, with
  four sites on `.easeOut`/`.easeInOut` instead — five, once `settings.html`'s
  identical token was counted. It is now one constant beside the two springs, and the
  38.1%-at-75ms hover gap turned out to *be* that curve: `.easeOut` differs from
  `cubic-bezier(.22,.9,.28,1)` by 0.3814 at p=0.273, which at 280ms is 76ms.
- **Hover had no overshoot at all**, so §9.1's central rule was not merely mismatched
  on that gesture, it was absent. Hover is now three clocks — shape on the width
  spring, the reveal's width on `--ease`/280ms, its opacity on `--ease`/160ms, the
  last two measured at 0.0% from the prototype — and the shape reaches 108.4% against
  the prototype's 108.0%. §9.1's *wiring* is now guarded too, by four separate
  read-count facts rather than two, which catches a swap-both-sites mutation a single
  counter could not.
- **Two sites deliberately keep `.easeInOut`, with numbers.** CSS eases each keyframe
  interval forwards while `autoreverses: true` mirrors the return leg, and `--ease` is
  front-loaded enough that mirrored it is nearly anti-phase — worst full-cycle
  deviation 0.638 against 0.903. Using `--ease` there would be **worse**.
- **The bezel fillets are back, at the prototype's `9pt`**, on the owner's report from
  real hardware. Both welds are drawn (the prototype's dormant suppression exists
  because its right flank can be 0 and ours is floored at 15), and symmetry is pinned
  row by row at scale 4 with each side *also* pinned separately, because a symmetric
  absence is still symmetric. **9, not the 15/20 the owner asked for literally:** the
  flush edge between weld and bottom corner measures 11.75 / 5.75 / **0.75**pt at
  9 / 15 / 20, so at 20 the island has no straight side left and each end is one
  continuous S — which is the hook the 2026-08-01 removal reacted to.
- **The 440ms radius transit is not delivered, and the endpoints are.** Plan 5's
  two-shape split means the bottom corner changes *owner* on open, and SwiftUI does
  not interpolate an inserted view's `animatableData`; the height clamp makes keeping
  the drawer half at zero height no help either. Ruled not worth re-unifying, since
  that moves `.contentShape`'s tappable rect and the aura's traced alpha.
- **The sheared fold got a 24pt bottom fade, and row snapping was ruled out on
  measurement**: rows are non-uniform, so snapping aligns one fold and shears the
  next. Confirmed the prototype has no cue at all, and that at one session its list
  box shrinks to 65px and leaves the face empty — so our fixed 420pt with empty space
  is right.
- **Six more browser-diff differences, all open.** Collapsed flank order is
  `[detail][tally]` not `[count][reveal]`; the prototype shows one number **per state
  in per-state hues**, which §6.2 contradicts (Plan 6.6's to settle); `.flank` has an
  80ms-delayed 150ms opacity fade we lack; `.face`'s 190ms crossfade covers the
  *flank* faces where ours covers only the drawer's; drawer padding 18 against our 16;
  the top inset is ~6pt off; and `.ask-q` is weight 400 against our semibold.
- **Deferred on the owner's instruction: the `getrusage` re-measurement.** Dormant
  cost is *expected* unchanged, not measured. Plan 6.1 measured motion `off` at 0.38%
  of a core against `full`'s ~12%, and a wider, more animated island could undo that —
  **so this is an open number, not a closed one.**
- **One guarded-presence-only cue:** `SessionListFace.foldFade` can be changed 24 → 40
  with all 744 tests still passing. The fade's existence is pinned; its depth is not.

## Plan 6.1's carried findings — keyboard and the switches

[The plan](2026-08-04-keyboard-and-switches.md), 6 tasks. Two findings already
worth reading out of order:

- **Motion `off` takes the dormant island from ~12% of a core to 0.38%.** Measured
  with `getrusage` from a real bundle across two runs: dormant `full` read 10.23%
  and 12.60%; dormant `off` read 0.38% on a quiet machine (0.37–0.39), landing
  exactly on the standalone hover monitor's own 0.35%. **That materially changes the
  open decision about the accepted ~12% resting cost** — there is now a real escape
  hatch, and it is a user's choice rather than a rewrite. The badge-transform spike
  named "~0.3%" as the figure that would close its attribution by measurement; this
  is it.
- **The motion bypass was in three places, not two.** The spike recorded
  `IslandBody.phase` and `BadgeCanvas`. `CatCanvas` had the identical bypass and
  nobody had written it down. All three now take a **required, undefaulted**
  `motion:`, so a fourth cannot be added silently.
- **`reduced` currently costs what `full` costs**, and that is honest rather than
  broken: `resolve(_:)` expresses reduced purely as halving `framesPerSecond`, which
  `minimumInterval(for:)` already applies, and a view transform is run by the render
  server regardless. Documented, not invented around. **Whether `reduced` should do
  more is the owner's call.**
- **`.agentIcon` draws an empty rounded square.** §6.2's third flank option is now
  selectable from disk and says nothing, while §4.3 is explicit that *shape* is what
  says which agent is speaking. **Plan 6.6 must not ship a picker for a
  placeholder** — either the marks land first (they exist: `island-motion.html`'s
  `MARKS` has four portable 24×24 `currentColor` geometries) or the option stays out
  of the picker.
- **The session list holds key for as long as it is open, with no time bound.** It
  ends only when the drawer closes. Verified on hardware that Escape and a second
  click both release it, and that typing reaches the terminal again afterwards — but
  if that turns out to be irritating in real use, the cheapest correct fix is to
  release key when another app activates.
- **§10.3's confirmation banner was never in the mockup, so the drawer's height was
  never budgeted for it.** Restoring `Other…` in Task 5 surfaced it: at production
  width, three choices plus `Other…` plus the destructive banner pushed `PanelBar`'s
  mute and gear **entirely out of frame** — confirmed by rendering, not by reading a
  negative margin. Contained two ways, both real fixes rather than loosened
  assertions: `QuestionFace.rows`' gap corrected to the prototype's `5px` (it was
  `8`, a pre-existing divergence this exposed), and `Other…` hidden while a
  confirmation is showing, reappearing when it clears. **The underlying mismatch
  stands** — the mockup gives `.question` 288pt and has no second ask in it at all,
  because §10.3 is a spec rule the prototype never drew. Whoever owns panel size
  (Plan 6.6) inherits the real budget question.
- **`.sessionCount(0)` now passes through instead of collapsing to `.nothing`.**
  `CollapsedLayout` already treats the two as indistinguishable on every axis, pinned
  by `aZeroCountCollapsesToNothing`, so the old ternary's special-casing was an
  accident of the hardcoding rather than a decision. And the cat's left edge was
  rasterised across all three `RightFlank` values and does not move — §5.3's
  constant `LW = 58pt` is what pins it, and a flank change that moved the cat would
  be a defect, not a side effect.
- **`off` renders at phase 0**, which is the prototype's own answer rather than a
  convenience: `island-motion.html:439`'s entire reduced-motion rule is
  `animation:none`, and a CSS element with no animation renders at its base style —
  the pose every keyframe set names at `0%`. Verified not mid-blink (the blink lives
  above 0.92) and not on `bang`'s raised mark (which shifts only past 0.5).

## Plan 6 also owns

Everything here used to be gated on one unknown: whether a `.nonactivatingPanel`
at `.statusBar` can take **key** events without stealing focus from the terminal
an agent runs in. Mouse input was measured in Plan 2 and does not.

**Resolved 2026-08-03 — Path A.** [The key-input
spike](../spikes/2026-08-03-notch-panel-key-input.md): the panel becomes key,
receives every keystroke **exclusively**, and never changes
`frontmostApplication`. Nothing below is blocked any more. Two findings came with
it, and the first is now a hard constraint on this plan rather than an
implementation detail:

- **Key status may be held only while a question is open.** Delivery is exclusive
  and `frontmost` does not change, so a panel left key at rest silently swallows
  everything the person types into a terminal that still shows every sign of
  having focus. Take key on open; give it back on answer, dismiss or lapse.
- **`NSApp.isActive` is not a usable proxy** — it read `true` in every run while
  focus demonstrably stayed elsewhere. Test against `frontmostApplication`.

- **Wiring the number keys.** `KeyRouting.pick` exists, is well tested, and is
  reachable from nothing. It takes a `Character`, so it consumes what the probe
  measured actually arriving (keypad and top-row digits alike) without change.
- **Restoring `Other…`.** Plan 4 cut the row because it opened a field nobody
  could type into and could not be backed out of. Typing works.
- **`IslandBody.phase` bypassing `MotionPreference`** — already assigned here and
  restated because it is the one item that must be fixed *inside* Plan 6 rather
  than after: with motion `off`, `needsTimeline` is false, `now` is one arbitrary
  `Date()`, and the cat freezes at a random point in its cycle — roughly 8% of
  the time mid-blink, i.e. a running cat with its eyes permanently shut. Inert
  only because nothing selects a level other than `.full` yet. The moment Plan 6
  ships the control, it is visible.
- **`MotionPreference.current()` is read once, at init**, so toggling the system
  Reduce Motion setting does nothing until relaunch.
  `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` is the fix.
- **The duplicate tier.** `NotchController.tier` and `IslandModel.tier` are now
  two separate pieces of state for one concept; the controller's is read by
  exactly one test and nothing in `Sources/`. Plan 4 created the second one, so
  the reconciliation belongs with whoever next touches the motion and tier code.

## Carried out of the second mockup-fidelity wave

Full account: [`.superpowers/sdd/mockup-fidelity-wave2.md`](../../../.superpowers/sdd/mockup-fidelity-wave2.md).
Nine of the eleven items on that wave's list are closed. What is left is here
because it is owned elsewhere, not because it was skipped.

- **The list panel is 388pt where the mockup's is 560px, and in production it is
  narrower still.** This is the real cause of line 2 truncating to `As…` in the
  rendered list — *not* the type ladder, which the wave matched to the mockup and
  measured as costing 40pt rather than saving any (10pt mono is wider than 11pt
  sans on `iTerm2 · Opus 4.8 · high`). The row's ink saturates at **420pt**; the
  mockup gives its rows 524. `IslandModel.drawerWidth` derives the drawer's width
  from the collapsed island's own resting layout — 273.1pt on the `mbp14` fixture
  — so the widest the list ever gets is a side effect of how many tallies are on
  the bar. §6.3 fixes the drawer's *height* per face and says nothing about width.
  **A per-face width, the way there is already a per-face height, is the fix.**
  Whoever owns §6.3 owns this; it is not a row-fidelity item.
- **`.pip.live` and `.ract.live .caret` are still not animated** (1.8s and 1.4s
  `softpulse`). Held back for two reasons, both deliberate: every raster assertion
  in the drawer suite becomes time-dependent the moment a row animates, and an
  open session list already costs +7 to +14pp of a core before any per-row
  animation is added — which touches an open cost decision the owner has not made.
  The hook exists: `SessionListFace` already runs a 1Hz `TimelineView` while
  anything is running, and `IslandView` already derives phase from a `now`. Do it
  with `MotionPreference` respected and the goldens rendered at a pinned phase.
- **`.rtop` is `align-items:baseline` in the mockup and centre-aligned here.** Left
  alone: the previous wave's `.lineLimit(1)` on the project name removed the case
  where it was visible (a wrapped name dragging the state pip off the baseline),
  so this is now a sub-pixel difference with a real risk of disturbing two golden
  heights. Worth doing in the same pass as the width above, where the row's layout
  is being re-measured anyway.

## Plan 7 — generic adapter and custom sources (§3)

§18 puts this in **v1**, and `Sources/VibeCatCore/Adapters/` still contains one
file. `SourceAdapter` and its registry were built to take more — the registry
already resolves a duplicate id in favour of the later adapter, precisely so a
user's custom source can shadow a built-in — so this fills a designed hole
rather than opening one.

**It came after Plan 6's Settings pages, and is now written** —
[the plan](2026-08-05-generic-adapter.md), 6 tasks. The reason it waited was that
*"a custom source is one a person configures, and there is nowhere to configure
anything until Settings exists"*. 6.4 built the shell and 6.5–6.6 two of its pages,
which is enough: **the definitions are config, and the UI that edits them is 6.7's.**
A source defined in a file is already useful and already testable, which is the same
"reachable, not dead" standard Plan 6.1 used for the right flank before its picker.

**It also carries the owner's icon request.** §3 already specified the mechanism —
*"VibeCat ships neutral geometric marks and lets a source point at its own icon
file"* — and `SourceAdapter` never had the field. Measured while reviewing the
owner's set: `NSImage` loads SVG, PNG and WebP with **no dependency**; two SVGs
reported `1×1` because they used `width="1em"` with no font context; and the icons
**must not be committed**, because the repo is public and MIT and MIT cannot grant
trademark rights — which is §3's own stated reason for the point-at-a-file design.

**The unresolved half is §4.3.** `CLIMark` is `currentColor` geometry tinted by the
state accent: shape says who, hue says what state. A brand logo arrives with its own
colour, so it puts a second meaning on hue. Task 1 rules; the plan says plainly there
may be no answer that satisfies both, and asks for the trade to be named in the
source rather than resolved silently.

Codex, Copilot and Gemini presets stay in §18's **Later** column. The generic
adapter is what makes them cheap when they come.

### What Plan 7 landed, and what it found (2026-08-06)

**Landed.** `SourceAdapter.icon` and a `SourceIcon` view (T1); a data-driven
`GenericAdapter` (T2); custom sources persisted in
`~/Library/Application Support/VibeCat/custom-sources.json`, loaded into the
registry, later-wins shadowing (T3); `HookSnippet`, the shell command line a
person pastes (T4); `SessionRow` drawing the real source's icon (T5); and Task 6,
which found that **none of it was connected to anything** and connected it.

**The gap Task 6 closed, because it is the pattern that keeps recurring.**
`SourceRegistry(adapters:)` existed once in `Sources/`, in the *hook* process.
`VibeEvent` contained the string `icon` zero times. `Session.icon` was declared
and assigned from nowhere. So the mechanism was complete, passed its tests end to
end, and no real definition could reach a real drawn row — this project's **third**
"built but never populated", after `Session.lastUserMessage` and Plan 6.4's three
write-only preferences. Closed on the app side: `AppModel.init(sources:)` builds a
registry through the same factory the hook uses and resolves `cli → icon` at
ingest. Not on the wire, deliberately — see §3's dated correction.

**`vibecat-hook` now has an installed home**, which it did not before:
`Scripts/build-app.sh` bundles it at `Contents/MacOS/vibecat-hook` and signs it
with the app, and `HookBinary.installIfNeeded()` mirrors it on launch to
`~/Library/Application Support/VibeCat/bin/vibecat-hook`, the fixed path a
generated snippet names. Two locations because a snippet pasted into another CLI's
config file has to survive the app being moved. **Plan 6.7's Integrations page
should read `HookBinary.resolvedPath()`** — a `nil` there is the whole of "not
installed".

**Proved on hardware, against Codex CLI 0.145.0.** A custom source defined as
data, its snippet generated by `HookSnippet`, installed in Codex's own
`hooks.json`, driven by a real `codex exec`. Codex's payload is expressible as
generic-adapter data with **no code at all** — `hook_event_name` / `session_id` /
`cwd`, the same three keys Claude Code uses. Events reached the island
(`cli=codex`, `model=gpt-5.5`), the row drew Codex's own `#5C74FF` (312 pixels,
against the idle accent `#40D99C`'s 61 in the same corner — §4.3's split-by-context
ruling, visible), and the hook exited **0** on every path including a deliberately
missing binary.

**Task 4's `/bin/sh -c` assumption is settled, and the reason was better than the
one given.** Codex runs a hook command through **`$SHELL -c`** — the *user's*
shell, measured as `/bin/zsh` 5.9, non-login. So the outer interpreter is not a
property of the CLI at all; it varies per machine. That is what the explicit
`/bin/sh -c` wrapper buys.

**The defect the hardware run found, and this is the one to remember.** Reading an
icon out of `~/Downloads` **hung the app's main thread inside `open(2)`,
indefinitely** — a TCC-protected directory, an `open`-launched bundle with no
inherited grant, and an `LSUIElement` app that cannot present TCC's prompt.
`SourceIcon.loadValidImage`'s doc comment claimed to handle "every way a path can
be wrong that must not throw, hang or crash" and enumerated five inputs, all of
them files whose `open(2)` *returns*. Now bounded and cached by
`SourceIconLoader` (50ms, then the geometric mark). **No test could have found
it** — every fixture is a file in `/tmp` the test process can always read — and
the first attempt to write one used a FIFO, which does not reproduce it
(`NSImage` `stat`s first and returns `nil` in 7ms; four tests passed in 0.001s
each against the very code they were written to catch).

### What Plan 7 leaves, in priority order

1. **Codex, Copilot and Gemini presets — still §18's Later.** Now much cheaper
   than when that was decided, and the measurement is in hand: Codex needs *only*
   data. What a preset still needs by hand is the one thing generic data cannot
   express, and it is Claude Code's own: **`PreToolUse`'s `body` needs a nested
   `tool_input` traversal with an eight-key preferred order plus a sorted-keys
   fallback, and its `choices` embed the tool name into a sentence** ("Allow every
   `Bash` call this session"). A preset is data plus, occasionally, a little code.
   **Do not widen the config language for it** — Task 2's own finding.
2. **`EventRule` has no literal `title`/`body`, only a key into the payload.**
   Found while writing a real Codex definition: there is no way to say "the
   sentence for this event is *Working*". Every §11 line-2 sentence therefore has
   to be a value the vendor happens to send. A `title` string beside `titleKey` is
   a two-line change and was deliberately not made here, because Task 2 ruled that
   the honest answer to "generic data cannot express this" is a note, not a wider
   language — and this one has not yet been shown to matter.
3. **Plan 6.7's Integrations page inherits:** the per-CLI list (`SourceRegistry
   .ids` and `displayName`), install status (`HookBinary.resolvedPath()`), the
   snippet to copy (`HookSnippet.command`), the "Add CLI" branch that writes a
   `CustomSourceDefinition`, and the icon file picker. **The picker must warn about
   `~/Downloads`, `~/Documents` and `~/Desktop`**: an icon there is bounded now
   rather than fatal, but it silently never appears. Copying the chosen file into
   `~/Library/Application Support/VibeCat/icons/` is what the hardware run had to
   do to see the icon at all, and is probably what the picker should do too.
4. **`CLIMark.displayName(cli:)` is still three hardcoded literals.** Its own doc
   comment says it becomes a one-line forward to `SourceAdapter.displayName` "when
   the app side gains a registry". The app side now has one (`AppModel.sources`),
   so the forward is available — not done here because the display name is not on
   `Session` and threading it is a Plan 6.7 concern, but the blocker named in that
   comment is gone.
5. **The `wantsReply` round trip was not exercised through a second CLI.** Codex's
   `PermissionRequest` fires only on a real approval, which a
   `--sandbox read-only --ask-for-approval never` run never produces. The
   definition declares it with `wantsReply: true` and two choices; `PipelineTests`
   covers the mechanism through `HookRunner`. Driving it from Codex interactively
   is untested.
6. **`SourceIconLoader` is bounded, not asynchronous.** A slow-but-answering path
   costs one 50ms main-thread stall the first time a source's row appears, once
   per path per process. If icons ever come off a network volume, the right shape
   is an `@Observable` cache that returns immediately and invalidates on arrival —
   which would mean rewriting every synchronous brand-colour golden assertion in
   `SourceIconTests` and `SessionRowTests`. The trade is written in the type.
7. **`VibeCat.app/Contents/MacOS/vibecat` run directly from a shell SIGABRTs**, TCC
   namespace, "must contain an `NSFocusStatusUsageDescription` key" — even though
   `Info.plist` does contain it, because a shell-launched bundle makes the *shell*
   the responsible process and TCC reads that process's plist. Exactly the hazard
   `Scripts/build-app.sh`'s footer warns about, now with four crash reports
   attached. Not a defect to fix; recorded so the next person to lose an hour to it
   does not have to.

## Plan 8 — matching motion cost to motion content (§9.1)

Every animation over-samples its own artwork by 3–6×: `squares` has 4 distinct
frames and draws 12 a cycle, `bang` has 2 and draws 13, `trot` has 3 and draws
12. Frame rate is the *entire* CPU cost — the animation spike measured 8fps at
~6% of a core against 120fps at ~15–18%, with path batching making no measurable
difference — so matching rate to distinct frames cuts cost proportionally with
**zero visual change**.

Two corrections to what the Plan 3 follow-ups recorded, both checked against the
source on 2026-08-02:

- **`MotionPreference.floorFPS = 8` does *not* block this.** `resolve` returns
  the profile unchanged at `.full` and only applies the floor in the `.reduced`
  branch, where it stops halving from going below 8. Nothing prevents setting a
  per-animation rate today. The follow-up said otherwise; it was wrong, and this
  work is cheaper than recorded.
- **`IslandBody.phase` and `.badgePhase`'s duplication** belongs here rather than
  with the frame-rate work — a shared helper taking a cycle removes it, and it is
  small enough to fold into whichever task touches those properties.

**It comes after Plan 5**, because the reason none of this is urgent today is
that the idle island costs 0.35% of a core and three of five moods have no
timeline at all. Plan 5 puts several sprites on screen at once. Optimise against
its measurements, not against Plan 3's single-sprite ones.

## Is everything the plans promised actually built?

Audited 2026-08-02 against the spec, section by section, because "the plan says
done" and "the behaviour exists" are different claims. Result: **the plans
delivered what they claimed**, with three exceptions, all now owned.

- **§6.2's right flank is not configurable.** The spec says "configurable:
  session count (default), agent icon, or nothing." `CollapsedLayout.RightContent`
  has all three cases, but `IslandModel.layout` hardcodes
  `sessionCount > 0 ? .sessionCount : .nothing`, so `.agentIcon` is constructed
  by nothing — the unreachable branch already recorded after Plan 3. The missing
  part is the *choosing*, which is a setting → **Plan 6**.
- **§16's AppleScript hint.** Four of its five rows are implemented and tested:
  socket missing fails open, a slow reply falls through to the CLI's default,
  a display change recomputes geometry from the API, and a notchless display
  gets the fallback pill. The fifth — "AppleScript blocked → show a hint linking
  to the Automation setting" — is not, and cannot be until there is an
  AppleScript call to block → **Plan 6, with jump**.
  (An earlier reading of this section here said §16 was "essentially
  unimplemented." That was wrong — one `standardError.write` and no file named
  `Error` is not the same as no error handling, and the behaviour is spread
  across `SocketClient`, `HookRunner`, `IslandGeometry` and `NotchController`.)
- ~~**§9.1's 190ms face crossfade** — absent, confirmed, and now named in Plan
  4.5.~~ **Present since Plan 5** — see Plan 4.5's own entry above for the two
  stages it took to get a caller.

Everything else the plans claimed is present: §2's socket and wire protocol,
§4's states and worst-state-wins, §5's geometry including the corner minimum,
§6.1's three tiers and §6.3's drawer heights, §7's five moods and five coats,
§8's five badges, §9.2's aura, §9.3's rule, and all of §10 bar the keyboard.
§§11–14 are Plans 5 and 6 and were never claimed.

## Not a plan, and still not done

- ~~**No licence has been chosen.**~~ **Resolved 2026-08-03: MIT.** `LICENSE` is in
  the repo root and the README points at it. Chosen for what this project actually
  is — a solo utility with no dependencies and no outside contributors — where
  Apache-2.0's patent grant and change-notice ceremony buy nothing yet, and copyleft
  would restrict users without protecting anything the design cares about (§15
  already rules out the App Store, so GPL closed no door here either).

  The trademark question §3 raises is untouched by this and deliberately so: VibeCat
  ships neutral geometric marks and lets a source point at its own icon file, so no
  third-party logo is redistributed and the licence never has to answer for one.

  With that settled, `main` may be pushed.
