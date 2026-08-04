import Foundation

/// The three levels Settings offers. Design §9.3.
///
/// **Moved here from `VibeCatUI/Cat/MotionPreference.swift` in Plan 6.1's Task
/// 1** — `Preferences.motion` needs a visible type and Core may never import
/// VibeCatUI, the same seam Plan 6.5's Task 1 hit with `SoundPack`. Only the
/// bare identity lives here; the precedence rule (`MotionPreference.effective`),
/// `MotionProfile`, and `resolve(_:)` all stay in `VibeCatUI/Cat/MotionPreference
/// .swift`, since they reach into AppKit and mood-specific frame rates that are
/// UI-level concerns.
public enum MotionLevel: String, Sendable, CaseIterable {
    case full, reduced, off
}
