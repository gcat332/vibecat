# Notifications Page Implementation Plan (Plan 6.5, §14)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** §14's Notifications page, wired to real behaviour — which agent events
alert you, the sound engine Plan 6.2 built finally getting its sheet, a stall
detector, and a system-notification fallback for when the island cannot be seen.

**Architecture:** The page is rows in groups, built from primitives measured
against the prototype rather than approximated. Every control writes one
`Preferences` field through the existing read-modify-write path. Two pieces of new
*behaviour* sit behind it: per-event alert gating, which is a filter on Plan 6.2's
existing `CueSelector`, and stall detection, which is a timer over
`Session.updatedAt`. The system-notification fallback is `UNUserNotificationCenter`
and is the only new framework.

**Tech Stack:** Swift 6, SwiftUI, `UserNotifications`, `AppKit`. All system
frameworks — **no package may be added.**

## Global Constraints

- **No external dependencies.** Swift 6, macOS 14 floor.
- **The prototype is the authority on appearance.**
  [`settings.html`](../prototypes/settings.html) — the Notifications page is
  **lines 323–378**, its controls' CSS is **lines 72–123**, its tokens **9–27**.
  Plan 6.4 diffed this file in a browser for the first time in the project's
  history and two of the seven differences it found were real bugs no assertion
  would have caught. **Do that again**: Task 7 is that diff.
- **Settings has its own palette and `--accent` means system blue here**, not the
  current state colour. Nothing in `Sources/VibeCatUI/Settings/` may reach for
  `IslandState.accent`. The four state hues are shared only where the sheet shows
  island state — `.pill.ok` is `--idle` and `.pill.warn` is `--waiting`, which are
  genuinely state-ish and correct.
- **A divergence from the prototype is either a fix or a written decision.** This
  plan contains four; do not add a fifth silently.
- **`swift-testing` only**, never XCTest.
- **A test that cannot fail is not a test.** **Plan 6.4 produced seven of them and
  four came from premises its author wrote** — including "a muted speaker draws
  more ink than an unmuted one", which is false, and a sidebar test asserting two
  renders *differ* which passed with the selection inverted, because **"differs" is
  not "differs in the right direction"**. Before each assertion, name the
  production change that would break it. **Report a mutation that stays green
  rather than adjusting the test.**
- **The mutation lists here are predictions.** Plan 6.4's were wrong in both
  directions — one predicted uncatchable turned out catchable because I had the
  clamping backwards. Trust what you observe.
- **`save()` writes the whole `Preferences` struct, so it is a clobber hazard.**
  Every writer must `load()`, mutate, `save()` without holding a snapshot. This
  page adds roughly ten writers, which is more than the rest of the app combined.
- **`ImageRenderer` cannot render a `ScrollView`**; use `rasteriseHosted` /
  `cacheDisplay` from `Tests/VibeCatUITests/Raster.swift`. But note Plan 6.4
  measured that path as **untrustworthy for flat background colours** — it read
  `#2E2E32` where the view painted `#1C1C1E`. `ImageRenderer` readings were exact
  to 3 levels. Pick the path per assertion and say which you used and why.
- **A mid-grey cannot be counted over a whole render.** Plan 6.4 found `#6E6E73`
  drew 111/145/131 phantom hits off text antialiasing ramps. Count a colour inside
  a box you predicted, not across the image.
- **Fail open (§2.3).** A crashed or absent island must never hang a terminal, and
  nothing this page adds may block the event path. **Asking for a permission
  without its usage description `abort()`s the process** — that is not theory,
  Plan 6.2 shipped it and `swift run vibecat` died on launch for a whole plan
  because no test runs `main.swift`. Any new permission needs its key in
  `Scripts/build-app.sh`'s `Info.plist` **and** a guard for the bare binary, in the
  shape `FocusStatusQuietHours.hasUsageDescription` establishes.
- **Measure with `getrusage(RUSAGE_SELF)`. Never `ps %cpu`.**
- Zero warnings in debug **and** `-c release`. `aLapsedQuestionClosesTheDrawer` is
  a known ~1-in-4 flake — re-run, do not chase. **If a test you add makes another
  test flake, the load is yours**: Plan 6.4's fix round added 2.2 s and broke
  `PipelineTests` 1-in-3, and fixed its own load rather than the other test's
  budget.
- Commit subjects state the insight. Trailer
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Never `git push`.** Ask, every time.

---

## What the page actually contains

Three groups, from `settings.html:323-378`:

**`Alert me when an agent`** — four switches: `Needs an answer` (on), `Finishes`
(on), `Fails` (on), and `Stalls for 5 minutes` (off, marked `new`) with the
sub-label *"Nothing has happened in the session and no question is pending."*

