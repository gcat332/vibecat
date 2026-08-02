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

    #if DEBUG
    /// Counts constructions of `IslandView`. Not `public` — visible only via
    /// `@testable import`, purely for
    /// `theHostingRootIsAssignedOnceAndSurvivesStateChanges` in
    /// NotchControllerTests.swift, which resets this to 0 and asserts it
    /// stays at 1 across several ingests.
    ///
    /// This exists because `panel.contentView === first` alone cannot tell
    /// "a fresh `IslandView` was assigned to an *existing* hosting view's
    /// `rootView`" apart from "the hosting view itself was replaced" — only
    /// the second one changes `contentView`'s identity. The pre-Task-9
    /// code's dominant path (once a hosting view already existed) was the
    /// first: `hosting.rootView = view`, leaving `contentView` completely
    /// untouched. A test that checks only `contentView` cannot catch that
    /// regression reappearing; counting constructions of the root value
    /// itself is the literal constraint ("assigned once").
    ///
    /// `#if DEBUG`-gated rather than shipped unconditionally: this counter
    /// (and the two read-counters on `IslandBody` below) exist purely for
    /// test instrumentation, and SwiftPM already builds the library in debug
    /// for `swift test`, so nothing the test suite needs is lost — only the
    /// per-construction increment a release build has no reason to pay for.
    @MainActor static var buildCount = 0
    #endif

    public init(model: IslandModel) {
        self.model = model
        #if DEBUG
        Self.buildCount += 1
        #endif
    }

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

    /// The system's answer to "what is behind the island", used only when
    /// nothing better is available. Taken from the environment rather than
    /// read off `NSApp` so a test can render both and a preview can show both.
    @Environment(\.colorScheme) private var colorScheme

    /// Which backdrop the aura has to be seen against.
    ///
    /// A measurement when there is one, and the system appearance otherwise.
    /// The two disagree in a case that is not rare: with the menu bar
    /// auto-hidden the island sits over the wallpaper, and on a real machine a
    /// dark wallpaper under a Light system captured at luminance 48 while
    /// `colorScheme` said `.light`. The glow would have been deepened when it
    /// needed to be bright.
    var auraTint: AuraTint {
        let light = switch model.backdrop {
        case .light: true
        case .dark: false
        case nil: colorScheme == .light
        }
        return AuraTint(accent: model.state.accent, onLightBackdrop: light)
    }

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

    /// 0…1 through the *badge's own* cycle (`Badge.motion.cycle`) — computed
    /// the same way as `phase` above, but deliberately kept as a separate
    /// property rather than sharing it.
    ///
    /// Before this, `content(cell:)` passed `phase` — the cat's phase — to
    /// `BadgeCanvas` too, so `Badge.motion.cycle` went unread in production
    /// entirely (confirmed by grep). That happened to look right only
    /// because sleep/trot/call's cycles equal zzz/squares/bang's; nothing
    /// enforced it. The concrete failure this coupling risks: `phase` is
    /// pinned to 0 whenever the *cat's* cycle is 0 (today only `.happy`), so
    /// any mood with a zero cycle paired with a *continuous* badge would
    /// freeze that badge at phase 0 forever, burning the timeline's cost for
    /// a picture that never changes. No such pairing exists today — `.idle`'s
    /// badge (`star`) isn't continuous, and A1 just removed the one pairing
    /// (dormant's `sleep` + `zzz`) that happened to demonstrate the coupling
    /// working rather than failing — which makes the hazard more invisible,
    /// not less. Deriving the badge's phase from its own cycle removes the
    /// coupling outright instead of leaving it to keep working by
    /// coincidence.
    ///
    /// Deliberately bypasses `MotionPreference` exactly as `phase` does —
    /// that gap is a separate, already-noted follow-up, and fixing it for
    /// only one of the two properties would leave them inconsistent with
    /// each other.
    private var badgePhase: Double {
        let cycle = model.badge.motion.cycle
        guard cycle > 0 else { return 0 }
        return now.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycle) / cycle
    }

    /// The body's width with hover's own contribution subtracted back out —
    /// depends only on the right flank's content (nothing / an icon / a
    /// session count), never on `model.hovering`. This is the half of the
    /// width the spring in `body` tracks; see `hoverRevealWidth` for the
    /// other half, and the comment in `body` for why the two are kept apart
    /// instead of both feeding a single `.animation(value: body.width)`.
    ///
    /// Not `private`: `theWidthSplitsIntoAContentHalfAndAnIndependentHoverHalf`
    /// in IslandViewTests.swift reads it directly. That is compile-time
    /// protection against exactly one regression — this property being
    /// *deleted* so the two halves are re-merged into reading
    /// `model.frames.body.width` directly — and no more than that: if
    /// `body` were instead reverted to the pre-Task-10 single-animation
    /// shape while this property is left sitting here unreferenced, that
    /// data-level test still passes, because it never evaluates `body` at
    /// all and the compiler has no "unused" diagnostic for an internal
    /// property a test still reads. `restingWidthReadCount` below is what
    /// actually proves `body` still routes through this property, because
    /// proving that needs `body` to be evaluated, and inspecting the
    /// resulting view tree for the *correct* `.animation` wiring would need
    /// a snapshot/view-inspection dependency this project doesn't take —
    /// so a read count is the narrower, honest thing this can actually show.
    var restingWidth: CGFloat {
        #if DEBUG
        Self.restingWidthReadCount += 1
        #endif
        let resting = CollapsedLayout(right: model.layout.right, hovering: false)
        return model.geometry.frames(rightFlank: resting.rightFlankWidth, tier: .rest).body.width
    }

    #if DEBUG
    /// Counts reads of `restingWidth`. Not `public` — visible only via
    /// `@testable import`, purely for
    /// `bodyActuallyRoutesThroughBothHalvesOfTheWidthSplit` in
    /// IslandViewTests.swift, which resets this to 0, evaluates `.body`, and
    /// asserts it moved. Same technique as `IslandView.buildCount` (Task 9)
    /// for the same underlying reason: a `some View` property's *result*
    /// can't be introspected without a disallowed dependency, but whether
    /// evaluating it touched a given property along the way can be counted
    /// directly. See `IslandView.buildCount` for why this is `#if DEBUG`-gated.
    @MainActor static var restingWidthReadCount = 0
    #endif

    /// The hover reveal's own contribution: `CollapsedLayout.hoverReveal`
    /// while hovering, `0` at rest — depends only on `model.hovering`, never
    /// on session count. Always sums with `restingWidth` back to the real
    /// `model.frames.body.width` (both `rightFlankWidth`'s branches add
    /// exactly `hoverReveal` for hovering vs. not, whatever the content), so
    /// splitting it out costs nothing the layout wasn't already going to draw.
    ///
    /// See `restingWidth`'s doc comment for what its own equivalent test
    /// coverage does and does not prove — the same limits apply here.
    var hoverRevealWidth: CGFloat {
        #if DEBUG
        Self.hoverRevealWidthReadCount += 1
        #endif
        return model.hovering ? CollapsedLayout.hoverReveal : 0
    }

    #if DEBUG
    /// Counts reads of `hoverRevealWidth`. See `restingWidthReadCount`.
    @MainActor static var hoverRevealWidthReadCount = 0
    #endif

    var body: some View {
        let panel = model.panelFrames
        let body = model.frames.body
        // `IslandFrames.bodyInPanel` expresses "this body, positioned inside
        // this panel" as one relative rect; it used to be tested but unused
        // in production, with the same offset hand-rolled here separately —
        // x as `body.minX - panel.panel.minX`, y hardcoded to 0 on the
        // strength of the panel having no top margin (exactly what
        // `bodyInPanel` already encodes). Pairing *this* body — the actual
        // current width, not the fixed panel's own maximal one — with the
        // fixed panel and reading `bodyInPanel` off that pairing reproduces
        // the hand-rolled value exactly (`panel.panel`'s left edge and
        // bottom-anchored top don't move with content width — see
        // `theFixedPanelDoesNotMoveTheLeftEdge` — but its own `body.minX`
        // does, on a fallback pill, where centring shifts with total width;
        // reading `model.panelFrames.bodyInPanel` directly instead would
        // silently swap in the fixed panel's own centring for the real
        // content's, misplacing the silhouette whenever the two widths
        // differ). Routing through the tested helper this way means one
        // place computes the offset, not two that can drift apart.
        let localOrigin = IslandFrames(body: body, panel: panel.panel).bodyInPanel.origin
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
                .shadow(color: Color(auraTint.colour)
                            .opacity(model.aura.opacity(at: now, tint: auraTint)),
                        radius: 18, x: 0, y: 2)
                .frame(width: restingWidth + hoverRevealWidth, height: body.height)
                .offset(x: localOrigin.x, y: localOrigin.y)
                // Design §9.1. Width overshoots more than height so the island
                // reads as one body with mass rather than a resizing box. The
                // panel itself never moves (Task 9's whole point) — only this
                // silhouette, inside it, animates.
                .animation(.spring(response: 0.42, dampingFraction: 0.72),
                           value: restingWidth)
                // Design §9.1's OTHER named animation: hover reveal, 280ms,
                // max-width 0 → 150pt — a distinct transition from the width
                // spring above, not the same curve wearing a second hat.
                // Keying each `.animation(value:)` to its own independent
                // input, rather than both to `body.width`, is what makes that
                // true: toggling `hovering` alone leaves `restingWidth`
                // unchanged, so the spring modifier has nothing to react to
                // and this one governs — and vice versa when only the session
                // count changes. A naive `withAnimation(.easeOut(duration:
                // 0.28))` wrapped around the `hovering` mutation instead would
                // be overridden by the spring above, because both would then
                // be keyed to the same changing `body.width`.
                .animation(.easeOut(duration: 0.28), value: hoverRevealWidth)
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
                BadgeCanvas(badge: model.badge, phase: badgePhase,
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
