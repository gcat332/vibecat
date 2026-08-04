import SwiftUI

/// `settings.html:106`'s `.sel`, `:111`'s `.btn`, and `:119`'s `.pill` — the
/// three controls Task 3 of Plan 6.5 owes the Notifications page, transcribed
/// rather than approximated the way `SettingsRow.swift` and `SettingsSwitch.swift`
/// already are.

// MARK: - .sel

/// `settings.html:106`'s `.sel`: `13px` `--bone` on `--card2`, radius `7`,
/// padding `5px 9px`.
///
/// **Hand-drawn, like `SettingsSwitch`, and for the same measured reason —
/// checked before assuming it, not after.** A `Picker` styled `.menu` and
/// rasterised through `rasteriseHosted` (the real-AppKit path
/// `SettingsSwitch.swift`'s own doc comment established as the one that
/// actually exercises a control's drawing code) painted a track of roughly
/// `#2E2E30` with label text near `#DFDFDF` — not `--card2 #323236` or
/// `--bone #F2F2F5` — and no modifier tried (`.tint`, `.foregroundStyle`, an
/// explicit `.background`) moved either colour. The same class of gap
/// `SettingsSwitch` already found in `Toggle`.
///
/// A `Menu` with a fully custom `label:` was tried next, on the theory that
/// `Menu`'s label (unlike a `Picker`'s) is ordinary SwiftUI content the caller
/// draws. Two more measurements ruled it out:
///
/// - **`Menu` cannot be rasterised through `rasterise` at all.** `ImageRenderer`
///   returned a solid warning-pattern block (`#FFCC00` and friends covering the
///   whole frame) instead of the label content — the same family of "cannot
///   render this AppKit-bridged view" failure `Raster.swift` already documents
///   for `ScrollView`, just with a different failure shape (a placeholder
///   image rather than a blank one).
/// - **Through `rasteriseHosted`, `.menuStyle(.borderlessButton)` did not
///   respect the label's own layout.** The custom background and padding
///   collapsed to a sliver a few points across regardless of the frame given
///   to the host — `NSPopUpButton`'s own sizing, not ours, wins even when the
///   *content* is fully custom.
///
/// So this draws every pixel itself — box, label, and the options list — from
/// primitives (`Text`, `RoundedRectangle`, `Button` in `.plain` style) that
/// `rasterise` already renders correctly elsewhere in this suite, which is
/// also why `SettingsControlsTests.aSelectShowsTheCurrentValueAndNotTheFirstOne`
/// can use the same plain `ImageRenderer` path every other golden test in this
/// file does, rather than needing `rasteriseHosted`.
///
/// Still a working control, not a static label: tapping opens a plain list of
/// `Value.allCases`, and tapping a row writes the binding and closes it. Real
/// keyboard/VoiceOver semantics for a genuine "select" role are a real gap this
/// leaves — `Button` carries none of `Picker`'s combo-box accessibility traits
/// — and are not tested here for the same reason `SettingsButton`'s action
/// closure is not: this project has no ViewInspector and will not add one, so
/// there is nothing headless that could tell an accessible select apart from
/// an inaccessible one either. Recorded as a gap, not silently assumed away.
public struct SettingsSelect<Value: Hashable & CaseIterable>: View {
    @Binding var selection: Value
    let label: (Value) -> String
    @State private var isOpen = false

    public init(_ selection: Binding<Value>, label: @escaping (Value) -> String) {
        self._selection = selection
        self.label = label
    }

