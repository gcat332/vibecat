# Keyboard and the Switches Implementation Plan (Plan 6.1, §9.3 · §10.1 · §6.2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Answer a question with the number keys, restore `Other…`, and fix the
three motion defects that only become visible once a motion control exists —
plus make §6.2's right flank actually choosable.

**Architecture:** Nothing here is new machinery. Every piece already exists and is
reachable from nothing: `KeyRouting.pick` is fully tested and called by no
production code, `ChoiceRow.isOther` is built by nobody, `CollapsedLayout`'s
`.agentIcon` case is constructed nowhere, and `MotionPreference` is read once at
launch. This plan connects them and fixes what connecting them exposes.

**Tech Stack:** Swift 6, SwiftUI with AppKit interop, `UserDefaults`. All system
frameworks — **no package may be added.**

## Global Constraints

- **No external dependencies.** Swift 6, macOS 14 floor.
- **Run the suite with `Scripts/test.sh`, not bare `swift test`.** It is
  `swift test --no-parallel`; the wrapper carries the reasoning. Parallel runs fail
  on nearly every run for reasons that are the suite's fault, not the product's —
  read the script's own header before doubting it. Current total is **647**, ~21s.
- **Zero warnings in debug and `-c release`.**
- **A test that cannot fail is not a test.** Plan 6.4 shipped **seven**; Plan 6.5
  caught three in its own new tests. Before writing an assertion, name the
  production change that would break it. **Report a mutation that stays green
  rather than adjusting the test** — every honest report of that across the last
  four plans found a real defect, several of them real bugs.
- **The mutation lists here are predictions**, and mine have been wrong in both
  directions. Trust what you observe and say so.
- **Reading a property proves nothing about what a SwiftUI view drew.** A `Canvas`
  renderer and a `TimelineView`'s content never run during `.body` access; this
  repo has three separate cases of a test passing against a broken implementation
  for that reason. **Rasterise.** And **count a colour inside a box you predicted,
  never across the render** — bone-text antialiasing lands within tolerance of a
  hairline blend when scanned whole-image, and a mid-grey drew 111 phantom hits.
- **`ImageRenderer` cannot render a `ScrollView` or a `Menu`**, and `cacheDisplay`
  is untrustworthy for flat background colours. `onAppear` does not fire under
  either — Plan 6.5 found that deleting an `.onAppear` is caught by nothing.
- **`@Observable` notifies on the write, not on the change**, and a *mutating* call
  goes through `_modify` and notifies **unconditionally**. Plan 4 shipped an equal
  write that ended no bloom, so a still mood kept a live 8 fps timeline running —
  **3.3% of a core, permanently**, in the state §6.1 says must look idle.
- **`save()` writes the whole `Preferences` struct**, so it is a clobber hazard:
  `load()`, mutate, `save()`, never hold a snapshot.
- **Do not create an `NSWindow` in a test** except through
  `SettingsWindowTests`'s existing retention helpers. A titled window that
  deallocates without `NSApplication.run()` takes the suite down with signal 11;
  the mechanism is documented there.
- **Measure with `getrusage(RUSAGE_SELF)`. Never `ps %cpu`** — a decaying average
  that produced a false failure here and cost most of a plan's budget.
- Commit subjects state the insight. Trailer
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Never `git push`.** Ask, every time.

---

## The hard constraint, from a spike rather than a preference

[The key-input spike](../spikes/2026-08-03-notch-panel-key-input.md) settled
**Path A**: a `.nonactivatingPanel` at `.statusBar` becomes key, receives every
keystroke **exclusively**, and never changes `frontmostApplication`. Two findings
came with it and the first governs this plan:

- **Key status may be held only while a question is open.** Delivery is exclusive
  and `frontmost` does not change, so **a panel left key at rest silently swallows
  everything the person types into a terminal that still shows every sign of having
  focus.** Take key on open; give it back on answer, on dismiss, and on lapse.
  There are three ways a question ends and all three must return it.
- **`NSApp.isActive` is not a usable proxy.** It read `true` in every spike run
  while focus demonstrably stayed elsewhere, and Plan 6.4 later read it `false`
  under a locked screen. It is unusable in both directions — test against
  `frontmostApplication`.

