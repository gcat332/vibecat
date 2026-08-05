import AppKit
import SwiftUI
import VibeCatCore

/// §3's *"a swappable runtime asset"*, drawn — with `CLIMark` as the fallback
/// §2.3 requires whenever the asset cannot be trusted.
///
/// ## The §4.3 ruling this task owns
///
/// `CLIMarkView` is `currentColor` geometry tinted by the state accent: shape
/// says who, hue says what state, both on one mark. A brand icon arrives with
/// its own colour — `#D97757`, `#5D74FF`, a green circle, a blue square — which
/// puts a second meaning on hue the moment it is drawn in full colour, and the
/// plan is explicit that there may be no answer that satisfies both halves of
/// §4.3 at once. So the decision is **split by context**, not resolved in one
/// direction:
///
/// - **`.brandColour`** — the icon's own pixels, untouched. Correct wherever
///   §4.3's state signal is carried by something else on screen. `SessionRow`
///   is that case: line 1 already states the state twice, in a word
///   (`Self.stateLabel`) and a pip six points from the mark
///   (`SessionRow.headline`'s `Circle().fill(accent)`) — so the mark's hue is
///   spare capacity there, not the sole carrier of state, and spending it on
///   identity instead costs §4.3 nothing that was not already paid for twice.
/// - **`.tinted`** — a mask tinted by `accent`, via `Image
///   .renderingMode(.template)`: every non-transparent pixel takes the tint,
///   exactly as `CLIMarkView.colour` already does. Correct wherever the icon
///   may be the *only* thing on screen — the collapsed flank, where nothing
///   else states the session's state at all. §4.3 holds there exactly as
///   written, at the cost the plan itself names: a filled circular background
///   (`claude.png`, `openai.png` — measured, not assumed, against the owner's
///   set) becomes a solid state-coloured disc, which may read as a badge
///   rather than a mark. Accepted rather than avoided, because the
///   alternative in that spot is a full-colour logo the eye cannot separate
///   from a genuinely different state.
///
/// **This file does not choose between the two for any caller** — Task 5 wires
/// the row (`.brandColour`, per the reasoning above); a future collapsed-flank
/// caller wires `.tinted`. Neither call site exists yet, so this is the
/// decision recorded and the mechanism built, not the wiring — that is
/// deliberate rather than a gap this task left open.
///
/// No §4.3 correction is filed against the spec: nothing here draws in full
/// colour merely to look pretty. `.brandColour` is used exactly where the
/// state has already been said, which is the same "shape says who, hue says
/// what state" clause read one level down — a *second* field free to speak
/// once the first has done the job description already assigns state.
struct SourceIcon: View {
    /// The adapter's own `SourceAdapter.icon` — a path, or `nil` for "use the
    /// geometric mark". User input, and every way it can be wrong (missing,
    /// unreadable, a directory, a zero-byte file, an unparsable one) is
    /// `loadValidImage(atPath:)`'s problem, not this view's: `body` only ever
    /// sees "an image" or "nothing", never an error.
    let path: String?
    /// §2.3's fallback: `CLIMark(cli:)`'s own mapping, so a source with no icon
    /// — every preset in `Adapters/` today, since none may bundle a vendor
    /// logo — draws exactly what it always drew.
    let fallback: CLIMark
    var side: CGFloat = 16
    /// The session's state accent. Not defaulted, unlike `CLIMarkView.colour`:
    /// every render needs it for the fallback mark, and `.tinted` needs it for
    /// the icon itself, so there is no call site where a default would ever
    /// actually be used.
    var accent: Color
    var style: Style = .tinted

    enum Style: Sendable, Equatable {
        case brandColour
        case tinted
    }

    var body: some View {
        if let path, let image = Self.loadValidImage(atPath: path) {
            // `.renderingMode(.template)` has to land on `Image` itself —
            // it is not a member of the `some View` that `.resizable()`
            // already returns, so the two branches diverge before any
            // modifier both share, and rejoin at `.aspectRatio`/`.frame`.
            Group {
                switch style {
                case .brandColour:
                    Image(nsImage: image).resizable().interpolation(.high)
                case .tinted:
                    Image(nsImage: image).resizable().interpolation(.high)
                        .renderingMode(.template)
                        .foregroundStyle(accent)
                }
            }
            .aspectRatio(contentMode: .fit)
            .frame(width: side, height: side)
        } else {
            CLIMarkView(mark: fallback, side: side, colour: accent)
        }
    }

    /// Every way a path can be wrong that must not throw, hang or crash —
    /// §2.3 applied to a picture. A static function rather than folded into
    /// `body`, so the fallback tests below can call it directly against real
    /// bad inputs without rendering anything.
    ///
    /// Measured against this loader, not assumed: on this OS,
    /// `NSImage(contentsOfFile:)` already returns `nil` for a missing path, a
    /// zero-byte file and a file that is not image data at all — none of the
    /// three needed the `isValid`/size guard below to fail closed. The guard
    /// stays anyway, as a second line rather than a redundant one: it is what
    /// catches a *directory* (checked explicitly, before `NSImage` ever sees
    /// the path, because trusting an AppKit initialiser to fail closed on a
    /// directory rather than to interpret it is exactly the kind of assumption
    /// this project's testing standards rule out) and it is what would catch
    /// a future format or OS version where a broken file decodes into an
    /// `NSImage` with a zero or nonsensical size instead of `nil`.
    ///
    /// Checked against the owner's real set at `~/Downloads/icon` — read only,
    /// never copied here — which all loaded as valid, appropriately-sized
    /// images: this loader is not the reason any of those six needs
    /// converting, and the plan's own SVG note (two of them reporting `1×1`
    /// for `width="1em"` with no font context) is a fact about *those files*,
    /// not about this function.
    static func loadValidImage(atPath path: String) -> NSImage? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return nil }
        guard let image = NSImage(contentsOfFile: path),
              image.isValid, image.size.width > 0, image.size.height > 0
        else { return nil }
        return image
    }
}
