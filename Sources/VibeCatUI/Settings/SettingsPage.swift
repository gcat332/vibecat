import SwiftUI

/// One of Settings' four pages: its key, its label, its chip colour and the
/// glyph inside that chip.
///
/// **The icon lives here, on the page, because two places draw it.**
/// `settings.html:532` says so in the prototype's own words — *"the pane
/// headings reuse the sidebar's icon so the two always agree"* — and then does
/// it, building both `.nav`'s chip and `.ptitle`'s chip out of the same `NAVS`
/// entry (`:525-538`). Declaring the glyph twice, once per call site, is the
/// failure that comment exists to prevent, so `SettingsChip(page:)` is the only
/// thing in this module that draws one and both surfaces call it.
///
/// **The four chip colours are macOS system colours, not this app's state
/// vocabulary.** Nothing here means `running` or `waiting`: Notifications' red is
/// `#FF3B30`, deliberately *not* `IslandState.failed.accent`'s `#FF5C5C`, and
/// `eachPageWearsItsOwnChipColourAndNoneIsAStateColour` in
/// `SettingsSidebarTests.swift` pins that none of the four ever collides with a
/// state hue. §4.3's "colour means state" is a rule about the island; a settings
/// sidebar is not the island, and a person reading a red bell must not be led to
/// think something failed.
public struct SettingsPage: Sendable, Equatable, Identifiable {
    public let key: String
    public let label: String
    public let chip: RGBA
    /// The glyph in the chip — the one the sidebar row and the pane heading
    /// both draw. See this type's own doc comment for why it is a property of
    /// the page rather than of either view.
    public let icon: SettingsPageIcon

    public var id: String { key }

    public init(key: String, label: String, chip: RGBA, icon: SettingsPageIcon) {
        self.key = key
        self.label = label
        self.chip = chip
        self.icon = icon
    }

    /// `settings.html:519-524`'s `NAVS`, in its order — which is also the order
    /// the panes appear in the document (`:210`, `:273`, `:323`, `:379`) and the
    /// order `SettingsPageKey.all` lists, since `VibeCatCore` has to reject a key
    /// that no longer names a pane and cannot see this file.
    public static let all: [SettingsPage] = [
        SettingsPage(key: "general", label: "General",
                     chip: RGBA(hex: "#6E6E73")!, icon: .gear),
        SettingsPage(key: "integrations", label: "Integrations",
                     chip: RGBA(hex: "#32ADE6")!, icon: .plug),
        SettingsPage(key: "notifications", label: "Notifications",
                     chip: RGBA(hex: "#FF3B30")!, icon: .bell),
        SettingsPage(key: "display", label: "Display",
                     chip: RGBA(hex: "#5E5CE6")!, icon: .letterforms),
    ]

    /// The page a stored key names, or `nil`.
    ///
    /// Deliberately *not* falling back to `all[0]` here: the two callers want
    /// different things from an unknown key, and folding them into one silent
    /// default is how a window ends up showing General while its stored
    /// preference says something else. `SettingsShell` resolves an unknown key to
    /// the first page because a pane has to draw *something*;
    /// `SettingsWindowController.init` clamps to `Preferences()`'s own default so
    /// the fact "the default page is General" stays in one place.
    public static func page(for key: String) -> SettingsPage? {
        all.first { $0.key == key }
    }

    /// Which plan owns the controls this page will grow, in the words the pane
    /// puts on its own face.
    ///
    /// **Plan 6.4 ships this window's chrome and none of its controls** (its own
    /// "Out of scope, deliberately"), so every pane says so. A pane that looks
    /// finished and does nothing is worse than one that names its owner: the next
    /// reader files the first as a bug and the second as a schedule.
    ///
    /// Returns `String?` rather than `String` because that is the shape the
    /// plan's own test asserts on, and because the answer genuinely disappears —
    /// once 6.5 lands the Notifications controls, that page's note goes away and
    /// this returns `nil` for it while the other three still have one.
    public static func ownerNote(for key: String) -> String? {
        switch key {
        case "general":
            "This page's controls are Plan 6.7's — launch at login, hover expansion, "
                + "visibility, dismissal and the interaction switches. Plan 6.4 built the "
                + "window, the sidebar and this heading."
        case "integrations":
            "This page's controls are Plan 6.7's — the per-CLI hook list, the reply "
                + "channel and the IDE extensions. Plan 6.4 built the window, the sidebar "
                + "and this heading."
        // `"notifications"` deliberately absent: Plan 6.5 shipped its controls,
        // so this returns `nil` for it and `SettingsPaneView` draws
        // `NotificationsPane` in the note's place. This is the disappearance the
        // `String?` return type was chosen for — see this method's own doc
        // comment, which predicted exactly this case.
        case "display":
            "This page's controls are Plan 6.6's — the notch preview, the flanks, the "
                + "cat's coat, the panel sizes, the session card and the motion control. "
                + "Plan 6.4 built the window, the sidebar and this heading."
        default:
            nil
        }
    }
}