**`Sound`** (marked `new`) — a pack `.sel`; three per-cue rows each with a `.sel`
and a **`Play`** `.btn` (`Needs an answer` → *"G5–C6–E6 rising, held on C6"*;
`Finished` → *"Major arpeggio over two octaves, held at the top"*; `Failed` →
*"Falling minor thirds on a saw, sagging at the end"*); a volume `range` at **60**;
and `Stay quiet during Do Not Disturb` (on).

**`Elsewhere`** — `Also post a system notification` (off) with *"Reaches you when
the island is on another Space or a fullscreen app is in front."*; then
`Notification permission` and `Automation permission` rows, each a `.pill` plus a
`System Settings…` `.btn`.

## The four written decisions

1. **`Soft`, `System`, `Blip` and `Buzz` are not implemented, and the pickers must
   not offer them.** Plan 6.2's written decision 3 established that nothing in this
   repo defines what they sound like — no frequencies, no waveforms, nothing.
   Offering a menu item that silently does nothing is worse than a shorter menu.
   The pack picker offers **Chiptune** and **Silent**; each per-cue picker offers
   its **default**, **Meow** (which exists) and **None**. `SoundPack` and this
   plan's `CueChoice` are both enums, so adding a case later is additive.
2. **`Automation permission` shows real status and never asks.** Nothing in the app
   uses Automation yet — jump is Plan 6 — so prompting would ask for a capability
   that does not exist. Read it with `AEDeterminePermissionToAutomateTarget` and
   `askUserIfNeeded: false`. §14 lists the row, so the row exists; it just tells the
   truth, including "not determined".
3. **A stall alerts once per stall, not every tick.** §14 gives no rule, and a
   detector that re-fires every 60 s while a session sits idle would be the loudest
   thing in the app. One alert per quiet period, re-armed by any event for that
   session.
4. **`Needs an answer` gates the sound, not the question.** Turning it off must not
   suppress the island's own amber state or the drawer — §4.2's worst-state-wins is
   about what the island reports and a switch on this page cannot silence a blocked
   agent. It gates the *cue* and the *notification*, nothing else.

## File Structure

| File | Responsibility |
|---|---|
| `Sources/VibeCatCore/Preferences.swift` | *(modify)* the new fields |
| `Sources/VibeCatCore/AlertPolicy.swift` | Which events alert, as data — in Core because `CueSelector` and the notifier both need it |
| `Sources/VibeCatCore/StallDetector.swift` | Pure: which sessions have gone quiet, given a store and a clock |
| `Sources/VibeCatUI/Settings/SettingsRow.swift` | `.row`, `.group`, `.lab`, `h2` — the primitives every remaining page needs |
| `Sources/VibeCatUI/Settings/SettingsControls.swift` | `.sel`, `.btn`, `.pill` |
| `Sources/VibeCatUI/Settings/NotificationsPane.swift` | The page |
| `Sources/VibeCatUI/Notifier.swift` | `UNUserNotificationCenter`, and permission status for both rows |

Modified: `Sources/VibeCatUI/Sound/CueSelector.swift` (takes a policy),
`Sources/VibeCatUI/AppModel.swift` (the stall timer), `Sources/VibeCatApp/main.swift`,
`Scripts/build-app.sh` (usage description if the notification path needs one).

---

## Task 1: The preferences this page writes

**Files:**
- Modify: `Sources/VibeCatCore/Preferences.swift`
- Create: `Sources/VibeCatCore/AlertPolicy.swift`
- Modify: `Sources/VibeCatCore/PreferenceStore.swift`
- Test: `Tests/VibeCatCoreTests/AlertPolicyTests.swift`, and extend
  `Tests/VibeCatCoreTests/PreferenceStoreTests.swift`

**Interfaces produced:**
```swift
public struct AlertPolicy: Sendable, Equatable {
    public var onNeedsAnswer: Bool   // true
    public var onFinish: Bool        // true
    public var onFail: Bool          // true
    public var onStall: Bool         // false — settings.html:335's aria-checked
    public init(onNeedsAnswer: Bool = true, onFinish: Bool = true,
                onFail: Bool = true, onStall: Bool = false)
    public func allows(_ cue: Cue) -> Bool     // see note below
}
public enum CueChoice: String, Sendable, CaseIterable { case standard, meow, none }
```
and on `Preferences`: `alerts: AlertPolicy`, `pack: SoundPack`,
`choiceForNeedsAnswer/Finish/Fail: CueChoice`, `postsSystemNotification: Bool` (false).

**`allows(_:)` cannot take a `Cue`** — `Cue` lives in `VibeCatUI` and `AlertPolicy`
is in Core, which cannot see it; the dependency direction is one-way and strict.
Take an event kind or a small Core-level enum instead. **Work out the right seam
and say what you chose** — if it means `AlertPolicy` keying on `VibeEvent.Kind`
plus a stall case, that is probably right, and `SoundPack`/`CueChoice` may have to
move to Core with it. **Report the move rather than making `VibeCatCore` import
`VibeCatUI`,** which would invert the architecture.

