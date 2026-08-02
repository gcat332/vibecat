import Foundation
import Observation

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

    /// Whether a click has actually opened the drawer. Deliberately separate
    /// from `question`: a question arriving must not open the drawer by
    /// itself (design §6.1's "Click" tier is a distinct gesture from a
    /// question merely existing) — it changes the cat and waits. This is
    /// what that "waits" is — `false` until `NotchController.click()` sets it,
    /// and reset to `false` whenever `question` clears (answered, dismissed,
    /// or lapsed) so a *later* question does not inherit a stale "open" from
    /// one that already closed.
    public var drawerOpen: Bool = false

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