// MARK: - the glyphs

/// The four `NAVS` glyphs, transcribed from `settings.html:520-523`'s own `d`
/// attributes into the same `24×24` viewBox they are authored in.
///
/// Same shape of port, and for the same reasons, as `CLIMark` (`CLIMark.swift`):
/// coordinates stay in the prototype's viewBox so they read against the SVG they
/// came from, and are scaled once at draw time. The prototype's own
/// `stroke-width` and `fill` choice per icon come along with the geometry —
/// `general` is the one filled glyph (`fill="currentColor"`, `stroke-width="0"`),
/// the other three are stroked at `2` with round caps and joins
/// (`settings.html:528-529`).
public enum SettingsPageIcon: String, Sendable, Equatable, CaseIterable {
    /// General's gear.
    case gear
    /// Integrations' plug.
    case plug
    /// Notifications' bell.
    case bell
    /// Display's letterforms — an `A` and a `P`, which is what the prototype's
    /// path data actually draws (`M4 18 8 6l4 12` and `M14 18v-7.5h2.6a2.4 2.4 0
    /// 0 1 0 4.8H14`), not a screen.
    case letterforms

    /// The prototype's own viewBox, exactly as `CLIMark.viewBox` keeps
    /// `island-motion.html`'s.
    public static let viewBox: CGFloat = 24

    /// `settings.html:529` — `stroke-width="${k==='general'?0:2}"`.
    public var lineWidth: CGFloat { self == .gear ? 0 : 2 }

    /// The stroked half, in the `24×24` viewBox. `nil` for `gear`, which the
    /// prototype fills instead.
    public var strokedPath: Path? {
        switch self {
        case .gear:
            return nil
        case .plug:
            // `M4 7.5h9a3.5 3.5 0 0 1 0 7H4zM20 9.5v5M17 10.5v3`
            var p = Path()
            p.move(to: CGPoint(x: 4, y: 7.5))
            p.addLine(to: CGPoint(x: 13, y: 7.5))
            addSVGArc(to: &p, from: CGPoint(x: 13, y: 7.5), to: CGPoint(x: 13, y: 14.5),
                      radius: 3.5, largeArc: false, sweep: true)
            p.addLine(to: CGPoint(x: 4, y: 14.5))
            p.closeSubpath()
            p.move(to: CGPoint(x: 20, y: 9.5))
            p.addLine(to: CGPoint(x: 20, y: 14.5))
            p.move(to: CGPoint(x: 17, y: 10.5))
            p.addLine(to: CGPoint(x: 17, y: 13.5))
            return p
        case .bell:
            // `M12 3a6 6 0 0 0-6 6v4l-1.6 2.6h15.2L18 13V9a6 6 0 0 0-6-6z`
            // plus the clapper, `M9.8 19a2.3 2.3 0 0 0 4.4 0`.
            var p = Path()
            p.move(to: CGPoint(x: 12, y: 3))
            addSVGArc(to: &p, from: CGPoint(x: 12, y: 3), to: CGPoint(x: 6, y: 9),
                      radius: 6, largeArc: false, sweep: false)
            p.addLine(to: CGPoint(x: 6, y: 13))          // v4
            p.addLine(to: CGPoint(x: 4.4, y: 15.6))      // l-1.6 2.6
            p.addLine(to: CGPoint(x: 19.6, y: 15.6))     // h15.2
            p.addLine(to: CGPoint(x: 18, y: 13))         // L18 13
            p.addLine(to: CGPoint(x: 18, y: 9))          // V9
            addSVGArc(to: &p, from: CGPoint(x: 18, y: 9), to: CGPoint(x: 12, y: 3),
                      radius: 6, largeArc: false, sweep: false)
            p.closeSubpath()
            p.move(to: CGPoint(x: 9.8, y: 19))
            addSVGArc(to: &p, from: CGPoint(x: 9.8, y: 19), to: CGPoint(x: 14.2, y: 19),
                      radius: 2.3, largeArc: false, sweep: false)
            return p
        case .letterforms:
            // `M4 18 8 6l4 12` — the A. `M5.6 14.4h4.8` — its crossbar.
            // `M14 18v-7.5h2.6a2.4 2.4 0 0 1 0 4.8H14` — the P.
            var p = Path()
            p.move(to: CGPoint(x: 4, y: 18))
            p.addLine(to: CGPoint(x: 8, y: 6))
            p.addLine(to: CGPoint(x: 12, y: 18))
            p.move(to: CGPoint(x: 5.6, y: 14.4))
            p.addLine(to: CGPoint(x: 10.4, y: 14.4))
            p.move(to: CGPoint(x: 14, y: 18))
            p.addLine(to: CGPoint(x: 14, y: 10.5))
            p.addLine(to: CGPoint(x: 16.6, y: 10.5))
            addSVGArc(to: &p, from: CGPoint(x: 16.6, y: 10.5), to: CGPoint(x: 16.6, y: 15.3),
                      radius: 2.4, largeArc: false, sweep: true)
            p.addLine(to: CGPoint(x: 14, y: 15.3))
            return p
        }
    }

