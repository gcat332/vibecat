# General and Integrations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship §14's two remaining Settings pages — General and Integrations — as
the prototype draws them, wiring every control that has machinery behind it and
declaring in code every control that does not.

**Architecture:** Four new controls (`.stepper`, `.field`, the full-width
`.slider` row, `.note`) join the six `Sources/VibeCatUI/Settings/` already has,
then two panes assemble them. Each pane owns an `@Observable` model over
`PreferenceStoring`, exactly as `NotificationsPaneModel` and `DisplayPaneModel`
do. `SettingsPage.ownerNote(for:)` loses its last two keys, which is what
"Plan 6.7 is done" means mechanically.

**Tech Stack:** Swift 6, SwiftUI + AppKit interop, `swift-testing`, no external
dependencies. `SMAppService` (`ServiceManagement`) for launch at login.

## Global Constraints

- **No external dependencies.** Not one package, for any reason.
- **The prototype is the authority on appearance.**
  `docs/superpowers/prototypes/settings.html` — General is `:210-270`,
  Integrations is `:273-320`, the CLI rows are rendered by the `CLIS` map at
  `:540-549`, and the CSS for every control named here is at `:95-136` and
  `:188-191`. **Open the file.** The spec's §14 is one line per page and is
  lossy; it is the authority on *which rows exist*, never on how they look.
- **Colour tokens come from `SettingsPalette`, never from a fresh `RGBA(hex:)`
  at a use site.** New tokens this plan needs: `.field`'s ground `#1F1F22`,
  `.field`'s focus ring is `var(--accent)` which in Settings means
  `SettingsPalette.systemBlue`, `.btn.danger`'s `#FF6B6B`, `.seg`'s pressed
  `#4A4A50`. Add them to `SettingsPalette` with their prototype line number.
- **`--accent` means system blue in Settings**, not the island's state colour.
  §4.3 is inverted here and `SettingsPalette.systemBlue` is the token.
- **Fail open (§2.3) is load-bearing and is not a preference.** The prototype's
  switch for it is **not built** — see the rulings below.
- **Any interval that becomes a deadline goes through a named clamp in
  `SocketClient`.** `clamped` bounds `0.02…60` for the *answer* deadline; this
  plan adds `clampedDelivery` at `0.05…2.0` for the delivery deadline. A
  `UserDefaults` plist is editable by anything running as this user, so a value
  read back out of preferences is untrusted input on exactly the same footing as
  one decoded off the wire.
- **Preferences live in an explicit `UserDefaults` suite, not `.standard`.**
  Measured: a binary with no bundle identifier gets a domain named after its
  executable, so `.standard` in `vibecat-hook` is a different file from
  `.standard` in the bundled app. See ruling 2.
- **Every new preference field is added to `Preferences`, to `save`, **and** to
  `load`.** `Preferences`' own doc comment says this because three fields have
  already been persisted and never read.
- `Scripts/test.sh` is the test command — `swift test --no-parallel`. The suite
  does not pass in parallel; that is measured, not suspected.
- **A control with no behaviour behind it must say so in code**, in
  `IntegrationsPane`/`GeneralPane`'s `declaredInert` list (Task 7). A row that
  looks finished and does nothing is worse than one that names its owner.

## The two rulings, given 2026-08-06

Both were raised as open conflicts between the prototype and §2.3. The owner has
ruled; this section records the rulings and the evidence behind them, so a later
reader finds a decision rather than reconstructing one.

### 1. `Carry on if VibeCat isn't running` — **the row is removed entirely**

The prototype draws it at `settings.html:293-295` as a switch defaulting on,
captioned *"A crashed island must never be able to hang your terminal. Turning
this off is not recommended."*

**Ruling: do not build the row, do not add a preference field. Fail open is
unconditional.** Not the pill-reading-`Always on` variant that was offered —
the owner asked for the row gone.

**The evidence, measured rather than reasoned.** Fail open here means "hand the
decision back to the terminal", not "allow it". `HookRunner.run` returns `nil`
on every failure path — dead socket, slow reply, crossed id, bad JSON
(`HookRunner.swift:28-51`) — and `nil` means the hook prints nothing at all.
With no `permissionDecision` on stdout, claude-code does what it did before
VibeCat existed: it prompts in the terminal. Nothing is auto-approved.

That kills the only argument for the switch. The plausible case for wanting it
off is *"VibeCat is my gate on dangerous commands; if it crashes I don't want
`rm -rf` waved through"* — which would be right if fail open answered `allow`.
It does not answer at all. So off protects nothing, and the only thing it can
accomplish is hanging a terminal, which is the one outcome §2.3 exists to make
impossible.

**The prototype's caption is half wrong and that is part of this record.** *"A
crashed island must never be able to hang your terminal"* is correct. *"Turning
this off is not recommended"* is not — there is no trade to recommend against,
because the alternative has no benefit.

**So the `Reply channel` group has two rows here and three in the prototype.**
That is a deliberate, written divergence, and it must be repeated in
`IntegrationsPane`'s doc comment where an implementer will actually meet it —
not only here. A reviewer diffing against the prototype will find a missing row
and needs to find the reason in the same file.

### 2. `Hook reply timeout` — **wired for real**

**Ruling: build the field, persist it, clamp it, and have the hook read it.**

The prototype's field (`settings.html:290-292`) holds `300` with a `ms` suffix,
which is the **delivery** deadline — the bound on reaching the app at all, not
the `answerDeadline` a person answers within.

`SocketClient.clamped`'s `0.02…60` is the answer deadline's range and is wrong
here: a 60-second delivery wait is §2.3 broken by arithmetic rather than by a
switch. **This plan adds its own bound, `0.05…2.0` seconds**, as a named constant
beside `clamped` in `SocketClient` — not a bare `min(max(...))` at the use site,
because this repo's rule is that every interval becoming a deadline goes through
one clamp and that rule is what stops the next one drifting.

#### The measured hazard that makes this task more than a text field

**A bare binary's `UserDefaults.standard` is not the app's domain.** Measured on
this machine 2026-08-06, with a throwaway executable compiled by `swiftc` and run
from a shell:

```
bundleIdentifier = (nil)
executable       = domain
standard read    = probe-domain          # wrote and read its own domain
app-suite read   = (nil)                 # could not see com.gcat332.vibecat
```

It created `~/Library/Preferences/domain.plist` — **a domain named after the
executable**. So `vibecat-hook` reading `UserDefaults.standard` would read
`vibecat-hook.plist`, never the app's `com.gcat332.vibecat.plist`. It would find
no key, fall back to the 300ms default, and **the field would look wired and do
nothing** — precisely the failure mode Task 7's declared-inert list exists to
prevent, arriving through the back door as an apparently-wired control.

**The fix, also measured.** An explicit suite crosses the process boundary:

```
wrote via suiteName from a bare binary, read back = 0.42
$ defaults read com.gcat332.vibecat
{ "vibecat.hookReplyTimeout" = "0.42"; }
```

So `UserDefaults(suiteName: "com.gcat332.vibecat")` works from a bare binary and
is visible to other processes.