    public var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            // `font-size:13px` — `.sel` carries no letter-spacing rule of its
            // own, unlike `.lab b`'s `-.01em`, so none is applied here.
            Text(label(selection))
                .font(.system(size: 13))
                .foregroundStyle(Color(SettingsPalette.bone))
                .padding(.vertical, 5)
                .padding(.horizontal, 9)
                .background(Color(SettingsPalette.card2))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if isOpen {
                optionsList
                    // Sits below the closed box rather than on top of it —
                    // `28` is the closed box's own rough height (5+5 padding
                    // plus a 13pt line), close enough that the list reads as
                    // hanging off the control rather than floating free.
                    .offset(y: 28)
            }
        }
        .zIndex(isOpen ? 1 : 0)
    }

    private var optionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Value.allCases), id: \.self) { value in
                Button {
                    selection = value
                    isOpen = false
                } label: {
                    Text(label(value))
                        .font(.system(size: 13))
                        .foregroundStyle(Color(SettingsPalette.bone))
                        .padding(.vertical, 5)
                        .padding(.horizontal, 9)
                        .frame(minWidth: 80, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(SettingsPalette.card2))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - .btn

/// `settings.html:111`'s `.btn`: `12.5px` `--bone` on `--card2`, radius `7`,
/// padding `6px 12px`, hover `#3E3E44` (`:113`).
///
/// A plain `Button`, not a hand-drawn control — unlike `.sel`, `.btn`'s whole
/// surface is a `label:` closure, so nothing here routes through `NSButton`'s
/// own chrome the way `Picker`/`Toggle`/`Menu` do. `.buttonStyle(.plain)`
/// strips SwiftUI's own bordered chrome so only this file's drawing shows.
public struct SettingsButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(Color(SettingsPalette.bone))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Color(isHovering ? SettingsButtonMetrics.hover : SettingsPalette.card2))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private enum SettingsButtonMetrics {
    /// `settings.html:113`'s `.btn:hover{background:#3E3E44}`.
    static let hover = RGBA(hex: "#3E3E44")!
}

extension SettingsButton {
    /// Invokes exactly the closure a real tap would, for
    /// `aButtonCallsItsActionExactlyOnce` in `SettingsControlsTests.swift` — the
    /// same shape of hook `PanelBar.toggleMuteForTesting()` already uses, and
    /// for the same reason: this project has no ViewInspector and will not add
    /// one, so **nothing headless can prove which closure a real `Button` tap
    /// is bound to.** This calls the stored closure directly, which is the same
    /// thing a tap does — no production behaviour is exposed here that a
    /// release build would not already have. Not `public`: visible only via
    /// `@testable import`, same reasoning as `NotchController.panelForTesting`.
    func actionForTesting() { action() }
}

// MARK: - .pill

/// A permission row's read of the system, not a boolean — `settings.html`'s own
/// static markup only ever shows the granted case (`:369`, `:373`), because the
/// mockup has no way to represent "ask the OS" at all. `notDetermined` is this
/// plan's own addition; see `SettingsPill`'s doc comment for why it exists and
/// what it looks like.
public enum PermissionState: Sendable, Equatable {
    case granted, denied, notDetermined
}

/// `settings.html:119`'s `.pill`: `11.5px`, `gap:5`, `.ok` → `--idle`,
/// `.warn` → `--waiting`, `.dot` a `13px` circle of `currentColor` holding a
/// `9px` glyph in `#111` (`:122-123`).
///
/// **The colour is the assertion that matters, per this task's own plan
/// section: a permission row that says "Granted" in amber, or "Denied" in
/// green, is a lie about a security state.** `granted` reads `IslandState.idle`
/// and `denied` reads `IslandState.waiting` — not a duplicated hex, per the
/// Global Constraint that `.pill.ok`/`.pill.warn` are the one legitimate place
/// this sheet borrows the island's state hues, because a permission pill
/// really is reporting a state.
///
/// **`notDetermined` is a written divergence, not a silent third thing.** The
/// prototype's own markup never shows it — every `.pill` in `settings.html` is
/// either `.ok` or `.warn` — but decision 2 of this plan reads Automation
/// permission with `askUserIfNeeded: false`, so "the OS has not been asked yet"
/// is a real, reachable state this control must render *something* for. It is
/// drawn neither green nor amber — either would claim a security fact nobody
/// has established — but `SettingsPalette.haze`, the sheet's own neutral
/// secondary-text grey, with a `?` glyph in its dot rather than the granted
/// tick or the denied cross. Not tested for its exact colour the way granted
/// and denied are (there is no state hue it needs to avoid colliding with —
/// `haze` is not in `IslandState`'s vocabulary at all), but recorded here so a
/// future reader finds the decision rather than reconstructing it.
public struct SettingsPill: View {
    let state: PermissionState

    public init(_ state: PermissionState) {
        self.state = state
    }

    private var colour: RGBA {
        switch state {
        case .granted:      IslandState.idle.accent
        case .denied:        IslandState.waiting.accent
        case .notDetermined: SettingsPalette.haze
        }
    }

    private var text: String {
        switch state {
        case .granted:       "Granted"
        case .denied:         "Denied"
        case .notDetermined:  "Not determined"
        }
    }

    private var glyph: String {
        switch state {
        case .granted:       "checkmark"
        case .denied:         "xmark"
        case .notDetermined:  "questionmark"
        }
    }

    public var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(colour))
                .frame(width: 13, height: 13)
                .overlay {
                    Image(systemName: glyph)
                        .font(.system(size: 9, weight: .bold))
                        // `.dot svg{color:#111}` — the glyph sits in the near-
                        // black `settings.html` gives it regardless of which
                        // state coloured the dot underneath it.
                        .foregroundStyle(Color(RGBA(hex: "#111111")!))
                }
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Color(colour))
        }
    }
}