    /// The filled half, in the `24×24` viewBox. Only `gear` has one.
    ///
    /// **Both of the gear's subpaths wind the same way, so the centre circle is
    /// not a hole under the non-zero fill rule** — and this transcription keeps
    /// the winding rather than "fixing" it, because SwiftUI's default `.fill()`
    /// is non-zero exactly as SVG's default `fill-rule` is, so whatever the
    /// browser draws for `settings.html` is what this draws. Confirmed against a
    /// real render of the prototype in Chrome during this task's fidelity pass —
    /// the browser's chip is a solid gear silhouette, and so is ours. Reaching
    /// for `FillStyle(eoFill: true)` here would have produced a hole the
    /// prototype does not have.
    public var filledPath: Path? {
        switch self {
        case .plug, .bell, .letterforms:
            return nil
        case .gear:
            var p = Path()
            // `M12 15.4a3.4 3.4 0 1 0 0-6.8 3.4 3.4 0 0 0 0 6.8z` — the hub,
            // as two half-circles, the way the prototype writes it.
            p.move(to: CGPoint(x: 12, y: 15.4))
            addSVGArc(to: &p, from: CGPoint(x: 12, y: 15.4), to: CGPoint(x: 12, y: 8.6),
                      radius: 3.4, largeArc: true, sweep: false)
            addSVGArc(to: &p, from: CGPoint(x: 12, y: 8.6), to: CGPoint(x: 12, y: 15.4),
                      radius: 3.4, largeArc: false, sweep: false)
            p.closeSubpath()
            // `M19.5 12c0-.5 0-1-.1-1.5l2-1.5-2-3.4-2.3 1a7.6 7.6 0 0 0-2.6-1.5
            //  L14.2 2.5H9.8l-.3 2.6c-1 .3-1.8.8-2.6 1.5l-2.3-1-2 3.4 2 1.5
            //  c-.1.5-.1 1-.1 1.5s0 1 .1 1.5l-2 1.5 2 3.4 2.3-1c.8.7 1.6 1.2 2.6 1.5
            //  l.3 2.6h4.4l.3-2.6c1-.3 1.8-.8 2.6-1.5l2.3 1 2-3.4-2-1.5
            //  c.1-.5.1-1 .1-1.5z` — the body, absolute coordinates resolved once
            // here so each vertex reads against the relative run it came from.
            p.move(to: CGPoint(x: 19.5, y: 12))
            p.addCurve(to: CGPoint(x: 19.4, y: 10.5),
                       control1: CGPoint(x: 19.5, y: 11.5), control2: CGPoint(x: 19.5, y: 11))
            p.addLine(to: CGPoint(x: 21.4, y: 9))
            p.addLine(to: CGPoint(x: 19.4, y: 5.6))
            p.addLine(to: CGPoint(x: 17.1, y: 6.6))
            addSVGArc(to: &p, from: CGPoint(x: 17.1, y: 6.6), to: CGPoint(x: 14.5, y: 5.1),
                      radius: 7.6, largeArc: false, sweep: false)
            p.addLine(to: CGPoint(x: 14.2, y: 2.5))
            p.addLine(to: CGPoint(x: 9.8, y: 2.5))
            p.addLine(to: CGPoint(x: 9.5, y: 5.1))
            p.addCurve(to: CGPoint(x: 6.9, y: 6.6),
                       control1: CGPoint(x: 8.5, y: 5.4), control2: CGPoint(x: 7.7, y: 5.9))
            p.addLine(to: CGPoint(x: 4.6, y: 5.6))
            p.addLine(to: CGPoint(x: 2.6, y: 9))
            p.addLine(to: CGPoint(x: 4.6, y: 10.5))
            p.addCurve(to: CGPoint(x: 4.5, y: 12),
                       control1: CGPoint(x: 4.5, y: 11), control2: CGPoint(x: 4.5, y: 11.5))
            // `s0 1 .1 1.5` — a smooth cubic, so the first control point is the
            // previous one reflected through the current point: (4.5,12)*2 −
            // (4.5,11.5) = (4.5,12.5).
            p.addCurve(to: CGPoint(x: 4.6, y: 13.5),
                       control1: CGPoint(x: 4.5, y: 12.5), control2: CGPoint(x: 4.5, y: 13))
            p.addLine(to: CGPoint(x: 2.6, y: 15))
            p.addLine(to: CGPoint(x: 4.6, y: 18.4))
            p.addLine(to: CGPoint(x: 6.9, y: 17.4))
            p.addCurve(to: CGPoint(x: 9.5, y: 18.9),
                       control1: CGPoint(x: 7.7, y: 18.1), control2: CGPoint(x: 8.5, y: 18.6))
            p.addLine(to: CGPoint(x: 9.8, y: 21.5))
            p.addLine(to: CGPoint(x: 14.2, y: 21.5))
            p.addLine(to: CGPoint(x: 14.5, y: 18.9))
            p.addCurve(to: CGPoint(x: 17.1, y: 17.4),
                       control1: CGPoint(x: 15.5, y: 18.6), control2: CGPoint(x: 16.3, y: 18.1))
            p.addLine(to: CGPoint(x: 19.4, y: 18.4))
            p.addLine(to: CGPoint(x: 21.4, y: 15))
            p.addLine(to: CGPoint(x: 19.4, y: 13.5))
            p.addCurve(to: CGPoint(x: 19.5, y: 12),
                       control1: CGPoint(x: 19.5, y: 13), control2: CGPoint(x: 19.5, y: 12.5))
            p.closeSubpath()
            return p
        }
    }
}

