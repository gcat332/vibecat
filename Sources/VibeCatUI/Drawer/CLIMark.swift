import SwiftUI

/// §4.3: "Which agent is speaking is carried by its **icon shape**, never by
/// hue." This is the shape.
///
/// A direct port of `MARKS` in `docs/superpowers/prototypes/island-motion.html`
/// (line 619) — four marks authored as portable geometry in a 24×24 viewBox
/// against `currentColor`, which is exactly why they port: no raster, no font,
/// no vendor artwork. **They are deliberately neutral geometric marks rather
/// than vendor logos** (six spokes, a hexagon with a centre dot, a
/// four-pointed star, a chevron with a rule), so nothing here reproduces a
/// trademark; §3 of the design spec is the reason that choice was made and it
/// is the reason this file can exist at all.
///
/// Until this file, the row's leading position held a *state* dot and the state
/// was then repeated in words beside it — so a row could say how a session was
/// doing twice over and which CLI it belonged to not at all.
enum CLIMark: String, CaseIterable, Sendable {
    case claude, codex, gemini, generic

    /// Maps `Session.cli` — the adapter's own name for its CLI, e.g.
    /// `claude-code` — onto a mark. Substring matching rather than an exact
    /// table because the wire value is a vendor's product name and versions of
    /// it (`claude-code`, `claude`, `gemini-cli`) must not each need a new
    /// case; **`generic` is the fallback**, which is the case that matters:
    /// an unknown CLI still gets a mark, so the leading position is never
    /// empty and the row never loses its identity column.
    init(cli: String) {
        let name = cli.lowercased()
        if name.contains("claude") { self = .claude }
        else if name.contains("codex") { self = .codex }
        else if name.contains("gemini") { self = .gemini }
        else { self = .generic }
    }

    /// The prototype's own viewBox. Every coordinate below is in this space and
    /// scaled once, at draw time, so the numbers stay readable against the SVG
    /// they came from rather than being pre-multiplied into 16pt.
    static let viewBox: CGFloat = 24

    /// The prototype's `stroke-width`, in viewBox units. `gemini` is a filled
    /// path and strokes nothing.
    var lineWidth: CGFloat {
        switch self {
        case .claude:  1.9
        case .codex:   1.7
        case .gemini:  0
        case .generic: 2
        }
    }

    /// The stroked half of the mark, in the 24×24 viewBox.
    var strokedPath: Path? {
        switch self {
        case .claude:
            // Six spokes: a vertical pair and two diagonal pairs, each a
            // separate segment with a gap at the centre — `v5.6` twice from
            // 3.4 and 15, and four 4.9×2.8 diagonals.
            var p = Path()
            for (from, to) in [(CGPoint(x: 12, y: 3.4), CGPoint(x: 12, y: 9.0)),
                               (CGPoint(x: 12, y: 15.0), CGPoint(x: 12, y: 20.6)),
                               (CGPoint(x: 4.6, y: 7.7), CGPoint(x: 9.5, y: 10.5)),
                               (CGPoint(x: 14.5, y: 13.5), CGPoint(x: 19.4, y: 16.3)),
                               (CGPoint(x: 4.6, y: 16.3), CGPoint(x: 9.5, y: 13.5)),
                               (CGPoint(x: 14.5, y: 10.5), CGPoint(x: 19.4, y: 7.7))] {
                p.move(to: from)
                p.addLine(to: to)
            }
            return p
        case .codex:
            // A pointy-top hexagon: `M12 3.3 19.5 7.65v8.7L12 20.7 4.5 16.35v-8.7z`.
            var p = Path()
            p.move(to: CGPoint(x: 12, y: 3.3))
            for point in [CGPoint(x: 19.5, y: 7.65), CGPoint(x: 19.5, y: 16.35),
                          CGPoint(x: 12, y: 20.7), CGPoint(x: 4.5, y: 16.35),
                          CGPoint(x: 4.5, y: 7.65)] {
                p.addLine(to: point)
            }
            p.closeSubpath()
            return p
        case .gemini:
            return nil
        case .generic:
            // A chevron and a rule: `M4.8 7.2 9.6 12l-4.8 4.8` plus `M12.6 16.8h6.6`.
            var p = Path()
            p.move(to: CGPoint(x: 4.8, y: 7.2))
            p.addLine(to: CGPoint(x: 9.6, y: 12))
            p.addLine(to: CGPoint(x: 4.8, y: 16.8))
            p.move(to: CGPoint(x: 12.6, y: 16.8))
            p.addLine(to: CGPoint(x: 19.2, y: 16.8))
            return p
        }
    }

    /// The filled half of the mark, in the 24×24 viewBox.
    var filledPath: Path? {
        switch self {
        case .claude, .generic:
            return nil
        case .codex:
            // The centre dot, `<circle cx="12" cy="12" r="2.5">`.
            return Path(ellipseIn: CGRect(x: 9.5, y: 9.5, width: 5, height: 5))
        case .gemini:
            // A four-pointed star of four identical cubics, each bowing *inward*
            // between two points 9.6 out from centre — the prototype writes it
            // as one relative `c` run with four coordinate sets, transcribed
            // here as absolute curves so each arm is legible on its own line.
            var p = Path()
            p.move(to: CGPoint(x: 12, y: 2.4))
            p.addCurve(to: CGPoint(x: 21.6, y: 12),
                       control1: CGPoint(x: 12, y: 7.7), control2: CGPoint(x: 16.3, y: 12))
            p.addCurve(to: CGPoint(x: 12, y: 21.6),
                       control1: CGPoint(x: 16.3, y: 12), control2: CGPoint(x: 12, y: 16.3))
            p.addCurve(to: CGPoint(x: 2.4, y: 12),
                       control1: CGPoint(x: 12, y: 16.3), control2: CGPoint(x: 7.7, y: 12))
            p.addCurve(to: CGPoint(x: 12, y: 2.4),
                       control1: CGPoint(x: 7.7, y: 12), control2: CGPoint(x: 12, y: 7.7))
            p.closeSubpath()
            return p
        }
    }
}

/// One mark, at the prototype's own `.mark{width:16px;height:16px}`.
///
/// **`colour` is not the session's accent, and that is deliberate.** §4.3's
/// last sentence does list marks among the things tinted by `--accent`, and the
/// prototype's CSS does exactly that — but the same section's *rule* is that
/// hue means state and shape means identity, and this row already carries state
/// in a pip immediately beside the state's own word. Tinting the mark as well
/// would make the row's leading glyph say state twice and identity once, which
/// is the arrangement this file was written to end. Recorded rather than
/// silently chosen: flipping it back is this one default.
struct CLIMarkView: View {
    let mark: CLIMark
    var side: CGFloat = 16
    var colour: Color = Color(boneColour)

    var body: some View {
        let scale = side / CLIMark.viewBox
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        ZStack {
            if let stroked = mark.strokedPath {
                stroked.applying(transform)
                    .stroke(colour, style: StrokeStyle(lineWidth: mark.lineWidth * scale,
                                                       lineCap: .round, lineJoin: .round))
            }
            if let filled = mark.filledPath {
                filled.applying(transform).fill(colour)
            }
        }
        .frame(width: side, height: side)
    }
}