`NotchController` already wires **Escape** through a local monitor, and the comment
at `NotchController.swift:50-56` explains why Escape was safe to wire before the
spike and number keys were not. Read it; the distinction it draws is the one this
plan acts on.

**And `KeyRouting`'s own doc comment states the rule that matters most:** whatever
drives it off a real keystroke must route the returned id back through
`QuestionModel.pick` and `.reply()`, exactly as `QuestionFace.tapped(_:)` does for
a mouse tap. **Never fabricate a `Reply` from a raw id** — that would let a
keyboard path walk straight around §10.3's second ask for a destructive command,
which is the one thing this must not do.

## What is dead today, verified by grep rather than assumed

| Thing | State |
|---|---|
| `KeyRouting.pick` | Fully tested. **No production caller** — three mentions in comments, none in code |
| `ChoiceRow.isOther` | The row exists. **`isOther: true` appears nowhere** in `Sources/` |
| `CollapsedLayout.RightContent.agentIcon` | Handled in three switches. **Constructed nowhere.** `IslandModel.layout:110` hardcodes `sessionCount > 0 ? .sessionCount : .nothing` |
| `MotionPreference.current()` | Called once, in `NotchController.init`, with `chosen` defaulted to `.full` |
| `NotchController.tier` | Read by exactly one test and **nothing in `Sources/`**; `IslandModel.tier` is the live one |

## The three motion defects, and why they are inert only for now

1. **`IslandBody.phase` bypasses `MotionPreference`** (`IslandView.swift:434`). It
   reads `now` and the mood's cycle and consults nothing. With motion `off`,
   `needsTimeline` is false, so `now` is one arbitrary `Date()` and **the cat
   freezes at a random point in its cycle — roughly 8% of the time mid-blink**,
   i.e. a running cat with its eyes shut for as long as it runs. Inert only
   because nothing selects a level other than `.full`. **This plan ships the
   preference, so this plan must fix it.**
2. **`MotionPreference.current()` is read once, at init.** Toggling the system's
   Reduce Motion does nothing until relaunch.
   `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` is the fix.
3. **`BadgeCanvas` never consults `MotionPreference` either** — recorded in the
   badge-transform spike as a second instance of the same bypass. Check whether it
   is still true and fix it in the same task if so; if it is no longer true, say so.

**§9.3's rule, which the fix must honour:** the system asking for less motion beats
a user asking for more, and it never drags a user who chose `off` back into motion.
`MotionPreference.effective` already encodes that — use it rather than
re-deriving it.

## File Structure

| File | Responsibility |
|---|---|
| `Sources/VibeCatCore/Preferences.swift` | *(modify)* `motion` and `rightFlank` |
| `Sources/VibeCatUI/Cat/MotionPreference.swift` | *(modify)* live updates |
| `Sources/VibeCatUI/IslandView.swift` | *(modify)* `phase` through the preference |
| `Sources/VibeCatUI/IslandModel.swift` | *(modify)* the right flank, the one `tier` |
| `Sources/VibeCatUI/NotchController.swift` | *(modify)* key status, the number-key monitor, tier |
| `Sources/VibeCatUI/Drawer/QuestionFace.swift` | *(modify)* `Other…` |
| `Sources/VibeCatApp/main.swift` | *(modify)* wiring |

---

## Task 1: The two preferences these switches need

**Files:**
- Modify: `Sources/VibeCatCore/Preferences.swift`, `PreferenceStore.swift`
- Test: extend `Tests/VibeCatCoreTests/PreferenceStoreTests.swift`

**Interfaces produced:** on `Preferences`, `motion: MotionLevel` (default `.full`)
and `rightFlank: RightFlank` (default `.sessionCount`), where
`public enum RightFlank: String, Sendable, CaseIterable { case sessionCount, agentIcon, nothing }`.

