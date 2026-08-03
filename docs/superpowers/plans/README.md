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
| 5 | The session list · plus the hover reveal's content and the sliver that shares its mechanism · plus a multi-sprite CPU measurement | §11, §9.1's reveal | **written** — [the plan](2026-08-03-session-list.md), 8 tasks |
| **6** | Sound, jump, all four Settings sections, the Full/Reduced/Off control · **plus everything gated on keyboard input** | §12, §13, §14, §9.3's UI | not written |
| **7** | Generic adapter and custom sources | §3 | not written |
| **8** | Matching motion cost to motion content | §9.1's rates | not written |

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
- **The motion curves.** The prototype is explicit cubic-beziers over
  `--t-shape: 440ms` — `--spring-w: cubic-bezier(.32,1.5,.5,1)` (that `1.5` is
  real overshoot) and `--spring-h: cubic-bezier(.34,1.22,.5,1)`. We use SwiftUI
  `.spring(response: 0.42, dampingFraction: 0.72)` for width and `0.42/0.78` for
  height. The *intent* translated — 0.42 ≈ 420ms against 440, and width
  overshoots more than height in both — but a spring settles asymptotically where
  a bezier lands exactly, so this is where the feel diverges most and it will not
  be settled by matching numbers. Render or record both and compare.
- **`--t-face: 190ms`, the face crossfade, was never implemented.** Already
  recorded in Plan 3's follow-ups as never assigned to a task.
- **The type scale has never been compared.** The prototype runs a dense ladder —
  9, 9.5, 10, 10.5, 11, 11.5, 12, 12.5, 13, 14.5px — across SF Pro Text and SF
  Mono. We have `RightFlankFont` and whatever Plan 4's drawer chose.

The deliverable is as much the **written record of deliberate divergences** as
the fixes. A divergence nobody wrote down gets re-introduced or re-removed by
the next person who notices it.

## Plan 5 also owns

Two items land here because they share a mechanism or a cause with the session
list, not because the list needs them.

- **The hover sliver.** `IslandBody`'s silhouette is one shape spanning the whole
  body height at the hover-coupled width, while Plan 4 made the drawer's width
  hover-independent. The result is a 150pt-wide opaque rectangle covering ~92% of
  the drawer's height, appearing and disappearing with hover. Fixing it means
  changing `IslandBody`'s hover-reveal mechanism — which is exactly the mechanism
  Plan 5 fills with §9.1's promised name and elapsed time. Doing both at once is
  cheaper than doing either twice.
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
- **A CPU measurement, as a task.** Plan 3's numbers are all single-sprite, on
  mains power, on a 120Hz built-in display. Plan 8 needs multi-sprite numbers to
  aim at, and Plan 5 is the first thing that produces several sprites. Measure
  with `getrusage(RUSAGE_SELF)` — **never `ps %cpu`**, which is a decaying
  average and once produced a false failure that cost most of a plan's
  investigation budget.

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

## Plan 7 — generic adapter and custom sources (§3)

§18 puts this in **v1**, and `Sources/VibeCatCore/Adapters/` still contains one
file. `SourceAdapter` and its registry were built to take more — the registry
already resolves a duplicate id in favour of the later adapter, precisely so a
user's custom source can shadow a built-in — so this fills a designed hole
rather than opening one.

**It comes after Plan 6** for one reason: a *custom* source is one a person
configures, and there is nowhere to configure anything until Settings exists.
The adapter engine could technically land earlier; its useful half cannot.

Codex, Copilot and Gemini presets stay in §18's **Later** column. The generic
adapter is what makes them cheap when they come.

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
- **§9.1's 190ms face crossfade** — absent, confirmed, and now named in Plan 4.5.

Everything else the plans claimed is present: §2's socket and wire protocol,
§4's states and worst-state-wins, §5's geometry including the corner minimum,
§6.1's three tiers and §6.3's drawer heights, §7's five moods and five coats,
§8's five badges, §9.2's aura, §9.3's rule, and all of §10 bar the keyboard.
§§11–14 are Plans 5 and 6 and were never claimed.

## Not a plan, and still not done

- **No licence has been chosen.** The project README says so. Local `main` is
  deliberately unpushed and now 158 commits ahead of `origin/main` — pushing
  publishes, so that decision comes first.
