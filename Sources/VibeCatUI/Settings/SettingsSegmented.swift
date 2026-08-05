import SwiftUI

/// `settings.html:101-104`'s `.seg`: container `background:#1F1F22`,
/// `border-radius:8px`, `padding:2px`, `gap:2px`; each button `font-size:12px`,
/// `color:var(--haze)`, `padding:5px 11px`, `border-radius:6px`; the pressed
/// button `background:#4A4A50`, `color:var(--bone)`.
///
/// **One control, not two.** The plan flagged that two of the prototype's five
/// segmented-looking rows — Clean/Detailed, `settings.html:393-398` — carry a
/// `<b>` title *and* an `<em>` description inside each button, and asked
/// whether that needs a second variant here. It does not, because that row is
/// not a `.seg` at all: it is `.modes`/`.mode` (`:154-164`), a **different CSS
/// class** with its own container (`gap:10px`, no pill background), its own
/// pressed state (a `2px` blue **border**, not a background fill), and its own
/// content (a `.mini` preview swatch plus `<b>`/`<em>`, not a bare label). Every
/// real `.seg` in the prototype — `Hook`/`Terminal`/`Off` (`:288`, Integrations,
/// out of scope here), `Count`/`Agent icon`/`Nothing` and `On hover`/`Always`/
/// `Never` (`:409`, `:412`), `Cat`/`Meter`/`Dot` (`:420`), and `Full`/`Reduced`/
/// `Off` (`:502`) — is a plain label, no exceptions. So this type covers every
/// shipping `.seg` use with room to spare, and Clean/Detailed's `.mode` is a
/// distinct control that belongs with whoever ships Clean/Detailed itself —
/// building it here would be speculative work for a control with no caller.
///
/// **Measured against the native `Picker(.segmented)` before drawing this by
/// hand, the standard `SettingsSwitch` and `SettingsSelect` set.** Bound to a
/// three-case `Standard`/`Meow`/`None` choice and rasterised two ways:
///
/// - **Through `ImageRenderer` (`rasterise`):** the same failure class already
///   on record for `Menu` (`SettingsSelect`'s own doc comment) — a solid
///   gradient of warning-pattern colour (`#FFCC00` down through orange and red)
///   covering the whole `200×24` frame, not the control's actual chrome. Not a
///   rendering path this control could use even if the colours matched.
/// - **Through `rasteriseHosted`'s real `NSWindow` + `cacheDisplay(in:to:)`
///   path** — the one that correctly draws `NSSwitch` and a `ScrollView`
///   elsewhere in this suite — the segmented control drew **nothing at all**.
///   Composited over a magenta test backdrop chosen specifically to collide
///   with no colour in this palette, the entire `400×60` capture came back
///   magenta-family pixels only: no grey chrome, no bevel, no pressed fill,
///   *0%* of the frame drawn. (An earlier pass backed the same capture with a
///   near-`#1F1F22` colour on the theory that it looked closer to "dark
///   background," and that produced a smooth grey-to-white gradient across the
///   whole frame — which looked like real chrome until the backdrop was
///   swapped for magenta and the same continuous ramp reappeared unchanged: an
///   interpolation artefact of the near-black backdrop against itself, not the
///   control. Recorded because it is exactly the kind of contaminated
///   measurement `CLAUDE.md` warns a colour-count assertion can produce.)
/// - **Unconstrained intrinsic size** (`NSHostingView.fittingSize`, no frame
///   applied): `236×24` for those three labels. Height alone is a real,
///   smaller-magnitude gap than `SettingsSwitch`'s Toggle finding — `24pt`
///   against the prototype's own `2 + 5 + ~14.4 + 5 + 2 ≈ 28.4pt` (container
///   padding, button padding, a `12px` line at the browser's default
///   `1.2×`-ish line-height, button padding, container padding) is about 15%
///   short, not 42% — but it is moot next to the invisibility above.
///
/// Both facts point the same way as `SettingsSwitch`'s and `SettingsSelect`'s
/// own measurements: hand-drawn, from `Text`, `RoundedRectangle` and `Button`
/// in `.plain` style, the same primitives this suite already rasterises
/// correctly elsewhere.
///
/// A real `Picker` still backs assistive technology, exactly as
/// `SettingsSelect` does and for the same reason — the drawing above is never
/// what accessibility sees.
public struct SettingsSegmented<Value: Hashable & CaseIterable>: View {
    @Binding var selection: Value
    let label: (Value) -> String

    public init(_ selection: Binding<Value>, label: @escaping (Value) -> String) {
        self._selection = selection
        self.label = label
    }

    public var body: some View {
        HStack(spacing: SettingsSegmentedMetrics.gap) {
            ForEach(Array(Value.allCases), id: \.self) { value in
                let isPressed = value == selection
                Button {
                    selection = value
                } label: {
                    Text(label(value))
                        .font(.system(size: SettingsSegmentedMetrics.fontSize))
                        .foregroundStyle(Color(isPressed ? SettingsPalette.bone : SettingsPalette.haze))
                        .padding(.vertical, SettingsSegmentedMetrics.buttonVerticalPadding)
                        .padding(.horizontal, SettingsSegmentedMetrics.buttonHorizontalPadding)
                        .background(isPressed ? Color(SettingsSegmentedMetrics.pressed) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: SettingsSegmentedMetrics.buttonRadius))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(SettingsSegmentedMetrics.containerPadding)
        .background(Color(SettingsSegmentedMetrics.container))
        .clipShape(RoundedRectangle(cornerRadius: SettingsSegmentedMetrics.containerRadius))
        // A native control for assistive tech, the drawn one for everyone else
        // — see this type's own doc comment and `SettingsSelect.body`, which
        // does the same thing for the same reason.
        .accessibilityRepresentation {
            Picker("", selection: $selection) {
                ForEach(Array(Value.allCases), id: \.self) { value in
                    Text(label(value)).tag(value)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

/// `.seg`'s geometry and colour, `settings.html:101-104`. Internal rather than
/// private so `SettingsSegmentedTests` can predict each segment's own box from
/// the same numbers this view draws with, rather than a value copied out by
/// hand and liable to drift from it.
enum SettingsSegmentedMetrics {
    static let containerPadding: CGFloat = 2
    static let gap: CGFloat = 2
    static let buttonVerticalPadding: CGFloat = 5
    static let buttonHorizontalPadding: CGFloat = 11
    static let buttonRadius: CGFloat = 6
    static let containerRadius: CGFloat = 8
    static let fontSize: CGFloat = 12
    static let container = RGBA(hex: "#1F1F22")!
    static let pressed = RGBA(hex: "#4A4A50")!
}
