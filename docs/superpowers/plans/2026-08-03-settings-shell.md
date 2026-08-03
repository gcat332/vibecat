# Settings Shell Implementation Plan (Plan 6.4, §14)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Settings window you can actually open from the island, with real
persisted preferences, and the panel footer that opens it — one of whose two
buttons does something end to end.

**Architecture:** A `Preferences` value type persisted through `UserDefaults` and
clamped on read, because Plan 6.4's own successors will write to those keys and
anything can be in a plist. The window is a plain `NSWindow` hosting SwiftUI,
owned by a controller that guarantees one instance — an `LSUIElement` app has no
Dock icon and no menu bar, so nothing reopens a window for us. The four pages get
their chrome and their sidebar; their *controls* are later plans'.

**Tech Stack:** Swift 6, SwiftUI in an `NSWindow` via `NSHostingView`,
`UserDefaults`. All system frameworks — **no package may be added.**

## Global Constraints

- **No external dependencies.** Swift 6, macOS 14 floor.
- **The prototype is the authority on appearance; the spec is the authority on
  rules.** For this plan the prototype is
  [`docs/superpowers/prototypes/settings.html`](../prototypes/settings.html) —
  **640 lines, and no plan in this project's history has ever diffed it.** §14 is
  four lines of prose summarising 22 subsections and roughly 47 controls. The
  panel footer's own reference is
  [`island-motion.html`](../prototypes/island-motion.html) **lines 516–530**
  (`.panelbar`, `#pmute`, `#pgear`).
- **Settings has its own palette, and it is not the island's.** This is the single
  most likely thing to get wrong — see "The palette collision" below. `--accent`
  means **system blue** here and **the current state colour** in the island.
- **A divergence from the prototype is either a fix or a written decision, never
  a silent third thing.**
- **`swift-testing` only** (`import Testing`, `@Test`, `#expect`), never XCTest.
- **A test that cannot fail is not a test.** Name what would have to break before
  writing an assertion. Mutation-verify everything and report before/after.
  Executing Plan 6.2 found **five tests that could not fail**, three of them in
  the plan's own hand-written assertions — assume this plan contains some too, and
  **report a mutation that stays green rather than adjusting the test.** Every
  time that was done on 6.2 it found a real defect.
- **A mutation list in this plan is a prediction.** Three of Plan 6.2's were
  wrong. If yours disagrees, report it; do not bend the code to match.
- **`ImageRenderer` cannot render a `ScrollView`** and **`--filter` is not a
  trustworthy mode, only a quieter one.** Use the `NSHostingView` +
  `cacheDisplay(in:to:)` helper in `Tests/VibeCatUITests/Raster.swift` for
  anything that scrolls, and prove new golden assertions over repeated *full*
  suite runs.
- **Anything with a lifecycle tears itself down.** `AppModel` and `HoverMonitor`
  both use `isolated deinit` because `RunLoop.main` holds a `Timer` strongly. A
  window controller holding a window is the same shape of problem.
- **`@Observable` notifies on the write, not on the change** — and a *mutating*
  call goes through `_modify`, which notifies **unconditionally** even when
  nothing changed. Guard writes.
- **Never truncate away the thing being decided**, and **the control carries the
  meaning, not a label** (§10.2).
- **Reduced motion is a real path.** Everything animated goes through
  `MotionPreference.resolve`.
- Zero compiler warnings. `aLapsedQuestionClosesTheDrawer` is a known ~1-in-4
  flake — re-run, do not chase.
- Commit subjects state the insight. Trailer
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Never `git push`.** Ask, every time.

---

## Why this plan is the shell and not §14

`settings.html` is **four pages, 22 subsections, 28 switches, 8 buttons, 7
sliders, 7 selects and 5 segmented controls** — counted, not estimated. Per page:
General 12 controls, Notifications 11, Display 21, Integrations 3 plus a CLI list
with per-source install status and an "Add CLI" branch.

That is four plans. And **no page is reachable until something can open a
window**, so the split is forced rather than chosen:

| Plan | Owns |
|---|---|
| **6.4 (this one)** | `Preferences` and its persistence · the window, titlebar and sidebar · the four panes' chrome · the panel footer · **mute, wired end to end** |
| 6.5 | The Notifications page — which is where Plan 6.2's `SoundSettings` finally gets its sheet, its per-cue pickers, its volume slider and a trigger for `meow` |
| 6.6 | The Display page — the biggest, and the one that re-threads `SessionRow.Options`, picks the list's overflow cue, settles §6.3's per-face width, and ships the motion control that makes `IslandBody.phase`'s `MotionPreference` bypass visible |
| 6.7 | General and Integrations |

**Mute is in this plan on purpose.** A plan that ships an empty window has not
shipped working software. Mute is one preference, it is in the footer this plan
builds anyway, and the island prototype states the coupling explicitly at
`island-motion.html:1060`: *"the panel's mute button and the app's sound toggle
are the same setting"*. So it closes a loop Plan 6.2 deliberately left open —
`SoundSettings` had no persistence — and it gives the window's first page
something true to show later.

## The palette collision — read this before writing any colour

`settings.html`'s tokens are **not** the island's, and one name means two
different things:

