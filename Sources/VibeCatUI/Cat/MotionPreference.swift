import Foundation
import VibeCatCore
#if canImport(AppKit)
import AppKit
#endif

/// How much motion is allowed. Design §9.3: Settings offers the three levels
/// and by default follows the system Reduce Motion setting, which overrides
/// the choice.
///
/// The override runs one way only. A system asking for less motion beats a
/// user asking for more; it does not drag a user who chose `off` back into
/// motion, because that is not what "reduce motion" means.
public struct MotionPreference: Sendable, Equatable {
    public let chosen: MotionLevel
    public let systemWantsReduced: Bool

    /// §14's *"Follow the system Reduce Motion setting"* switch, on by default.
    ///
    /// **This is not a new invariant, it is the one §9.3 already stated and this
    /// file's own summary had dropped.** §9.3, verbatim: *"Settings offers Full /
    /// Reduced / Off, and **by default** follows the system Reduce Motion setting,
    /// which overrides the choice."* Two words — "by default" — presuppose a switch
    /// that can turn the following off, and §14 lists exactly that switch. Without
    /// it, "by default" describes nothing.
    ///
    /// Plan 6.6's own plan file called this a contradiction with §9.3 and asked for
    /// a dated spec correction. **There is no contradiction and §9.3 is unchanged.**
    /// The contradiction came from `CLAUDE.md`'s summary of §9.3, which kept the
    /// override's direction and lost the qualifier — the same failure mode as the
    /// `9px` radius Plan 6.3 untangled, where four documents repeated a summary
    /// nobody had checked against the line it summarised.
    ///
    /// **What does not change:** while following is on, the override still runs one
    /// way only. A system asking for less motion beats a user asking for more, and
    /// it never drags a user who chose `off` back into motion.
    public let followsSystem: Bool

    public init(chosen: MotionLevel = .full, systemWantsReduced: Bool,
                followsSystem: Bool = true) {
        self.chosen = chosen
        self.systemWantsReduced = systemWantsReduced
        self.followsSystem = followsSystem
    }

    public var effective: MotionLevel {
        guard followsSystem, systemWantsReduced else { return chosen }
        return chosen == .off ? .off : .reduced
    }

    /// The lowest rate worth running. Below this the steps read as stutter
    /// rather than as animation.
    private static let floorFPS: Double = 8

    /// Turns a mood's profile into what may actually run.
    ///
    /// A profile that is already still (`isContinuous == false`) is returned
    /// unchanged at every level — `reduced`'s branch below hardcodes
    /// `isContinuous: true`, so without this guard a sleeping cat would be
    /// set moving by a request for *less* motion.
    public func resolve(_ profile: MotionProfile) -> MotionProfile {
        guard profile.isContinuous else { return profile }
        switch effective {
        case .full:
            return profile
        case .reduced:
            return MotionProfile(
                framesPerSecond: max(Self.floorFPS, profile.framesPerSecond / 2),
                cycle: profile.cycle,
                isContinuous: true)
        case .off:
            return .still
        }
    }

    /// Whether anything may move at all.
    ///
    /// The single gate every animated surface asks — `IslandBody.phase` and
    /// `.badgePhase` (where in a cycle a sprite is drawn) and `CatCanvas` /
    /// `BadgeCanvas` (whether their repeating transforms run at all) — so the
    /// four of them cannot drift apart into four readings of §9.3.
    ///
    /// **`resolve(_:)` is deliberately not that gate**, for two reasons that
    /// are both load-bearing:
    ///
    /// - It returns an already-still profile *unchanged at every level*, and
    ///   that guard is there on purpose (a request for *less* motion must not
    ///   set a sleeping cat moving). So `Badge.bang` — `isContinuous: false`,
    ///   `cycle: 1.1` — keeps a live cycle straight through motion `.off`, and
    ///   a phase gated on the resolved profile would leave that badge frozen at
    ///   whichever of its two positions an arbitrary `Date()` happened to name.
    /// - Since Plan 4.5 a sprite's *transform* is a different mechanism from
    ///   its frame rate. `sleep` and `dead` are both `isContinuous: false` and
    ///   both still drowse and sway, so `isContinuous` says nothing at all
    ///   about whether a transform should be running.
    ///
    /// **`reduced` still moves, deliberately.** `resolve(_:)` expresses
    /// "reduced" purely as halving `framesPerSecond`, leaving `cycle` and
    /// continuity alone — so a reduced cycle is at the same point at the same
    /// instant as a full one, merely sampled half as often, which is
    /// `IslandView.minimumInterval(for:)`'s job and already done there. Giving
    /// `reduced` a shortened period, a smaller amplitude or a frozen phase here
    /// would be inventing a behaviour §9.3 does not describe and
    /// double-counting a reduction that is already applied. `off` is the level
    /// that stops motion, and it stops all of it.
    public var allowsMotion: Bool { effective != .off }
}

#if canImport(AppKit)
extension MotionPreference {
    /// Combines a stored choice with a fresh read of the system's Reduce
    /// Motion setting. Gated to AppKit so the rule above stays testable
    /// without it — this is the only place in the file that touches
    /// NSWorkspace.
    @MainActor public static func current(chosen: MotionLevel = .full,
                                         followsSystem: Bool = true) -> MotionPreference {
        MotionPreference(
            chosen: chosen,
            systemWantsReduced: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            followsSystem: followsSystem)
    }

    /// This preference with a fresh read of the system setting and the user's
    /// own `chosen` level left exactly as it is.
    ///
    /// Reduce Motion is a live system switch, and `current()` was read once at
    /// launch — so toggling it did nothing until the app was relaunched. This is
    /// what the observer `NotchController.present()` installs calls.
    ///
    /// **`current()` cannot serve here**, and the reason is §9.3 itself: its
    /// `chosen` defaults to `.full`, so re-resolving through it would promote a
    /// user who chose `.off` or `.reduced` back to full motion the first time
    /// the system posted an accessibility change. §9.3's override runs one way
    /// only — the system asking for less beats a user asking for more, and it
    /// never drags a user who chose `off` back into motion — and that includes
    /// not doing it by accident on a refresh.
    ///
    /// **`followsSystem` is carried across for the same reason, one field later.**
    /// It defaults to `true`, so omitting it here would silently switch the
    /// following back on the first time the system posted an accessibility change —
    /// exactly the accident the paragraph above describes, in a field added after
    /// that paragraph was written. Both stored choices survive a refresh; only the
    /// system's own bit is re-read, which is the whole point of the method.
    @MainActor public func refreshed() -> MotionPreference {
        MotionPreference(
            chosen: chosen,
            systemWantsReduced: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            followsSystem: followsSystem)
    }

    /// What `NSWorkspace` posts when Reduce Motion — or any other accessibility
    /// display option — is toggled. Named here so the one file that knows how to
    /// read the setting is also the one that knows when to re-read it.
    ///
    /// It is posted on **`NSWorkspace.shared.notificationCenter`**, not on
    /// `NotificationCenter.default`: an observer registered on the default
    /// centre compiles, installs, and then never fires.
    public static let systemMotionSettingDidChange =
        NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
}
#endif
