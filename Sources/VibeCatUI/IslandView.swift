import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

extension Color {
    init(_ c: RGBA) { self.init(red: c.r, green: c.g, blue: c.b) }
}

/// The right flank's session-count font: `swiftUI` (used by the rendered
/// `Text` in `IslandBody.rightFlank`) and `measuredDigitWidth()` (used by
/// `CollapsedLayout.Metrics.standard`) are two independent constructions
/// kept in step deliberately, side by side in one declaration instead of
/// scattered across the file.
///
/// Only `size` is actually shared, so only `size` is compiler-enforced.
/// SwiftUI's `Font.Weight` and AppKit's `NSFont.Weight` are unrelated types
/// with no bridge between them, so `weight` and `design` are each spelled
/// out once per API rather than derived from one value — "semibold" and
/// "rounded" say the same thing in both places today, but nothing stops
/// one from being edited without the other. Change either, and change both.
enum RightFlankFont {
    static let size: CGFloat = 12
    static let swiftUI: Font = .system(size: size, weight: .semibold, design: .rounded)

    #if canImport(AppKit)
    /// AppKit's equivalent of `swiftUI`, used only to measure a digit's real
    /// advance width — `.monospacedDigitSystemFont` bakes in the same
    /// tabular-figure feature `Text.monospacedDigit()` applies on the
    /// SwiftUI side, verified by measuring "0" through "9" and finding
    /// identical widths.
    ///
    /// Not held as a stored `NSFont`: `NSFont` is a non-`Sendable` class, so
    /// a persistent `static let` of one trips Swift 6's global-mutable-state
    /// check. Returning a plain `CGFloat` instead means nothing but a
    /// number outlives this call — `Metrics.standard` below still measures
    /// exactly once, since a `static let`'s initialiser runs a single time.
    static func measuredDigitWidth() -> CGFloat {
        let monospaced = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        let font = monospaced.fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: size) } ?? monospaced
        return ("0" as NSString).size(withAttributes: [.font: font]).width
    }
    #endif
}

#if canImport(AppKit)
extension CollapsedLayout.Metrics {
    /// Design §5.4: measured from the real font, once, rather than guessed.
    /// Hover polling rebuilds `CollapsedLayout` at 30Hz, so this is computed
    /// a single time into a `static let` rather than re-measuring text on
    /// every call.
    public static let standard = CollapsedLayout.Metrics(
        digitWidth: RightFlankFont.measuredDigitWidth())
}
#else
extension CollapsedLayout.Metrics {
    /// No AppKit to measure with on this platform; falls back to the old
    /// estimate rather than failing to build.
    public static let standard = CollapsedLayout.Metrics(digitWidth: 9)
}
#endif

/// The one view the hosting panel ever gets. Built once in
/// `NotchController.present()` and never rebuilt — everything that changes
/// afterwards is a mutation of the `IslandModel` it reads, observed by
/// SwiftUI directly. See the spike's fourth finding: rebuilding
/// `NSHostingView.rootView` on every change is survivable at a handful of
/// renders per second and nothing more; at sprite rates it is the dominant
/// cost.
public struct IslandView: View {
    private let model: IslandModel

    public init(model: IslandModel) { self.model = model }

    public var body: some View {
        // A real branch, not a paused timeline. Measured: a paused-but-present
        // TimelineView still costs ~6% of a core; removing it costs 0.0%, and
        // that is the only way an idle machine actually stays idle.
        if model.needsTimeline {
            TimelineView(.animation(minimumInterval: Self.minimumInterval(for: model.activeProfile),
                                    paused: false)) { ctx in
                IslandBody(model: model, now: ctx.date)
            }
        } else {
            IslandBody(model: model, now: Date())
        }
    }

    /// `1 / framesPerSecond` — never the display rate (measured: an
    /// unpaced `.animation` timeline runs at the display's own refresh rate,
    /// silently doubling the work on a 120Hz panel versus a 60Hz assumption).
    ///
    /// Guarded rather than a bare division because `activeProfile.framesPerSecond`
    /// is genuinely 0 for a steady mood *and* badge — `.failed`'s `dead`/`cross`,
    /// `.idle`'s `happy`/`star` — and `needsTimeline` can still be true there:
    /// an aura bloom in flight is the one thing that keeps a steady state's
    /// timeline alive (see `IslandModel.needsTimeline`). Left unguarded,
    /// `1.0 / 0` is `.infinity`, and handing that to `TimelineView` as
    /// `minimumInterval` would let its very first frame be its last —
    /// freezing the glow instead of letting it fade, the one outcome
    /// `AuraTrigger`'s own doc comment rules out ("a glow that stayed lit
    /// would be a second indicator"). Falls back to the same 8 fps floor
    /// `MotionPreference` already treats as the slowest rate worth running.
    ///
    /// Explicitly `nonisolated`: `IslandView`'s conformance to `View` (whose
    /// `body` requirement this SDK isolates to `@MainActor`) infers the same
    /// isolation onto every member of the type by default, including this
    /// one — but it is a pure calculation over `Sendable` value types with no
    /// actor-isolated state to touch, so it should be freely callable (and
    /// testable) from anywhere, `body` included.
    nonisolated static func minimumInterval(for profile: MotionProfile) -> Double {
        profile.framesPerSecond > 0 ? 1.0 / profile.framesPerSecond : 1.0 / 8.0
    }
}

/// Design §7.1: the sprite ground colour, named there as `#05070B`. Kept as
/// an `RGBA(hex:)` value rather than a bare `Color(red:green:blue:)` triple
/// so it is greppable by its spec name, the same way every other colour in
/// this module is.
private let islandGroundColour = RGBA(hex: "#05070B")!