| Token | Settings (`settings.html:9-27`) | The island |
|---|---|---|
| `--bg` | `#1C1C1E` | — (the island's ground is `#07080A`) |
| `--chrome` | `#232326` | — |
| `--pane` | `#161618` | — |
| `--card` | `#2A2A2D` | — |
| `--line` | `rgba(255,255,255,.08)` | — |
| `--bone` | `#F2F2F5` | `#E8EDF5`-ish, a different value |
| `--haze` | `#9A9AA2` | a different value |
| `--dim` | `#6A6A74` | **`#5A6273`** — different |
| `--blue` | `#0A84FF` | not present |
| **`--accent`** | **`var(--blue)`, always** | **the current state's colour** |

**That last row is the trap.** In the island, §4.3's rule is that colour means
state and only state, and `--accent` is how it says so. In Settings, `--accent` is
macOS system blue and carries no state meaning at all — a switch is blue because
it is on, not because anything is running. Reaching for `IslandState.accent` in a
Settings view would tint a checkbox amber because an agent somewhere is blocked.

So: **declare a separate token set.** Do not extend the island's, do not import
it, and do not name the new one `accent` if that invites the confusion.

The four state hues **do** appear in `settings.html` (`--idle:#3FD99B`,
`--running:#5B9DF9`, `--waiting:#FFA63C`, `--error:#FF5C5C`) and are identical to
the island's — they are used for previews of the island, which is the one place
state colour belongs in a settings sheet.

## File Structure

| File | Responsibility |
|---|---|
| `Sources/VibeCatCore/Preferences.swift` | The persisted values and their defaults. In Core because it is data, has no UI, and both the app and later adapters will read it |
| `Sources/VibeCatCore/PreferenceStore.swift` | `UserDefaults` reading and writing, clamped |
| `Sources/VibeCatUI/Settings/SettingsPalette.swift` | The token set above, separate from the island's on purpose |
| `Sources/VibeCatUI/Settings/SettingsSwitch.swift` | The control used 28 times, after a measured decision about the native one |
| `Sources/VibeCatUI/Settings/SettingsPage.swift` | The four pages: key, label, chip colour, icon |
| `Sources/VibeCatUI/Settings/SettingsSidebar.swift` | The 196pt nav |
| `Sources/VibeCatUI/Settings/SettingsWindow.swift` | The `NSWindow` and its single-instance controller |
| `Sources/VibeCatUI/Drawer/PanelBar.swift` | The footer's two buttons, in the 44pt `DrawerView` already reserves |

Modified: `Sources/VibeCatUI/Drawer/DrawerView.swift` (the reserved footer stops
being `Color.clear`), and wherever the app is wired (`Sources/VibeCatApp/main.swift`).

---

## Task 1: Preferences, persisted and clamped

**Files:**
- Create: `Sources/VibeCatCore/Preferences.swift`
- Create: `Sources/VibeCatCore/PreferenceStore.swift`
- Test: `Tests/VibeCatCoreTests/PreferenceStoreTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  ```swift
  public struct Preferences: Sendable, Equatable {
      public var soundEnabled: Bool          // true
      public var volume: Double              // 0.60 — settings.html:358's slider
      public var quietDuringDoNotDisturb: Bool // true — settings.html:359
      public var selectedPage: String        // "general" — settings.html:210's data-active
      public init(soundEnabled: Bool = true, volume: Double = 0.60,
                  quietDuringDoNotDisturb: Bool = true, selectedPage: String = "general")
  }
  public protocol PreferenceStoring: Sendable {
      func load() -> Preferences
      func save(_ preferences: Preferences)
  }
  public struct UserDefaultsPreferenceStore: PreferenceStoring {
      public init(defaults: UserDefaults = .standard, keyPrefix: String = "vibecat.")
  }
  public struct InMemoryPreferenceStore: PreferenceStoring { public init(_ initial: Preferences = Preferences()) }
  ```

Only four values, deliberately. §14 has roughly 47 controls and **this plan owns
none of them except mute**; adding the other 43 keys now would be inventing
defaults for behaviour that does not exist, and every one would be untested
surface. `selectedPage` is here because the window has to reopen where you left it.

**Clamping is not defensive padding, it is the boundary.** Plans 6.5–6.7 will
write these keys, and a `UserDefaults` plist is a file any process running as this
user can edit. Plan 6.2 already had to clamp `volume` at two entry points for
exactly this reason, and this project's fail-open invariant has a precedent: any
interval that becomes a deadline goes through one clamp, because an absurd value
saturates a `DispatchTime` into `.distantFuture` and parks a thread forever. A
volume of `NaN` reaching an `AVAudioEngine` gain is the same class of thing.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import VibeCatCore

// MARK: - defaults

@Test func anEmptyStoreReturnsThePrototypesOwnDefaults() {
    // Every one of these is a value read off settings.html, not a preference of
    // ours: the volume slider's value="60", the DND switch's aria-checked="true",
    // and the General pane's data-active="true".
    let prefs = UserDefaultsPreferenceStore(defaults: freshDefaults()).load()
    #expect(prefs.soundEnabled == true)
    #expect(prefs.volume == 0.60)
    #expect(prefs.quietDuringDoNotDisturb == true)
    #expect(prefs.selectedPage == "general")
}

// MARK: - round trip

@Test func everyFieldSurvivesASaveAndReload() {
    // One store, two operations. If a field is missing from either the write or
    // the read, exactly that field comes back as its default — so this fails
    // field by field rather than all at once.
    let defaults = freshDefaults()
    let store = UserDefaultsPreferenceStore(defaults: defaults)
    let written = Preferences(soundEnabled: false, volume: 0.15,
                              quietDuringDoNotDisturb: false, selectedPage: "display")
    store.save(written)
    #expect(store.load() == written)
}

@Test func savingOneFieldDoesNotResetTheOthers() {
    let defaults = freshDefaults()
    let store = UserDefaultsPreferenceStore(defaults: defaults)
    store.save(Preferences(volume: 0.9))
    var next = store.load()
    next.soundEnabled = false
    store.save(next)
    #expect(store.load().volume == 0.9, "the second save dropped the first's volume")
}

// MARK: - the boundary

@Test func anAbsurdVolumeInThePlistIsClampedRatherThanTrusted() {
    // A UserDefaults plist is a file anything running as this user can edit, and
    // 6.5 will write this key. An unclamped value reaches an AVAudioEngine gain.
    let defaults = freshDefaults()
    defaults.set(42.0, forKey: "vibecat.volume")
    #expect(UserDefaultsPreferenceStore(defaults: defaults).load().volume == 1.0)
    defaults.set(-3.0, forKey: "vibecat.volume")
    #expect(UserDefaultsPreferenceStore(defaults: defaults).load().volume == 0.0)
}

@Test func aNonFiniteVolumeIsReplacedByTheDefaultRatherThanClampedToAnEdge() {
    // NaN fails every comparison, so `min(max(x, 0), 1)` passes it straight
    // through — clamping alone does not catch this one. It has to be tested
    // separately or it will not be caught at all.
    let defaults = freshDefaults()
    defaults.set(Double.nan, forKey: "vibecat.volume")
    let v = UserDefaultsPreferenceStore(defaults: defaults).load().volume
    #expect(v == 0.60, "expected the default, got \(v)")
    defaults.set(Double.infinity, forKey: "vibecat.volume")
    #expect(UserDefaultsPreferenceStore(defaults: defaults).load().volume == 1.0)
}

@Test func anUnknownSelectedPageFallsBackToGeneralRatherThanOpeningNothing() {
    // A page key that no longer exists — a renamed pane, a hand-edited plist —
    // must not open a window with no pane selected.
    let defaults = freshDefaults()
    defaults.set("kitchen-sink", forKey: "vibecat.selectedPage")
    #expect(UserDefaultsPreferenceStore(defaults: defaults).load().selectedPage == "general")
}

// MARK: - fixture

/// A `UserDefaults` nobody else in the suite shares. The whole suite runs in
/// parallel and `.standard` is process-wide — two tests writing the same key
/// would flake in a way that looks like a bug in the store.
private func freshDefaults() -> UserDefaults {
    let suite = "vibecat.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter PreferenceStoreTests 2>&1 | tail -20`

Expected: `cannot find 'UserDefaultsPreferenceStore' in scope`.

- [ ] **Step 3: Write `Preferences.swift`**

```swift
import Foundation

/// The preferences that exist today. **Four, deliberately.**
///
/// §14 describes roughly 47 controls across four pages, and Plan 6.4 owns none of
/// them but mute. Adding the other 43 keys now would mean inventing defaults for
/// behaviour that does not exist and shipping 43 pieces of untested surface;
/// Plans 6.5–6.7 add theirs as they add the controls that mean something.
///
/// Every default below is read off `settings.html`, not chosen: the volume
/// slider's `value="60"` (line 358), the Do Not Disturb switch's
/// `aria-checked="true"` (line 359), and the General pane's `data-active="true"`
/// (line 210).
public struct Preferences: Sendable, Equatable {
    public var soundEnabled: Bool
    /// `0…1`, from `settings.html`'s `0…100` slider.
    public var volume: Double
    public var quietDuringDoNotDisturb: Bool
    /// Which pane the window reopens on. A key, not an index, so reordering the
    /// sidebar cannot silently change which page someone lands on.
    public var selectedPage: String

    public init(soundEnabled: Bool = true, volume: Double = 0.60,
                quietDuringDoNotDisturb: Bool = true, selectedPage: String = "general") {
        self.soundEnabled = soundEnabled
        self.volume = volume
        self.quietDuringDoNotDisturb = quietDuringDoNotDisturb
        self.selectedPage = selectedPage
    }
}
```

- [ ] **Step 4: Write `PreferenceStore.swift`**

```swift
import Foundation

public protocol PreferenceStoring: Sendable {
    func load() -> Preferences
    func save(_ preferences: Preferences)
}

/// Preferences in `UserDefaults`, **clamped on the way in**.
///
/// The clamping is the boundary, not defensive padding. A `UserDefaults` plist is
/// a file any process running as this user can edit, Plans 6.5–6.7 will write
/// these keys, and an unclamped `volume` reaches an `AVAudioEngine` gain. This
/// repo already has the precedent in a harsher form: every interval that becomes
/// a deadline goes through one clamp, because a value read off the socket can
/// saturate a `DispatchTime` into `.distantFuture` and park a thread forever.
///
/// `NaN` needs its own branch. It fails every comparison, so `min(max(x, 0), 1)`
/// passes it straight through — clamping alone does not catch it.
public struct UserDefaultsPreferenceStore: PreferenceStoring {
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "vibecat.") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    private func key(_ name: String) -> String { keyPrefix + name }

    public func load() -> Preferences {
        let fallback = Preferences()
        var prefs = fallback
        if defaults.object(forKey: key("soundEnabled")) != nil {
            prefs.soundEnabled = defaults.bool(forKey: key("soundEnabled"))
        }
        if defaults.object(forKey: key("quietDuringDoNotDisturb")) != nil {
            prefs.quietDuringDoNotDisturb = defaults.bool(forKey: key("quietDuringDoNotDisturb"))
        }
        if defaults.object(forKey: key("volume")) != nil {
            prefs.volume = Self.clampedVolume(defaults.double(forKey: key("volume")),
                                              fallback: fallback.volume)
        }
        if let page = defaults.string(forKey: key("selectedPage")),
           SettingsPageKey.isKnown(page) {
            prefs.selectedPage = page
        }
        return prefs
    }

    public func save(_ preferences: Preferences) {
        defaults.set(preferences.soundEnabled, forKey: key("soundEnabled"))
        defaults.set(preferences.volume, forKey: key("volume"))
        defaults.set(preferences.quietDuringDoNotDisturb, forKey: key("quietDuringDoNotDisturb"))
        defaults.set(preferences.selectedPage, forKey: key("selectedPage"))
    }

    static func clampedVolume(_ value: Double, fallback: Double) -> Double {
        guard !value.isNaN else { return fallback }
        return min(max(value, 0), 1)
    }
}

/// The page keys, here rather than in `VibeCatUI`, because `load()` has to reject
/// a key that no longer names a pane and `VibeCatCore` cannot see the views.
/// Kept in step with `SettingsPage.all` by `theCoreAndTheUIAgreeOnThePageKeys`.
public enum SettingsPageKey {
    public static let all = ["general", "integrations", "notifications", "display"]
    public static func isKnown(_ key: String) -> Bool { all.contains(key) }
}

/// For tests, and for any surface that should not touch the user's real defaults.
public struct InMemoryPreferenceStore: PreferenceStoring {
    private final class Box: @unchecked Sendable { var value: Preferences; init(_ v: Preferences) { value = v } }
    private let box: Box
    public init(_ initial: Preferences = Preferences()) { box = Box(initial) }
    public func load() -> Preferences { box.value }
    public func save(_ preferences: Preferences) { box.value = preferences }
}
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `swift test --filter PreferenceStoreTests`

Expected: 6 passing.

- [ ] **Step 6: Mutation-verify**

1. Drop the `isNaN` guard from `clampedVolume` →
   `aNonFiniteVolumeIsReplacedByTheDefaultRatherThanClampedToAnEdge` must fail.
2. Replace `min(max(value, 0), 1)` with `value` →
   `anAbsurdVolumeInThePlistIsClampedRatherThanTrusted` must fail.
3. Drop `volume` from `save` → `everyFieldSurvivesASaveAndReload` must fail.
4. Drop the `SettingsPageKey.isKnown` check →
   `anUnknownSelectedPageFallsBackToGeneralRatherThanOpeningNothing` must fail.
5. Replace each `defaults.object(forKey:) != nil` guard with an unconditional
   read → `anEmptyStoreReturnsThePrototypesOwnDefaults` must fail on
   `soundEnabled` and `quietDuringDoNotDisturb`, because `bool(forKey:)` returns
   `false` for an absent key and both default to `true`. **This is the mutation
   that matters most** — it is the difference between "unset" and "set to false",
   and getting it wrong means a fresh install ships with sound off.

- [ ] **Step 7: Run the full suite and commit**

```bash
swift test 2>&1 | tail -5
git add Sources/VibeCatCore/Preferences.swift Sources/VibeCatCore/PreferenceStore.swift \
        Tests/VibeCatCoreTests/PreferenceStoreTests.swift
git commit -m "feat: an absent preference and one set to false are not the same thing

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 2: The Settings palette, and a measured decision about the switch

**Files:**
- Create: `Sources/VibeCatUI/Settings/SettingsPalette.swift`
- Create: `Sources/VibeCatUI/Settings/SettingsSwitch.swift`
- Test: `Tests/VibeCatUITests/SettingsPaletteTests.swift`

**Interfaces:**
- Consumes: `Tests/VibeCatUITests/Raster.swift`'s helpers for the measurement.
- Produces:
  ```swift
  public enum SettingsPalette {
      public static let background: RGBA   // #1C1C1E
      public static let chrome: RGBA       // #232326
      public static let pane: RGBA         // #161618
      public static let card: RGBA         // #2A2A2D
      public static let hairline: RGBA     // white at 8%
      public static let bone: RGBA         // #F2F2F5
      public static let haze: RGBA         // #9A9AA2
      public static let dim: RGBA          // #6A6A74
      public static let systemBlue: RGBA   // #0A84FF
      public static let switchOff: RGBA    // #48484E
  }
  ```
  and whatever `SettingsSwitch` turns out to be after Step 1.

**Read `settings.html` lines 9–27 for the tokens and 87–93 for the switch.** Then
read the "palette collision" section at the top of this plan: **`--accent` means
system blue here and the current state colour in the island, and there is no
token named `accent` in this enum on purpose.**

Note the names deliberately do not match the island's: `hairline` not `line`,
`systemBlue` not `blue`, `background` not `bg`. A reader who greps for `dim` will
find two and has to choose; a reader who greps for `accent` finds only the
island's, which is the one that means state.

- [ ] **Step 1: Measure the native switch before deciding to draw one**

`settings.html:87-93` draws its own switch: `38×22`, radius `11`, knob `18×18` at
`top:2 left:2`, `translateX(16)` when on, `#48484E` off and `--blue` on, focus
ring `2px` accent at `2px` offset. Those numbers are macOS's own switch drawn by
hand — §14 asks for "macOS-native layout", so **the native `Toggle` may already be
the fidelity choice, and drawing our own would be the divergence.**

Do not assume either way. Rasterise a `Toggle(…).toggleStyle(.switch)` at 1× and
2× using `Tests/VibeCatUITests/Raster.swift`, measure the drawn control's width,
height and knob travel, and compare against `38×22` and `16`. Write the numbers
into the report and into a doc comment.

Then decide:
- **Within about a point** → use the native `Toggle`, and `SettingsSwitch` is a
  thin wrapper that fixes the tint and nothing else. Record the measurement as the
  evidence, because "it looks native" is not evidence.
- **Materially different** → draw it to the prototype's geometry, and record the
  measured native numbers as the reason. A hand-drawn control must still be
  operable by keyboard and carry the same accessibility role as a switch.

**Whichever you choose, write the decision and its numbers down.** This is the
"either a fix or a written decision" rule at its most literal.

- [ ] **Step 2: Write the failing test**

```swift
import Testing
import Foundation
import SwiftUI
@testable import VibeCatUI

// MARK: - the palette is the settings sheet's, not the island's

@Test func settingsHasItsOwnInkAndDoesNotBorrowTheIslands() {
    // The collision this guards: `--accent` is system blue in settings.html and
    // the current state's colour in the island. A settings switch tinted from
    // IslandState would turn amber because some agent is blocked. If someone
    // "unifies" the two palettes, this fails.
    #expect(SettingsPalette.systemBlue == RGBA(hex: "#0A84FF")!)
    #expect(SettingsPalette.dim == RGBA(hex: "#6A6A74")!)
    // The island's own dim is a different colour. Asserting the difference is
    // what makes the test about the collision rather than about one value.
    #expect(SettingsPalette.dim != IslandState.dormant.accent,
            "the island's dim (#5A6273) is not the settings sheet's (#6A6A74)")
}

@Test func everyPaletteTokenMatchesTheProtoypesOwnValue() {
    // Transcribed from settings.html:9-27. A wrong digit here is invisible.
    #expect(SettingsPalette.background == RGBA(hex: "#1C1C1E")!)
    #expect(SettingsPalette.chrome     == RGBA(hex: "#232326")!)
    #expect(SettingsPalette.pane       == RGBA(hex: "#161618")!)
    #expect(SettingsPalette.card       == RGBA(hex: "#2A2A2D")!)
    #expect(SettingsPalette.bone       == RGBA(hex: "#F2F2F5")!)
    #expect(SettingsPalette.haze       == RGBA(hex: "#9A9AA2")!)
    #expect(SettingsPalette.switchOff  == RGBA(hex: "#48484E")!)
}

@Test func theStateHuesInSettingsAreTheIslandsExactlyBecauseTheyPreviewIt() {
    // settings.html carries --idle/--running/--waiting/--error at the same values
    // as the island, because the Display page previews the island. This is the
    // one place state colour belongs in a settings sheet, and if the two ever
    // drift the preview stops being a preview.
    #expect(RGBA(hex: "#3FD99B")! == IslandState.idle.accent)
    #expect(RGBA(hex: "#5B9DF9")! == IslandState.running.accent)
    #expect(RGBA(hex: "#FFA63C")! == IslandState.waiting.accent)
    #expect(RGBA(hex: "#FF5C5C")! == IslandState.failed.accent)
}

// MARK: - the switch actually draws its two states differently

@Test func anOnSwitchDrawsSystemBlueAndAnOffSwitchDoesNot() throws {
    // Two renders differing in exactly one input, and asserting on a colour only
    // the thing under test can emit. A count-of-colours assertion would pass
    // against a switch that never changed at all — that exact mistake has been
    // made in this repo before, with a sprite emptied and eighty colours still
    // counted from everything else.
    let on  = try Raster.rasterise(SettingsSwitch(isOn: .constant(true)),  size: CGSize(width: 44, height: 28))
    let off = try Raster.rasterise(SettingsSwitch(isOn: .constant(false)), size: CGSize(width: 44, height: 28))
    #expect(on.contains(Raster.Pixel(SettingsPalette.systemBlue), tolerance: 12),
            "an on switch must carry system blue")
    #expect(!off.contains(Raster.Pixel(SettingsPalette.systemBlue), tolerance: 12),
            "an off switch must not")
}
```

**Two helper facts, verified rather than assumed while writing this plan.**
`RGBA`'s hex initialiser is **failable and takes a `String`** —
`RGBA(hex: "#0A84FF")!`, defined at `Sources/VibeCatUI/IslandState.swift:17`.
An earlier draft of this plan wrote `RGBA(hex: 0x0A84FF)` in fifteen places and
**none of it would have compiled**; that is the same defect class that reached an
implementer twice on Plan 6.2, so it was checked this time. `Raster.Pixel(_ colour: RGBA)`
does exist (`Raster.swift:190`).

`contains(_:tolerance:)` was **not** verified. Check `Tests/VibeCatUITests/Raster.swift`
for what the suite actually uses to assert a colour, use that, and say in the
report what you used. Do not add a helper if one already fits.

- [ ] **Step 3: Run it and watch it fail**

Run: `swift test --filter SettingsPaletteTests 2>&1 | tail -20`

Expected: `cannot find 'SettingsPalette' in scope`.

- [ ] **Step 4: Write both files**

Write `SettingsPalette.swift` with the nine tokens above, each carrying the
`settings.html` line it came from. Write `SettingsSwitch.swift` as Step 1's
measurement decided, with the measured numbers in its doc comment.

- [ ] **Step 5: Run the tests, then mutation-verify**

1. Set `SettingsPalette.dim` to the island's `#5A6273` →
   `settingsHasItsOwnInkAndDoesNotBorrowTheIslands` must fail.
2. Change any one token by a single digit →
   `everyPaletteTokenMatchesTheProtoypesOwnValue` must fail.
3. Make `SettingsSwitch` ignore `isOn` and always draw the off state →
   `anOnSwitchDrawsSystemBlueAndAnOffSwitchDoesNot` must fail. **This is the
   mutation that matters** — an unwired control is the defect this whole file
   exists to prevent, and a rasterised colour assertion is the only thing that
   catches it, because reading a property proves nothing about what was drawn.
4. Tint the switch from `IslandState.waiting.accent` instead → the same test must
   fail, and say in the report which assertion caught it.

- [ ] **Step 6: Run the full suite twice and commit**

Twice, because these are new raster assertions and `--filter` is only quieter.

```bash
swift test 2>&1 | tail -3 && swift test 2>&1 | tail -3
git add Sources/VibeCatUI/Settings/ Tests/VibeCatUITests/SettingsPaletteTests.swift
git commit -m "feat: accent means system blue in Settings and state in the island

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 3: The panel footer

**Files:**
- Create: `Sources/VibeCatUI/Drawer/PanelBar.swift`
- Modify: `Sources/VibeCatUI/Drawer/DrawerView.swift` — the `Color.clear` at the
  reserved footer, around line 93
- Test: `Tests/VibeCatUITests/PanelBarTests.swift`

**Interfaces:**
- Consumes: `SettingsPalette`.
- Produces:
  ```swift
  public struct PanelBar: View {
      public init(muted: Bool, onToggleMute: @escaping () -> Void, onOpenSettings: @escaping () -> Void)
  }
  ```

**The prototype is `island-motion.html` lines 516–530.** `.panelbar` holds a
`<span class="spacer">` then `#pmute` then `#pgear`, both `.pbtn`, each a `24×24`
`viewBox` SVG. The spacer pushes both to the trailing edge. Read the actual SVG
path data there — the mute icon has a speaker, two arcs (`.wave1`, `.wave2`) and a
`.slash` that appears when muted; the gear is a circle plus eight spokes.

`DrawerView` already reserves this space: `footerHeight = 44` and a
`Color.clear.frame(height:)` placeholder, with a comment at
`DrawerView.swift:35` saying the footer is Plan 6's. **Read that comment and the
constraint it records before changing the layout** — `QuestionFace` has hard-won
comments at lines 87–95 and 139–141 about the footer being invaded and clipped by
a confirmation banner, and about there being no room for a second line. Do not
change `footerHeight`.

Two shapes, not glyphs: this repo has already had to replace `●`/`☐`/`☑` with
drawn shapes once, and a gear is not `⚙`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
import SwiftUI
@testable import VibeCatUI

@Test func theMuteButtonShowsASlashOnlyWhenMuted() throws {
    // Two renders differing in exactly one input. The slash is a diagonal, so it
    // adds ink where the unmuted icon has none — count the difference rather
    // than the total, because a total would pass against two identical renders.
    let size = CGSize(width: 120, height: 44)
    let quiet = try Raster.rasterise(PanelBar(muted: true,  onToggleMute: {}, onOpenSettings: {}), size: size)
    let loud  = try Raster.rasterise(PanelBar(muted: false, onToggleMute: {}, onOpenSettings: {}), size: size)
    // **Do not assert that muted draws MORE ink.** That premise is false and an
    // earlier draft of this plan asserted it: muted *hides* the two arcs while it
    // shows the slash, so it is a swap, not an addition — measured 301 against
    // 308, the wrong way round. The test passed against a bar that ignored
    // `muted` entirely. Assert on something only the muted state can produce: the
    // tint change, plus a pixel the slash alone covers.
    #expect(quiet != loud, "the muted flag changes nothing that is drawn")
}

@Test func bothButtonsSitAgainstTheTrailingEdge() throws {
    // The prototype's `.panelbar` opens with a `<span class="spacer">`, so both
    // buttons are pushed right. A leading-aligned bar would put a gear where the
    // session list's own content begins.
    let bar = try Raster.rasterise(PanelBar(muted: false, onToggleMute: {}, onOpenSettings: {}),
                                   size: CGSize(width: 200, height: 44))
    #expect(bar.isBlank(inColumns: 0..<100), "the leading half of the bar must be empty")
    #expect(!bar.isBlank(inColumns: 120..<200), "both buttons belong at the trailing edge")
}

@Test func tappingEachButtonCallsItsOwnClosureAndNotTheOther() {
    // Cheap, and it catches the likeliest wiring error in the file: two buttons
    // whose actions are swapped, or one wired to both.
    var muteCalls = 0, settingsCalls = 0
    let bar = PanelBar(muted: false, onToggleMute: { muteCalls += 1 }, onOpenSettings: { settingsCalls += 1 })
    bar.toggleMuteForTesting()
    #expect((muteCalls, settingsCalls) == (1, 0))
    bar.openSettingsForTesting()
    #expect((muteCalls, settingsCalls) == (1, 1))
}

@Test func theReservedFooterIsNoLongerEmpty() throws {
    // DrawerView reserved 44pt for this in Plan 4 and filled it with
    // Color.clear. If someone reverts the wiring, the bar's own tests still pass
    // and only this one notices.
    let drawn = try Raster.hostAndRasterise(
        DrawerView.footerProbeForTesting(muted: false),
        size: CGSize(width: 388, height: DrawerView.footerHeight))
    #expect(drawn.opaquePixelCount > 0, "the reserved footer is still Color.clear")
}
```

`opaquePixelCount`, `isBlank(inColumns:)` and `hostAndRasterise` may not exist
under those names. **Check `Tests/VibeCatUITests/Raster.swift` and use what is
there**; add a helper only if nothing fits, and say which you added. Likewise
`toggleMuteForTesting()` / `openSettingsForTesting()` / `footerProbeForTesting` —
if exposing those means putting test-only API into a production view, prefer
whatever the suite already does for this (check how `IslandView`'s `#if DEBUG`
counters are gated) and report the choice.

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter PanelBarTests 2>&1 | tail -20`

Expected: `cannot find 'PanelBar' in scope`.

- [ ] **Step 3: Write `PanelBar.swift` and wire it into `DrawerView`**

Draw both icons as `Path`s from the prototype's SVG data. Replace
`DrawerView`'s `Color.clear.frame(height: Self.footerHeight)` with the bar, and
**leave `footerHeight` at 44**.

- [ ] **Step 4: Run the tests, then mutation-verify**

1. Ignore `muted` and always draw the slash → `theMuteButtonShowsASlashOnlyWhenMuted`
   must fail.
2. Remove the leading spacer → `bothButtonsSitAgainstTheTrailingEdge` must fail.
3. **Predicted uncaught, and it is.** Wiring the gear's action to
   `onToggleMute` cannot be caught without a ViewInspector-style dependency or
   real click simulation, and this project has neither and may add neither. A
   test hook that calls the closures directly does not see a `Button` wired to
   the wrong one. **Adjudicated as an accepted blind spot**, and it generalises:
   any footer control with two buttons and two closures has it. Report it, do not
   paper over it.
4. Restore `Color.clear` in `DrawerView` → `theReservedFooterIsNoLongerEmpty`
   must fail **and the other three must still pass**, which is the point of
   having it. **Write this test against a rendered `DrawerView`, not against a
   shared static** — an earlier draft read a constant independently of `body`, so
   reverting the wiring left it green. That is the same defect this test exists to
   catch, in the test itself.

- [ ] **Step 5: Look at it**

```bash
VIBECAT_LIST_SHOT=/tmp/list.png swift test --filter sessionListShot
```

Open the PNG. The footer is now drawn — **check it has not clipped the last row**,
which is precisely what `QuestionFace.swift:139-141` records happening once
before. Then open `island-motion.html` in a browser, look at its `.panelbar`, and
report which elements you compared.

- [ ] **Step 6: Full suite twice, then commit**

```bash
swift test 2>&1 | tail -3 && swift test 2>&1 | tail -3
git add Sources/VibeCatUI/Drawer/PanelBar.swift Sources/VibeCatUI/Drawer/DrawerView.swift \
        Tests/VibeCatUITests/PanelBarTests.swift