**`MotionLevel` currently lives in `Sources/VibeCatUI/Cat/MotionPreference.swift`
and `Preferences` is in `VibeCatCore`, which cannot import `VibeCatUI`.** That is
the same seam Plan 6.5's Task 1 hit with `AlertPolicy` and `Cue`; it moved the bare
`SoundPack` enum to Core and left its behaviour in the UI as an extension.
**Do the same shape here** — move `MotionLevel` to Core, leave `MotionPreference`,
`MotionProfile` and `resolve` where they are. **Report the move.** Making Core
import the UI is not an option.

`RightFlank` mirrors `CollapsedLayout.RightContent`'s three cases but is **not**
that type: `RightContent.sessionCount` carries an `Int` payload, and a stored
preference must not carry a live count. Task 5 maps one to the other.

- [ ] **Step 1: Extend both round-trip tests, then watch them fail**

`Tests/VibeCatCoreTests/PreferenceStoreTests.swift` already has two of different
kinds and **both must be updated**:

- `everyFieldRoundTripsAndNoTwoSiblingKeysAreCrossed` — add the two fields with
  values that differ from their defaults **and from each other's type-siblings**.
  There is now more than one `String`-backed enum in the struct; **crossing two
  keys that hold the same value changes nothing observable**, which is precisely
  what let Plan 6.5's original mutation through.
- `aFieldAddedWithoutPersistenceFailsWithoutAnyoneRememberingToTestIt` — its
  `readChildren.count == 10` assertion will fail at 12. **That is the test doing
  its job**; update the number and say so in the report.

Run: `Scripts/test.sh --filter PreferenceStoreTests`. Expected: the count
assertion fails first, before you have written any production code.

- [ ] **Step 2: Implement, watch pass, then mutation-verify**

1. Drop `motion` from `save` → the Mirror test must fail **naming `motion`**.
2. Drop `rightFlank` from `load` → the Mirror test must fail naming it.
3. Cross the two new keys → the explicit test must fail. **If it does not, your
   two chosen values collide** — fix the values, not the assertion.
4. Use `MotionLevel(rawValue:)!` instead of a fallback → an unknown plist value
   must **crash rather than fail**, which is the same correct outcome Plan 6.5
   recorded for `SoundPack` and the reason the fallback exists.

- [ ] **Step 3: Full suite, commit**

---

## Task 2: The cat that freezes mid-blink

**Files:**
- Modify: `Sources/VibeCatUI/IslandView.swift` (`phase`, around line 434, and
  `needsTimeline`), `Sources/VibeCatUI/Cat/MotionPreference.swift`
- Modify: `Sources/VibeCatUI/Cat/BadgeCanvas.swift` if the second bypass is still
  real
- Test: `Tests/VibeCatUITests/MotionBypassTests.swift`

This is the task that must not be skipped, because **shipping the switch is what
makes the bug visible** and this plan ships the switch.

**Read first:** `MotionPreference.effective` (it already encodes §9.3's precedence
— the system asking for less beats a user asking for more, and it never drags a
user who chose `off` back into motion), `MotionProfile`, and `resolve(_:)`. Use
them; do not re-derive the precedence.

**The bug, precisely.** With motion `off`, `needsTimeline` is false, so the view is
handed a single arbitrary `Date()`. `phase` divides that by the mood's cycle and
returns a fraction — so the cat is frozen at whatever point that arbitrary instant
happens to name. The blink occupies roughly 8% of the cycle, so **about one launch
in twelve gives a running cat its eyes shut for the whole run.**

**The fix is not "return 0".** Think about what each level means:
- `full` — as now.
- `off` — a *deliberate, chosen* pose, not an arbitrary one. Whatever you pick, it
  must be the same every launch and must not be mid-blink.
- `reduced` — read `resolve(_:)` and honour what the profile says rather than
  inventing a third behaviour.

**State what you chose and why in the source.** A reader who finds `phase`
returning a constant deserves to know it is a decision.

- [ ] **Step 1: Write the failing tests**

The assertions that matter, and none of them can be a property read:

