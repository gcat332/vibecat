import SwiftUI

/// The switch `settings.html` draws 28 times (`.sw`, lines 87-93): `38×22`,
/// corner radius `11`, an `18×18` knob inset `2pt` from the top-left, sliding
/// `16pt` on `isOn`, off-track `#48484E`, on-track system blue, and a `2pt`
/// focus ring at a `2pt` outset.
///
/// **This is a hand-drawn control, and here is the measurement that decided
/// it rather than assuming either way (`docs/superpowers/plans/2026-08-03-settings-shell.md`,
/// Task 2, Step 1).** A native `Toggle("", isOn:).toggleStyle(.switch)` was
/// rasterised headlessly through `Tests/VibeCatUITests/Raster.swift`'s
/// `rasteriseHosted` (the `ImageRenderer` path draws AppKit controls as flat,
/// untinted colour blocks in this offscreen context — `rasteriseHosted`'s real
/// `NSWindow` + `cacheDisplay(in:to:)` path is the one that actually exercises
/// `NSSwitch`'s drawing code):
///
/// - **Drawn size:** `54×24pt`, against the prototype's `38×22` — **16pt wider,
///   roughly 42%,** not "within about a point".
/// - **Knob travel:** `18pt`, against the prototype's `16pt`.
/// - **On-state colour:** the native control's track did **not** turn blue for
///   `isOn == true` in this render path — on and off measured the same
///   `#47474A`-ish grey, and neither an explicit `.tint(Color(#0A84FF))` nor a
///   `.frame(width: 38, height: 22)` constraint changed the drawn size or
///   colour at all. `NSSwitch`'s chrome is not stylable to the mockup's spec
///   through the modifiers SwiftUI exposes for it.
///
/// Both facts point the same way, so this draws to the prototype's own
/// geometry instead of wrapping the native control. It is still a genuine
/// `Toggle` under a custom `ToggleStyle` — not a `Button` reimplementing one —
/// specifically so the accessibility role, the value ("on"/"off"), and
/// Full Keyboard Access's Space-to-activate stay the platform's own rather than
/// something this file would have to reinvent and could get wrong.
public struct SettingsSwitch: View {
    @Binding var isOn: Bool

    public init(isOn: Binding<Bool>) {
        self._isOn = isOn
    }

    public var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(SettingsSwitchStyle())
            .labelsHidden()
    }
}

/// Draws `settings.html:87-93`'s geometry and colours. Kept private —
/// `SettingsSwitch` is the public surface, this is only how it paints.
private struct SettingsSwitchStyle: ToggleStyle {
    static let trackSize = CGSize(width: 38, height: 22)
    static let knobDiameter: CGFloat = 18
    static let knobInset: CGFloat = 2
    /// `translateX(16px)` — `settings.html:92`.
    static let knobTravel: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        let isOn = configuration.isOn
        RoundedRectangle(cornerRadius: Self.trackSize.height / 2)
            .fill(Color(isOn ? SettingsPalette.systemBlue : SettingsPalette.switchOff))
            .frame(width: Self.trackSize.width, height: Self.trackSize.height)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: Self.knobDiameter, height: Self.knobDiameter)
                    .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                    .padding(.leading, Self.knobInset)
                    .offset(x: isOn ? Self.knobTravel : 0)
            }
            .animation(.easeInOut(duration: 0.18), value: isOn)
            .contentShape(Rectangle())
            .onTapGesture { configuration.isOn.toggle() }
            .focusable()
            .onKeyPress(.space) {
                configuration.isOn.toggle()
                return .handled
            }
            // `Toggle` already carries the platform's own switch accessibility
            // role and On/Off value even under a custom `ToggleStyle` — this
            // just keeps that value explicit rather than trusting it silently,
            // since the whole point of a custom style is that everything else
            // about the drawing is now this file's responsibility.
            .accessibilityValue(isOn ? "on" : "off")
    }
}
