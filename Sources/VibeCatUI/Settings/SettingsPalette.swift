import Foundation

/// The Settings sheet's own ink — deliberately **not** the island's.
///
/// `settings.html:9-27` declares a token set that shares some *names* with the
/// island's (`--dim`, `--bone`, `--haze`) at **different values**, and one name,
/// `--accent`, that means a different *thing* entirely: system blue here, the
/// current session state's colour in the island (`IslandState.accent`,
/// `IslandState.swift`). §4.3 makes colour mean state and only state in the
/// island; a Settings switch is blue because it is on, never because some agent
/// somewhere is blocked. Reaching for `IslandState.waiting.accent` to tint a
/// switch would paint it amber for a reason that has nothing to do with the
/// switch.
///
/// So this enum is a separate token set, on purpose: it does not extend or
/// import the island's, and there is deliberately no member named `accent` —
/// spelling out `systemBlue` instead means a reader who greps for `accent` finds
/// only the island's, which is the one that means state. The other names
/// (`hairline` not `line`, `background` not `bg`) diverge from `settings.html`'s
/// own CSS variable names for the same reason.
///
/// The four state hues (`--idle`, `--running`, `--waiting`, `--error`) are **not**
/// duplicated here even though `settings.html` carries them at values identical
/// to the island's — they exist there only to preview the island on the Display
/// page, which is the one place state colour belongs in a settings sheet.
/// `theStateHuesInSettingsAreTheIslandsExactlyBecauseTheyPreviewIt` in
/// `SettingsPaletteTests.swift` asserts the two stay in agreement without this
/// enum needing to hold a copy.
public enum SettingsPalette {
    /// `settings.html:10` — the window's own ground, one level up from the
    /// island's `#07080A`.
    public static let background = RGBA(hex: "#1C1C1E")!
    /// `settings.html:11` — the titlebar.
    public static let chrome = RGBA(hex: "#232326")!
    /// `settings.html:12` — the sidebar.
    public static let pane = RGBA(hex: "#161618")!
    /// `settings.html:13` — a settings group's card.
    public static let card = RGBA(hex: "#2A2A2D")!
    /// `settings.html:14` — `rgba(255,255,255,.08)`, the hairline between rows.
    /// `RGBA` carries no alpha channel (see `Color(_:)` at `IslandView.swift:8`,
    /// which only reads `r`/`g`/`b`) — every other token here is fully opaque, so
    /// adding a fourth stored property to a type nothing else needs one on would
    /// be the wrong place to plumb it through. This is the colour component;
    /// a caller draws it at 8% the way `settings.html`'s own CSS does, e.g.
    /// `Color(SettingsPalette.hairline).opacity(0.08)`.
    public static let hairline = RGBA(r: 1, g: 1, b: 1)
    /// `settings.html:16` — primary text.
    public static let bone = RGBA(hex: "#F2F2F5")!
    /// `settings.html:17` — secondary/description text.
    public static let haze = RGBA(hex: "#9A9AA2")!
    /// `settings.html:18` — the dimmest label ink. **Not** the island's dim
    /// (`#5A6273`, `IslandState.dormant.accent`) — the collision this file
    /// exists to avoid.
    public static let dim = RGBA(hex: "#6A6A74")!
    /// `settings.html:19`, `--blue`. What `--accent` resolves to in Settings,
    /// unconditionally — never a session state's colour.
    public static let systemBlue = RGBA(hex: "#0A84FF")!
    /// `settings.html:88` — `.sw`'s un-toggled track colour.
    public static let switchOff = RGBA(hex: "#48484E")!
}