git commit -m "feat: the 44pt Plan 4 reserved has had a mute and a gear in it since the mockup

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 4: Mute, end to end

**Files:**
- Modify: `Sources/VibeCatUI/Sound/SoundPlayer.swift` — accept a preference source
- Modify: `Sources/VibeCatApp/main.swift` — load preferences, wire the bar
- Test: `Tests/VibeCatUITests/MuteWiringTests.swift`

**Interfaces:**
- Consumes: `Preferences`, `PreferenceStoring`, `PanelBar`, `SoundPlayer`,
  `SoundSettings`.
- Produces: no new type. `SoundPlayer.settings.enabled` becomes driven by
  `Preferences.soundEnabled`, and toggling the bar's mute persists.

`island-motion.html:1060` states the coupling: *"the panel's mute button and the
app's sound toggle are the same setting"*. One value, two surfaces — so muting
from the island must be what the Settings sheet later shows, and neither may hold
its own copy.

**Read `SoundPlayer.swift` first.** Plan 6.2's fix round gave it a render cache
keyed on `(settings, sampleRate)`. Changing `settings` therefore invalidates that
cache — check what the invalidation actually does before wiring a switch to it,
and say in the report whether toggling mute repeatedly can cause repeated
re-rendering. If it can, that is a real cost: uncached, `error` measured **860 ms
on the main actor in a debug build**.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
import VibeCatCore
@testable import VibeCatUI