**And this is a pre-existing bug, not one this plan introduces.**
`UserDefaultsPreferenceStore.init` defaults to `.standard`
(`PreferenceStore.swift:26`), so **`swift run vibecat` already writes to
`vibecat.plist` while the bundled app writes to `com.gcat332.vibecat.plist`** —
two different files for the same preferences, which is why
`~/Library/Preferences/com.gcat332.vibecat.plist` is 42 bytes after a week of
development. Task 1 fixes this at the root by making the store's default an
explicit suite, which repairs the app, the dev binary and the hook in one change.
Nothing is migrated: the existing domain is effectively empty and there are no
users.

---

## File Structure

**Created:**

| File | Responsibility |
|---|---|
| `Sources/VibeCatUI/Settings/SettingsStepper.swift` | `.stepper` — a value with ▲▼, `settings.html:95-99` |
| `Sources/VibeCatUI/Settings/SettingsField.swift` | `.field` — a bordered text field with an optional unit suffix, `:108-110` |
| `Sources/VibeCatUI/Settings/SettingsSliderRow.swift` | the full-width `.slider` row: `.top b` / `.v` readout / track / `.ticks`, `:126-136` |
| `Sources/VibeCatUI/Settings/SettingsNote.swift` | `.note` — the blue-ruled explanatory strip, `:188-191` |
| `Sources/VibeCatUI/Settings/GeneralPane.swift` | §14 General: five groups, thirteen rows, plus `GeneralPaneModel` |
| `Sources/VibeCatUI/Settings/IntegrationsPane.swift` | §14 Integrations: four groups plus `IntegrationsPaneModel` |
| `Sources/VibeCatUI/Settings/LaunchAtLogin.swift` | the `SMAppService` seam and its test double |
| `Tests/VibeCatUITests/Settings/SettingsStepperTests.swift` | |
| `Tests/VibeCatUITests/Settings/SettingsFieldTests.swift` | |
| `Tests/VibeCatUITests/Settings/SettingsSliderRowTests.swift` | |
| `Tests/VibeCatUITests/Settings/GeneralPaneTests.swift` | |
| `Tests/VibeCatUITests/Settings/IntegrationsPaneTests.swift` | |
| `Tests/VibeCatUITests/Settings/LaunchAtLoginTests.swift` | |

**Modified:**

| File | Change |
|---|---|
| `Sources/VibeCatCore/Preferences.swift` | fifteen new fields, with `save`/`load` |
| `Sources/VibeCatCore/PreferenceStore.swift` | clamping for the numeric fields, **and the default domain moves from `.standard` to an explicit suite** |
| `Sources/VibeCatTransport/SocketClient.swift` | `clampedDelivery`, and `deliveryDeadline` becomes an instance property |
| `Sources/VibeCatHookKit/HookRunner.swift` | reads the delivery deadline out of preferences |
| `Sources/vibecat-hook/main.swift` | builds the store and passes the deadline in |
| `Sources/VibeCatUI/Settings/SettingsPalette.swift` | four new tokens |
| `Sources/VibeCatUI/Settings/SettingsControls.swift` | `SettingsButton.Variant` (`.plain`/`.link`/`.danger`); `SettingsStatusPill` |
| `Sources/VibeCatUI/Settings/SettingsPage.swift` | `ownerNote(for:)` loses `"general"` and `"integrations"` |
| `Sources/VibeCatUI/Settings/SettingsPane.swift` | draws the two new panes |
| `Sources/VibeCatUI/Settings/SettingsWindow.swift` | builds the two new models |
| `Sources/VibeCatUI/AppModel.swift` | `idleTTL` becomes a preference rather than a `static let` |
| `Tests/VibeCatUITests/Settings/SettingsSidebarTests.swift` | the owner-note test's expected set shrinks to empty |
| `docs/superpowers/plans/README.md` | 6.7 marked done, findings carried |

---

### Task 1: The sixteen preference fields, and the domain they live in

**Files:**
- Modify: `Sources/VibeCatCore/Preferences.swift`
- Modify: `Sources/VibeCatCore/PreferenceStore.swift`
- Test: `Tests/VibeCatCoreTests/PreferencesTests.swift`

**Interfaces:**
- Consumes: `Preferences`, `PreferenceStoring`, `UserDefaultsPreferenceStore`,
  `SocketClient.clamped`.
- Produces: the fifteen field names below, and two new enums —
  `IdleCleanup: String, CaseIterable` and `ReplyChannel: String, CaseIterable`.
  Every later task binds to these names.

**Defaults are the prototype's own `aria-checked` and `selected` values, not
taste.** Read them off `settings.html` rather than from this table if the two
ever disagree:

| Field | Type | Default | Prototype |
|---|---|---|---|
| `launchAtLogin` | `Bool` | `true` | `:215` |
| `expandOnHover` | `Bool` | `true` | `:221` |
| `hoverDuration` | `Double` | `0.30` | `:224` (`value="30"`, `data-scale="100"`) |
| `smartSuppression` | `Bool` | `true` | `:227` |
| `hideInFullscreen` | `Bool` | `true` | `:234` |
| `autoHideWithNoSessions` | `Bool` | `true` | `:236` |
| `autoCollapseOnMouseLeave` | `Bool` | `false` | `:243` |
| `autoRevealDwell` | `Int` | `5` | `:245` (`5s`) |
| `dismissRevealOnOutsideClick` | `Bool` | `false` | `:249` |
| `idleCleanup` | `IdleCleanup` | `.twoHours` | `:252` (`<option selected>2 hours`) |
| `disableClickToJump` | `Bool` | `false` | `:260` |
| `numberKeysPickAnswers` | `Bool` | `true` | `:263` |
| `confirmDestructiveAnswers` | `Bool` | `true` | `:266` |
| `autoConfigureNewCLIs` | `Bool` | `true` | `:279` |
| `replyChannel` | `ReplyChannel` | `.hook` | `:286` (`aria-pressed` on `Hook`) |
| `hookReplyTimeout` | `Double` | `0.300` | `:290` (`value="300"`, ms) |

All sixteen ship. `hookReplyTimeout` is wired for real in Task 7 per ruling 2 —
it is not a declared-inert field. There is **no** `failOpen` field: ruling 1
removed that row, so no preference backs it.

**Also in this task, because every later task depends on it:** change
`UserDefaultsPreferenceStore.init`'s default from `defaults: UserDefaults = .standard`
to an explicit suite for `com.gcat332.vibecat`. Ruling 2 has the measurement; the
short version is that `.standard` resolves per-executable when there is no bundle
identifier, so the app, `swift run vibecat` and `vibecat-hook` are three
different files today.

- [ ] **Step 1: Write the failing round-trip test**