Persistence: extend the existing store. **`InMemoryPreferenceStore` does not clamp
and `UserDefaultsPreferenceStore` does**, which Plan 6.4 recorded as a latent trap
and left because the window's fallback depends on it. Do not let any new test
depend on which store it got.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import VibeCatCore

@Test func theAlertDefaultsAreThePrototypesOwnSwitchStates() {
    // settings.html:328-336: the first three are aria-checked="true", the stall
    // switch is "false". A stall alert on by default would make a quiet machine
    // noisy, which is the opposite of §6.1's rule that an idle machine looks idle.
    let p = AlertPolicy()
    #expect((p.onNeedsAnswer, p.onFinish, p.onFail) == (true, true, true))
    #expect(p.onStall == false)
}

@Test func eachSwitchGatesOnlyItsOwnEvent() {
    // The likeliest defect in this file: one guard copied four times with the
    // wrong field. A single-bit probe per switch is what catches it.
    var p = AlertPolicy()
    p.onFinish = false
    #expect(p.allows(.needsAnswer))
    #expect(!p.allows(.finished))
    #expect(p.allows(.failed))
}

@Test func aNewAlertFieldRoundTripsAndDefaultsWhenAbsent() {
    // `withFreshDefaults` is the real fixture, installed by Plan 6.4's fix round —
    // a fixed suite plus a per-test `keyPrefix`, cleaned up on the way out. Its
    // predecessor built a suite per test and leaked 175 plists into
    // `~/Library/Preferences`, because emptying a defaults domain is not cleaning
    // up after yourself: `cfprefsd` writes it back.
    withFreshDefaults { defaults, prefix in
        let store = UserDefaultsPreferenceStore(defaults: defaults, keyPrefix: prefix)
        #expect(store.load().alerts == AlertPolicy(), "an untouched store must give the prototype's states")
        var p = store.load()
        p.alerts.onStall = true
        p.postsSystemNotification = true
        store.save(p)
        #expect(store.load().alerts.onStall == true)
        #expect(store.load().postsSystemNotification == true)
        // And the fields this plan did not touch survived.
        #expect(store.load().volume == 0.60)
    }
}

@Test func anUnknownPackOrChoiceInThePlistFallsBackRatherThanCrashing() {
    // 6.2's decision 3: Soft/System/Blip do not exist. A plist naming one — or a
    // future build's key read by an older one — must not produce a nil enum.
    withFreshDefaults { defaults, prefix in
        defaults.set("soft", forKey: prefix + "pack")
        defaults.set("blip", forKey: prefix + "choiceForFail")
        let loaded = UserDefaultsPreferenceStore(defaults: defaults, keyPrefix: prefix).load()
        #expect(loaded.pack == .chiptune)
        #expect(loaded.choiceForFail == .standard)
    }
}
```

**Verified while writing this plan, not assumed:** the fixture is
`withFreshDefaults { defaults, prefix in … }` — a fixed shared suite plus a
per-test `keyPrefix`, cleaned up on exit — and `SessionKey(cli:session:)` has a
public memberwise init. An earlier draft of this task wrote `freshDefaults()` and
`prefix()` as bare calls and **neither exists**; that is the defect class that
reached implementers on all three preceding plans, so it was checked this time.

**There is no `store(_:at:)` or `session(_:_:)` helper in `Tests/VibeCatCoreTests/`** —
Task 5's snippets below use both. `Tests/VibeCatUITests/CueSelectorTests.swift` has
equivalents; either lift them or write local ones, and say which.

- [ ] **Step 2–4: Fail, implement, pass, then mutation-verify**

1. Default `onStall` to `true` → `theAlertDefaultsAreThePrototypesOwnSwitchStates` fails.
2. Make `allows` read `onFinish` for every case → `eachSwitchGatesOnlyItsOwnEvent` fails.
3. Drop the new keys from `save` → `aNewAlertFieldRoundTripsAndDefaultsWhenAbsent` fails.
4. Use `SoundPack(rawValue:)!` instead of a fallback →
   `anUnknownPackOrChoiceInThePlistFallsBackRatherThanCrashing` **crashes** rather
   than failing. Note that in the report: a crash is a pass for this mutation, and
   is the reason the fallback exists.
5. Read `volume`'s key for `postsSystemNotification` → the round-trip test fails on
   the untouched-field assertion.

- [ ] **Step 5: Full suite, then commit**

---

## Task 2: The row primitives every remaining page needs

**Files:**
- Create: `Sources/VibeCatUI/Settings/SettingsRow.swift`
- Test: `Tests/VibeCatUITests/SettingsRowTests.swift`

**Interfaces produced:**
```swift
public struct SettingsGroup<Content: View>: View { public init(@ViewBuilder content: () -> Content) }
public struct SettingsRow<Control: View>: View {
    public init(_ title: String, detail: String? = nil, isNew: Bool = false,
                @ViewBuilder control: () -> Control)
}
public struct SettingsSectionHeading: View { public init(_ text: String, isNew: Bool = false) }
```

Transcribe from `settings.html`, and **derive nothing from what looks right**:

| Element | Line | Values |
|---|---|---|
| `.group` | 73 | `--card` `#2A2A2D`, radius `10`, `margin-bottom:18` |
| `.row` | 74 | `padding:11px 14px`, `gap:14`, `inset 0 1px 0 var(--line)` top hairline |
| `.lab` | 76 | `flex:1`, `min-width:190px` |
| `.lab b` | 77 | `13px`, weight `400`, `letter-spacing:-.01em` |
| `.lab > span` | 79 | `11.5px`, `--haze`, `padding-top:3`, `line-height:1.45` |
| `.ctlarea` | 80 | `flex:none`, `gap:8` |
| `h2` | 72 | `12px`, weight `600`, `--bone`, `padding:0 2px 8px`, `letter-spacing:-.01em` |
| `.new` | 82 | `9.5px`, `letter-spacing:.06em`, uppercase, colour `--idle` |

