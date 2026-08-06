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
        //
        // Plan 5: no longer `let question = model.question` alongside the
        // tier check — `model.tier` reaches `.drawer` with no question at
        // all now (an open session list), and `DrawerView`'s own `question`
        // parameter is optional for exactly that case (see its own doc
        // comment). Requiring a question here would have reintroduced the
        // bug `IslandModel.tier`'s restructure just fixed, one level up.
        .overlay(alignment: .topLeading) {
            if case .drawer = model.tier {
                // model.drawerWidth, not model.frames.body.width (finding 5
                // of the final whole-branch review): the latter carries the
                // collapsed pill's own hover reveal, which nothing in the
                // drawer's content needs — see `IslandModel.drawerWidth`'s
                // own doc comment for why the drawer's width holds steady
                // regardless of where the cursor drifts while it is open.
                DrawerView(question: model.question, sessions: model.sessions,
                           options: model.cardOptions, rowQuestions: model.questions,
                           onDismiss: { model.onDismiss?($0) },
                           accent: model.state.accent, width: model.drawerWidth,
                           // The same 20pt the drawer half of `IslandBody`'s
                           // silhouette draws, from the same
                           // `IslandTier.bottomRadius`. It has to be: this fills
                           // directly over that half in the identical ground
                           // colour, so the visible corner is the union of the
                           // two, and the shallower one wins. A `DrawerView` left
                           // at the collapsed 15 paints a 15pt corner over a
                           // correct 20pt one and nothing else changes.
                           bottomRadius: model.tier.bottomRadius,
                           onAnswer: { model.onAnswer?($0) },
                           muted: model.muted,
                           onToggleMute: { model.onToggleMute?() },
                           onOpenSettings: { model.onOpenSettings?() })
                    .padding(.leading, drawerLeadingOffset)
                    .padding(.top, model.geometry.notch.height)
            }
        }
        // Gated by §9.3 since Plan 6.3 Task 5, like the island's other five clocks
        // — see `IslandMotion.gated`. The height spring itself now runs 30ms longer
        // than the width's, which is `IslandMotion.heightResponse`'s job and not
        // this line's.
        .animation(IslandMotion.gated(IslandMotion.heightSpring, by: model.motion), value: drawerHeight)
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
        if case let .drawer(face) = model.tier { return face.height }
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
/// The third rung of the same family, `--dim`, is `dimColour` below — it was
/// missing here until the second mockup-fidelity wave, and its absence is why
/// every quiet field in §11's row was drawn one rung too bright.
let boneColour = RGBA(hex: "#EDEFF4")!
let hazeColour = RGBA(hex: "#8A93A6")!

/// `--dim`, the third rung of the same ladder, which the prototype spends **13
/// times** and which we had folded into `hazeColour` everywhere — flattening a
/// three-tier ink hierarchy to two and making §11's row read busier than the
/// mockup it was drawn from.
///
/// Which fields take it is read off the prototype's CSS field by field, never
/// guessed from the name: in the row block (lines 344–388) `--dim` is `.rmeta`,
/// `.rsaid`, `.rwt`, `.rblock .bh em`, `.tk.done`, `.ag .m` and `.rblock .sub`,
/// while `.tk`, `.ag` and `.rblock .bh` stay `--haze`. The rule that falls out of
/// that list: **`--haze` is a field you read, `--dim` is a field you refer back
/// to** — a timestamp, a summary in brackets, a done item, a machine detail.
///
/// `#5A6273` is also `IslandState.dormant.accent`, and this token is deliberately
/// **not** written as `IslandState.dormant.accent`. That would state a dependency
/// that does not exist: the prototype's `--dim` and its dormant grey are the same
/// hex because the palette has one cool grey ramp and both want its darkest rung,
/// not because a dim label is in any sense dormant. Tying them together would
/// mean a future retune of the dormant island silently repainted every timestamp
/// in the drawer.
let dimColour = RGBA(hex: "#5A6273")!