```swift
@Test func theGeneralAndIntegrationsFieldsSurviveARoundTrip() {
    let store = UserDefaultsPreferenceStore(defaults: .standard, keyPrefix: Self.prefix)
    var p = Preferences()
    // Every field set to the *opposite* of its default, so a `save` that drops
    // one is caught by the value coming back as the default rather than as this.
    p.launchAtLogin = false
    p.expandOnHover = false
    p.hoverDuration = 0.75
    p.smartSuppression = false
    p.hideInFullscreen = false
    p.autoHideWithNoSessions = false
    p.autoCollapseOnMouseLeave = true
    p.autoRevealDwell = 12
    p.dismissRevealOnOutsideClick = true
    p.idleCleanup = .never
    p.disableClickToJump = true
    p.numberKeysPickAnswers = false
    p.confirmDestructiveAnswers = false
    p.autoConfigureNewCLIs = false
    p.replyChannel = .terminal
    store.save(p)

    let back = store.load()
    #expect(back.launchAtLogin == false)
    #expect(back.expandOnHover == false)
    #expect(back.hoverDuration == 0.75)
    #expect(back.smartSuppression == false)
    #expect(back.hideInFullscreen == false)
    #expect(back.autoHideWithNoSessions == false)
    #expect(back.autoCollapseOnMouseLeave == true)
    #expect(back.autoRevealDwell == 12)
    #expect(back.dismissRevealOnOutsideClick == true)
    #expect(back.idleCleanup == .never)
    #expect(back.disableClickToJump == true)
    #expect(back.numberKeysPickAnswers == false)
    #expect(back.confirmDestructiveAnswers == false)
    #expect(back.autoConfigureNewCLIs == false)
    #expect(back.replyChannel == .terminal)
}
```

**Why each assertion can fail:** every field's non-default value differs from
`Preferences()`'s, so a field added to `save` but forgotten in `load` — the
defect this repo has shipped three times — returns the default and fails here.
Use the existing suite's `keyPrefix` fixture; do **not** add a
`removePersistentDomain`, which was measured leaking 175 plists.

- [ ] **Step 2: Run it and watch it fail**

`Scripts/test.sh --filter theGeneralAndIntegrationsFieldsSurviveARoundTrip`
Expected: compile failure — `Preferences` has no member `launchAtLogin`.

- [ ] **Step 3: Add the fields, the two enums, and the save/load pairs**

```swift
/// §14 General's `Idle session cleanup` — `settings.html:252-255`.
///
/// A `TimeInterval?` would be the natural type and is the wrong one: the
/// prototype offers four discrete choices and `Never` is not a duration. The
/// enum keeps "Never" from being spelled as a magic large number, and
/// `seconds` is `nil` for it so `AppModel.prune` reads the absence directly.
public enum IdleCleanup: String, Sendable, CaseIterable, Codable {
    case thirtyMinutes, twoHours, eightHours, never

    public var seconds: TimeInterval? {
        switch self {
        case .thirtyMinutes: 30 * 60
        case .twoHours:      2 * 60 * 60
        case .eightHours:    8 * 60 * 60
        case .never:         nil
        }
    }
}

/// §14 Integrations' `Send answers` — `settings.html:286-289`.
public enum ReplyChannel: String, Sendable, CaseIterable, Codable {
    case hook, terminal, off
}
```

Add the sixteen `public var`s in the prototype's own row order — the order is
documentation, and `Preferences` is read as a schema. Extend `save` and `load`
in `UserDefaultsPreferenceStore` in the same order.

- [ ] **Step 4: Clamp the two numeric fields on the way in**

`hoverDuration` and `autoRevealDwell` are not deadlines the hook waits on, but
both reach an animation or a timer. Clamp in `load`, beside `volume`'s existing
clamp, and state the range's source:

```swift
// `settings.html:224`'s range is `min="0" max="150"` at `data-scale="100"`,
// so 0…1.5s is the prototype's own domain, not a bound invented here.
p.hoverDuration = min(max(raw, 0), 1.5)
// The stepper has no stated range; 1…60s bounds it to something a person
// would choose, and an unbounded dwell parks a panel open forever.
p.autoRevealDwell = min(max(rawDwell, 1), 60)
```

- [ ] **Step 5: Add a clamping test that would fail without the clamp**

```swift
@Test func anAbsurdHoverDurationOutOfThePlistIsClampedRatherThanTrusted() {
    let store = UserDefaultsPreferenceStore(defaults: .standard, keyPrefix: Self.prefix)
    // Written the way another process editing the plist would write it —
    // straight to the key, bypassing `save`, which is the only route by which
    // an out-of-range value can arrive.
    UserDefaults.standard.set(9_999.0, forKey: Self.prefix + "hoverDuration")
    #expect(store.load().hoverDuration == 1.5)
    UserDefaults.standard.set(-4.0, forKey: Self.prefix + "hoverDuration")
    #expect(store.load().hoverDuration == 0)
}
```

Match the real key name and prefix scheme by reading `save`; do not guess it.

- [ ] **Step 6: Run, watch pass, and mutate**

Delete the `min(max(...))` and confirm the clamp test goes red. Delete one line
from `load` and confirm the round-trip test goes red. **Verify the edit applied
before reporting the mutant's colour** — a replacement that never matched the
file reports green and means nothing.

- [ ] **Step 7: Commit**

```bash
git add Sources/VibeCatCore/Preferences.swift Sources/VibeCatCore/PreferenceStore.swift \
        Tests/VibeCatCoreTests/PreferencesTests.swift
git commit -m "feat: the sixteen General and Integrations preferences, clamped on the way in"
```

---

### Task 2: `SettingsStepper` and `SettingsField`

**Files:**
- Create: `Sources/VibeCatUI/Settings/SettingsStepper.swift`
- Create: `Sources/VibeCatUI/Settings/SettingsField.swift`
- Modify: `Sources/VibeCatUI/Settings/SettingsPalette.swift`
- Test: `Tests/VibeCatUITests/Settings/SettingsStepperTests.swift`
- Test: `Tests/VibeCatUITests/Settings/SettingsFieldTests.swift`

**Interfaces:**
- Consumes: `SettingsPalette`, `Raster`/`rasterise` from
  `Tests/VibeCatUITests/Raster.swift`.
- Produces:
  - `SettingsStepper(value: Binding<Int>, in: ClosedRange<Int>, format: (Int) -> String)`
  - `SettingsField(text: Binding<String>, suffix: String? = nil, width: CGFloat = 58)`
  - `SettingsPalette.fieldGround` (`#1F1F22`), `.segPressed` (`#4A4A50`),
    `.danger` (`#FF6B6B`).

**Prototype, verbatim** (`settings.html:95-99`, `:108-110`):

```
.stepper{display:flex;align-items:center;gap:8px;font-size:13px}
.stepper .val{color:var(--bone)}
.stepper button{width:22px;height:24px;background:var(--card2);border:none;border-radius:6px;
                color:var(--haze);font-size:9px;display:grid;place-items:center;line-height:1}
.stepper button:hover{color:var(--bone)}
.field{font:inherit;font-size:12.5px;color:var(--bone);background:#1F1F22;
       border:1px solid var(--line2);border-radius:7px;padding:6px 10px;outline:none}
.field:focus{border-color:var(--accent)}
```

`--line2` already exists in `SettingsPalette`; read it rather than re-deriving.
The prototype's markup is `▲` then `▼`, in that order — increase above decrease
(`:248`, `aria-label="Increase"` first), which is not the macOS convention and is
what the prototype says. The `.val` readout sits *before* both buttons (`:247`).