Two traps, both from Plan 6.4:

- **`SettingsPalette.hairline` is opaque white**; `RGBA` has no alpha. The
  prototype's `--line` is `rgba(255,255,255,.08)`. Apply
  `SettingsPalette.hairlineOpacity` — 6.4's fix round added it precisely so the
  number is one fact — and **assert the blended result derived from the rule**, not
  the token against itself, which 6.4 found was passing at `0.30`.
- **`line-height:1.45` at `11.5px` is not `lineSpacing(1.45)`.** 6.4 measured that
  the system font's own line height at `11.5pt` is `14pt`, so matching CSS's
  `16.675pt` pitch takes `lineSpacing` of about `2.7`, and CSS's half-leading pads
  *outside* the first and last line where SwiftUI's does not. **Measure it; do not
  convert it arithmetically and hope.** Report the number and how you got it.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func aRowWithADetailIsTallerThanOneWithout() throws {
    // Two renders differing in exactly one input. Not a pixel count — a measured
    // height, because "more ink" is exactly the premise that was false in 6.4.
    let bare = try Raster.measureHeight(SettingsRow("Fails") { EmptyView() }, width: 500)
    let full = try Raster.measureHeight(SettingsRow("Stalls for 5 minutes",
                                                   detail: "Nothing has happened in the session and no question is pending.")
                                        { EmptyView() }, width: 500)
    #expect(full > bare + 10, "the detail line adds nothing: \(bare) vs \(full)")
}

@Test func theNewBadgeIsGreenAndOnlyAppearsWhenAsked() throws {
    // `.new` is --idle green, which is the one state colour that legitimately
    // appears in this sheet. Count it inside the row's own box, never across the
    // whole render — 6.4 found a mid-grey drew 111 phantom hits off text
    // antialiasing.
    let plain = try Raster.rasterise(SettingsRow("Sound") { EmptyView() }, size: CGSize(width: 300, height: 44))
    let badged = try Raster.rasterise(SettingsRow("Sound", isNew: true) { EmptyView() }, size: CGSize(width: 300, height: 44))
    let green = Raster.Pixel(RGBA(hex: "#3FD99B")!)
    #expect(badged.pixelCount(near: green, tolerance: 8) > 0)
    #expect(plain.pixelCount(near: green, tolerance: 8) == 0)
}

