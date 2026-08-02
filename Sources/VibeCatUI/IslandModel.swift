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

    public init(geometry: IslandGeometry, coat: Coat = .tabby, motion: MotionPreference) {
        self.geometry = geometry
        self.coat = coat
        self.motion = motion
    }

    public var layout: CollapsedLayout {
        CollapsedLayout(right: sessionCount > 0 ? .sessionCount(sessionCount) : .nothing,
                        hovering: hovering)
    }

    public var frames: IslandFrames {
        geometry.frames(rightFlank: layout.rightFlankWidth, tier: .rest)
    }

    /// The panel never resizes, so the view lays out against this.
    public var panelFrames: IslandFrames { geometry.maxCollapsedFrames() }

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