- [ ] **Step 1: Write the failing tests**

```swift
/// The one thing a stepper must not do: run past its own range. Nothing in the
/// prototype expresses a range, so this is the plan's addition — and it is the
/// assertion that would fail if the buttons simply did `value += 1`.
@Test @MainActor func aStepperStopsAtBothEndsOfItsRange() {
    var v = 5
    let s = SettingsStepper(value: Binding(get: { v }, set: { v = $0 }), in: 1...6) { "\($0)s" }
    s.incrementForTesting(); #expect(v == 6)
    s.incrementForTesting(); #expect(v == 6, "stepped past the top of the range")
    v = 1
    s.decrementForTesting(); #expect(v == 1, "stepped below the bottom of the range")
}

/// `.stepper button{width:22px;height:24px}` and `gap:8px`, against a
/// hand-built replica of the intended box. A size assertion is weak on its own,
/// so this compares two renders differing in exactly one input: the same
/// stepper at two ranges must be *identical*, because range is not a visual
/// property — a stepper that shrank its buttons when disabled at an end would
/// fail here.
@Test @MainActor func aStepperAtTheEndOfItsRangeLooksTheSameAsInTheMiddle() throws {
    func render(_ start: Int, _ range: ClosedRange<Int>) throws -> Raster {
        var v = start
        return try rasterise(
            SettingsStepper(value: Binding(get: { v }, set: { v = $0 }), in: range) { "5s" },
            scale: 4)
    }
    #expect(try render(5, 1...60).samePixels(as: render(60, 1...60)))
}
```

`samePixels(as:)` may not exist — `Raster` is not `Equatable`. **Grep
`Tests/VibeCatUITests/Raster.swift` for the real comparison helper and use
that name.** Inventing a `Raster` API that does not exist has cost this plan's
predecessors four separate compile cycles.

```swift
/// `.field` holds a *string*, not a number, because the prototype's is an
/// `<input>` a user can empty mid-edit. The parse and the clamp belong to the
/// model, not here — and this test is what stops someone "helpfully" making the
/// binding an `Int` and eating a partially-typed value.
@Test @MainActor func aFieldPassesItsTextThroughUnparsed() {
    var t = "30"
    let f = SettingsField(text: Binding(get: { t }, set: { t = $0 }), suffix: "ms")
    f.setTextForTesting("")
    #expect(t == "", "an emptied field was rewritten rather than reported")
}
```

- [ ] **Step 2: Run both, watch them fail**

`Scripts/test.sh --filter Stepper` then `--filter Field`. Expected: compile
failure, no such type. **`--filter` has been unreliable in this repo** — if a
filter reports zero tests run, run the whole target and read the names.

- [ ] **Step 3: Implement both controls**

Hand-drawn, like `SettingsSelect` and `SettingsButton` — not `Stepper` and not
`TextField` with system chrome. `SettingsField` wraps a `TextField` with
`.textFieldStyle(.plain)` so only this file's drawing shows, the same reason
`SettingsButton` uses `.buttonStyle(.plain)`. Expose
`incrementForTesting()`/`decrementForTesting()`/`setTextForTesting(_:)` as
non-`public` hooks, with the doc comment `SettingsButton.actionForTesting`
already carries: no production behaviour is exposed that a release build lacks.

- [ ] **Step 4: Run, watch pass, mutate**

Change `22` to `26` and confirm a size assertion moves. Remove the range clamp
and confirm the stepper test goes red.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatUI/Settings/SettingsStepper.swift \
        Sources/VibeCatUI/Settings/SettingsField.swift \
        Sources/VibeCatUI/Settings/SettingsPalette.swift \
        Tests/VibeCatUITests/Settings/SettingsStepperTests.swift \
        Tests/VibeCatUITests/Settings/SettingsFieldTests.swift
git commit -m "feat: .stepper and .field, the two inline controls General and Integrations need"
```

---

### Task 3: `SettingsSliderRow` and `SettingsNote`

**Files:**
- Create: `Sources/VibeCatUI/Settings/SettingsSliderRow.swift`
- Create: `Sources/VibeCatUI/Settings/SettingsNote.swift`
- Test: `Tests/VibeCatUITests/Settings/SettingsSliderRowTests.swift`

**Interfaces:**
- Consumes: `SettingsPalette`, `SettingsGroup`.
- Produces:
  - `SettingsSliderRow(title: String, value: Binding<Double>, in: ClosedRange<Double>, ticks: Int, format: (Double) -> String)`
  - `SettingsNote(_ text: String)`

**Prototype** (`settings.html:126-136` and `:223-226`, `:188-191`):

```
.slider{display:flex;flex-direction:column;gap:7px;width:100%}
.slider .top{display:flex;align-items:center}
.slider .top b{flex:1;font-size:13px;font-weight:400}
.slider .top .v{font-family:ui-monospace,"SF Mono",Menlo,monospace;font-size:11.5px;color:var(--haze)}
.ticks{display:flex;justify-content:space-between;padding:0 2px}
.ticks i{width:2px;height:2px;border-radius:50%;background:var(--dim);display:block}
.note{display:flex;gap:9px;padding:10px 14px;font-size:11.5px;color:var(--haze);
      line-height:1.55;box-shadow:inset 0 1px 0 var(--line)}
.note i{width:2px;border-radius:2px;background:var(--blue);flex:none}
```

**A tick is a `2×2` round dot in `--dim`, spaced by `justify-content:space-between`
across the track's width less `2px` of padding** — not a `1pt` line. That matters
for the tick-count test below: at `scale: 2` a dot is 4px across, so count
*clusters* rather than columns.

The hover-duration row is `<div class="row" data-shown-by="hoverdur">` wrapping
a `.slider` (`:223-226`) — so it is a **full-width row with no `.lab`/`.ctlarea` split**,
unlike the volume slider `NotificationsPane` already ships, which sits inside a
`180pt` `.ctlarea`. That difference is the reason this is a new component rather
than a reuse. `.note i` is a `2pt` blue rule, full height of the note, `9pt` from the text —
and the note carries `box-shadow:inset 0 1px 0 var(--line)`, the same hairline
`SettingsGroup`'s rows use, so it reads as a final row of the group rather than
as a floating caption.

- [ ] **Step 1: Write the failing test**

```swift
/// Two renders differing in exactly one input. The readout is the only thing a
/// value change may move, so a slider row rendered at 0.30 and at 1.20 must
/// differ — and a row that forgot to draw the readout at all would come back
/// identical, which is the defect this catches.
@Test @MainActor func theSliderRowsReadoutTracksItsValue() throws {
    func render(_ v: Double) throws -> Raster {
        var x = v
        return try rasterise(
            SettingsSliderRow(title: "Hover duration",
                              value: Binding(get: { x }, set: { x = $0 }),
                              in: 0...1.5, ticks: 16) { String(format: "%.2fs", $0) }
                .frame(width: 872),
            scale: 2)
    }
    #expect(!(try render(0.30).samePixels(as: render(1.20))))
}