@Test func aRowsTopHairlineIsTheBlendOfTheProtoypesEightPercent() throws {
    // Derived from settings.html:14's rgba(255,255,255,.08) over --card #2A2A2D,
    // not from our own token. If someone drops the opacity this fails; 6.4 found
    // the token-against-itself version passing at 0.30.
    let card = RGBA(hex: "#2A2A2D")!
    let blend = RGBA(r: card.r + (1 - card.r) * 0.08,
                     g: card.g + (1 - card.g) * 0.08,
                     b: card.b + (1 - card.b) * 0.08)
    let row = try Raster.rasterise(SettingsGroup { SettingsRow("Fails") { EmptyView() } },
                                   size: CGSize(width: 300, height: 60))
    #expect(row.pixelCount(near: Raster.Pixel(blend), tolerance: 3) > 0,
            "no hairline at the prototype's 8%")
}
```

`Raster.measureHeight` may not exist. **Read `Tests/VibeCatUITests/Raster.swift`
and use what is there** — Plan 6.4 found `contains(_:tolerance:)` absent and used
`pixelCount(near:tolerance:)`, and added `fullyOpaquePixelCount` after
premultiplied-alpha antialiasing gave false positives. Say what you used.

- [ ] **Step 2–4: Fail, implement, pass, mutation-verify**

1. Ignore `detail` → the height test fails.
2. Draw the `new` badge unconditionally → the badge test's `plain` assertion fails.
3. Tint the badge from `SettingsPalette.systemBlue` → the badge test fails.
4. Drop the hairline's opacity → the blend test fails.
5. Change `.row` padding from `11` to `14` → **predicted uncaught.** Nothing here
   pins padding. Report it, and say whether a derived-geometry assertion is worth
   adding or whether Task 7's browser diff is the right place for it.

- [ ] **Step 5: Full suite twice, then commit**

---

## Task 3: The select, the button and the permission pill

**Files:**
- Create: `Sources/VibeCatUI/Settings/SettingsControls.swift`
- Test: `Tests/VibeCatUITests/SettingsControlsTests.swift`

**Interfaces produced:**
```swift
public struct SettingsSelect<Value: Hashable & CaseIterable>: View {
    public init(_ selection: Binding<Value>, label: (Value) -> String)
}
public struct SettingsButton: View { public init(_ title: String, action: @escaping () -> Void) }
public enum PermissionState: Sendable, Equatable { case granted, denied, notDetermined }
public struct SettingsPill: View { public init(_ state: PermissionState) }
```

From the prototype: `.sel` (line 106) `13px`, `--bone` on `--card2` `#323236`,
radius `7`, padding `5px 9px`. `.btn` (111) `12.5px`, same fill, radius `7`,
padding `6px 12px`, hover `#3E3E44`. `.pill` (119) `11.5px`, `gap:5`,
`.ok` → `--idle`, `.warn` → `--waiting`, `.dot` a `13px` circle of `currentColor`
holding a `9px` glyph in `#111`.

**The pill's colour is the assertion that matters.** A permission row that says
"Granted" in amber, or "Denied" in green, is a lie about a security state — and it
is the kind of wiring error a property read cannot see. `notDetermined` is neither
`ok` nor `warn` in the prototype, which only shows those two: **decide what it
looks like and record the decision.**

- [ ] **Step 1: Write the failing tests**

```swift
@Test func aGrantedPillIsGreenAndADeniedPillIsAmber() throws {
    let size = CGSize(width: 120, height: 24)
    let ok = try Raster.rasterise(SettingsPill(.granted), size: size)
    let no = try Raster.rasterise(SettingsPill(.denied), size: size)
    let idle = Raster.Pixel(RGBA(hex: "#3FD99B")!), waiting = Raster.Pixel(RGBA(hex: "#FFA63C")!)
    #expect(ok.pixelCount(near: idle, tolerance: 8) > 0 && ok.pixelCount(near: waiting, tolerance: 8) == 0)
    #expect(no.pixelCount(near: waiting, tolerance: 8) > 0 && no.pixelCount(near: idle, tolerance: 8) == 0)
}

@Test func aSelectShowsTheCurrentValueAndNotTheFirstOne() throws {
    // The defect this catches: a picker rendering `allCases.first` regardless of
    // its binding, which looks perfect until you change it.
    let a = try Raster.rasterise(SettingsSelect(.constant(CueChoice.standard)) { "\($0)" },
                                 size: CGSize(width: 140, height: 28))
    let b = try Raster.rasterise(SettingsSelect(.constant(CueChoice.meow)) { "\($0)" },
                                 size: CGSize(width: 140, height: 28))
    #expect(a != b, "the select ignores its binding")
}

@Test func aButtonCallsItsActionExactlyOnce() {
    var calls = 0
    SettingsButton("System Settings…") { calls += 1 }.actionForTesting()
    #expect(calls == 1)
}
```

**Note the honest limit on the second test**, which Plan 6.4 hit three times
independently: `a != b` proves the binding is *read*, not that the right label is
shown, and **nothing headless can prove which closure a `Button` was bound to** —
no ViewInspector, and the project will not add one. Say so rather than implying
more coverage than exists. If you can assert the rendered *text* rather than mere
difference, do — that is strictly better and is what 6.4's sidebar fix did.

- [ ] **Step 2–5: Fail, implement, pass, mutation-verify, full suite twice, commit**

Mutations: swap the pill's two colours (both pill assertions must fail); render
`allCases.first` in the select (the select test must fail); make the pill ignore
its state entirely (both must fail).

---

## Task 4: Per-event gating, in the one place a cue is decided

**Files:**
- Modify: `Sources/VibeCatUI/Sound/CueSelector.swift`
- Modify: `Sources/VibeCatUI/AppModel.swift`
- Test: extend `Tests/VibeCatUITests/CueSelectorTests.swift`

