# The Cat, Badges and Motion — carried follow-ups

Triaged by the whole-branch review at the end of Plan 3. Everything here was
found, judged, and deliberately deferred. The execution ledger it came from is
gone; this is the surviving record.

## Seen, and not right yet

The cat was finally rendered — not on screen, but offscreen with `ImageRenderer`,
which draws these views headlessly and needs no unlocked session. That technique
is the answer to a gap that blocked visual verification across two plans, and it
should be the first tool reached for next time.

> **Resolved 2026-08-02.** All three artwork items below were fixed after the
> contact sheet (`Tests/VibeCatUITests/Cat/ContactSheet.swift`) rendered them
> side by side for the first time — commits `6c4cab3`, `b09be7b`. Each new test
> was mutation-checked against the exact art that shipped. The originals are
> kept here because the *pattern* is the finding: every one of these had a
> passing test that asserted inequality where the question was perceptibility.

- ~~**The `zzz` badge does not read as z's.**~~ The "big z" was a 3×3
  `###`/`.#.`/`###` indistinguishable from an I-beam; the "small z" a solid 2×2
  block with no glyph at all. A 3×3 z *cannot* work: with top and bottom bars
  the middle stroke can only be the centre column, which is where an I's stem
  goes — the same nine cells. Redrawn with four rows for the big z and four
  columns for the small.
- ~~**`plain` differs from `tabby` by 6 cells out of 210.**~~ The cause was
  worse than the symptom: `tabby` painted *nothing*, and the test pinning that
  was `tabbyIsTheBaseGridUnchanged` — the defect written down as the expected
  result. `tabby` now has forehead bars and cheek stripes; the tightest coat
  pair is 20 cells against a 12-cell floor.
- ~~**`call` and `trot` are near-identical sprites.**~~ `trot` now steps twice
  per cycle and `call` hops once and holds, and `call`'s mouth opens into a 2×2
  instead of widening an existing dark mark.
- **Hover opens 150pt of empty black.** Confirmed on screen 2026-08-02: hover
  works, and the island opens to 420pt with a cat, a badge, a count and a void.
  Correct until Plan 4/5 fill it, but worth a conscious decision rather than
  shipping by omission.

## What a real screen showed, 2026-08-02

First time the app has been looked at rather than reasoned about. Geometry is
exact: the island's left edge landed on 605pt with the cutout at 663–848, i.e.
`notch.minX − 58` to the point. State colours, badge shapes, the session count's
position right of the hole, and the hover reveal are all correct.

Two things the render could not have told us:

- **The aura fires and cannot be seen.** 24 screen samples across a state change
  traced the exact `sin(phase · π)` curve, ~960ms wide — and its peak lifted the
  band outside the island by *six levels summed across R, G and B*. Fixed in
  `45e1e31`; `peakOpacity` 0.14 → 0.34. Plan 2's follow-up predicted both the
  symptom and the cause.
- **The corner mismatch is two curves in the same fifteen points.** Ours is
  15pt, the hardware's measures ~14. Fixed in `e72ba07` by clearing the cutout
  by a full corner radius so ours covers theirs — matching Apple's radius by eye
  does not converge. Pinned by test; **not yet confirmed on screen**, because
  the machine locked before the rebuild could be photographed.

One method that does **not** work, recorded so it is not tried again:
`NSWindow.windowNumber(at:)` returns 0 for windows outside the calling process,
so it cannot test click-through from a separate probe — the control point reads
0 too. `ignoresMouseEvents = true` is set in `NotchPanel`; confirming it needs a
real click.

## Spec behaviours consciously not implemented

Design §7–§9 items absent from this branch, so the next plan does not rediscover
them as bugs:

| Behaviour | Spec | Why not |
|---|---|---|
| `sleep`'s slow drowse, `dead`'s slow wobble | §7.2 | Ruled by the owner: a live timeline costs ~3.6% of a core and these are all-day states. Cycles retained so it is a one-line revert. |
| `happy`'s one spring pop | §7.2 | Not ruled — simply missed. Unlike the two above this is a *bounded* one-shot, the same shape as the aura, and would not cost an idle timeline. Worth implementing. |
| `star`'s twinkle every 2.2s | §8 | Same reasoning as sleep/dead; `star` is still. |
| The 190ms face crossfade | §9.1 | Never assigned to a task. |
| Reduced-motion Full/Reduced/Off control | §9.3 | The *rule* ships (`MotionPreference`); the Settings UI is Plan 6. |

## Must be fixed **in** Plan 6, not after

**`phase` bypasses `MotionPreference`.** `IslandBody.phase` reads the *unresolved*
`mood.motion.cycle`, and `ResolvedCat.offset` gates on the raw
`mood.motion.isContinuous`. With motion set to `off`, `needsTimeline` is false, so
`now` is a single arbitrary `Date()` — the cat freezes at a random point in its
cycle. Roughly 8% of the time that point is mid-blink, i.e. a running cat with
its eyes permanently shut.