/// `ticks: 16` is `data-ticks="16"` at `settings.html:226`, and `.ticks`' CSS is
/// `:135-136`. Sixteen marks and
/// none is the assertion; a tick row that silently drew a fixed count would
/// pass any size check and fail this.
@Test @MainActor func theTickCountIsTheOneAsked() throws {
    // Derive the expectation from the rule: count columns containing a tick
    // pixel in the bottom strip of the render, at a scale where a 1pt tick is
    // several pixels wide and cannot be lost to rounding.
}
```

Fill in the second test's body against the real `Raster` API. **Do not widen a
tolerance until it passes** — derive the expected count from `ticks:`.

- [ ] **Step 2: Run, watch fail** — `Scripts/test.sh --filter SliderRow`.

- [ ] **Step 3: Implement both**

- [ ] **Step 4: Run, watch pass, mutate** — hardcode the tick count to 13 and
      confirm the count test goes red.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatUI/Settings/SettingsSliderRow.swift \
        Sources/VibeCatUI/Settings/SettingsNote.swift \
        Tests/VibeCatUITests/Settings/SettingsSliderRowTests.swift
git commit -m "feat: the full-width slider row and the .note strip"
```

---

### Task 4: `SettingsStatusPill`, and `.btn`'s link and danger variants

**Files:**
- Modify: `Sources/VibeCatUI/Settings/SettingsControls.swift`
- Test: `Tests/VibeCatUITests/Settings/SettingsControlsTests.swift`

**Interfaces:**
- Consumes: `SettingsPill`, `PermissionState`, `SettingsButton`,
  `IslandState.idle.accent` / `.waiting.accent`.
- Produces:
  - `SettingsStatusPill(_ state: SettingsStatusPill.State)` where `State` is
    `.active`, `.needsSetup`, `.installed`, `.notInstalled`.
  - `SettingsButton(_ title:, variant: SettingsButton.Variant = .plain, action:)`
    with `Variant` = `.plain | .link | .danger`.

**Why a sibling rather than a generalisation of `SettingsPill`.**
`SettingsPill` takes a `PermissionState` and its three cases are
`Granted`/`Denied`/`Not determined` — a *read of the OS*. Integrations' pills say
`Active`/`Needs setup`/`Installed`/`Not installed`, which are reads of our own
install state, and `.pill.ok`/`.pill.warn` in the prototype are the same two
colours for both. Widening `PermissionState` to carry four more cases would put
"is the hook installed" into a type named for TCC. Share the geometry, not the
vocabulary: extract the `13pt` dot, `9pt` glyph, `5pt` gap, `11.5pt` label into
one private view both use, so a metric fixed in one is fixed in both.

`.pill.warn` is `var(--waiting)` — `IslandState.waiting.accent`, `#FFA63C`. Note
the prototype's warn pill has **no dot** (`:546` renders only the text), while
the ok pill does (`<span class="dot" data-tick>`). That asymmetry is in the
markup; keep it.

- [ ] **Step 1: Write the failing tests**

```swift
/// The two pills that must not be confusable, compared against each other
/// rather than against a colour count — a render with the label emptied still
/// produces eighty-odd colours from everything else and would pass a count.
@Test @MainActor func anActivePillAndANeedsSetupPillDifferInMoreThanText() throws {
    let a = try rasterise(SettingsStatusPill(.active), scale: 4)
    let b = try rasterise(SettingsStatusPill(.needsSetup), scale: 4)
    // `.pill.ok` is `#3FD99B` and `.pill.warn` is `#FFA63C`: assert on the hue
    // only one of them can emit, which is the rule this repo's own testing
    // standards state for a colour assertion.
    #expect(a.contains(IslandState.idle.accent))
    #expect(!a.contains(IslandState.waiting.accent))
    #expect(b.contains(IslandState.waiting.accent))
    #expect(!b.contains(IslandState.idle.accent))
}

/// `.btn.danger{color:#FF6B6B;background:none}` — note `background:none`, so
/// the danger variant is *not* a red-filled button. A wide block of solid
/// colour shouts, which is this project's stated rule for the recommended
/// answer and applies identically to a destructive one.
@Test @MainActor func theDangerVariantIsTintedRatherThanFilled() throws {
    let r = try rasterise(SettingsButton("Uninstall", variant: .danger) {}, scale: 4)
    #expect(r.contains(SettingsPalette.danger))
    #expect(!r.contains(SettingsPalette.card2), "the danger variant drew .btn's plain ground")
}
```

Grep `Raster.swift` for the real `contains`/colour-membership helper before
writing this — `contains(_:tolerance:)` does **not** exist and has been invented
in this repo's plans twice.

- [ ] **Step 2: Run, watch fail.**

- [ ] **Step 3: Implement.** Extract the shared pill geometry; add `Variant` to
      `SettingsButton` without changing its existing call sites' behaviour.

- [ ] **Step 4: Run the whole suite**, not just the filter — `SettingsButton`
      gains a parameter and every existing use must still compile and render
      unchanged.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatUI/Settings/SettingsControls.swift \
        Tests/VibeCatUITests/Settings/SettingsControlsTests.swift
git commit -m "feat: a status pill for install state, and .btn's link and danger variants"
```

---

### Task 5: `GeneralPane`