@Test @MainActor func mutingStopsACueFromRenderingAtAll() {
    // Not "plays quietly" — renders nothing. A muted app that still spends
    // 860ms rendering a buffer it throws away is the defect here.
    let store = InMemoryPreferenceStore(Preferences(soundEnabled: false))
    let player = SoundPlayer(settings: SoundSettings(enabled: store.load().soundEnabled),
                             quietHours: NeverQuiet())
    #expect(player.buffer(for: .ask) == nil)
}

@Test @MainActor func unmutingMakesTheVerySameCueRenderAgain() {
    // Two players differing in exactly one input.
    let player = SoundPlayer(settings: SoundSettings(enabled: true), quietHours: NeverQuiet())
    #expect(player.buffer(for: .ask) != nil)
}

@Test func togglingMuteFromTheIslandPersists() {
    // The coupling island-motion.html:1060 states. If the bar keeps its own
    // copy, the Settings sheet 6.5 builds will disagree with it.
    let store = InMemoryPreferenceStore(Preferences(soundEnabled: true))
    var prefs = store.load()
    prefs.soundEnabled = false
    store.save(prefs)
    #expect(store.load().soundEnabled == false)
}

@Test @MainActor func aStoredMuteIsHonouredOnTheNextLaunch() {
    // The whole point of persistence: mute at 2am, still muted at 9am.
    let store = InMemoryPreferenceStore(Preferences(soundEnabled: false))
    let player = SoundPlayer(settings: SoundSettings(enabled: store.load().soundEnabled),
                            quietHours: NeverQuiet())
    #expect(player.buffer(for: .done) == nil, "a stored mute did not survive construction")
}
```

- [ ] **Step 2: Run it and watch it fail**, then wire it, then watch it pass.

Run: `swift test --filter MuteWiringTests 2>&1 | tail -20`

- [ ] **Step 3: Mutation-verify**

1. Ignore `soundEnabled` when constructing `SoundSettings` →
   `aStoredMuteIsHonouredOnTheNextLaunch` and `mutingStopsACueFromRenderingAtAll`
   must both fail.
2. Have the bar hold its own `@State` for muted instead of the store →
   `togglingMuteFromTheIslandPersists` must fail. **If it does not**, the test is
   asserting the store rather than the wiring — say so and strengthen it, do not
   leave it.

- [ ] **Step 4: Verify on hardware, and be honest about what you cannot check**

```bash
Scripts/build-app.sh && open .build/VibeCat.app
VIBECAT_SOCKET=/tmp/vibecat-dev.sock Scripts/replay.sh permission
```

Confirm the app does not crash, the hook still exits `0` (**§2.3 fail-open is this
repo's one unbreakable invariant** — a settings read must never be able to hang a
terminal), and that mute survives a quit and relaunch. **You cannot hear.** Do not
claim any audible check; the four listening items Plan 6.2 left open stay open.

- [ ] **Step 5: Full suite three times, then commit**

Three, because this touches the app's wiring and a full-suite-only failure here is
a real bug.

---

## Task 5: The window, from an app with no Dock icon

**Files:**
- Create: `Sources/VibeCatUI/Settings/SettingsWindow.swift`
- Test: `Tests/VibeCatUITests/SettingsWindowTests.swift`

**Interfaces:**
- Consumes: `SettingsPalette`, `Preferences`, `PreferenceStoring`.
- Produces:
  ```swift
  @MainActor public final class SettingsWindowController {
      public init(store: PreferenceStoring)
      public func show()
      public var isOpen: Bool { get }
  }
  ```

**`LSUIElement = true` is the whole problem.** No Dock icon, no menu bar, so
nothing in AppKit will reopen this window for us and there is no `Settings` scene
to lean on. The gear is the only door, which means: exactly one instance, brought
to front if it already exists, and **it must be able to become key without
stealing focus in a way that breaks the island's own rule.** Plan 5's key-input
spike settled Path A for the *panel* — the panel takes key exclusively and never
changes `frontmostApplication`. A settings window is a different case: it is a
normal window and the person is deliberately looking at it. Say in the report what
you observed about `frontmostApplication` when it opens, and note that
**`NSApp.isActive` is not a usable proxy** — it read `true` in every spike run
while focus demonstrably stayed elsewhere.

`.titlebar` in `settings.html:198-201` is a real macOS titlebar with traffic
lights and the title **"VibeCat Settings"**. Use a real one; do not draw it.

**Tear-down.** `AppModel` and `HoverMonitor` both use `isolated deinit` because
`RunLoop.main` holds a `Timer` strongly and a listening socket's accept thread
otherwise runs forever. A controller holding an `NSWindow` that holds an
`NSHostingView` that holds an `@Observable` is the same shape. Make the window
release itself on close and say what you did.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
import AppKit
import VibeCatCore
@testable import VibeCatUI

@Test @MainActor func showingTwiceReusesTheOneWindow() {
    // The gear is the only door. Two windows means two views of one truth, and
    // the second one silently wins whatever it writes last.
    let c = SettingsWindowController(store: InMemoryPreferenceStore())
    c.show()
    let first = c.windowForTesting
    c.show()
    #expect(c.windowForTesting === first, "show() built a second window")
}

@Test @MainActor func theWindowCarriesTheTitleTheProtoypeGivesIt() {
    let c = SettingsWindowController(store: InMemoryPreferenceStore())
    c.show()
    #expect(c.windowForTesting?.title == "VibeCat Settings")
}

@Test @MainActor func closingTheWindowLetsItGo() {
    // The lifecycle rule this repo learned the hard way twice.
    let c = SettingsWindowController(store: InMemoryPreferenceStore())
    c.show()
    #expect(c.isOpen)
    c.windowForTesting?.performClose(nil)
    #expect(!c.isOpen, "the controller still thinks a closed window is open")
}

@Test @MainActor func theWindowOpensOnThePageThatWasStored() {
    let store = InMemoryPreferenceStore(Preferences(selectedPage: "display"))
    let c = SettingsWindowController(store: store)
    c.show()
    #expect(c.selectedPageForTesting == "display")
}

@Test @MainActor func anUnknownStoredPageStillOpensSomething() {
    // The store clamps this, but the window must not depend on that to avoid
    // showing an empty content area. Two layers, deliberately.
    let store = InMemoryPreferenceStore(Preferences(selectedPage: "kitchen-sink"))
    let c = SettingsWindowController(store: store)
    c.show()
    #expect(SettingsPageKey.isKnown(c.selectedPageForTesting))
}
```