```swift
@Test @MainActor func withMotionOffTheCatIsPosedTheSameWayEveryTime() throws {
    // The bug: `phase` read an arbitrary Date, so the pose was whatever instant
    // the view happened to be built at. Two renders from two *different* instants
    // must be identical when motion is off — which is exactly what fails today.
    let a = try Raster.rasterise(islandProbe(motion: .off, now: Date(timeIntervalSince1970: 1_000_000)), …)
    let b = try Raster.rasterise(islandProbe(motion: .off, now: Date(timeIntervalSince1970: 1_000_037)), …)
    #expect(a.pixelCount(near: …) == b.pixelCount(near: …))
}

@Test @MainActor func withMotionOffTheCatsEyesAreOpen() throws {
    // The specific harm: ~8% of arbitrary instants land mid-blink, so a running
    // cat could have its eyes shut for the whole run. Assert on ink in the eye
    // region only — count inside a box you predicted, not across the render.
}

@Test @MainActor func withMotionFullTheCatStillMoves() throws {
    // The regression guard. A fix that froze the cat at every level would pass
    // both tests above.
}
```

**Fill these in against the real API** — `islandProbe` is illustrative, and the
existing raster idioms are in `Tests/VibeCatUITests/IslandGoldenTests.swift`.
`Raster` is not `Equatable`, so compare a measured quantity, not the images.

- [ ] **Step 2: Add live updates to `MotionPreference`**

`current()` is called once at init. Observe
`NSWorkspace.shared.notificationCenter`'s
`accessibilityDisplayOptionsDidChangeNotification` and re-resolve.

**Anything with a lifecycle tears itself down** — `AppModel` and `HoverMonitor`
both use `isolated deinit` because `RunLoop.main` retains a `Timer` and an accept
thread otherwise runs forever, and a block-based observer outlives the object it
captures unless something removes it. Plan 6.4's `SettingsWindowController` is the
nearest model. **And do not notify unconditionally** — see the `@Observable` rule
in Global Constraints, and Plan 4's 3.3%-of-a-core precedent.

- [ ] **Step 3: Check the second bypass**

The badge-transform spike recorded that `BadgeCanvas` never consults
`MotionPreference`, so motion `.off` with system reduce-motion on changed the cost
by nothing. **Check whether that is still true.** If it is, fix it here; if it is
not, say so and cite what changed.

- [ ] **Step 4: Mutation-verify, then measure**

1. Restore the arbitrary `Date()` in `phase` → the identical-pose test must fail.
2. Freeze at every level, not just `off` → the still-moves test must fail.
3. Remove the observer → add a test that the observer is *installed*, in the shape
   `NotchControllerTests.escapeMonitorForTesting` establishes. Plan 6.4's review
   found that deleting a whole monitor installation block failed no test, because
   every behavioural test drove the handler directly.
4. **Measure the idle cost with motion `off` using `getrusage`.** §6.1 says an idle
   machine must look idle and cost nothing, and `off` should cost strictly less
   than `full`. Report both numbers. If `off` does not cost less, that is a
   finding.

- [ ] **Step 5: Full suite, commit**

---

## Task 3: One `tier`, not two

**Files:**
- Modify: `Sources/VibeCatUI/NotchController.swift`, `IslandModel.swift`
- Test: whichever test reads `NotchController.tier`

`NotchController.tier` and `IslandModel.tier` are two pieces of state for one
concept. The controller's is read by **exactly one test and nothing in
`Sources/`**; `IslandModel.tier` is the live one. Plan 4 created the second.

**Delete the dead one and repoint its test** — unless reading the code tells you
the controller's is the one that should survive, in which case say why and do that
instead. Either way there must be one.

This is small, and it is in this plan because it is in the motion and tier code
Task 2 touches, and the register says the reconciliation belongs with whoever next
touches it. **Do it after Task 2, so you are not reconciling a moving target.**

- [ ] Read both, decide which survives, and say why in the commit message.
- [ ] Repoint or delete the one test that reads the loser.
- [ ] Confirm nothing in `Sources/` referenced it — `grep`, and put the result in
      the report.
- [ ] Full suite, commit.

---

## Task 4: The number keys

**Files:**
- Modify: `Sources/VibeCatUI/NotchController.swift`
- Test: extend `Tests/VibeCatUITests/NotchControllerTests.swift`

**Interfaces consumed:** `KeyRouting.pick(character:in:) -> String?`,
`QuestionModel.pick`, `QuestionModel.reply()`, and the existing
`setQuestion(_:)` / dismiss / lapse paths.

