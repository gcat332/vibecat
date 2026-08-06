import SwiftUI

/// The drawer's own footer: the two shortcuts you reach for without wanting
/// to open Settings. `island-motion.html:516-530`'s `.panelbar` — a leading
/// `<span class="spacer">` then `#pmute` then `#pgear`, both `.pbtn`, each a
/// `24×24` `viewBox` SVG drawn at `16×16` (`.pbtn svg{width:16px;height:16px}`).
///
/// This is the island's own footer, not Settings' — it lives inside
/// `island-motion.html`'s `.drawer`, so its ink comes from that prototype's
/// tokens (`hazeColour`, `dimColour`, `hairlineOpacity`, already declared in
/// `IslandView.swift` for exactly this palette) rather than
/// `SettingsPalette`, whose values (`haze:#9A9AA2`, `dim:#6A6A74`) are a
/// different palette for a different window — see the plan's own "palette
/// collision" section, which exists precisely so this file does not repeat it
/// one document over.
///
/// **One recorded divergence, in how the band is filled rather than in what is
/// drawn.** The prototype's `.panelbar` is `height:28px` at `bottom:9px` with
/// `padding-top:7px` above the buttons, inside a `.face[data-side="d"]` whose own
/// `padding-bottom` is `42px`; this fills the whole `DrawerView.footerHeight`
/// reservation with `.frame(maxHeight: .infinity)`, so the rule sits at the top of
/// a 44pt band and the buttons are centred in what is left. Left as it is
/// deliberately: the band's height is Plan 4's (the prototype's footer measures
/// 37pt against our fixed 44pt, a carried item that predates this file), and
/// redistributing inside a band whose height is already known to be wrong would be
/// guessing at two numbers instead of one. Recorded here so it is a decision
/// rather than an omission — CLAUDE.md's rule for exactly this.
public struct PanelBar: View {
    let muted: Bool
    let onToggleMute: () -> Void
    let onOpenSettings: () -> Void

    public init(muted: Bool, onToggleMute: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.muted = muted
        self.onToggleMute = onToggleMute
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(spacing: 0) {
            // `.panelbar{border-top:1px solid var(--hairline)}` — the drawer's
            // own top edge for this row. `hairlineOpacity` (0.09) is
            // `island-motion.html`'s `--hairline`, not Settings' `--line`
            // (0.08) — the two prototypes disagree on this exact value, which
            // is the "carried foot-gun" this file has to get right rather
            // than reach for whichever hairline constant is closest to hand.
            //
            // **Inset by the same 18pt as the buttons, because the border is on
            // an element that is itself inset.** `island-motion.html:181` is
            // `.panelbar{position:absolute;left:18px;right:18px;…;border-top:1px
            // solid var(--hairline)}`, so the rule spans `width − 36`, not the
            // full drawer width. This file drew it full-width for three plans,
            // and `PanelBarTests` recorded the divergence as a *measured fact
            // about the prototype* — "that hairline alone paints every column at
            // `y == 0`" was true of our render and false of the CSS. Checked in
            // the prototype's own source before this was changed.
            Rectangle()
                .fill(Color.white.opacity(hairlineOpacity))
                .frame(height: 1)
            HStack(spacing: 4) {
                // `.panelbar .spacer{flex:1}` — a leading spacer, not
                // trailing, so both buttons sit against the drawer's right
                // edge rather than its left, where the session list's own
                // content begins.
                Spacer(minLength: 0)
                muteButton
                gearButton
            }
            .frame(maxHeight: .infinity)
        }
        // One inset for the whole `.panelbar` box, rather than one on the
        // buttons and none on the rule — which is what let the two drift apart.
        .padding(.horizontal, 18)
    }