A window test needs a window server for some operations. **If any of these cannot
run headless, say which and why rather than deleting it** — and check first
whether it genuinely needs one, because this project has twice called a visual
check environmentally blocked when it was not.

- [ ] **Step 2–4: Fail, implement, pass, mutation-verify**

1. Build a new window on every `show()` → `showingTwiceReusesTheOneWindow` fails.
2. Hardcode the initial page to `"general"` →
   `theWindowOpensOnThePageThatWasStored` fails.
3. Never clear the window reference on close → `closingTheWindowLetsItGo` fails.
4. Remove the window's own unknown-page fallback →
   `anUnknownStoredPageStillOpensSomething` must still pass (the store clamps it),
   so **report this mutation as uncaught** and say whether the second layer is
   worth keeping. Do not add a test that reaches around the store to force it.

- [ ] **Step 5: Full suite twice, then commit**

---

## Task 6: The sidebar and the four panes

**Files:**
- Create: `Sources/VibeCatUI/Settings/SettingsPage.swift`
- Create: `Sources/VibeCatUI/Settings/SettingsSidebar.swift`
- Modify: `Sources/VibeCatUI/Settings/SettingsWindow.swift` — host the real content
- Test: `Tests/VibeCatUITests/SettingsSidebarTests.swift`

**Interfaces:**
- Consumes: `SettingsPalette`, `SettingsPageKey`, `Preferences`.
- Produces:
  ```swift
  public struct SettingsPage: Sendable, Equatable, Identifiable {
      public let key: String, label: String
      public let chip: RGBA
      public var id: String { key }
      public static let all: [SettingsPage]
  }
  public struct SettingsSidebar: View { public init(selection: Binding<String>) }
  ```