/// `.ract em` — the ink of the command on §11's line 2, `#B9C4D6`.
///
/// The only colour in the prototype's row CSS that is neither a `--var` nor a
/// state hue, and the reason it exists is legible from where it sits: the command
/// has to outrank the sentence around it without being promoted all the way to
/// `--bone`, which line 1's project name owns. Substituting `boneColour`
/// preserved the emphasis and overstated it — two fields on different lines then
/// claimed the row's brightest ink.
let commandColour = RGBA(hex: "#B9C4D6")!

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
        Self.phase(at: now, cycle: model.mood.motion.cycle, motion: model.motion)
    }

    /// 0…1 through `cycle` at `now`, or a **fixed** 0 when §9.3 says nothing
    /// may move. Shared by `phase` and `badgePhase` so the two cannot disagree
    /// about what a suppressed cycle looks like.
    ///
    /// ## Why `off` returns a constant, and why 0 is the constant
    ///
    /// This property used to read `now` and the cycle and consult
    /// `MotionPreference` for nothing at all. With motion `off`,
    /// `IslandModel.needsTimeline` is false, so `IslandView` hands the body a
    /// single arbitrary `Date()` — and this divided it by the cycle and returned
    /// a fraction. The pose was therefore whatever instant the view happened to
    /// be built at: **not merely still, but randomly still.** `ResolvedCat
    /// .applyFace` shuts `trot`'s eyes for `phase > 0.92`, so roughly one launch
    /// in twelve gave a *running* cat its eyes closed for as long as it ran, and
    /// `Badge.holes(at:)` put `bang` at one of its two positions by coin toss.
    ///
    /// So the fix is a *chosen* pose, not the absence of one, and it is the same
    /// pose every launch. **0 is the rest frame**, and that is the prototype's
    /// own answer rather than an invention:
    ///
    /// - `island-motion.html:439` is the mockup's whole reduced-motion rule —
    ///   `@media (prefers-reduced-motion:reduce){*{animation:none!important}}`.
    ///   A CSS element with no animation renders at its **base** style, which for
    ///   every badge and the cat is the untransformed one, and every one of the
    ///   mockup's keyframe sets names that same pose at `0%`
    ///   (`@keyframes quad{0%,100%{transform:scale(.5)…}}`, `zfloat`, `twinkle`).
    /// - It cannot be mid-blink: `applyFace` blinks strictly above 0.92.
    /// - It is `bang`'s lower, resting mark (`holes(at:)` shifts up only past 0.5).
    ///
    /// `reduced` is deliberately identical to `full` here. `MotionPreference
    /// .resolve(_:)` expresses reduced purely as halving `framesPerSecond`,
    /// leaving `cycle` untouched, so where a cycle *is* at a given instant does
    /// not change — only how often it is sampled, which
    /// `IslandView.minimumInterval(for:)` already applies off the resolved
    /// profile. Freezing or slewing the phase here as well would reduce it twice.
    ///
    /// The gate is `MotionPreference.allowsMotion` and not the resolved
    /// profile's own `cycle`; see that property for the two reasons, of which the
    /// sharp one is that `resolve(_:)` returns an already-still profile unchanged
    /// at every level, so `bang`'s 1.1s cycle survives `.off` intact.
    ///
    /// `internal static`, so `MotionBypassTests` can pin the rule directly as
    /// well as through a render.
    static func phase(at now: Date, cycle: TimeInterval, motion: MotionPreference) -> Double {
        guard motion.allowsMotion, cycle > 0 else { return 0 }
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
    /// Goes through `MotionPreference` exactly as `phase` does — the note that
    /// stood here recorded the bypass as "a separate, already-noted follow-up"
    /// and said fixing one property without the other would leave them
    /// inconsistent. Both are fixed, in the one shared `phase(at:cycle:motion:)`
    /// above, which is where the reasoning for the `off` pose lives. `bang` is
    /// the badge that actually reads this, and it is the badge that was frozen
    /// at a random one of its two positions.
    private var badgePhase: Double {
        Self.phase(at: now, cycle: model.badge.motion.cycle, motion: model.motion)
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
    /// **Tier-aware since Plan 6.3 Task 1, and that is what makes the open island
    /// one body rather than two.** `tier: .rest` was hardcoded here, so with a
    /// drawer open the collapsed bar above the notch line stayed at its collapsed
    /// 273.1pt while the drawer below it took the face's own 560 — a 287pt step
    /// across exactly the line §9.1 says the island must read as continuous.
    /// Passing `model.tier` gives both halves the same number. It changes nothing
    /// while the drawer is closed: `.rest` and `.hover` both fall to
    /// `leftFlank + notch + rightFlank` in `IslandGeometry.frames`, which is what
    /// the hardcoded `.rest` always computed.
    ///
    /// Still hover-independent, which is the property the split above depends on:
    /// `.rest` and `.hover` differ in name only as far as width goes, and the open
    /// width does not consult the flanks at all.
    var restingWidth: CGFloat {
        #if DEBUG
        Self.restingWidthReadCount += 1
        #endif
        let resting = CollapsedLayout(right: model.layout.right, hovering: false)
        return model.geometry.frames(rightFlank: resting.rightFlankWidth,
                                     tier: model.tier).body.width
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

    /// How much of the body's height sits *below* the notch line: an open
    /// drawer's own height, and `0` whenever no drawer is open.
    ///
    /// One expression, read by three places that each need the same answer —
    /// the two silhouette rects in `body` and the hover reveal in
    /// `content(cell:)`. It used to be a `let` local to `body`, which is
    /// precisely why `content(cell:)` could not consult it and F1 happened.
    var drawerBelowNotch: CGFloat {
        max(0, model.frames.body.height - model.geometry.notch.height)
    }

    /// The hover reveal's width **as actually laid out**: `hoverRevealWidth`
    /// with the drawer open case subtracted back out.
    ///
    /// §6.1's tiers are progressive — Rest, then Hover, then Click — so once
    /// the drawer is open the reveal has already done its job. Dropping it
    /// makes the collapsed bar and the drawer exactly the same width
    /// (`restingWidth` and `drawerWidth` are both `DrawerFace.width`'s 560 on the
    /// mbp14 fixture, since Plan 6.3 Task 1 gave the open tier a width and
    /// `restingWidth` began reading it; both were 273.1 before that, for the same
    /// reason — they agree, whatever the number is):
    /// one column, which is what §9.1's "one body with mass" asks for and what
    /// the prototype does with its single element. Without it, an open drawer
    /// showed a collapsed bar `hoverReveal` points wider than itself — a step
    /// off to the right of every question, for as long as the question was up.
    ///
    /// That `model.hovering` is *true* throughout an open drawer is not
    /// obvious, and is what makes this the ordinary case rather than an edge:
    /// `NotchController.click()` toggles `model.drawerOpen` and never touches
    /// the controller's own `tier`, so that tier stays `.hover` and
    /// `reflow()`'s `model.hovering = (tier == .hover)` stays true — and it has
    /// to, because `panel.acceptsClicks` is gated on it, so a drawer you cannot
    /// hover is a drawer you cannot answer.
    ///
    /// **Why this is a property and not two expressions** (F1 of the final
    /// whole-branch review): Task 1 subtracted the reveal from the silhouette's
    /// `.frame` alone and left `content(cell:)` laying `RevealContent` out at
    /// the full `CollapsedLayout.hoverReveal` whenever `model.hovering`. The
    /// `HStack` then overran a frame with no room for it and SwiftUI squeezed
    /// the only flexible child — §5.4's session-count `Text`. Measured off the
    /// render, accent pixels to the right of the cutout: 13 closed+hover, 13
    /// open+no-hover, **0** open+hover. Through `NSHostingView` the digit came
    /// out as a clipped "p". Both call sites reading this one property is the
    /// fix; `theRightFlanksContentIsNeverSqueezedByTheHoverReveal` is the test (renamed
    /// from `theSessionCountSurvivesAnOpenDrawerWhileHovering` by Task 6, which
    /// replaced the count with a label while open — see that test).
    /// **Plan 6.3 Task 2: the predicate is now `model.tier.takesHoverReveal`,
    /// not `drawerBelowNotch > 0`.** The two give the same answer today — a body
    /// is taller than the notch exactly when `IslandTier.extraHeight` is
    /// non-zero, and every `DrawerFace.height` is positive — but they are not the
    /// same *question*. "Is any of the body below the notch line" is a fact about
    /// the height, and it was deciding a rule about the width; a face that ever
    /// took height 0 would have silently put the reveal back. `takesHoverReveal`
    /// is where that rule is stated, alongside the width half of it in
    /// `IslandGeometry.frames`, so both halves move together or neither does.
    var revealWidth: CGFloat {
        model.tier.takesHoverReveal ? hoverRevealWidth : 0
    }

    /// The bottom radius this island draws right now — 15 collapsed, 20 open.
    /// Plan 6.3 Task 5.
    ///
    /// A one-line forward to `IslandTier.bottomRadius`, which is where the rule and
    /// its reasoning live, exactly as `revealWidth` forwards to
    /// `takesHoverReveal`. Here so `body` names the quantity once and the two
    /// silhouette halves, the clip shape and the `.animation`'s `value:` cannot
    /// drift into four readings of it.
    ///
    /// Not `private`: `theOpenAndCollapsedRadiiAreTheTwoPrototypeValues` reads it
    /// directly, the same compile-time protection `restingWidth` has.
    var bottomRadius: CGFloat { model.tier.bottomRadius }

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
        let drawerBelow = drawerBelowNotch
        // Plan 6.3 Task 5. `island-motion.html:86` is the third clause of the one
        // rule that moves the island's shape: `transition:width var(--t-shape)
        // var(--spring-w), transform … var(--spring-w), border-radius
        // var(--t-shape) var(--ease)`. So the radius shares the width's *clock* and
        // not its *curve* — 440ms, on the bezier, deliberately not on the
        // overshooting spring, because a corner that overshoots past 20pt and
        // settles back is a wobble and a width that does it is mass.
        //
        // One `let` feeding both silhouette halves rather than
        // `IslandMotion.ease(duration:)` at each: the two are stacked in the same
        // colour, so the visible corner is the *union* of their coverage and a pair
        // that disagreed mid-transition would paint the shallower of the two. It
        // also keeps `IslandView.swift` at three `--ease` call sites rather than
        // four, which is the number `theFiveEaseSitesAllRouteThroughIslandMotion`
        // now pins.
        let radiusMorph = IslandMotion.gated(
            IslandMotion.ease(duration: IslandMotion.shapeDuration), by: model.motion)

        // Plan 5, Task 1: **two** silhouette rects, not one.
        //
        // One rect could not carry two different widths, and since Task 8 it was
        // being asked to. `body.height` includes an open drawer's own height, and
        // Plan 4 deliberately made the drawer's width hover-independent — so a
        // single hover-coupled rect spanning both painted `hoverReveal` points of
        // island ground straight down the right of the drawer, over ~92% of its
        // height. Not "appearing and disappearing with the cursor" — that
        // understates it, and the comment on the `.frame` below says so 40 lines
        // later: `model.hovering` stays *true* for the whole life of an open
        // drawer, so in production the sliver stood there for as long as the
        // question did. Measured before this: the ground colour at 2pt past the
        // drawer's own right edge, 60pt below the notch line.
        //
        // The collapsed half rounds nothing while the drawer is open
        // (`roundsBottom:`) — two rounded shapes stacked would put a pair of
        // corners across the middle of one body, a seam at exactly the line the
        // island is meant to read as continuous across.

        ZStack(alignment: .topLeading) {
            Color.clear
            // `.leading`, never the default `.center`: the two halves are
            // different widths by design, and a centred stack would push the
            // narrower one's right edge *past* `drawerWidth` by half the
            // difference — which reproduced the very sliver this split removes,
            // just shifted. It would also unpin the left edge §5.3 exists to
            // keep fixed.
            VStack(alignment: .leading, spacing: 0) {
                // `filletRadius:` on **this** half and on its clip, and on
                // nothing else in the tree. Plan 6.3 Task 6: the top corners weld
                // to the bezel over `IslandGeometry.filletRadius`
                // (`island-motion.html:94–100`), and this is the only shape that
                // touches the bezel. The clip has to carry the same number or it
                // masks the welds straight back off — see `IslandShape.filletRadius`.
                IslandShape(roundsBottom: drawerBelow == 0, bottomRadius: bottomRadius,
                            filletRadius: IslandGeometry.filletRadius)
                    .fill(Color(islandGroundColour))
                    .overlay(alignment: .topLeading) { content(cell: cell) }
                    .clipShape(IslandShape(roundsBottom: drawerBelow == 0,
                                           bottomRadius: bottomRadius,
                                           filletRadius: IslandGeometry.filletRadius))
                    // **Where the radius transition is declared.** On this half and
                    // not the drawer's because this is the half that *persists*
                    // across the gesture — SwiftUI does not interpolate the
                    // `animatableData` of a view it is inserting, so a modifier on
                    // the conditionally-inserted drawer half below could never fire.
                    //
                    // Written *above* the `.frame` on purpose, the same mechanism
                    // `content(cell:)`'s two reveal clocks use:
                    // `.animation(_:value:)` governs what is below it in the chain,
                    // so this reaches the fill and the clip shape — the two things
                    // whose radius it is about — and the outer
                    // `.animation(widthSpring, value: restingWidth)` keeps the
                    // frame's own width. Hoisted outside the `.frame` it would take
                    // the width off §9.1's spring and onto a bezier on every click,
                    // since both values change on the same gesture.
                    //
                    // **Recorded divergence, Plan 6.3 Task 5: today this
                    // interpolation is masked, and the corner still hard-cuts.**
                    // Plan 5 split the silhouette in two, and the bottom corner
                    // therefore changes *owner* at the instant the drawer opens —
                    // this half stops rounding (`roundsBottom:` below) and the
                    // drawer half appears already at 20. So what the eye sees is a
                    // 20pt corner unrolling as the drawer's own height clamps the
                    // radius (`IslandShape.path`'s `min(r, rect.height, …)`), on the
                    // height spring's clock, not a 15→20 bezier on 440ms. The
                    // *values* are the prototype's at both ends, which is what
                    // `theOpenIslandsBottomCornerIsTheProtoypes20ptAndTheCollapsed
                    // OneIsStill15` measures; the 440ms in between is not reachable
                    // without re-unifying the two halves. Not done here: since Task
                    // 1 gave the open tier a width and `revealWidth` drops the
                    // reveal, the two halves are the same width whenever a drawer is
                    // open, so re-unifying is now *possible* — but the split also
                    // pins `.contentShape`'s tappable rect and the aura's traced
                    // alpha, and that is a structural change, not a radius one.
                    //
                    // **Ruled on 2026-08-05 by Task 6, which was asked to decide it
                    // rather than carry it again: the halves stay split, and the
                    // 440ms transit stays unreachable.** Three reasons, in the order
                    // that decided it.
                    //
                    // 1. **The height clamp is the mechanism, not the insertion**,
                    //    and that kills the cheap version of the fix. The obvious
                    //    move is to stop *inserting* the drawer half — keep it in the
                    //    tree at height 0 so it persists across the gesture and its
                    //    `animatableData` can interpolate. It would persist, and it
                    //    would still not transit: `IslandShape.path` clamps the
                    //    radius with `min(r0, rect.height, rect.width / 2)`, so a
                    //    half 3pt tall cannot paint a 20pt corner whatever its
                    //    `bottomRadius` says. The visible corner would still unroll
                    //    on the height's clock. Only a shape that is already
                    //    `notch.height` tall at t=0 — one shape, spanning both — has
                    //    a corner free to run 15 → 20 on a bezier.
                    // 2. **Unification would put the width and the height under one
                    //    `.animation` chain, and Task 5's 30ms lag is exactly what is
                    //    at stake.** One shape means one `.frame(width:height:)`, and
                    //    both of its numbers change on the click, so keeping the
                    //    width on `widthSpring` and the height on `heightSpring`
                    //    would rest on SwiftUI resolving two nested
                    //    `.animation(_:value:)` modifiers per enclosed frame modifier
                    //    rather than per subtree. **That is reasoned, not measured**,
                    //    and it cannot be measured here: this suite has no way to
                    //    sample intermediate frames of a live SwiftUI animation (see
                    //    `theRadiusIsTheShapesAnimatableData`, which records the same
                    //    limit — one frame of a hard cut and one frame of a finished
                    //    interpolation are the same picture). So the trade is a
                    //    *verified* hard cut between two verified endpoints against an
                    //    *unverifiable* interpolation that risks a lag no test in this
                    //    repo could see disappear.
                    // 3. The original two costs still stand, and Task 6 added a
                    //    third: `.contentShape`'s tappable rect, the aura's traced
                    //    alpha, and now the fillets — which belong to the half that
                    //    touches the bezel and would have to stay conditional inside
                    //    a unified path.
                    //
                    // What would change the ruling is not a better radius argument,
                    // it is a harness that can sample a running animation's frames.
                    // That is test infrastructure, and it is worth more than this
                    // corner: it is the same instrument every `.animation` claim in
                    // this file is currently asserted around rather than through.
                    .animation(radiusMorph, value: bottomRadius)
                    // `revealWidth`, not `hoverRevealWidth`: the reveal is
                    // dropped while a drawer is open (see that property for why),
                    // and this frame and `content(cell:)`'s own reveal frame now
                    // read the *same* property so they cannot disagree about how
                    // wide it is. They did disagree, and that was F1 of the final
                    // whole-branch review — see `revealWidth`'s doc comment.
                    .frame(width: restingWidth + revealWidth,
                           height: model.geometry.notch.height)
                if drawerBelow > 0 {
                    // The half that actually *shows* the open radius: while a
                    // drawer hangs below it the collapsed half rounds nothing, so
                    // 20pt is drawn here and by `DrawerView`'s own fill on top of
                    // it. Both read `IslandTier.bottomRadius`.
                    IslandShape(bottomRadius: bottomRadius)
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
                // `IslandMotion.widthSpring`, not an inline
                // `.spring(response:dampingFraction:)`: the assembled-here
                // version is what let Plan 6.3 Task 2's mutation — this site
                // reading `heightDamping` — pass the whole suite. The named
                // accessor is counted, so it cannot silently become the other
                // half of §9.1. See `IslandMotion.widthSpringReadCount`.
                //
                // **Through `IslandMotion.gated`, Plan 6.3 Task 5.** §9.3's motion
                // `off` reached the cat, the badge and their phases (Plan 6.1 Task
                // 2) and none of the island's own six clocks; see `gated`'s doc
                // comment for what `off` and `reduced` mean for a transition and
                // why that is not the same answer Task 2 gave for a loop.
                .animation(IslandMotion.gated(IslandMotion.widthSpring, by: model.motion), value: restingWidth)
                // **The hover's SHAPE clock — the first of hover's three, and the
                // same spring as the click above.** Kept as a second modifier
                // rather than folded into the first because the two are keyed to
                // independent inputs: toggling `hovering` alone leaves
                // `restingWidth` unchanged, so that modifier has nothing to react
                // to and this one governs; when only the session count changes it
                // is the other way round. Keying both to `body.width` instead
                // would let whichever came last swallow the other, which is also
                // why a naive `withAnimation(…)` wrapped around the `hovering`
                // mutation does not work here.
                //
                // **`IslandMotion.widthSpring`, not `IslandMotion.ease(duration:
                // 0.28)`, since Plan 6.3 Task 4.** The prototype's line 84–85 is
                // `.island{transition:width var(--t-shape) var(--spring-w),
                // transform var(--t-shape) var(--spring-w)}` — one rule, covering
                // *every* width change the island makes, hover included. Line 125's
                // `--t-hover`/`--ease` governs the `.detail` element inside it, not
                // the island, and that is now where our two `--ease` clocks live
                // too (see `content(cell:)`). So this modifier and the one above
                // are the same curve because the prototype has one width rule, not
                // because one is doubling for the other.
                //
                // What it buys, measured: `--spring-w` peaks at **108.0%** of its
                // travel at 230ms and `widthSpring` at **108.4%** at 268ms, where a
                // 280ms `--ease` never exceeds 100%. §9.1 — width overshoots more
                // than height so the island reads as one body with mass — was
                // wired on the click since Task 2 and **absent on hover**, which is
                // a width change. On a 150pt reveal the island now runs 12.5pt past
                // its hovered width and settles back. `IslandMotion.hoverReveal
                // Duration`'s doc comment carries the full before/after table
                // including what this costs on the front half of the gesture.
                .animation(IslandMotion.gated(IslandMotion.widthSpring, by: model.motion), value: hoverRevealWidth)
                // Fix round 1: the click that opens the drawer. Scoped to
                // the stack's own rect via `.contentShape` — that is
                // `restingWidth + revealWidth` wide by `body.height` tall,
                // offset within the panel, so with a drawer open it is the
                // collapsed bar and the drawer together at the one shared
                // width and *not* `restingWidth + hoverRevealWidth`, which is
                // 150pt wider than anything painted (see `revealWidth`)
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
                          cellSize: cell, motion: model.motion)
                    .frame(width: LeftFlankLayout.catWidth, height: 14)
                BadgeCanvas(badge: model.badge, phase: badgePhase,
                            tint: model.state.accent, cellSize: 2, motion: model.motion)
                    .frame(width: LeftFlankLayout.badgeWidth,
                           height: LeftFlankLayout.badgeWidth)
            }
            .padding(.leading, LeftFlankLayout.leadingPadding)
            .padding(.trailing, LeftFlankLayout.trailingPadding)

            // The dead zone. Never a view — just the width of the cutout.
            Color.clear.frame(width: model.geometry.notch.width)

            // **While a face is open the right flank is a label, not a number**
            // (Plan 6.3 Task 6; found by Task 1 and deferred to here).
            // `island-motion.html:474–476` gives the `ask`, `askmulti` and `list`
            // faces a `.face.r` holding a mark and a `.label` — "Claude Code",
            // "4 sessions" — and `:115–118` right-aligns it
            // (`.flank.r{justify-content:flex-end}`,
            // `.flank .face.r{padding:0 15px 0 12px}`). Ours showed §5.4's session
            // count in every tier.
            //
            // The `Spacer` is what right-aligns it, and it is inside the `if` on
            // purpose: collapsed, the flanks are measured from their own content
            // (§5.4) and this `HStack` is exactly as wide as their sum, so a
            // spacer there would be 0pt at rest and would fight `RevealContent`
            // for the 150pt reveal while hovering.
            //
            // **Three siblings rather than an if/else over the whole tail, and
            // that is not a style choice.** `RevealContent` below has to stay in
            // the tree at both tiers, for the reason its own comment gives at
            // length — dropping the subview replaces its 280ms clip with an
            // uninterpolated pop, and closing the drawer while hovering is exactly
            // when the reveal has to animate back in. Wrapping it in an `else`
            // also took `IslandBody`'s gated-clock count from 5 to 3 while a
            // drawer was open, which
            // `motionOffSuppressesEveryOneOfTheIslandsSixClocks` reported
            // immediately. So the count is suppressed and the label added, and
            // the reveal is untouched by either.
            if model.tier.openFace != nil { Spacer(minLength: 0) }
            if let face = model.tier.openFace {
                openFlank(face: face)
            } else {
                rightFlank
            }

            // §9.1/§5.2's hover reveal: the session's name and elapsed time,
            // filling the 150pt `CollapsedLayout.hoverReveal` already reserves
            // once hovering — see `rightFlankWidth`'s own `reveal` line. Width
            // (not just opacity) is driven by `revealWidth` too, and
            // `.clipped()` is load-bearing: §5.1 forbids content in the
            // cutout's columns, and an unclipped `Text` at width 0 still
            // paints past its frame.
            //
            // `revealWidth`, **not** `model.hovering`: this is the half of F1's
            // fix that lives here. The enclosing `IslandShape`'s own frame is
            // `restingWidth + revealWidth`, so laying this out at any width that
            // property does not agree with overruns the frame and SwiftUI
            // squeezes whichever child is flexible — which is §5.4's session
            // count, not this. See `revealWidth`'s doc comment for the measured
            // before/after.
            //
            // Kept as a zero *width* rather than an `if` that drops the subview:
            // the drawer-closed hover reveal has to keep behaving exactly as it
            // did, and the `.animation(IslandMotion.ease(duration:
            // IslandMotion.hoverRevealDuration), value: revealWidth)` below
            // animates this frame's width. An `if` would replace that 280ms clip
            // with an uninterpolated pop. Width 0 + `.clipped()` is already
            // measured to paint nothing at all — the drawer-open, not-hovering
            // render counts 0 `--bone` pixels — so "no width" is also "no
            // content" here, and `.opacity` is not what carries it.
            //
            // **Correction, 2026-08-04 (Plan 6.1 Task 2).** That last clause used
            // to read "`.opacity` (which `ImageRenderer` is on record as
            // ignoring)". `ImageRenderer` does *not* ignore it: measured directly,
            // an `.opacity(0)` inside a rendered tree renders 0 opaque pixels.
            // What the earlier reading actually saw was `onAppear` firing under
            // `ImageRenderer` — it does, and its state change reaches the same
            // render — which flipped `BadgeCanvas.pulsing` to true and took the
            // opacity to 1 before anything was drawn. The sentence's own
            // conclusion is unaffected: width 0 plus `.clipped()` is what makes
            // this paint nothing, and that half was measured.
            // **Hover's second and third clocks, and the order below is what
            // assigns each one to its own property.** `island-motion.html:125`:
            // `transition:max-width var(--t-hover) var(--ease),opacity 160ms
            // var(--ease),margin var(--t-hover) var(--ease)` — the `.detail`'s
            // width and margin run 280ms, its opacity 160ms, and until Plan 6.3
            // Task 4 both of those plus the island's own shape were one
            // `.animation(IslandMotion.ease(duration: 0.28))` on the enclosing
            // stack. Three clocks is a shorter fade *inside* a container still
            // widening: at 160ms the reveal's own width is at 97.0% of 150pt, so
            // the text reads as uncovered rather than as arriving.
            //
            // `.animation(_:value:)` governs the modifiers **below** it in the
            // chain and is overridden by any nearer one, so the fade animation
            // sitting between `.opacity` and `.frame` is what makes 160ms the
            // opacity's clock and 280ms the width's — and it is also what keeps
            // the enclosing stack's `widthSpring` from reaching either. That
            // ordering is the whole mechanism, so
            // `theRevealsTwoClocksSitOnTheirOwnProperties` asserts it against this
            // file's own source rather than trusting the comment: SwiftUI offers no
            // way to ask a built view which curve is on which modifier, and this
            // repo does not take a view-inspection dependency.
            RevealContent(session: model.revealed, now: now)
                .opacity(revealWidth > 0 ? 1 : 0)
                .animation(IslandMotion.gated(IslandMotion.ease(duration: IslandMotion.hoverFadeDuration), by: model.motion),
                           value: revealWidth)
                .frame(width: revealWidth, alignment: .leading)
                .clipped()
                .animation(IslandMotion.gated(IslandMotion.ease(duration: IslandMotion.hoverRevealDuration), by: model.motion),
                           value: revealWidth)
        }
        .frame(height: model.geometry.notch.height)
    }

    /// The right flank **while a drawer is open**: the mark, then the face's own
    /// label, right-aligned against the island's edge.
    ///
    /// `island-motion.html:474–476` and `:115–118`. Measured off the running
    /// prototype rather than read off the CSS, because three paddings nest here:
    /// the mark is `16pt`, the label is `12.5px` `--bone` with `margin-left:9px`,
    /// and the label's right edge sits **15pt** from the island's own right edge
    /// (`.flank .face.r`'s `padding-right`, which wins over the flank's own 12px
    /// because the face is `inset:0` inside it).
    ///
    /// The mark is tinted by the state accent, not by identity — §4.3's closing
    /// sentence and `.mark{color:var(--accent)}`, the same rule `SessionRow`'s own
    /// mark follows. Shape says who; hue says what state.
    @ViewBuilder private func openFlank(face: DrawerFace) -> some View {
        HStack(spacing: OpenFlankLayout.gap) {
            CLIMarkView(mark: openMark(face: face), side: OpenFlankLayout.markSide,
                        colour: accent)
            Text(openLabel(face: face))
                .font(.system(size: OpenFlankLayout.labelSize))
                .foregroundStyle(Color(boneColour))
                .lineLimit(1)
                // §11's own rule, and for the same reason: what is being truncated
                // is an identity, and the tail of a CLI's name is what
                // distinguishes two versions of it.
                .truncationMode(.middle)
        }
        .padding(.trailing, OpenFlankLayout.trailingPadding)
    }

    /// The prototype's own three numbers for the open flank, named for the same
    /// reason `LeftFlankLayout`'s are: so a test can pin them against the mockup
    /// rather than against a literal repeated at the call site.
    enum OpenFlankLayout {
        /// `.mark{width:16px}`.
        static let markSide: CGFloat = 16
        /// `.label{margin-left:9px}`.
        static let gap: CGFloat = 9
        /// `.flank .face.r{padding:0 15px 0 12px}`, measured as 15pt from the
        /// island's right edge to the label's.
        static let trailingPadding: CGFloat = 15
        /// `.label{font-size:12.5px}`.
        static let labelSize: CGFloat = 12.5
    }

    /// Which mark the open flank shows.
    ///
    /// A question's own CLI, and **`.generic` for the list** — which is the
    /// prototype's own choice (`data-face="list" data-mark="generic"`) and not a
    /// fallback: a list can hold sessions from several CLIs at once, so no single
    /// mark is true of it, and its label is a count rather than an identity.
    func openMark(face: DrawerFace) -> CLIMark {
        guard face != .sessionList, let cli = model.question?.event.cli else { return .generic }
        return CLIMark(cli: cli)
    }

    /// What the open flank says: the CLI's name for a question, the row count for
    /// the list. `island-motion.html:474–476` — "Claude Code", "4 sessions".
    ///
    /// The singular is ours; the mockup has only its own four-session fixture. A
    /// one-session list is reachable (§4.2 opens the list whenever no question is
    /// pending), and "1 sessions" in the one place the island writes a sentence
    /// would be the kind of detail that makes everything around it look unfinished.
    func openLabel(face: DrawerFace) -> String {
        guard face == .sessionList else {
            return CLIMark.displayName(cli: model.question?.event.cli ?? "")
        }
        let n = model.sessions.count
        return n == 1 ? "1 session" : "\(n) sessions"
    }

    /// The right flank's content **while collapsed** — §5.4's count, §6.2's icon,
    /// or nothing.
    ///
    /// ## Two divergences found by Task 6's browser diff, both left standing
    ///
    /// Measured on the running prototype rather than read off its CSS, and both
    /// belong to Plan 6.6, which owns the right flank's content picker:
    ///
    /// - **Order.** The prototype's collapsed flank is `[.detail][.tally]` — the
    ///   revealed text sits to the **left** of the numbers, with
    ///   `.detail{margin-right:9px}` separating them
    ///   (`island-motion.html:130–131`). Ours is `[count][RevealContent]`. Not
    ///   swapped here, because the order is only observable together with the item
    ///   below, and swapping one of the two leaves the flank half-migrated: today
    ///   our number would slide 150pt right on every hover, where the prototype's
    ///   number stays put and the text opens beside it.
    /// - **Content.** The prototype shows **one number per state, most urgent
    ///   first**, each in its own state hue — measured on its `multi` state, the
    ///   tally is `<b>1</b><b>2</b>` with `--accent: var(--waiting)` and
    ///   `var(--running)` on the two. Ours shows a single session count, which is
    ///   what §6.2 asks for ("session count (default), agent icon, or nothing").
    ///   **This is a spec-against-prototype disagreement, not a defect**, and it is
    ///   the one item in this file where the spec is the narrower of the two.
    @ViewBuilder private var rightFlank: some View {
        switch model.layout.right {
        case .nothing:
            EmptyView()
        case .agentIcon:
            CLIMarkView(mark: collapsedMark, side: CollapsedLayout.iconWidth, colour: accent)
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

    /// Which mark `.agentIcon` draws. Plan 6.6's Task 5, conflict 2.
    ///
    /// **Ruling: land the mark, not the empty rounded square this case used to
    /// draw.** §6.2 offers the option and §4.3 requires shape to carry identity
    /// — "which agent is speaking is carried by its icon shape" — and a blank
    /// `RoundedRectangle` said nothing about which agent that was. Plan 6.1
    /// shipped it selectable-and-blank and recorded that as a rule this plan must
    /// not repeat: do not ship a picker for a placeholder.
    ///
    /// **Whose mark, when several sessions from different CLIs are open:** the
    /// same rule `openMark(face:)` already answers for the open drawer's session
    /// list, which can hold sessions from several CLIs at once and shows
    /// `.generic` rather than picking one arbitrarily — "no single mark is true
    /// of it." This reads `model.sessions` (§11's own list, assigned on every
    /// render regardless of which right flank is chosen) rather than
    /// `model.revealed`: `revealed` names one session — the most urgent — and
    /// "how many distinct CLIs are actually open" is a question about the whole
    /// set, not about whichever one is most urgent. One CLI open, however many
    /// sessions, gets its own mark; more than one gets `.generic`, the same
    /// answer the open flank already gives for exactly this ambiguity.
    private var collapsedMark: CLIMark {
        let clis = Set(model.sessions.map(\.cli))
        guard clis.count == 1, let only = clis.first else { return .generic }
        return CLIMark(cli: only)
    }
}