    private var muteButton: some View {
        Button(action: onToggleMute) {
            MuteIcon(muted: muted)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .frame(width: 26, height: 26)
        .accessibilityLabel("Mute alerts")
    }

    private var gearButton: some View {
        Button(action: onOpenSettings) {
            GearIcon()
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .frame(width: 26, height: 26)
        .accessibilityLabel("Settings")
    }
}

/// `#pmute`'s SVG, `island-motion.html:519-522` — a filled speaker plus two
/// stroked arcs that hide when muted, plus a stroked slash that shows only
/// then. `.pbtn[aria-pressed="true"]{color:var(--dim)}` also recolours the
/// whole glyph, not just the slash, so muted draws in `dimColour` throughout.
///
/// No animated crossfade between the two states: the prototype's
/// `transition:opacity 120ms` is real, but this repo's own rule is that
/// **everything animated goes through `MotionPreference.resolve`**
/// (`CLAUDE.md`), and `PanelBar`'s interface (fixed by this plan's Task 4
/// dependency) takes no motion preference to resolve against. A silent
/// left-in animation that ignores reduced motion would be worse than the
/// instantaneous swap this draws instead — recorded here rather than left
/// for a reader to wonder whether it was missed.
///
/// Not `private`: `PanelBarTests.theMuteButtonShowsASlashOnlyWhenMuted`
/// rasterises this directly, isolated from `#pgear` — the gear is always
/// `hazeColour` regardless of `muted`, so a colour- or ink-based assertion
/// made against the *whole* `PanelBar` cannot tell "the mute icon changed"
/// apart from "the gear is sitting right there being its own usual colour".
/// Still not `public` — same reasoning as `NotchController.panelForTesting`.
struct MuteIcon: View {
    let muted: Bool
    private var tint: Color { Color(muted ? dimColour : hazeColour) }

    var body: some View {
        ZStack {
            SpeakerShape().fill(tint)
            if !muted {
                Wave1Shape().stroke(tint, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                Wave2Shape().stroke(tint, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            }
            if muted {
                SlashShape().stroke(tint, style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
            }
        }
    }
}

/// `#pgear`'s SVG, `island-motion.html:524-528` — a `r=3.1` circle plus eight
/// spokes. Always `hazeColour`: the gear carries no muted/unmuted state.
private struct GearIcon: View {
    var body: some View {
        ZStack {
            GearRingShape().stroke(Color(hazeColour), style: StrokeStyle(lineWidth: 1.7))
            GearToothShape().stroke(Color(hazeColour), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
        }
    }
}

// MARK: - Path data, lifted straight from the prototype's `viewBox="0 0 24 24"`
//
// The four mute-icon shapes below (`SpeakerShape`, `Wave1Shape`, `Wave2Shape`,
// `SlashShape`) are not `private`, unlike `GearRingShape`/`GearSpokesShape`:
// `PanelBarTests.theMuteButtonShowsASlashOnlyWhenMuted` rasterises each in
// isolation to find a pixel only the slash ever paints, rather than trusting
// a hand-computed SVG coordinate — an earlier draft of that test did the
// trigonometry by hand and picked a point that turned out to sit inside
// `wave1`'s own stroke. Still not `public`.

/// Maps a point in the SVG's `24×24` coordinate space into `rect`, uniformly
/// scaling (the viewBox is square and every caller here is drawn into a
/// square frame) and honouring `rect.minX`/`minY` the way `IslandShape` does,
/// rather than assuming the shape always starts at the origin.
private func svgPoint(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
    let s = rect.width / 24
    return CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
}

/// `M4 9.5v5h3.6L13 19V5L7.6 9.5H4z` — the speaker body.
struct SpeakerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: svgPoint(4, 9.5, in: rect))
        p.addLine(to: svgPoint(4, 14.5, in: rect))     // v5
        p.addLine(to: svgPoint(7.6, 14.5, in: rect))   // h3.6
        p.addLine(to: svgPoint(13, 19, in: rect))
        p.addLine(to: svgPoint(13, 5, in: rect))       // V5
        p.addLine(to: svgPoint(7.6, 9.5, in: rect))
        p.closeSubpath()
        return p
    }
}

/// An SVG `a r r 0 0 1 0 dy` arc from a fixed `x` at `startY` to the same `x`
/// at `endY` — exactly the shape both wave arcs use (`dx` is always 0 in
/// `island-motion.html`'s path data). Solved directly rather than
/// approximated: the centre lies on the arc's chord's perpendicular
/// bisector, at the one point that is `radius` from both endpoints, and
/// `sweep-flag="1"` in a `y`-down space is the branch that bulges away from
/// the speaker (increasing `x`), which is `center.x < x`.
private func verticalArcPath(x: CGFloat, startY: CGFloat, endY: CGFloat, radius: CGFloat, in rect: CGRect) -> Path {
    let s = rect.width / 24
    let midY = (startY + endY) / 2
    let halfChord = (endY - startY) / 2
    let dx = (radius * radius - halfChord * halfChord).squareRoot()
    let centerSVG = CGPoint(x: x - dx, y: midY)
    let center = svgPoint(centerSVG.x, centerSVG.y, in: rect)
    let startAngle = Angle(radians: Double(atan2(startY - midY, dx)))
    let endAngle = Angle(radians: Double(atan2(endY - midY, dx)))
    var p = Path()
    p.addArc(center: center, radius: radius * s, startAngle: startAngle, endAngle: endAngle, clockwise: false)
    return p
}

/// `M16.2 9.2a4 4 0 0 1 0 5.6` — the inner wave.
struct Wave1Shape: Shape {
    func path(in rect: CGRect) -> Path {
        verticalArcPath(x: 16.2, startY: 9.2, endY: 14.8, radius: 4, in: rect)
    }
}

/// `M18.6 6.8a7.4 7.4 0 0 1 0 10.4` — the outer wave.
struct Wave2Shape: Shape {
    func path(in rect: CGRect) -> Path {
        verticalArcPath(x: 18.6, startY: 6.8, endY: 17.2, radius: 7.4, in: rect)
    }
}

/// `M5 19 19 5` — the mute slash.
struct SlashShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: svgPoint(5, 19, in: rect))
        p.addLine(to: svgPoint(19, 5, in: rect))
        return p
    }
}