### The three rules this task exists to honour

1. **Route through `pick` then `reply()`. Never fabricate a `Reply` from an id.**
   `KeyRouting`'s doc comment says so and gives the reason: a keyboard path that
   built a `Reply` directly would walk around **§10.3's second ask** for a
   destructive command. `QuestionFace.tapped(_:)` is the shape to copy.
2. **Take key status on open; give it back on answer, on dismiss, and on lapse.**
   All three. A panel left key at rest swallows everything typed into a terminal
   that still looks focused — the spike measured delivery as *exclusive*.
3. **`Other…` has no digit, structurally.** It is synthesised at render time as
   `Choice(id: "__other__")` and is not in `question.rows` at all, so no digit can
   name it. Do not add one.

- [ ] **Step 1: Write the failing tests**

Cover, at minimum:
- digit `1` answers the first row, and the reply that reaches the hook is the one
  the row names
- a digit past the last row does nothing — no reply, question still open
- **a destructive command's second ask is not skipped**: the digit picks, and a
  confirmation is still required. This is the assertion this whole task is for.
- key status is held while a question is open and **released on each of the three
  endings**. Test the state, not the AppKit call, so it runs headless
- Escape still works, unchanged

- [ ] **Step 2–4: Implement, pass, mutation-verify**

1. Fabricate a `Reply` from the id instead of going through `pick`/`reply()` →
   the destructive-second-ask test must fail. **If it does not, that test is the
   most important one in this plan and it does not work** — say so and fix it
   before continuing.
2. Never release key status → the release test must fail for each ending.
3. Release it on answer but not on lapse → only the lapse case must fail, proving
   the three are covered separately rather than by one shared assertion.
4. Accept `0` → a test must fail. Badges number from `1`.

- [ ] **Step 5: Verify on hardware, because no test can deliver a real keystroke**

There is no window server in `swift test`, so nothing above proves a real key
arrives. `Sources/VibeCatApp/KeyDownProbe.swift` exists for this and is gated on
`--keydown-probe` under `#if DEBUG`.

```bash
Scripts/build-app.sh && open .build/VibeCat.app
VIBECAT_SOCKET=/tmp/vibecat-dev.sock Scripts/replay.sh permission
```

Then press `1`. Report: did the CLI receive the decision? Did the terminal keep
focus? **Did anything typed after the question closed still reach the terminal** —
that is rule 2, and it is the one with teeth. And confirm the hook exits `0`:
§2.3 fail-open is this repo's one unbreakable invariant.

**Check `frontmostApplication`, never `NSApp.isActive`** — it has read wrong in
both directions in this project. If the screen is locked, say so and mark the
reading void rather than reporting it; Plan 6.4 lost a measurement that way.

- [ ] **Step 6: Full suite, commit**

---

## Task 5: `Other…`, and the right flank

**Files:**
- Modify: `Sources/VibeCatUI/Drawer/QuestionFace.swift`,
  `Sources/VibeCatUI/IslandModel.swift`, `Sources/VibeCatApp/main.swift`
- Test: extend `Tests/VibeCatUITests/QuestionFaceTests.swift` and
  `IslandModelTests.swift`

Two independent items, together because both are one-line reachability fixes on
existing code and both need the same wiring pass.

### `Other…`

Plan 4 cut the row because it opened a field nobody could type into and could not
be backed out of. **Typing works now.** `ChoiceRow.isOther` exists and
`isOther: true` appears nowhere in `Sources/`.

Restore it, and note what Plan 4's reason implies: **it must be possible to back
out.** A row that opens a field with no way back is the defect that got it cut.
`ChoiceRow.swift:111`'s `else if isOther` branch is where to start reading.

### The right flank

`IslandModel.layout` at line 110 hardcodes
`right: sessionCount > 0 ? .sessionCount(sessionCount) : .nothing`, so
`.agentIcon` is constructed nowhere. §6.2 says the flank is "configurable: session
count (default), agent icon, or nothing."

