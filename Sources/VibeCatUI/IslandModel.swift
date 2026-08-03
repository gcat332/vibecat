import Foundation
import Observation
import VibeCatCore

/// Everything the island view reads, in one observable place.
///
/// This exists because the previous render path assigned a freshly built
/// SwiftUI tree to `NSHostingView.rootView` on every change. That survives a
/// handful of renders per second and nothing more; at sprite rates it is the
/// dominant cost. The hosting view's root is now assigned once and reads this.
@MainActor @Observable public final class IslandModel {
    public var state: IslandState = .dormant
    public var sessionCount: Int = 0
    public var hovering: Bool = false
    public var geometry: IslandGeometry
    public var aura = AuraTrigger()
    public var coat: Coat
    public var motion: MotionPreference

    /// What is actually behind the island, when it can be measured. Nil means
    /// "not measured", not "dark" — the view falls back to the system
    /// appearance rather than to a default that looks like a reading.
    ///
    /// Only the aura uses it. See `BackdropSampler`: on a real machine, with
    /// the menu bar auto-hidden over a dark wallpaper, the system reported
    /// Light while the captured strip came back at luminance 48.
    public var backdrop: Backdrop?

    /// The question the drawer is showing, if any. `nil` is the only "closed"
    /// state this model has — `IslandView` reads this one property to decide
    /// both whether to draw a drawer at all and how tall it is, rather than a
    /// separate open/closed flag that could disagree with it.
    public var question: QuestionModel?

    /// The session the hover reveal names. §4.2's most urgent one, assigned by
    /// `NotchController.render()` alongside `state` — the island reports the most
    /// urgent session, so the reveal names that same one rather than a second
    /// notion of "current".
    public var revealed: Session?

    /// Whether a click has actually opened the drawer. Deliberately separate
    /// from `question`: a question arriving must not open the drawer by
    /// itself (design §6.1's "Click" tier is a distinct gesture from a
    /// question merely existing) — it changes the cat and waits. This is
    /// what that "waits" is — `false` until `NotchController.click()` sets it,
    /// and reset to `false` whenever `question` clears (answered, dismissed,
    /// or lapsed) so a *later* question does not inherit a stale "open" from
    /// one that already closed.
    public var drawerOpen: Bool = false

    /// Fires when the island itself — the collapsed silhouette, not the
    /// drawer — is clicked. Wired by `NotchController.present()` to call
    /// `click()`. `@ObservationIgnored`: this is wiring, the same reasoning
    /// as `AppModel.onChange`'s own doc comment — nothing should re-render
    /// because this closure was reassigned.
    @ObservationIgnored
    public var onIslandClick: (@MainActor () -> Void)?

    /// Fires when the drawer produces an answer: a single-select pick (once
    /// confirmed, if §10.3 asked twice) or a multi-select Send. Wired by
    /// `NotchController.present()` to call `appModel.answer(_:)`. Read by
    /// `IslandView`, threaded down to `DrawerView`/`QuestionFace` as a plain
    /// closure parameter rather than passing `IslandModel` itself into the
    /// drawer's own view tree — `DrawerView` stays face-agnostic and
    /// `QuestionModel`-only, the same reasoning its own doc comment gives.
    @ObservationIgnored
    public var onAnswer: (@MainActor (Reply) -> Void)?

    public init(geometry: IslandGeometry, coat: Coat = .tabby, motion: MotionPreference) {
        self.geometry = geometry
        self.coat = coat
        self.motion = motion
    }

    public var layout: CollapsedLayout {
        CollapsedLayout(right: sessionCount > 0 ? .sessionCount(sessionCount) : .nothing,
                        hovering: hovering)
    }

    /// Design §6.1's three tiers, derived rather than stored redundantly:
    /// `.drawer` only when a click actually opened one *and* there is still a
    /// question to show (the guard's `let question` covers the question
    /// clearing out from under an already-open drawer — the lapse path does
    /// exactly this); otherwise whatever the hover state already was. `.rest`
    /// and `.hover` compute identically for `frames`/`panelFrames` below
    /// (`IslandTier.extraHeight` is 0 for both) — the case only matters to
    /// callers that switch on it, none of which exist yet.
    public var tier: IslandTier {
        guard drawerOpen, let question else { return hovering ? .hover : .rest }
        return .drawer(height: question.face.height)
    }