/// The collapsed island. Left flank, dead zone, right flank.
///
/// Design §5.1: the black shape may span the cutout because the cutout is black
/// too — but content may not. The middle is a fixed-width spacer, never a view.
///
/// Reads everything from `model` rather than storing its own copies, so a
/// mutation of the model is all a re-render ever needs — there is no second
/// place for `IslandView`/`NotchController` to keep in step with it.
struct IslandBody: View {
    let model: IslandModel
    let now: Date

    /// The left flank's anatomy, named instead of inlined so a test can pin
    /// their sum against `IslandGeometry.leftFlank` (see
    /// `leftAndRightFlankLiteralsAgreeWithTheGeometryConstants` in
    /// IslandViewTests.swift). `leadingPadding + catWidth + gap + badgeWidth +
    /// trailingPadding` must equal `IslandGeometry.leftFlank` — that sum is the
    /// only reason the dead-zone spacer starts precisely at the cutout's left
    /// edge. Change one side of the equation without the other and content
    /// slides under the cutout, the one rule design §5.1 calls absolute, with
    /// no test failing except the one this comment points at.
    enum LeftFlankLayout {
        static let leadingPadding: CGFloat = 12
        static let catWidth: CGFloat = 18
        static let gap: CGFloat = 4
        static let badgeWidth: CGFloat = 14
        static let trailingPadding: CGFloat = 10
    }

    /// The right flank's padding, split out for the same reason.
    /// `leadingPadding + trailingPadding` must equal `CollapsedLayout.padding`
    /// for the session-count case. `iconPadding` is derived from
    /// `CollapsedLayout.padding` rather than a second literal precisely so
    /// the icon case can't drift from what `CollapsedLayout.rightFlankWidth`
    /// actually reserves the way it once did (a 2pt discrepancy: reserved
    /// `padding + iconWidth` = 36, rendered `10 + 14 + 10` = 34).
    enum RightFlankLayout {
        static let leadingPadding: CGFloat = 10
        static let trailingPadding: CGFloat = 12
        static var iconPadding: CGFloat { CollapsedLayout.padding / 2 }
    }

    private var accent: Color { Color(model.state.accent) }

    /// 0…1 through the current mood's cycle. `IslandView` supplies `now` —
    /// the `TimelineView`'s own context date while a timeline is running,
    /// `Date()` once when it is not — so this never reads the wall clock
    /// itself.
    private var phase: Double {
        let cycle = model.mood.motion.cycle
        guard cycle > 0 else { return 0 }
        return now.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycle) / cycle
    }

    var body: some View {
        let panel = model.panelFrames
        let body = model.frames.body
        let localX = body.minX - panel.panel.minX
        let cell: CGFloat = 1

        ZStack(alignment: .topLeading) {
            Color.clear
            IslandShape()
                .fill(Color(islandGroundColour))
                .overlay(alignment: .topLeading) { content(cell: cell) }
                .clipShape(IslandShape())
                // A shadow on the shape traces its rendered alpha, rounded
                // corners included, so the aura follows the silhouette rather
                // than a bounding box — and follows the drawer down for free.
                .shadow(color: accent.opacity(model.aura.opacity(at: now)),
                        radius: 18, x: 0, y: 2)
                .frame(width: body.width, height: body.height)
                .offset(x: localX, y: 0)
                // Design §9.1. Width overshoots more than height so the island
                // reads as one body with mass rather than a resizing box. The
                // panel itself never moves (Task 9's whole point) — only this
                // silhouette, inside it, animates.
                .animation(.spring(response: 0.42, dampingFraction: 0.72),
                           value: body.width)
        }
        .frame(width: panel.panel.width, height: panel.panel.height,
               alignment: .topLeading)
    }

    @ViewBuilder private func content(cell: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Left flank — the cat and its badge.
            HStack(spacing: LeftFlankLayout.gap) {
                CatCanvas(cat: ResolvedCat(coat: model.coat, mood: model.mood, phase: phase),
                          palette: CatPalette(accent: model.state.accent),
                          cellSize: cell)
                    .frame(width: LeftFlankLayout.catWidth, height: 14)
                BadgeCanvas(badge: model.badge, phase: phase,
                            tint: model.state.accent, cellSize: 2)
                    .frame(width: LeftFlankLayout.badgeWidth,
                           height: LeftFlankLayout.badgeWidth)
            }
            .padding(.leading, LeftFlankLayout.leadingPadding)
            .padding(.trailing, LeftFlankLayout.trailingPadding)

            // The dead zone. Never a view — just the width of the cutout.
            Color.clear.frame(width: model.geometry.notch.width)

            rightFlank
        }
        .frame(height: model.geometry.notch.height)
    }

    @ViewBuilder private var rightFlank: some View {
        switch model.layout.right {
        case .nothing:
            EmptyView()
        case .agentIcon:
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: CollapsedLayout.iconWidth, height: 14)
                .padding(.horizontal, RightFlankLayout.iconPadding)
        case .sessionCount:
            // `model.layout.sessionCountText` is the one place a count is
            // clamped for display — see `CollapsedLayout.sessionCountText` —
            // so this never reaches for the raw count (or `min(...)`) itself
            // and can't drift from the width `rightFlankWidth` already
            // reserved for it.
            if let text = model.layout.sessionCountText {
                Text(text)
                    .font(RightFlankFont.swiftUI)
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .padding(.leading, RightFlankLayout.leadingPadding)
                    .padding(.trailing, RightFlankLayout.trailingPadding)
            } else {
                EmptyView()
            }
        }
    }
}