`CueSelector.cue(for:before:after:)` is Plan 6.2's pure trigger rule and is the
only place a cue is decided. Add the policy there rather than filtering afterwards:
a second filter downstream would be a second place to forget.

**Read `Sources/VibeCatUI/Sound/CueSelector.swift` first.** Two facts from 6.2 that
this task must not break:
- **`done` comes off the event, not from a state comparison.** `SessionState` has
  no `done` case and `init(kind:)` folds `.done` into `.idle`, so by the time
  `after` exists nothing remembers a run finished.
- **A cue fires only when demand *rises*.** `askMulti → ask` is silent, because
  answering one of two questions is not news. That is 6.2's written decision 2.

**Written decision 4 of this plan binds here:** turning `Needs an answer` off gates
the *cue*, never the island's amber state or the drawer. §4.2's worst-state-wins is
about what the island reports.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func turningOffAnAlertSilencesOnlyThatCue() {
    var policy = AlertPolicy(); policy.onFinish = false
    let before = store([session("a", .running)])
    let after  = store([session("a", .done)])
    #expect(CueSelector.cue(for: session("a", .done), before: before, after: after, policy: policy) == nil)
    // …and the others still sound.
    let asking = store([session("a", .permission)])
    #expect(CueSelector.cue(for: session("a", .permission), before: before, after: asking, policy: policy) == .ask)
}

@Test func silencingAnAlertDoesNotChangeWhatTheIslandReports() {
    // Written decision 4, and the invariant it protects. A switch on a settings
    // page cannot hide a blocked agent — §4.2 is about what the island reports.
    var policy = AlertPolicy(); policy.onNeedsAnswer = false
    let after = store([session("a", .permission)])
    #expect(CueSelector.cue(for: session("a", .permission),
                            before: SessionStore(), after: after, policy: policy) == nil)
    #expect(IslandState(store: after) == .waiting, "the island must still say waiting")
    #expect(after.counts[.waiting] == 1)
}

@Test func theDefaultPolicyChangesNothingAboutPlan62sBehaviour() {
    // Every one of 6.2's eleven CueSelector tests must still hold with a default
    // policy. This is the regression guard for adding a parameter to a pure
    // function eleven tests already pin.
    let before = store([session("a", .permission)])
    let after  = store([session("a", .permission), session("b", .question)])
    #expect(CueSelector.cue(for: session("b", .question), before: before, after: after,
                            policy: AlertPolicy()) == .askMulti)
}
```

If you give `policy:` a default value, 6.2's existing eleven tests keep compiling —
**decide whether that is right.** A default makes the change invisible at every
call site, which is convenient and is also how a caller forgets to pass the user's
real policy. Say which you chose and why.

- [ ] **Step 2–5: Fail, implement, pass, mutation-verify, full suite twice, commit**

Mutations: gate `.done` on `onNeedsAnswer` (the first test fails); apply the policy
*before* the `.done` branch so a silenced finish also silences everything after it;
have `AppModel` pass `AlertPolicy()` instead of the user's stored one — **that last
one is the important mutation**, because it is the failure that leaves the whole
page decorative, and if no test catches it, say so.

---

## Task 5: Stall detection

**Files:**
- Create: `Sources/VibeCatCore/StallDetector.swift`
- Modify: `Sources/VibeCatUI/AppModel.swift`
- Test: `Tests/VibeCatCoreTests/StallDetectorTests.swift`

**Interfaces produced:**
```swift
public struct StallDetector: Sendable {
    public static let threshold: TimeInterval = 5 * 60   // settings.html:334
    public static func stalled(in store: SessionStore, now: Date,
                               alreadyReported: Set<SessionKey>) -> Set<SessionKey>
}
```

The prototype's sub-label is the specification: *"Nothing has happened in the
session and no question is pending."* So a session stalls when
`now - updatedAt >= 5 minutes` **and** it is not `waiting`. A session blocked on a
question is not stalled — it is blocked, and the island already says so in amber.

Make it **pure**, taking `now` and the set already reported. `AppModel` owns the
timer and the set. Three reasons, all from this repo's history: a pure function is
testable without waiting five minutes; `AppModel.prune` already runs a 60 s timer
that this can ride rather than adding a second one; and **`@Observable` notifies on
the write, not on the change** — `prune` only notifies when a prune removed
something, and a stall tick that notifies every 60 s would re-render the island
forever, in the state §6.1 says must look idle and cost nothing.

**Written decision 3:** one alert per quiet period. The `alreadyReported` set is
how, and any event for that session must clear its entry.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func aSessionQuietForFiveMinutesStalls() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let s = store([session("a", .running)], at: t0)
    #expect(StallDetector.stalled(in: s, now: t0.addingTimeInterval(299), alreadyReported: []).isEmpty)
    #expect(StallDetector.stalled(in: s, now: t0.addingTimeInterval(300), alreadyReported: [])
            == [SessionKey(cli: "claude-code", session: "a")])
}

@Test func aSessionWaitingOnAQuestionIsBlockedRatherThanStalled() {
    // The prototype's own sub-label: "and no question is pending". The island is
    // already amber for this session; a stall alert would be a second, duller
    // way of saying the same thing.
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let s = store([session("a", .permission)], at: t0)
    #expect(StallDetector.stalled(in: s, now: t0.addingTimeInterval(3600), alreadyReported: []).isEmpty)
}

@Test func aStallIsReportedOnceAndNotEveryTick() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let s = store([session("a", .running)], at: t0)
    let key = SessionKey(cli: "claude-code", session: "a")
    #expect(StallDetector.stalled(in: s, now: t0.addingTimeInterval(600), alreadyReported: [key]).isEmpty)
}

@Test func aFailedSessionDoesNotAlsoStall() {
    // A failed run has already stopped, and §4.2 says so explicitly. Alerting
    // twice for one event is the defect.
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let s = store([session("a", .failed)], at: t0)
    #expect(StallDetector.stalled(in: s, now: t0.addingTimeInterval(3600), alreadyReported: []).isEmpty)
}

@Test func theThresholdIsTheProtoypesFiveMinutes() {
    #expect(StallDetector.threshold == 300)
}
```