/// Appends SVG's elliptical-arc command — `a r r 0 largeArc sweep dx dy` — to
/// `path`, as up to four cubic Béziers.
///
/// **Restricted to the circular case (`rx == ry`), which is every arc in
/// `settings.html`'s four glyphs** (`3.4 3.4`, `3.5 3.5`, `6 6`, `2.3 2.3`,
/// `7.6 7.6`, `2.4 2.4`). An arc with unequal radii would need the spec's full
/// F.6.5 conversion; nothing here has one, so this does not pretend to implement
/// it.
///
/// Built out of explicit control points rather than `Path.addArc(center:…)` on
/// purpose. `addArc`'s `clockwise:` flag is interpreted against the *current
/// coordinate space*, and SVG's `sweep-flag` is defined in a y-down space, so
/// mapping one onto the other is exactly the kind of sign question this repo
/// has already had to settle empirically once (`PanelBar.verticalArcPath`'s
/// own comment). The cubic approximation below has no direction flag to get
/// wrong: it walks from the start angle to the end angle through whatever
/// `delta` the spec's own flag arithmetic produced.
private func addSVGArc(to path: inout Path, from p0: CGPoint, to p1: CGPoint,
                       radius: CGFloat, largeArc: Bool, sweep: Bool) {
    // SVG F.6.2: a zero-length arc is dropped entirely.
    let half = CGPoint(x: (p0.x - p1.x) / 2, y: (p0.y - p1.y) / 2)
    let chordHalfSquared = half.x * half.x + half.y * half.y
    guard chordHalfSquared > 0 else { return }
    // SVG F.6.6: a radius too small to span the chord is grown until it fits.
    let r = max(radius, chordHalfSquared.squareRoot())
    // SVG F.6.5, with rx == ry and no x-axis rotation: the centre sits on the
    // chord's perpendicular bisector, and the flags pick which of the two.
    let scale = ((r * r - chordHalfSquared) / chordHalfSquared).squareRoot()
        * (largeArc != sweep ? 1 : -1)
    let centre = CGPoint(x: scale * half.y + (p0.x + p1.x) / 2,
                         y: -scale * half.x + (p0.y + p1.y) / 2)

    var start = atan2(p0.y - centre.y, p0.x - centre.x)
    let end = atan2(p1.y - centre.y, p1.x - centre.x)
    var delta = end - start
    // `sweep` is "the arc runs in the direction of increasing angle" — which in
    // SVG's y-down space is what a reader sees as clockwise.
    if sweep, delta < 0 { delta += 2 * .pi }
    if !sweep, delta > 0 { delta -= 2 * .pi }

    // A cubic approximates a circular arc well up to a quarter turn; past that
    // the error is visible, so split.
    let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
    let step = delta / CGFloat(segments)
    // The standard control-point magnitude for a circular arc of `step`
    // radians, tangent to the circle at both ends.
    let k = 4.0 / 3.0 * tan(step / 4)
    for _ in 0..<segments {
        let a1 = start, a2 = start + step
        let from = CGPoint(x: centre.x + r * cos(a1), y: centre.y + r * sin(a1))
        let to = CGPoint(x: centre.x + r * cos(a2), y: centre.y + r * sin(a2))
        path.addCurve(to: to,
                      control1: CGPoint(x: from.x - k * r * sin(a1), y: from.y + k * r * cos(a1)),
                      control2: CGPoint(x: to.x + k * r * sin(a2), y: to.y - k * r * cos(a2)))
        start = a2
    }
}