**The prototype is `settings.html` lines 519–540.** `NAVS` gives four pages in
order, each with a key, a label, a chip colour and SVG path data:

| Key | Label | Chip |
|---|---|---|
| `general` | General | `#6E6E73` |
| `integrations` | Integrations | `#32ADE6` |
| `notifications` | Notifications | `#FF3B30` |
| `display` | Display | `#5E5CE6` |

Those are macOS system colours, **not** VibeCat state colours — nothing here means
`running` or `waiting`.

**And a structural rule the prototype states in a comment at line 534:** *"the
pane headings reuse the sidebar's icon so the two always agree"*. It builds each
pane's `.ptitle` chip from the same `NAVS` entry. Do the same — one source for
both — rather than declaring the icon twice and hoping.

The sidebar is `196pt` wide, background `--pane` `#161618`, a `1px --line`
right border, padding `10px 8px` (`settings.html:53`).

Each pane in this plan is **chrome only**: the coloured chip, the `<h1>`, and a
note naming which plan owns its controls. An empty pane that lies about being
finished is worse than one that says "6.6 owns this".

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
import SwiftUI
@testable import VibeCatUI
import VibeCatCore

@Test func theFourPagesAreTheProtoypesFourInItsOrder() {
    #expect(SettingsPage.all.map(\.key) == ["general", "integrations", "notifications", "display"])
    #expect(SettingsPage.all.map(\.label) == ["General", "Integrations", "Notifications", "Display"])
}