- [ ] **Step 2–5: Fail, implement, pass, mutation-verify, full suite three times, commit**

Three runs: this adds a timer, and **a test that only fails under full-suite load
is a real bug in thread discipline, not a flake.** Read `AppModel.swift:100-114`
before writing any threaded test — `DispatchQueue.main.sync` from a `Task.detached`
deadlocks under full-suite load, reproduced with an empty `sync {}` body.

Mutations: drop the `waiting` exclusion; drop the `alreadyReported` check; use `>`
instead of `>=` at exactly 300; set the threshold to 60. Also: **make the stall
tick notify unconditionally and measure the idle cost with `getrusage`** — report
the number, because §6.1 says an idle machine must cost nothing and this is the
first thing in the app that could quietly break that.

---

## Task 6: The Sound subsection, wired to the engine that already exists

**Files:**
- Create: `Sources/VibeCatUI/Settings/NotificationsPane.swift` (the Sound group)
- Modify: `Sources/VibeCatApp/main.swift`
- Test: `Tests/VibeCatUITests/SoundSectionTests.swift`

The rows, from `settings.html:339-361`: pack; three per-cue rows each with a
picker and a **Play**; volume; DND.

**Everything behind these already exists.** `SoundPlayer.play(_:)` and `.settings`
are public; `Preferences.volume` and `.quietDuringDoNotDisturb` are persisted *and*
read as of 6.4's fix round. So this task is wiring and appearance — with two real
hazards:

1. **Changing the volume re-renders every cue: measured 859 ms.** 6.4's fix round
   narrowed the cache key so *mute* is free, but volume is genuinely part of the
   render. **A slider that renders on every drag frame is unusable.** Debounce,
   commit on release, or scale at playback instead of at render — decide, implement,
   and **measure with `getrusage`, never `ps %cpu`.** Report before and after.
2. **`Play` must not be the only thing that works.** A Play button that plays while
   the real event path is silenced by a policy bug would hide exactly the defect
   Task 4's last mutation describes. Play deliberately bypasses the policy — a
   preview is a preview — so **say so in the source**, or the next reader will read
   it as proof the pipeline works.

Per written decision 1 the pickers offer only what exists: pack **Chiptune** /
**Silent**; each cue **its default** / **Meow** / **None**.

- [ ] Write the failing tests: that each picker writes its own field and not
      another's; that the volume slider's committed value reaches `Preferences`
      clamped; that `None` makes that cue render nothing while the others still
      render; and that `Play` calls the player for the row's own cue.
- [ ] Implement, pass, and mutation-verify each of those by pointing one control at
      the wrong field — the copy-paste defect this section is most exposed to, with
      six near-identical rows.
- [ ] **Measure the slider.** Report `getrusage` before and after your fix.
- [ ] Full suite twice, commit.

---

## Task 7: `Elsewhere`, the assembled page, and the browser diff

**Files:**
- Create: `Sources/VibeCatUI/Notifier.swift`
- Modify: `Sources/VibeCatUI/Settings/NotificationsPane.swift`, `main.swift`,
  `Scripts/build-app.sh`
- Test: `Tests/VibeCatUITests/NotifierTests.swift`,
  `Tests/VibeCatUITests/NotificationsPaneTests.swift`

**Interfaces produced:**
```swift
@MainActor public final class Notifier {
    public init()
    public var notificationPermission: PermissionState { get }
    public var automationPermission: PermissionState { get }
    public func requestAuthorizationIfNeeded()
    public func post(title: String, body: String)
}
```

