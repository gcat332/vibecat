import Foundation

/// The preferences that exist today. **Four, deliberately.**
///
/// §14 describes roughly 47 controls across four pages, and Plan 6.4 owns none of
/// them but mute. Adding the other 43 keys now would mean inventing defaults for
/// behaviour that does not exist and shipping 43 pieces of untested surface;
/// Plans 6.5–6.7 add theirs as they add the controls that mean something.
///
/// Every default below is read off `settings.html`, not chosen: the volume
/// slider's `value="60"` (line 358), the Do Not Disturb switch's
/// `aria-checked="true"` (line 359), and the General pane's `data-active="true"`
/// (line 210).
public struct Preferences: Sendable, Equatable {
    public var soundEnabled: Bool
    /// `0…1`, from `settings.html`'s `0…100` slider.
    public var volume: Double
    public var quietDuringDoNotDisturb: Bool
    /// Which pane the window reopens on. A key, not an index, so reordering the
    /// sidebar cannot silently change which page someone lands on.
    public var selectedPage: String

    public init(soundEnabled: Bool = true, volume: Double = 0.60,
                quietDuringDoNotDisturb: Bool = true, selectedPage: String = "general") {
        self.soundEnabled = soundEnabled
        self.volume = volume
        self.quietDuringDoNotDisturb = quietDuringDoNotDisturb
        self.selectedPage = selectedPage
    }
}
