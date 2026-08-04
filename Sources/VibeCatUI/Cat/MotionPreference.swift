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

    public init(chosen: MotionLevel = .full, systemWantsReduced: Bool) {
        self.chosen = chosen
        self.systemWantsReduced = systemWantsReduced
    }

    public var effective: MotionLevel {
        guard systemWantsReduced else { return chosen }
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
}

#if canImport(AppKit)
extension MotionPreference {
    /// Combines a stored choice with a fresh read of the system's Reduce
    /// Motion setting. Gated to AppKit so the rule above stays testable
    /// without it — this is the only place in the file that touches
    /// NSWorkspace.
    @MainActor public static func current(chosen: MotionLevel = .full) -> MotionPreference {
        MotionPreference(
            chosen: chosen,
            systemWantsReduced: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}
#endif