/// A page's coloured chip — `settings.html:62-63`, `.chip{width:24px;height:24px;
/// border-radius:6px}` with a `14×14` white glyph centred in it.
///
/// **The one place a page's glyph is drawn.** `SettingsSidebar`'s rows and
/// `SettingsPaneView`'s heading both use this, which is what `settings.html:532`
/// asks for in so many words: *"the pane headings reuse the sidebar's icon so
/// the two always agree."* Two hand-copied glyph declarations that agree today
/// is the arrangement that comment is warning against.
struct SettingsChip: View {
    let page: SettingsPage
    /// `.chip{width:24px;height:24px}`.
    var side: CGFloat = 24
    /// `.chip svg{width:14px;height:14px}`.
    var glyphSide: CGFloat = 14

    var body: some View {
        let scale = glyphSide / SettingsPageIcon.viewBox
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        // `.chip svg{color:#fff}` — white, not `--bone`. The chip's own colour
        // is already the page's identity; the glyph on top of it is the one
        // place in this window that wants pure white.
        let glyph = Color.white
        // `border-radius:6px`. CSS radii are circular, so this is
        // `RoundedRectangle`'s default style, not `.continuous` — Apple's
        // squircle is the more native-looking shape and the prototype does not
        // draw it (checked in Chrome during this task's fidelity pass).
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(page.chip))
            .frame(width: side, height: side)
            .overlay {
                ZStack {
                    if let stroked = page.icon.strokedPath {
                        stroked.applying(transform)
                            .stroke(glyph, style: StrokeStyle(lineWidth: page.icon.lineWidth * scale,
                                                              lineCap: .round, lineJoin: .round))
                    }
                    if let filled = page.icon.filledPath {
                        // `.fill()` is non-zero, exactly as SVG's default
                        // `fill-rule` is — see `filledPath`'s own comment about
                        // the gear's hub.
                        filled.applying(transform).fill(glyph)
                    }
                }
                .frame(width: glyphSide, height: glyphSide)
            }
    }
}