@Test func theCoreAndTheUIAgreeOnThePageKeys() {
    // SettingsPageKey lives in VibeCatCore because `load()` must reject an
    // unknown key and Core cannot see the views. Two lists of the same truth is
    // a drift waiting to happen — this is the only thing that would notice.
    #expect(SettingsPage.all.map(\.key) == SettingsPageKey.all)
}

@Test func eachPageWearsItsOwnChipColourAndNoneIsAStateColour() {
    #expect(SettingsPage.all.map(\.chip) == [RGBA(hex: "#6E6E73")!, RGBA(hex: "#32ADE6")!,
                                             RGBA(hex: "#FF3B30")!, RGBA(hex: "#5E5CE6")!])
    // The point of the assertion: a sidebar chip must never be mistaken for the
    // island's state vocabulary. Notifications' red is #FF3B30; failed is #FF5C5C.
    let stateHues = Set(IslandState.allCases.map(\.accent))
    for page in SettingsPage.all {
        #expect(!stateHues.contains(page.chip), "\(page.key)'s chip is a state colour")
    }
}

@Test func theSelectedPageIsTheOnlyOneMarkedCurrent() throws {
    // Two renders differing in exactly one input. A sidebar that highlights
    // everything, or nothing, is the likeliest defect and a property read would
    // not see it.
    let general = try Raster.rasterise(SettingsSidebar(selection: .constant("general")),
                                       size: CGSize(width: 196, height: 200))
    let display = try Raster.rasterise(SettingsSidebar(selection: .constant("display")),
                                       size: CGSize(width: 196, height: 200))
    #expect(general != display, "the selection changes nothing that is drawn")
}

