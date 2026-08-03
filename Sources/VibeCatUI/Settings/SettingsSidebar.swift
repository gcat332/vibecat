import SwiftUI

/// The window's `196pt` nav — `settings.html:53`, `.side{width:196px;flex:none;
/// background:var(--pane);border-right:1px solid var(--line);padding:10px 8px}`
/// — and the four rows in it (`.nav`, `:54-63`).
///
/// `196` is the whole width *including* the right border, because the prototype
/// sets `box-sizing:border-box` on everything (`settings.html:29`): the border is
/// drawn as an overlay inside the frame rather than added to it, so the sidebar
/// takes exactly the space the CSS says and the pane beside it starts at `196`.
///
/// **Selection is a page key, never an index** — the same reason
/// `Preferences.selectedPage` is: reordering the four pages must not silently
/// move someone to a different one.
public struct SettingsSidebar: View {
    @Binding private var selection: String

    public init(selection: Binding<String>) {
        self._selection = selection
    }

    /// `settings.html:53`.
    static let width: CGFloat = 196

    public var body: some View {
        VStack(spacing: 0) {
            // No spacing between rows: `.nav` is a full-width block with its own
            // `padding:6px 8px` and no margin, so the prototype's rows touch.
            ForEach(SettingsPage.all) { page in
                SettingsNavRow(page: page, isCurrent: page.key == selection) {
                    selection = page.key
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(width: Self.width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(SettingsPalette.pane))
        .overlay(alignment: .trailing) {
            // `border-right:1px solid var(--line)`. **`SettingsPalette.hairline`
            // is stored as opaque white** — `RGBA` has no alpha channel — so the
            // `.08` has to be applied here, by the caller, exactly as that
            // property's own doc comment says. Getting this wrong draws a bright
            // white rule down the middle of the window, which is why
            // `theSidebarsRightBorderIsTheHairlineAndNotOpaqueWhite` asserts on
            // the blended value rather than merely on "something was drawn".
            Rectangle()
                .fill(Color(SettingsPalette.hairline).opacity(SettingsPalette.hairlineOpacity))
                .frame(width: 1)
        }
    }
}

/// One `.nav` row: `settings.html:54-63`. A `24pt` chip, a `10pt` gap, a `13pt`
/// label, `6/8` padding inside a `7pt` corner radius, and a background that is
/// `rgba(255,255,255,.11)` for the current page and `.05` under the pointer.
///
/// **Nothing here animates**, and that is a decision rather than an omission.
/// The prototype's `transition:background 120ms var(--ease)` is real, but this
/// repo's rule is that everything animated resolves through
/// `MotionPreference.resolve` — and this view, like `PanelBar`, is handed no
/// motion preference to resolve against. An animation left in that quietly
/// ignores a request for reduced motion is worse than an instant state change,
/// so the swap is instantaneous and recorded here, the same way `MuteIcon`'s is.
private struct SettingsNavRow: View {
    let page: SettingsPage
    let isCurrent: Bool
    let select: () -> Void

    @State private var hovering = false

    /// `.nav[aria-current="true"]{background:rgba(255,255,255,.11)}` and
    /// `.nav:hover{background:rgba(255,255,255,.05)}`. Current wins: the
    /// prototype declares `[aria-current]` after `:hover`, so the selected row
    /// does not dim when the pointer crosses it.
    private var backgroundOpacity: Double {
        if isCurrent { 0.11 } else if hovering { 0.05 } else { 0 }
    }

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                SettingsChip(page: page)
                Text(page.label)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(SettingsPalette.bone))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // `border-radius:7px`, circular as every CSS radius is — see
                // `SettingsChip`'s own note on not reaching for `.continuous`.
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(backgroundOpacity))
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        // `aria-current="true"` on the selected `.nav`. The trait is what makes
        // the highlight readable to something that cannot see 11% white.
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}