**Asking for a permission without its usage description `abort()`s the process.**
Plan 6.2 shipped exactly that and `swift run vibecat` died on launch for a whole
plan, invisible to 509 green tests because no test runs `main.swift`. So:
`UNUserNotificationCenter` needs whatever key it needs in `Scripts/build-app.sh`'s
`Info.plist` **and** a bare-binary guard in the shape
`FocusStatusQuietHours.hasUsageDescription` establishes — and the test that catches
it **calls** the guarded method, so removing the guard takes the run down rather
than failing an assertion. Copy that pattern; it is in
`Tests/VibeCatUITests/QuietHoursTests.swift`.

**Written decision 2:** `automationPermission` reads with
`AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: false)` and **never
prompts.** Nothing uses Automation until jump ships.

- [ ] Build `Notifier`, with the guard and the abort-catching test.
- [ ] Build the `Elsewhere` group: the switch, and the two permission rows using
      Task 3's pill and button. `System Settings…` opens the right pane via
      `NSWorkspace.shared.open` with the appropriate `x-apple.systempreferences:`
      URL — **verify the URL actually opens the right pane on this OS** and report
      what you observed, rather than trusting a string.
- [ ] Assemble all three groups into the pane, replace 6.4's owner-note placeholder
      for `notifications`, and confirm the other three panes still announce theirs.
- [ ] **The browser diff.** Open `settings.html` in a real browser. Use
      `getBoundingClientRect` and `getComputedStyle` on every element of the
      Notifications page and compare against your rasterised renders — this is what
      Plan 6.4 did and it found two real bugs no assertion would have caught
      (`.continuous` corners where every CSS radius is circular, and a
      doubly-flexible `Rectangle` that dragged a 500pt card with it). **Report which
      elements you compared and every difference you found.**
- [ ] Launch **both** the bare binary and the signed bundle. Confirm the hook still
      exits `0` — §2.3. **You cannot hear**; Plan 6.2's four audible items stay
      open, and do not claim otherwise.
- [ ] Full suite three times, zero warnings in debug and release, commit.

---

## Out of scope, deliberately

- **`Soft`, `System`, `Blip`, `Buzz`** — written decision 1. No values exist.
- **The General, Integrations and Display pages** — 6.6 and 6.7. Their panes keep
  their owner notes.
- **Jump itself** — Plan 6. This page shows Automation's status and never asks.
- **The four audible checks** Plan 6.2 left open. This plan cannot close them.
- **A `prototype-fidelity` pass over the drawer**, which 6.4 recommended because
  `PanelBar` moved the footer. Worth doing, not this plan's.

## Self-review

**§14's Notifications section, row by row.** All four alert switches → Tasks 1 and
4. Sound pack, three per-cue pickers with Play, volume, DND → Task 6. System
notification and both permission rows → Task 7. **Nothing in the section is
unaccounted for**, and the two things it names that cannot be honoured —
unspecified packs, and Automation before jump — are written decisions 1 and 2
rather than silent omissions.

**Placeholders.** None. Tasks 6 and 7 give their steps as prose with named
hazards, measurements and mutations rather than full code blocks, because both are
assembly of primitives Tasks 1–3 define with exact values — the values live where
they are declared, and repeating them in a sixth place is how they drift.

**Type consistency.** `AlertPolicy`, `CueChoice`, `PermissionState`,
`SettingsGroup`, `SettingsRow`, `SettingsSectionHeading`, `SettingsSelect`,
`SettingsButton`, `SettingsPill`, `StallDetector`, `Notifier` — each defined once
and used with that spelling later. `PermissionState` is declared in Task 3 with the
pill that renders it and consumed by Task 7's `Notifier`, which is the direction
that keeps `Notifier` free of view concerns.

**Two things handed over rather than guessed.**
1. **`AlertPolicy.allows` cannot take a `Cue`** — `Cue` is in `VibeCatUI` and
   `AlertPolicy` must be in Core for the notifier to share it. Task 1 says to find
   the seam and report it, possibly moving `SoundPack`/`CueChoice` to Core.
   **Making Core import VibeCatUI would invert the architecture and is not an
   option.**
2. **Task 2's mutation 5 is predicted uncaught** — nothing pins `.row`'s padding.
   Said plainly, with the question of whether that belongs in a derived assertion
   or in Task 7's browser diff left to whoever finds out.

**And one prediction I am deliberately recording as likely wrong.** Task 4's last
mutation — `AppModel` passing a default `AlertPolicy()` instead of the user's
stored one — is the failure that would leave this entire page decorative, and I do
not currently see which test catches it. Plan 6.4 had exactly this shape three
times (`volume` and `quietDuringDoNotDisturb` persisted and never read, and
`selectedPage` never saved), and **all three shipped through six task reviews.** If
no test catches it, that is the finding, and it needs one.