@Test func everyPaneAnnouncesWhichPlanOwnsItsControls() {
    // This plan ships chrome. A pane that looks finished and does nothing is
    // worse than one that says so, and this is what stops the next reader
    // filing it as a bug.
    for page in SettingsPage.all where page.key != "notifications" {
        #expect(SettingsPage.ownerNote(for: page.key) != nil, "\(page.key) has no owner note")
    }
}
```

- [ ] **Step 2–4: Fail, implement, pass, mutation-verify**

1. Reorder `SettingsPage.all` → `theFourPagesAreTheProtoypesFourInItsOrder` and
   `theCoreAndTheUIAgreeOnThePageKeys` must both fail.
2. Change one chip to `IslandState.failed.accent` →
   `eachPageWearsItsOwnChipColourAndNoneIsAStateColour` must fail.
3. Ignore `selection` in the sidebar → `theSelectedPageIsTheOnlyOneMarkedCurrent`
   must fail. **This is the one that matters** — an unwired selection is invisible
   to every property read.
4. Remove a key from `SettingsPageKey.all` only →
   `theCoreAndTheUIAgreeOnThePageKeys` must fail, proving the two lists are pinned
   to each other rather than merely both existing.

- [ ] **Step 5: Diff it against the prototype, with your eyes**

Open `settings.html` in a browser. Compare, element by element: the sidebar's
width and inset, each chip's colour and icon, the pane title's chip-then-heading
arrangement, and the window chrome. **Report which elements you compared and every
difference you found**, however small — a divergence nobody wrote down gets
re-introduced by the next person who notices it.

This step is why this plan exists in the shape it does. `settings.html` is 640
lines and **no plan in six has ever diffed it.** You are the first.

- [ ] **Step 6: Full suite twice, then commit**

---

## Out of scope, deliberately

- **Every control on General, Integrations and Display**, and Notifications' own
  controls. Plans 6.5–6.7. Each pane says so on its face.
- **`Soft`, `System` and `Blip` sound packs** — no values exist for them anywhere.
  Plan 6.2's written decision 3 stands.
- **Launch at login** (`SMAppService`), **smart suppression**, **hide in
  fullscreen**, **notch tuning offsets**, **right-of-notch content**, **panel
  size**, **motion levels** — all behaviour that does not exist yet, all named by
  §14, none of it this plan's.
- **The four audible checks Plan 6.2 left open.** Still open. This plan cannot
  close them and must not appear to.

## Self-review

**Spec coverage of §14.** "Four sections, macOS-native layout" → Tasks 5 and 6,
with the native-versus-drawn switch decided by measurement in Task 2 rather than
by assertion. The four section *names* and their order → Task 6, from the
prototype's `NAVS` rather than §14's prose. **Everything else in §14 is explicitly
deferred above with an owner**, which is the honest reading of a four-line spec
section that summarises 47 controls.

**Placeholder scan.** No TBDs. Every code step carries code; every test step
carries assertions. Three places name a helper that may not exist under that
spelling (`RGBA(hex:)`, `opaquePixelCount`, `hostAndRasterise`) and each says
explicitly to check `Raster.swift` and report what was used instead — that is a
known unknown handed over, not a placeholder.

**Type consistency.** `Preferences`, `PreferenceStoring`,
`UserDefaultsPreferenceStore`, `InMemoryPreferenceStore`, `SettingsPageKey.all`,
`SettingsPalette`, `SettingsSwitch`, `PanelBar`, `SettingsWindowController`,
`SettingsPage.all`, `SettingsSidebar` — each defined in exactly one task and used
with that spelling later. `SettingsPageKey.all` (Core) and `SettingsPage.all` (UI)
are two lists of one truth **on purpose**, and Task 6's
`theCoreAndTheUIAgreeOnThePageKeys` is the only thing that would catch them
drifting.

**One thing I could not resolve while writing this, handed over rather than
guessed.** Task 5's mutation 4 is predicted to stay **uncaught**: removing the
window's own unknown-page fallback leaves `anUnknownStoredPageStillOpensSomething`
passing, because the store already clamps. Two layers of defence with one test
between them. I have said so rather than inventing a test that reaches around the
store to force the second layer, because Plan 6.2 shipped five tests that could
not fail and three of them were mine. **If the implementer finds a clean way to
test the second layer, take it; if not, the honest answer may be to delete the
fallback.**