/// `<circle cx="12" cy="12" r="3.1"/>` — the gear's hub.
/// **A written divergence from the prototype, and the prototype is the one that is
/// wrong.** `island-motion.html:526-527` draws `#pgear` as a `r=3.1` circle plus eight
/// *detached* radial ticks — which is the classic **brightness** glyph, not a gear. A
/// gear's teeth are attached to a ring; ticks floating around a small hub read as rays.
/// The owner looked at the running app and called it a brightness icon before knowing
/// what the SVG said, which is the whole evidence needed.
///
/// §10.2's rule is that the control carries the meaning, so a Settings button that reads
/// as "adjust screen brightness" has lost the only job the glyph has. **Fixed rather
/// than reproduced**, and the fix is minimal: the ticks already run from `r 8.80` to
/// `r 6.50` (measured off the prototype's own path data), so adding the ring they should
/// have been attached to at `6.5` turns rays into teeth and changes nothing else. The
/// hub stays at the prototype's `3.1`.
struct GearRingShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        let centre = svgPoint(12, 12, in: rect)
        var p = Path()
        p.addEllipse(in: CGRect(center: centre, radius: 3.1 * s))
        // The tooth root. `6.5` is where every tick in `GearSpokesShape` ends, so the
        // teeth meet it exactly rather than hovering a fraction clear of it.
        p.addEllipse(in: CGRect(center: centre, radius: 6.5 * s))
        return p
    }
}

/// The gear's eight **teeth** — `island-motion.html:526-527` calls them nothing, and
/// they were `spokes` here until they gained the ring that makes them teeth:
/// `M12 3.2v2.3M12 18.5v2.3M20.8 12h-2.3M5.5 12H3.2M18.2 5.8l-1.6 1.6M7.4
/// 16.6l-1.6 1.6M18.2 18.2l-1.6-1.6M7.4 7.4 5.8 5.8` — four cardinal, four
/// diagonal, each its own `moveTo`/`lineTo` pair the way the source SVG
/// draws four independent subpaths sharing one `<path>` element.
struct GearToothShape: Shape {
    func path(in rect: CGRect) -> Path {
        let spokes: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (12, 3.2, 12, 5.5),
            (12, 18.5, 12, 20.8),
            (20.8, 12, 18.5, 12),
            (5.5, 12, 3.2, 12),
            (18.2, 5.8, 16.6, 7.4),
            (7.4, 16.6, 5.8, 18.2),
            (18.2, 18.2, 16.6, 16.6),
            (7.4, 7.4, 5.8, 5.8),
        ]
        var p = Path()
        for (x1, y1, x2, y2) in spokes {
            p.move(to: svgPoint(x1, y1, in: rect))
            p.addLine(to: svgPoint(x2, y2, in: rect))
        }
        return p
    }
}

private extension CGRect {
    init(center: CGPoint, radius: CGFloat) {
        self.init(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}

extension PanelBar {
    /// Invokes exactly the closure a real tap would, for
    /// `tappingEachButtonCallsItsOwnClosureAndNotTheOther` in
    /// `PanelBarTests.swift`. Not `#if DEBUG`-gated the way `IslandView`'s
    /// counters are: those instrument state that only exists mid-render,
    /// where a `#if DEBUG` build is unavoidable anyway (SwiftPM's own test
    /// build); these two just call a stored closure, the same thing a real
    /// `Button.action` does, so there is no production behaviour being
    /// exposed here that a release build wouldn't already have. Not
    /// `public` — visible only via `@testable import`, same reasoning as
    /// `NotchController.panelForTesting`.
    func toggleMuteForTesting() { onToggleMute() }
    /// See `toggleMuteForTesting()`.
    func openSettingsForTesting() { onOpenSettings() }
}
