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
| **5** | The session list · **plus the hover reveal's content and the sliver that shares its mechanism** · plus a multi-sprite CPU measurement | §11, §9.1's reveal | **next** |
| **6** | Sound, jump, all four Settings sections, the Full/Reduced/Off control · **plus everything gated on keyboard input** | §12, §13, §14, §9.3's UI | not written |
| **7** | Generic adapter and custom sources | §3 | not written |
| **8** | Matching motion cost to motion content | §9.1's rates | not written |

Everything that had no owner now has one. What follows is where each thing went
and why, so a later reader does not have to reconstruct the reasoning.

## Fix now — no plan, four small commits and one measurement

These need no design decision, so wrapping them in a plan would be ceremony.

- **`.truncationMode(.middle)` on the drawer's command body.** Plan 4's
  `.lineLimit(1)` stopped the confirmation banner clipping, but SwiftUI's
  default `.tail` truncation eats the *destination* of a long command:
  `rm -rf /Users/dev/projects/vibe…`. A person is asked to authorise a
  destructive command unable to see what it targets. **Do this first** — it is
  the only item anywhere on this list that touches safety.
- **`@MainActor` on `theConfirmationBannerNamesTheControlThatActuallyConfirms`**
  (`QuestionFaceTests.swift`) — the only test in its file without it, and the
  branch's one compiler warning.
- **Cache `CatPalette`'s five accent-derived tones.** `ground` and `white` are
  already cached; the other five are rebuilt on every subscript access, 210
  cells a frame. No decision to make, so it does not need to wait for Plan 8.
- **Run `KeyDownProbe` on an unlocked machine** (`VIBECAT_KEYDOWN_PROBE=1`).
  It is a measurement, not code, and it unblocks two Plan 6 items. It prints the
  frontmost application before and after and aborts on `loginwindow`, so it
  cannot repeat the void reading that nearly became a recorded fact.

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
- **`render()`'s unconditional writes.** It assigns `model.state` and
  `model.sessionCount` on every call, and `@Observable` notifies on the write
  rather than on a change, so every hook event invalidates the body two or three
  times when nothing differs. Harmless at today's rates; Plan 5 is what raises
  them.
- **A CPU measurement, as a task.** Plan 3's numbers are all single-sprite, on
  mains power, on a 120Hz built-in display. Plan 8 needs multi-sprite numbers to
  aim at, and Plan 5 is the first thing that produces several sprites. Measure
  with `getrusage(RUSAGE_SELF)` — **never `ps %cpu`**, which is a decaying
  average and once produced a false failure that cost most of a plan's
  investigation budget.

## Plan 6 also owns

Everything here is gated on the same unknown: whether a `.nonactivatingPanel` at
`.statusBar` can take **key** events without stealing focus from the terminal an
agent runs in. Mouse input was measured and does not. Run the probe first.

- **Wiring the number keys.** `KeyRouting.pick` exists, is well tested, and is
  reachable from nothing.
- **Restoring `Other…`.** Plan 4 cut the row because it opened a field nobody
  could type into and could not be backed out of. It returns when typing works.
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

## Not a plan, and still not done

- **No licence has been chosen.** The project README says so. Local `main` is
  deliberately unpushed and now 158 commits ahead of `origin/main` — pushing
  publishes, so that decision comes first.
