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
        // `IslandBody`'s own outer `.frame` is the *full panel* width (it
        // reserves room for the widest the collapsed island ever gets, per
        // `maxCollapsedFrames`), while its actual painted silhouette sits
        // offset inside that at `drawerLeadingOffset` — `DrawerView` is only
        // ever as wide as the live body, so the overlay below applies that
        // same offset as its own leading padding rather than the two drifting
        // apart. (Originally a `VStack(alignment: .leading)`, whose *default*
        // `.center` was confirmed by rendering to drift the drawer sideways,
        // centring it under the wider panel instead of the narrower body
        // above it — `.leading` fixed that. The overlay below replaced the
        // VStack entirely for a different reason, see its own comment, and
        // carries the explicit leading padding forward from that fix.)
        Group {
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
        // Design §6.1's third tier: the drawer hangs below the collapsed
        // body, inside this same view rather than a second window.
        //
        // An overlay, not a VStack sibling — Task 8 changed what has to
        // happen here. `IslandBody`'s own outer `.frame` reads
        // `model.panelFrames`, which is now tier-aware and already grows to
        // cover an open drawer's own height (see `IslandModel.tier` — the
        // live `NSPanel` has to grow by exactly that much too, which is the
        // whole reason `panelFrames` had to stop being a hardcoded `.rest`).
        // A VStack sibling would add `DrawerView`'s height a *second* time on
        // top of that — confirmed by rendering it that way: the rasterised
        // scene came out exactly `panelFrames.panel.height +
        // question.face.height` tall, with a dead gap of ground colour and
        // nothing else sitting between the collapsed body and where the
        // drawer's own title text actually started. `.topLeading` plus an
        // explicit top offset of the collapsed content's own height is what
        // makes this overlay start exactly where `IslandBody`'s own shape
        // keeps going for the drawer, instead of at the *panel's* bottom
        // edge, which sits `auraMargin` further down than the shape itself
        // ever paints.
        //
        // Gated on `model.tier` being `.drawer`, not merely `model.question`
        // being non-nil (what this read before Task 8 introduced the tier):
        // a question must not open the drawer on its own, and `model.tier`
        // is now the one place that already enforces exactly that (it stays
        // `.rest`/`.hover` until `NotchController.click()` sets
        // `drawerOpen`). Gating on `question` alone here would show
        // `DrawerView` (and, per the paragraph above, expect `IslandBody`'s
        // *un*grown frame to somehow already contain it) the moment a
        // question arrived, before any click — relying on nothing but the
        // live window happening to stay too small to reveal it, the same
        // fragile-by-omission shape as the bug this comment already
        // describes fixing once.
        .overlay(alignment: .topLeading) {
            if case .drawer = model.tier, let question = model.question {
                // model.drawerWidth, not model.frames.body.width (finding 5
                // of the final whole-branch review): the latter carries the
                // collapsed pill's own hover reveal, which nothing in the
                // drawer's content needs — see `IslandModel.drawerWidth`'s
                // own doc comment for why the drawer's width holds steady
                // regardless of where the cursor drifts while it is open.
                DrawerView(question: question, accent: model.state.accent,
                           width: model.drawerWidth,
                           onAnswer: { model.onAnswer?($0) })
                    .padding(.leading, drawerLeadingOffset)
                    .padding(.top, model.geometry.notch.height)
            }
        }
        .animation(.spring(response: IslandMotion.response,
                           dampingFraction: IslandMotion.heightDamping), value: drawerHeight)
    }

    /// 0 with the drawer closed, else the open face's own height — the one
    /// value the §9.1 spring above is keyed to. Mirrors
    /// `IslandBody.restingWidth`/`.hoverRevealWidth`: one property per
    /// independent animation, so this spring cannot be overridden by one
    /// keyed to something that did not change, and vice versa.
    ///
    /// Keyed to `model.tier`, not `model.question?.face.height ?? 0` (what
    /// this read before the final whole-branch review): a question arriving
    /// changes `model.question` — and so the old expression — the instant it
    /// arrives, before any click, which is exactly the moment §6.1/Task 8
    /// says nothing visual may happen yet (see `IslandModel.tier`'s own doc
    /// comment, and `aQuestionWithoutAClickRendersIdenticallyToNoQuestionAtAll`
    /// below). And it does NOT change when `drawerOpen` flips true, because
    /// the question that was already there is still there — so the one
    /// gesture this spring exists for (§9.1) never actually triggered it.
    /// `model.tier` is the one property that already enforces "closed until
    /// clicked, closed again once cleared" (`drawerOpen` together with
    /// `question`), so reading it here instead is what makes the spring key
    /// on the right event.
    ///
    /// Not `private`: pinned by `drawerHeightTracksTheTierOpeningNotTheQuestionArriving`
    /// in DrawerGoldenTests.swift, the same reasoning `restingWidth`'s own
    /// doc comment gives for why that property isn't `private` either — a
    /// test needs the actual computed value, not just whether it was *read*
    /// (which `drawerHeightReadCount` below already covers, and which stayed
    /// green throughout the defect this describes: `model.question?.face
    /// .height ?? 0` is also "a property," just the wrong one).
    var drawerHeight: CGFloat {
        #if DEBUG
        Self.drawerHeightReadCount += 1
        #endif
        if case let .drawer(height) = model.tier { return height }
        return 0
    }

    #if DEBUG
    /// Counts reads of `drawerHeight`. A static render cannot observe *which*
    /// curve a `.animation(value:)` is keyed to — proving that needs the same
    /// read-counter trick `IslandBody.restingWidthReadCount`/
    /// `.hoverRevealWidthReadCount` already use for their own two springs,
    /// for the identical reason: `body`'s *result* can't be introspected for
    /// the correct wiring without a view-inspection dependency this project
    /// doesn't take, but whether building `body` touched this property can be
    /// counted directly. See `IslandBody.restingWidthReadCount`'s own doc
    /// comment for what this does and does not prove. `#if DEBUG`-gated for
    /// the same reason those two are.
    @MainActor static var drawerHeightReadCount = 0
    #endif

    /// Where the collapsed body's own *painted* silhouette starts inside
    /// `IslandBody`'s wider, panel-sized outer frame — the same value
    /// `IslandBody.body` computes as `localOrigin.x` for its own offset, read
    /// back through the public `IslandFrames`/`IslandModel` surface rather
    /// than duplicated, so the two can't drift apart. `body.minX` never
    /// depends on how much of the right flank is showing (see
    /// `IslandGeometry.frames`'s own `left =` line), which is why this is a
    /// single fixed offset — not something that needs recomputing whenever
    /// the live width does.
    private var drawerLeadingOffset: CGFloat {
        IslandFrames(body: model.frames.body, panel: model.panelFrames.panel).bodyInPanel.origin.x
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

/// The island's own body colour: the prototype's `--void`.
///
/// **Corrected 2026-08-03, Plan 4.5.** This was `#05070B` with a doc comment
/// citing "Design §7.1: the sprite ground colour" — and that is exactly what
/// went wrong. §7.1 names `#05070B` as the base the *sprite's* outline and
/// shadow tones composite the accent over (`O = accent 20% over #05070B`), which
/// `CatPalette` uses correctly and still does. Nothing in the spec names a
/// colour for the island body at all, so the only authority on it is the
/// prototype the spec header points at — and there, `.island` is
/// `background: var(--void)` with `--void: #07080A`. `#05070B` appears in that
/// whole file only twice, both inside `color-mix` for the sprite tones.
///
/// So the largest area of colour in the interface was painted with a constant
/// borrowed from the sprite's shading maths, two levels a channel off, for four
/// plans. See `theIslandGroundIsThePrototypesVoidNotTheSpritesMixBase` for why
/// every test in this suite agreed with it.
///
/// Not `private`: the drawer hangs below this same silhouette and has to
/// match it exactly (`DrawerView.swift`, a different file in this module),
/// so this stays module-visible rather than being re-declared a second time
/// with its own copy of the literal to drift from.
let islandGroundColour = RGBA(hex: "#07080A")!

/// The prototype's two named text tones, `--bone` and `--haze`, which it uses 32
/// times between them — 16 each — and which we had none of.
///
/// **Added 2026-08-03, Plan 4.5.** Every label in the drawer was `Color.white` or
/// `Color.white.opacity(…)`. That is a different colour family, not a near miss:
/// white at 65% over `islandGroundColour` renders ≈(168,169,169), dead neutral,
/// where `--haze` is (138,147,166) — about 30 levels darker **and cool**, with
/// `b − r = 28` against our 1. No opacity value reaches a hue, so this needed the
/// tokens rather than a tuning pass.
///
/// Which tone a label takes is read off the prototype's own drawer markup, not
/// guessed: `.ask-q` (the question) is `--bone`; `.detail.mono` (the command
/// body) is `--haze`; `.choice.alt` — a non-recommended row — is `--haze`, and
/// `.choice.alt:hover` promotes it to `--bone`; `.confirm .tally` is `--haze`.
/// `--dim` already exists in `IslandState` as dormant's colour, which is the
/// third of the same family.
let boneColour = RGBA(hex: "#EDEFF4")!
let hazeColour = RGBA(hex: "#8A93A6")!

/// `--hairline: rgba(255,255,255,.09)`. One token in the prototype, against three
/// different values of ours (`0.05`, `0.06`, `0.08`) for the same job — a divider
/// or an inert fill. Kept as an opacity rather than a solid because that is what
/// the prototype does, and it has to composite over whatever is behind it.
let hairlineOpacity: Double = 0.09

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

        // Plan 5, Task 1: **two** silhouette rects, not one.
        //
        // One rect could not carry two different widths, and since Task 8 it was
        // being asked to. `body.height` includes an open drawer's own height, and
        // Plan 4 deliberately made the drawer's width hover-independent — so a
        // single hover-coupled rect spanning both painted `hoverReveal` points of
        // island ground straight down the right of the drawer, over ~92% of its
        // height, appearing and disappearing with the cursor. Measured before
        // this: the ground colour at 2pt past the drawer's own right edge, 60pt
        // below the notch line.
        //
        // The collapsed half rounds nothing while the drawer is open
        // (`roundsBottom:`) — two rounded shapes stacked would put a pair of
        // corners across the middle of one body, a seam at exactly the line the
        // island is meant to read as continuous across.
        let drawerBelow = max(0, body.height - model.geometry.notch.height)

        ZStack(alignment: .topLeading) {
            Color.clear
            // `.leading`, never the default `.center`: the two halves are
            // different widths by design, and a centred stack would push the
            // narrower one's right edge *past* `drawerWidth` by half the
            // difference — which reproduced the very sliver this split removes,
            // just shifted. It would also unpin the left edge §5.3 exists to
            // keep fixed.
            VStack(alignment: .leading, spacing: 0) {
                IslandShape(roundsBottom: drawerBelow == 0)
                    .fill(Color(islandGroundColour))
                    .overlay(alignment: .topLeading) { content(cell: cell) }
                    .clipShape(IslandShape(roundsBottom: drawerBelow == 0))
                    // The reveal is dropped while a drawer is open, and this is
                    // the second half of the sliver fix rather than an extra.
                    //
                    // `model.hovering` is *true* throughout an open drawer in
                    // production, which is not obvious: `click()` toggles
                    // `model.drawerOpen` and never touches `NotchController.tier`,
                    // so that tier stays `.hover` and `reflow()`'s
                    // `model.hovering = (tier == .hover)` stays true — and it has
                    // to, because `panel.acceptsClicks` is gated on it, so a
                    // drawer you cannot hover is a drawer you cannot answer.
                    //
                    // So without this, an open drawer permanently showed a
                    // collapsed bar `hoverReveal` points wider than itself: a
                    // step off to the right of every question, for as long as the
                    // question was up. §6.1's tiers are progressive — Rest, then
                    // Hover, then Click — so once the drawer is open the reveal
                    // has already done its job, and dropping it makes the bar and
                    // the drawer exactly the same width (`restingWidth` and
                    // `drawerWidth` are both 273.1 on the mbp14 fixture). One
                    // column, which is what §9.1's "one body with mass" asks for
                    // and what the prototype does with its single element.
                    .frame(width: restingWidth + (drawerBelow > 0 ? 0 : hoverRevealWidth),
                           height: model.geometry.notch.height)
                if drawerBelow > 0 {
                    IslandShape()
                        .fill(Color(islandGroundColour))
                        .frame(width: model.drawerWidth, height: drawerBelow)
                }
            }
            // The aura traces the *whole* rendered alpha, rounded corners
            // included (§9.2) — so it goes on the stack, not on either half.
            // Applied per-half it would trace two shapes and draw a seam of glow
            // between them, and §9.2's own reason for being a shadow rather than
            // an overlay is that it follows the drawer down for free.
            .shadow(color: Color(auraTint.colour)
                        .opacity(model.aura.opacity(at: now, tint: auraTint)),
                    radius: 18, x: 0, y: 2)
                .offset(x: localOrigin.x, y: localOrigin.y)
                // Design §9.1. Width overshoots more than height so the island
                // reads as one body with mass rather than a resizing box. The
                // panel itself never moves (Task 9's whole point) — only this
                // silhouette, inside it, animates.
                .animation(.spring(response: IslandMotion.response,
                                   dampingFraction: IslandMotion.widthDamping),
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
                // Fix round 1: the click that opens the drawer. Scoped to
                // this shape's own rect (`restingWidth + hoverRevealWidth` ×
                // `body.height`, offset within the panel) via `.contentShape`
                // — not the outer `.frame` below, which is the full,
                // oversized panel width and would otherwise make the entire
                // unused margin tappable too. `model.onIslandClick`, not a
                // direct `NotchController` reference: `IslandBody` only ever
                // holds `model`, and `NotchController.present()` is what
                // wires this closure to `click()` — see that property's own
                // doc comment. A no-op via `?()` if nothing is listening yet
                // (a fresh model with no controller behind it, as most
                // renders in this test suite are).
                .contentShape(IslandShape())
                .onTapGesture { model.onIslandClick?() }
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