    /// The collapsed content's own frame — the cat, the badge, the count.
    /// Tier-aware for height so a rendered `IslandBody` can actually show an
    /// open drawer's extra space (see `IslandGoldenTests
    /// .nothingIsDrawnInsideTheCutoutWithTheDrawerOpen`), but this changes
    /// nothing for any caller while the drawer is closed: `.rest` and
    /// `.hover` both contribute zero extra height, exactly as the hardcoded
    /// `.rest` this replaces always did.
    public var frames: IslandFrames {
        geometry.frames(rightFlank: layout.rightFlankWidth, tier: tier)
    }

    /// The real panel's own bounds. Tier-aware for height only — `rightFlank`
    /// stays pinned to the theoretical widest regardless of tier, so opening
    /// the drawer grows the panel downward and never sideways (see
    /// `IslandGeometry.maxCollapsedFrames`'s own comment on why the width
    /// ceiling is unconditional). `NotchController.reflow()` is what actually
    /// resizes the live window to match this once tier changes.
    public var panelFrames: IslandFrames { geometry.maxCollapsedFrames(tier: tier) }

    /// The drawer's own width — deliberately independent of `hovering`,
    /// unlike `frames.body.width`. Final whole-branch review, finding 5:
    /// `frames.body.width` carries the collapsed pill's own 150pt hover
    /// reveal (§9.1's `CollapsedLayout.hoverReveal`), which exists so the
    /// *pill* can show a session's name and elapsed time once hovered.
    /// Nothing in the drawer's own content (`QuestionFace`'s title, body, or
    /// rows) reads either of those, so widening the drawer for the same
    /// reason serves it no purpose — and doing so anyway meant every row
    /// reflowed instantly the moment the cursor drifted off `hover.frame`
    /// (measured before this fix: 423.1pt while hovering, 273.1pt while not,
    /// on the identical open question), while the collapsed silhouette above
    /// it eased the identical width change over 280ms
    /// (`IslandBody.hoverRevealWidth`'s own `.easeOut(duration: 0.28)`).
    ///
    /// Decision: the drawer's width does not depend on hover at all, rather
    /// than animating the snap with the island's own reveal timing — there is
    /// no content in the drawer that timing would ever need to reveal, so
    /// matching the *other* animation's duration would just be dressing up a
    /// change that should not happen in the first place. Computed the same
    /// way `IslandBody.restingWidth` is (same session count, `hovering:
    /// false` always), rather than reusing that private-to-`IslandView`
    /// property directly, so `IslandModel` stays the one place a non-view
    /// caller (a future settings surface, a test) can ask "how wide is the
    /// drawer" without constructing a view first.
    public var drawerWidth: CGFloat {
        let resting = CollapsedLayout(right: layout.right, hovering: false)
        return geometry.frames(rightFlank: resting.rightFlankWidth, tier: .rest).body.width
    }

    public var mood: CatMood { CatMood(state: state) }
    public var badge: Badge { Badge(state: state) }

    /// Whichever of the cat and the badge wants redrawing more often.
    public var activeProfile: MotionProfile {
        let cat = motion.resolve(mood.motion)
        let badge = motion.resolve(self.badge.motion)
        if cat.isContinuous && badge.isContinuous {
            return cat.framesPerSecond >= badge.framesPerSecond ? cat : badge
        }
        return cat.isContinuous ? cat : badge
    }

    /// True only when something genuinely needs per-frame redraws. Measured: a
    /// live timeline costs ~6% of a core even at 8 fps, and removing it costs
    /// 0.0% — so this is the only thing that makes an idle machine idle.
    public var needsTimeline: Bool {
        if motion.effective == .off { return false }
        if activeProfile.isContinuous { return true }
        return aura.isBlooming(at: Date())
    }
}
