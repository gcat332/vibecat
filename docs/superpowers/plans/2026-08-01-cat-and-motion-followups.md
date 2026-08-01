# The Cat, Badges and Motion — carried follow-ups

Triaged by the whole-branch review at the end of Plan 3. Everything here was
found, judged, and deliberately deferred. The execution ledger it came from is
gone; this is the surviving record.

## Seen, and not right yet

The cat was finally rendered — not on screen, but offscreen with `ImageRenderer`,
which draws these views headlessly and needs no unlocked session. That technique
is the answer to a gap that blocked visual verification across two plans, and it
should be the first tool reached for next time.

What the renders show:

- **The `zzz` badge does not read as z's.** The "big z" is a 3×3 `###`/`.#.`/`###`
  that is indistinguishable from an I-beam; the "small z" is a solid 2×2 block
  with no glyph at all. §8's "drift up and fade" has no fade. The badge is now
  still (see below), so this is purely an artwork problem.
- **`plain` differs from `tabby` by 6 cells out of 210** and is effectively
  invisible. The coat tests assert *inequality*, not *perceptibility* — they pass
  on it, which is a test sharing a premise with the code.
- **`call` and `trot` are near-identical sprites.** `ResolvedCat.offset` takes the
  mood but uses it only for the `isContinuous` guard, so both get the same
  one-cell bob; `call` differs from `trot` by 2 cells out of 210 (the mouth).
  §7.2 specifies "quick bob" for one and "attention pulse" for the other.
- **Hover opens 150pt of empty black.** Correct until Plan 4/5 fill it, but worth
  a conscious decision rather than shipping by omission.

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

- **`hasRightContent` returns true for `.nothing` while hovering.** Semantic drift
  introduced when hover started opening the reveal unconditionally. Inert today —
  nothing in `Sources/` reads it — but it is `public` and a later plan will
  believe the name. Rename to `reservesRightFlankWidth` or restore the
  content-only meaning.
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