**Files:**
- Create: `Sources/VibeCatUI/Settings/GeneralPane.swift`
- Create: `Sources/VibeCatUI/Settings/LaunchAtLogin.swift`
- Test: `Tests/VibeCatUITests/Settings/GeneralPaneTests.swift`
- Test: `Tests/VibeCatUITests/Settings/LaunchAtLoginTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–4; `SettingsGroup`, `SettingsRow`,
  `SettingsSectionHeading`, `SettingsSwitch(isOn:)`,
  `SettingsSelect(_:label:)`, `PreferenceStoring`.
- Produces: `GeneralPane(model: GeneralPaneModel)` and
  `@MainActor @Observable final class GeneralPaneModel`, built the way
  `NotificationsPaneModel` is — `init(store: PreferenceStoring, onChange: @escaping (Preferences) -> Void = { _ in })`
  and one `Binding` accessor per field. Also
  `protocol LoginItemControlling { var isEnabled: Bool { get } ; func setEnabled(_: Bool) throws }`
  with `SMAppServiceLoginItem` and `InMemoryLoginItem`.

**Structure — the prototype's five groups, in its order** (`:210-270`):

| Heading | Rows |
|---|---|
| `System` | Launch at Login |
| `Expansion` | Expand notch on hover (reveals) · **Hover duration** slider row · Smart suppression |
| `Visibility` | Hide in fullscreen · Auto-hide when no active sessions |
| `Dismissal` | Auto-collapse on mouse leave · Auto reveal dwell (stepper) · Dismiss auto reveal on outside click · Idle session cleanup (select) |
| `Interaction` | Disable click-to-jump · Number keys pick answers `new` · Confirm destructive answers `new` |

Detail strings are the prototype's `<span>`s **verbatim** — copy them, do not
paraphrase. `Number keys pick answers` (`:263`) and `Confirm destructive answers` (`:266`)
carry `isNew: true`; nothing else on this page does — **`Disable click-to-jump`
at `:260` does not**, which is easy to get wrong because it is the row directly
above them.

**`data-shown-by="hoverdur"` is real behaviour, not decoration.** The hover
duration row exists only while `expandOnHover` is on — the switch at `:222`
carries `data-reveals="hoverdur"`, the row at `:223` carries `data-shown-by`,
and `syncReveals()` at `:628-636` sets `display:none`. It is **removed from
layout, not hidden in place**. A row that stays visible and does nothing when hover is off is a
divergence.

**Launch at login needs a seam.** `SMAppService.mainApp.register()` throws from
a bare binary with no bundle identifier, and `swift test` is exactly that
environment — so a model that calls it directly cannot be tested and will throw
on every test run. `LoginItemControlling` is the seam; `InMemoryLoginItem` is
what tests bind. Record in `LaunchAtLogin.swift`'s doc comment that **the real
path is unverified until someone runs `Scripts/build-app.sh && open .build/VibeCat.app`
and checks System Settings → General → Login Items** — label an unmeasured claim
as unmeasured, in the source.

- [ ] **Step 1: Write the failing tests**

```swift
/// The conditional row, which is the only behaviour on this page that a static
/// render can prove. Two renders differing in exactly one input.
@Test @MainActor func theHoverDurationRowIsAbsentWhileHoverExpansionIsOff() throws {
    func render(_ on: Bool) throws -> Raster {
        let store = InMemoryPreferenceStore(with: { var p = Preferences(); p.expandOnHover = on; return p }())
        return try rasterise(GeneralPane(model: GeneralPaneModel(store: store)).frame(width: 872), scale: 1)
    }
    let with = try render(true), without = try render(false)
    // Derived from the rule rather than measured-then-accepted: the slider row
    // is a `.row` of its own, so removing it must shorten the pane. Assert the
    // *direction and rough size*, and state the derivation.
    #expect(without.height < with.height)
}

/// A model that writes through to the store, for one field, proving the
/// binding is a binding and not a `@State` that forgets. Every other field's
/// accessor is the same shape; this is the one that would catch a copy-paste
/// that bound two rows to the same key.
@Test @MainActor func eachSwitchWritesItsOwnFieldAndNoOther() {
    let store = InMemoryPreferenceStore()
    let m = GeneralPaneModel(store: store)
    m.hideInFullscreenBinding.wrappedValue = false
    let p = store.load()
    #expect(p.hideInFullscreen == false)
    #expect(p.autoHideWithNoSessions == true, "a neighbouring field moved too")
}
```

`InMemoryPreferenceStore` may be named differently — grep
`Tests/VibeCatUITests/Settings/` for the fixture `NotificationsPaneModel`'s
tests use and reuse it.

- [ ] **Step 2: Run, watch fail.**

- [ ] **Step 3: Implement `LaunchAtLogin.swift`, then `GeneralPaneModel`, then
      the pane.** Model first: a pane written before its model tempts you into
      `@State`.

- [ ] **Step 4: Run, watch pass, mutate** — bind two rows to the same field and
      confirm the second test goes red.

- [ ] **Step 5: Render evidence.** Dispatch `render-evidence` for a contact
      sheet of the pane at both hover states, and look at it. A pane that
      compiles and draws thirteen rows in the wrong order passes every test
      above.

- [ ] **Step 6: Commit**

---

### Task 6: `IntegrationsPane`

**Files:**
- Create: `Sources/VibeCatUI/Settings/IntegrationsPane.swift`
- Test: `Tests/VibeCatUITests/Settings/IntegrationsPaneTests.swift`

**Interfaces:**
- Consumes: Tasks 1–4; `SourceRegistry` (`.ids: [String]`,
  `.adapter(for:) -> (any SourceAdapter)?`, and each adapter's `displayName`),
  `SocketPath.default`, `BundledIcon.forSourceID`, `SettingsSegmented`.
- Produces: `IntegrationsPane(model: IntegrationsPaneModel)` and the model.

**Structure — the prototype's four groups** (`:273-320`), noting that `CLI
Hooks` is *two* `.group`s — the CLI list at `:277` and `Auto-configure new CLIs`
in its own group at `:278-282`:

| Heading | Rows |
|---|---|
| `CLI Hooks` | one row per source, then `⊕ Add CLI Branch…` (`.btn.link`, `:548`), then a `.note` (`:549`) |
| *(second group)* | Auto-configure new CLIs |
| `Reply channel` `new` | Send answers (segmented Hook/Terminal/Off, `:286`) · Hook reply timeout (field + `ms`, `:290`) — **two rows, not the prototype's three** |
| `IDE Extensions` | VS Code (pill + `.btn.danger` Uninstall) · JetBrains (pill + `.btn` Install) · a `.note` — `:298-305` |
| `Developer` | Custom Jump Rules (`.btn.link` `Open ↗`) · Socket `new` (mono path + `Reveal`) · Event log `new` (`Open…`) — `:308-319`, heading at `:308` |

**The CLI list comes off `SourceRegistry`, never from a literal.** §3's rule is
that a source is configuration and *"nothing above this line learns their
names"* — a hardcoded `["Claude Code", "Codex", …]` in a view is that rule
broken in the one place a user would notice. The prototype's five entries are
mock data; the real list is whatever
`SourceRegistry.loadingCustomSources(builtIns:…)` resolved at launch, which
includes a user's custom sources. `displayName` is the label,
`BundledIcon.forSourceID(id)` supplies no icon here — the prototype's CLI rows
have **no icon**, only a bold label; do not add one.

**The socket row shows `SocketPath.default`**, in mono at `10.5pt` per
`:314`'s inline `font-size:10.5px`. The prototype's literal string is
`~/Library/Application Support/VibeCat/vibecat.sock` — check that against what
`SocketPath.default` actually returns and record any difference rather than
matching the prototype's string.

**`Carry on if VibeCat isn't running` (`:293-295`) is deliberately absent.**
Ruling 1: fail open is unconditional, so there is no switch and no row. Put that
sentence in `IntegrationsPane`'s own doc comment, with the prototype line number
and a pointer to §2.3 — a reviewer diffing this pane against the prototype will
find a row short and must find the reason here rather than filing it as a defect.
It is the plan's job to make the divergence visible at the place someone meets
it, which is this repo's own stated rule.

**`Hook reply timeout` renders here and is wired in Task 7.** This task builds
the field and the model's parse-and-clamp; Task 7 makes the hook read it.

- [ ] **Step 1: Write the failing tests**