Map Task 1's stored `RightFlank` onto `RightContent`, remembering that
`.sessionCount` carries a live `Int` the preference must not store. **Decide what
`.sessionCount` does at zero sessions** — today it silently becomes `.nothing`, and
that behaviour is either worth keeping (say why) or was an accident of the
hardcoding.

**There is no UI for either preference yet** — Plan 6.6's Display page owns the
picker. That is *reachability*, not dead code: a value in the plist changes what
the island draws, and a test can set it. Say so in the report so nobody files it
as unfinished.

- [ ] Tests first: each `RightFlank` value produces a visibly different collapsed
      island (**rasterise; three renders differing in exactly one input**), and
      `Other…` appears, opens a field, and can be backed out of.
- [ ] Mutation-verify: ignore the preference and always return `.sessionCount` →
      the flank tests must fail. Make `Other…` unbackable-out-of → its test must
      fail.
- [ ] Full suite, commit.

---

## Task 6: Wire it up, and check the whole thing on hardware

**Files:** `Sources/VibeCatApp/main.swift`, `Scripts/build-app.sh` if needed

- [ ] Thread the stored `motion` and `rightFlank` from `Preferences` into
      `NotchController`/`IslandModel` at launch. **`AppModel.init`'s
      `preferences:` parameter already defaults**, and Plan 6.5's Task 4 recorded
      why that default cannot protect `main.swift`: **no test runs `main.swift`**,
      because an `executableTarget` with a `main.swift` cannot be
      `@testable import`ed. So the risk here is real and unguarded by construction.
      **Say how you convinced yourself the wiring is right** — reading the diff is
      an acceptable answer; claiming a test covers it is not.
- [ ] Launch **both** the bare binary and the signed bundle (`open`, never the
      binary inside). Confirm nothing aborts: Plan 6.2 shipped a launch-path abort
      that 509 green tests could not see.
- [ ] Set each preference by hand (`defaults write`) and confirm the island
      actually changes. This is the only end-to-end proof that exists for a
      preference with no UI.
- [ ] Full suite three times, zero warnings in debug and release, commit.

---

## Out of scope, deliberately

- **Jump (§13) and §16's AppleScript hint.** The next slice. There is no jump code
  in `Sources/` at all, and the hint cannot exist before there is an AppleScript
  call to be blocked.
- **The Display page's motion and right-flank pickers.** Plan 6.6. This plan makes
  both preferences real and reachable; 6.6 gives them controls.
- **Plan 6.2's four audible checks.** Still open, still need a person's ears.
- **The parallel-test-suite rework.** Recorded in `plans/README.md`;
  `Scripts/test.sh` is the interim answer.

## Self-review

**Spec coverage.** §10.1's number keys → Task 4. §10's `Other…` → Task 5. §9.3's
`resolve` being bypassed → Task 2, both instances. §6.2's configurable flank →
Tasks 1 and 5. The duplicate tier → Task 3. **Everything the register lists under
"Plan 6 also owns" except jump is covered**, and jump is named as out of scope with
its reason.

**Placeholders.** Task 2's test bodies are deliberately sketched rather than
complete, and the plan says so and names the file whose idioms to copy — because
`islandProbe` is invented and the real raster helpers have bitten three plans in a
row (`Raster.measureHeight`, `contains(_:tolerance:)`, `Raster != Raster` and
`RGBA(hex: 0x…)` all did not exist when a plan claimed them). **Writing a fourth
set of guessed helper names would be worse than saying "use what is there".**

**Type consistency.** `MotionLevel` (moved to Core in Task 1), `RightFlank` (new,
Core), `RightContent` (existing, UI, carries a payload), `MotionPreference` /
`MotionProfile` / `resolve` (stay in UI). Task 1 defines the two new ones; Tasks 2
and 5 consume them with those spellings.

**One thing I expect to be wrong.** Task 2's mutation 4 asks whether motion `off`
costs less than `full`. I believe it should, but the badge-transform spike found
the opposite shape once already — `BadgeCanvas` ignoring `MotionPreference` meant
`off` changed the cost by nothing. **If `off` does not measure cheaper, that is the
finding, not a failure of the task**, and it belongs in Plan 8's lap.