Inert today only because nothing selects a level other than `.full`. The moment
Plan 6 ships the motion control, this becomes visible. Pin `phase = 0` when
`needsTimeline` is false, and route the offset through the resolved profile.

**`MotionPreference.current()` is read once, at init.** Toggling system Reduce
Motion while the app runs does nothing until relaunch. `NSWorkspace`'s
`accessibilityDisplayOptionsDidChangeNotification` is the fix.

## Rate is decoupled from content

The animation spike's central finding is that frame rate is the entire CPU cost.
Every profile here names a rate in 8–12 fps chosen to satisfy the plan's "never
the display rate" constraint — not to match the number of distinct frames each
sprite actually has:

| animation | distinct frames | draws per cycle |
|---|---|---|
| squares | 4 | 12 |
| bang | 2 | 13 |
| trot | 3 | 12 |

Every one over-samples by 3–6×. Matching rate to distinct frames would cut CPU
proportionally with **zero visual change**. `MotionPreference.floorFPS = 8` blocks
this, and its stated justification — "below this the steps read as stutter" — is
an uncited assertion that is plainly wrong for a 2-frame sprite.

## Smaller, safe, unhurried

- ~~**`hasRightContent` returns true for `.nothing` while hovering.**~~ Fixed in
  `e72ba07`, forced by the corner minimum: a nonzero floor would have made
  `rightFlankWidth > 0` permanently true. It now switches on `right` and answers
  the question its name asks.
- **`.agentIcon`'s render branch is unreachable and untested.** `IslandModel.layout`
  never emits it, so no test can construct an `IslandBody` that reaches it.
- **`Tone(rawValue:)` maps an unknown character to `nil`** — a transparent hole. A
  typo in the grid art would silently punch a hole in the cat and no test would
  notice, because `noCoatIntroducesAToneTheBaseGridDoesNotUse` derives its
  expectation from `base` itself. One assertion — 210 non-transparent cells —
  closes it. (Verified: 0 unknown characters today.)
- **The fur-only coat guard has no regression test.** `noCoatTouchesTheEyes` covers
  only `W`/`K`/`P`; nothing would catch `furTones` being widened into `O`/`E`/`N`,
  which is precisely what the owner's ruling protects.
- **`CatPalette` rebuilds five `RGBA(hex:)!` values on every subscript access**
  while `ground`/`white` are cached. 210 cells per frame; immeasurable next to a
  timeline, but fold it into the frame-rate work.
- **C2's fallback-pill offset has no regression test.** `IslandBody` pairs the
  *actual* body with the *fixed* panel deliberately; the naive substitution its
  comment warns against would misplace content on a notchless display, and
  nothing would fail.
- **`render()` writes `model.state`/`sessionCount`/`aura` unconditionally.**
  `@Observable` notifies on the write, not on a change, so every hook event
  invalidates the body two or three times even when nothing changed. Fine at
  Plan 3 rates; revisit for Plan 5's session list.
- **`NotchController.tier` is write-only bookkeeping.** It immediately becomes
  `model.hovering`, `IslandTier.hover` has `extraHeight == 0`, and
  `frames(tier:)` is only ever called with `.rest` in production.
- **`IslandBody.phase` and `.badgePhase` are near-identical.** A shared private
  helper taking a cycle would remove the duplication.

## The testing ceiling this branch hit

Three times in this plan a test passed against a broken implementation because an
`@escaping` closure — `Canvas`'s renderer, `TimelineView`'s content,
`NSHostingView.rootView` — never ran during `.body` access. Each time the fix was
to hoist work into an eager property and count reads from a `static var`. Three
such counters now exist, behind `#if DEBUG`.

That is a clever substitute for view introspection, but each counter only proves a
property was *touched*, never that it was *wired to the right modifier*. The
branch has reached the ceiling of testing SwiftUI this way. The honest next move
is not a fourth counter — it is `ImageRenderer` golden-image tests, which work
headlessly against these exact types with no new dependency.

> **Done 2026-08-02** (`3116b89`), with one correction to the reasoning above:
> the golden tests do **not** supersede the counters, and both are kept.
> Reverting `body` to `.frame(width: body.width)` with a single `.animation`
> renders *identically* — the sum is the same number — so no image can see it,
> and only the read counts drop to zero. The render covers geometry reaching the
> frame; the counter covers which value the animation is keyed on. They fail on
> different mutations.
>
> Also established: `ImageRenderer` **does** run `Canvas`'s renderer closure
> (29,664 opaque pixels in 9 tones for the cat alone), so the escaping-closure
> hazard that motivated the counters does not apply to a render. And a
> colour-count assertion is not enough to prove the cat drew — with the cat's
> `Canvas` emptied, the island still rendered eighty-odd distinct colours from
> the badge and antialiased text. The fixed facial tones are the discriminator.