```swift
/// The §3 rule, as an assertion: a registry with one source nobody hardcoded
/// must produce a row for it. A pane with a literal list passes every render
/// test and fails this one.
@Test @MainActor func everyRegisteredSourceGetsARowIncludingOneNobodyHardcoded() throws {
    struct Invented: SourceAdapter {
        let id = "a-cli-invented-by-this-test"
        let displayName = "Invented CLI"
        let jumpStrategy = JumpStrategy.none
        let reports: Set<Kind> = [.running]
        func parse(_ raw: [String: Any], origin: Origin) throws -> VibeEvent? { nil }
    }
    let one = SourceRegistry(adapters: [ClaudeCodeAdapter()])
    let two = SourceRegistry(adapters: [ClaudeCodeAdapter(), Invented()])
    func render(_ r: SourceRegistry) throws -> Raster {
        try rasterise(IntegrationsPane(model: IntegrationsPaneModel(
            store: InMemoryPreferenceStore(), registry: r)).frame(width: 872), scale: 1)
    }
    #expect(try render(two).height > render(one).height,
            "adding a source to the registry did not add a row")
}

/// The socket path shown is the one the app actually listens on. A row that
/// displayed the prototype's literal string would be a lie a user could act on
/// — they are given a `Reveal` button next to it.
@Test @MainActor func theSocketRowShowsTheRealResolvedPathAndNotTheMockupsString() {
    let m = IntegrationsPaneModel(store: InMemoryPreferenceStore(),
                                  registry: SourceRegistry(adapters: []))
    #expect(m.socketPath == SocketPath.default)
}
```

- [ ] **Step 2: Run, watch fail.**

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run, watch pass, mutate** — replace the registry loop with a
      two-element literal and confirm the first test goes red.

- [ ] **Step 5: Render evidence**, as Task 5.

- [ ] **Step 6: Commit**

---

### Task 7: Wire the behaviour that exists, and declare in code what does not

**Files:**
- Modify: `Sources/VibeCatUI/AppModel.swift`
- Modify: `Sources/VibeCatUI/Settings/GeneralPane.swift`
- Modify: `Sources/VibeCatUI/Settings/IntegrationsPane.swift`
- Modify: `Sources/VibeCatTransport/SocketClient.swift`
- Modify: `Sources/VibeCatHookKit/HookRunner.swift`
- Modify: `Sources/vibecat-hook/main.swift`
- Test: `Tests/VibeCatUITests/AppModelTests.swift`
- Test: `Tests/VibeCatUITests/Settings/InertControlsTests.swift`
- Test: `Tests/VibeCatTransportTests/SocketClientTests.swift`
- Test: `Tests/VibeCatHookKitTests/HookRunnerTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `GeneralPane.declaredInert: [String]` and
  `IntegrationsPane.declaredInert: [String]` — the row titles whose preference
  is persisted and read by nothing yet.

**What has machinery today, and must actually work:**

| Row | Wire it to |
|---|---|
| `Idle session cleanup` | `AppModel.prune` — `Self.idleTTL` becomes `preferences.idleCleanup.seconds`, and `nil` means **do not prune at all** |
| `Number keys pick answers` | Plan 6.1's keyboard answering — find the flag it already reads |
| `Confirm destructive answers` | `DestructiveGuard` — find its existing on/off input |
| `Expand notch on hover` + `Hover duration` | `HoverMonitor` / Plan 6.3's reveal clocks |
| `Auto-collapse on mouse leave` | the same |
| `Hook reply timeout` | `SocketClient`'s delivery deadline, read by the hook — ruling 2 |
| `Launch at Login` | `LoginItemControlling` from Task 5 |

**Grep for each flag's current home before adding a second one.** Plan 6.1
shipped keyboard answering and the destructive guard; if either already reads a
constant, this task replaces the constant with the preference — it does not
introduce a parallel switch. Two sources of truth for "are number keys on" is
strictly worse than one hardcoded `true`.

**The hook reading preferences is new plumbing and gets its own steps.** Today
`SocketClient` fixes the delivery deadline as a constant and `vibecat-hook`'s
`main.swift` builds a client with no preferences at all. Three changes, smallest
first:

1. `SocketClient.clampedDelivery(_:) -> TimeInterval` bounding `0.05…2.0`,
   beside the existing `clamped`, with a doc comment saying why the ranges
   differ: one bounds how long a *person* may take, the other how long *IPC* may
   take, and 60 seconds of IPC is §2.3 violated by arithmetic.
2. `SocketClient` takes `deliveryDeadline` as an init parameter defaulting to the
   current constant, so nothing that does not pass one changes behaviour.
3. `vibecat-hook`'s `main.swift` builds a `UserDefaultsPreferenceStore` — which
   after Task 1 points at the explicit suite — reads `hookReplyTimeout`, and
   passes it through `clampedDelivery`.

**The cost of step 3 is on the 300ms path and must be stated.** The hook is a
short-lived process launched on every event; reading a plist adds work before the
socket write. Measure it with `getrusage`, never `ps %cpu`, and record the number.
If it is material, the answer is that the deadline is read once per process and
the process handles one event — not that the feature is dropped.

**What does not, and must say so:**

Everything else — smart suppression, hide in fullscreen, auto-hide with no
sessions, auto reveal dwell, dismiss on outside click, disable click-to-jump
(§13's jump is Plan 6's), auto-configure new CLIs, reply channel's `Terminal`
and `Off`, the per-CLI enable switches and their install status, the IDE
extension rows, custom jump rules, and the event log.

- [ ] **Step 1: Write the failing tests**

```swift
/// `Never` must mean never. A prune that ran anyway with a very large TTL would
/// pass any "did it prune after 2 hours" test and fail this one.
@Test @MainActor func idleCleanupSetToNeverPrunesNothingEver() async throws {
    let m = AppModel(/* the suite's existing fixture shape */)
    // …ingest an idle session, set `idleCleanup = .never`, advance `now` by a
    // year, call `prune(now:)`, and assert the session is still there.
}

/// **The test that would have caught the domain bug**, and the reason ruling 2
/// has a measurement in it. A hook reading `.standard` finds nothing, falls back
/// to 300ms, and looks wired — so asserting "the hook uses 300ms by default"
/// passes either way and proves nothing. This writes a *non-default* value the
/// way the app writes it, then reads it the way the hook reads it.
@Test func theHookReadsTheDeadlineTheAppWroteRatherThanItsOwnDefault() {
    let store = UserDefaultsPreferenceStore(defaults: <the explicit suite>, keyPrefix: Self.prefix)
    var p = store.load()
    p.hookReplyTimeout = 0.85
    store.save(p)
    // Built the way `vibecat-hook`'s `main.swift` builds it — same suite, same
    // prefix, a separate store instance standing in for a separate process.
    let asTheHookSeesIt = UserDefaultsPreferenceStore(defaults: <the explicit suite>,
                                                      keyPrefix: Self.prefix).load()
    #expect(asTheHookSeesIt.hookReplyTimeout == 0.85,
            "the hook's store did not see what the app's store wrote")
}

/// `clampedDelivery` is a *different* range from `clamped`, and this is the
/// assertion that fails if someone routes the delivery deadline through the
/// answer clamp because both are "the deadline clamp".
@Test func aDeliveryDeadlineIsBoundedMuchTighterThanAnAnswerDeadline() {
    #expect(SocketClient.clampedDelivery(30) == 2.0)
    #expect(SocketClient.clamped(30) == 30, "the answer clamp permits 30s and must keep doing so")
    #expect(SocketClient.clampedDelivery(0.001) == 0.05)
}

