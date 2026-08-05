import Foundation

/// Which markings the cat wears. Design §7.3: a coat repaints cells with a
/// tone already in the ramp, so the fur stays the state's colour and "colour
/// means state" survives the customisation.
///
/// **Moved here from `VibeCatUI/Cat/CatGrid.swift` in Plan 6.6's Task 1** —
/// `Preferences.coat` needs a visible type and Core may never import
/// `VibeCatUI`, the same seam Plan 6.5's Task 1 hit with `SoundPack` and Plan
/// 6.1's Task 1 hit with `MotionLevel`. Only the bare identity lives here;
/// `CatGrid.apply(_:)` — the switch that actually repaints cells, and needs
/// `Tone`, a UI-level concept — stays in `VibeCatUI/Cat/CatGrid.swift`.
public enum Coat: String, Sendable, CaseIterable {
    case tabby, plain, tuxedo, siamese, patched
}