/// The declared-inert list is the point of this task: it must name every row
/// whose preference nothing reads. The test is a *reminder mechanism*, not a
/// tautology — it fails when a row is added without a ruling either way.
@Test @MainActor func everyRowIsEitherWiredOrDeclaredInert() {
    let general = GeneralPane.allRowTitles
    let wired = GeneralPane.wiredRowTitles
    let inert = GeneralPane.declaredInert
    #expect(Set(wired).isDisjoint(with: Set(inert)), "a row is claimed both wired and inert")
    #expect(Set(wired).union(inert) == Set(general),
            "unclassified: \(Set(general).subtracting(wired).subtracting(inert))")
}
```

**Name what would have to break for the second test to fail:** adding a
fourteenth row to `GeneralPane` without adding its title to either list. That is
a real defect — an unclassified row is exactly the "looks finished, does
nothing" failure this project has already shipped once in the Display pane. If
`allRowTitles` is written by hand, the test is a tautology and worthless; derive
it from the same array the pane's body iterates, or the test is not a test.

- [ ] **Step 2: Run, watch fail.**

- [ ] **Step 3: Implement the wiring.** One row at a time, running the suite
      between each — `AppModel.prune`'s change touches `@Observable`
      notification behaviour, which `prune` already guards.

- [ ] **Step 4: Dispatch `concurrency-auditor`.** `AppModel.prune` and anything
      touching `HoverMonitor`'s clocks are exactly its remit, and the repo's own
      rule is that a change to `AppModel` gets this pass.

- [ ] **Step 5: Run the whole suite three times**, serially. A test that only
      fails under load is a real bug.

- [ ] **Step 6: Commit**

---

### Task 8: Retire the two owner notes and close the plan

**Files:**
- Modify: `Sources/VibeCatUI/Settings/SettingsPage.swift`
- Modify: `Sources/VibeCatUI/Settings/SettingsPane.swift`
- Modify: `Sources/VibeCatUI/Settings/SettingsWindow.swift`
- Modify: `Tests/VibeCatUITests/Settings/SettingsSidebarTests.swift`
- Modify: `docs/superpowers/plans/README.md`
- Modify: `docs/superpowers/specs/2026-07-31-vibecat-design.md` (a dated §14
  correction, if anything here contradicted it — and the fail-open ruling does)

**Interfaces:** consumes Tasks 5–7. Produces nothing new.

- [ ] **Step 1: Make `ownerNote(for:)` return `nil` for both keys**, and follow
      the pattern the `"notifications"` and `"display"` cases already set: the
      absent case gets a comment explaining *why* it is absent, in place of the
      string. That method's doc comment predicted this exact disappearance —
      the comment should note that it is now complete for all four pages.

- [ ] **Step 2: Update `everyPaneWithoutControlsAnnouncesWhichPlanOwnsThem`.**
      Its expected set becomes empty. **A test asserting an empty set is
      usually worthless** — check what it still proves. If nothing, replace it
      with the inverse: every page draws a pane and none draws a note. That is
      the property worth keeping once the schedule is finished.

- [ ] **Step 3: Wire both models in `SettingsWindow`/`SettingsPaneView`**,
      following `notifications:` and `display:`.

- [ ] **Step 4: Run the whole suite** three times, serially, zero warnings.

- [ ] **Step 5: Dispatch `prototype-fidelity`.** Its brief must contain:
      `docs/superpowers/prototypes/settings.html`, the General pane at
      `:210-270`, the Integrations pane at `:273-320`, the `CLIS` renderer at
      `:540-549`, the reveal JS at `:628-636`, and the control CSS at `:95-136`
      / `:188-191`. Ask it to name
      what it compared. A review that never opened the prototype can report
      self-consistency and nothing else — that is the failure this repo wrote a
      whole CLAUDE.md section about.

- [ ] **Step 6: Dispatch `test-premise-auditor`** over every assertion this plan
      added, and act on what it finds.

- [ ] **Step 7: Dispatch `plan-archivist`** to mark 6.7 done in
      `plans/README.md`, carry the findings, and record what this plan
      deliberately left for 6.8 and Plan 6.

- [ ] **Step 8: Commit, then stop.** `main` is pushed but a push publishes —
      ask before pushing, every time.

---

## Out of scope, deliberately

Named so the next reader files these as a schedule rather than a bug.

- **Hook installation.** The per-CLI switches persist and the pills read
  `Needs setup` for everything, because nothing writes a hook into a CLI's
  config yet. That is the substantial engineering behind this page and wants its
  own plan — it edits files in a user's home directory for four different CLIs
  with four different config formats.
- **IDE extensions.** Two rows, two buttons, no extension exists.
- **Event log.** §14 says "the last 500 events with the payload each hook sent";
  nothing records them.
- **§13's jump**, so `Disable click-to-jump` is inert. Plan 6 owns it.
- **Smart suppression** needs to know which terminal tab has focus, which is
  Automation-permission territory and belongs with jump.

**Not out of scope but not present either:** `Carry on if VibeCat isn't running`.
It is *removed by decision*, which is a different thing from deferred — nothing
later will build it. Ruling 1 above is the record, and `IntegrationsPane`'s doc
comment must repeat it.

## Spec follow-up

§14's Integrations line reads *"Reply channel, hook timeout, fail-open"*. After
ruling 1 the third of those is not a control. Task 8 adds a dated §14 correction
in §5.5's form saying so, and why: fail open returns no answer rather than
`allow`, so a switch for it protects nothing and can only hang a terminal.

## Self-review

**Spec coverage.** §14 General lists thirteen items; the table in Task 5 has
thirteen rows. §14 Integrations lists eight items; Task 6's four groups cover
seven of them (`CLI hooks with per-source enable and install status`, `Add CLI
branch`, `Auto-configure new CLIs`, `Reply channel` and `hook timeout`, `IDE
extensions`, `Custom jump rules`, `Socket`, `Event log`) and deliberately do not
cover the eighth, `fail-open`, per ruling 1 — which is why the Spec follow-up
above amends §14 rather than leaving the gap to read as an oversight.

**Placeholders.** Two test bodies are deliberately left as derivations rather
than code — `theTickCountIsTheOneAsked` and `idleCleanupSetToNeverPrunesNothingEver`
— because both depend on a `Raster` and an `AppModel` fixture API this plan must
not guess at. Every such gap says *what to grep for*. That is the compromise
this repo's history argues for: four separate plans shipped invented `Raster`
APIs (`measureHeight`, `contains(_:tolerance:)`, `isTransparent(x:y:)`,
`Raster != Raster`) and each cost a compile cycle. A named grep is more useful
than a confident wrong signature.

**Type consistency.** `IdleCleanup`/`ReplyChannel` are defined in Task 1 and
used in Tasks 5–7 under those names. `LoginItemControlling` is defined in Task 5
and used in Task 7. `SettingsStatusPill.State` is defined in Task 4 and used in
Task 6. `SettingsButton.Variant` likewise. `declaredInert` is produced in Task 7
and consumed by nothing later, which is correct — it exists for a reader and a
test.
