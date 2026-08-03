import SwiftUI
import Testing
@testable import VibeCatUI

/// The aura fires correctly and cannot be seen.
///
/// Measured on hardware: firing a state change and sampling the screen 24
/// times across 2.5s produced a clean symmetric hump — the `sin(phase · π)`
/// curve, ~960ms wide, exactly as `AuraTrigger` specifies. Its peak deviation
/// in the band just outside the island was **6 levels summed across R, G and
/// B**: two per channel. Plan 2's follow-up predicted this in as many words —
/// "if it looks absent, check `AuraTrigger.peakOpacity` before suspecting the
/// trigger" — and it was right.
///
/// `AuraTriggerTests` covers the curve. This covers whether the curve reaches
/// anyone's eyes, which is a different question and the one that was failing.
@Suite("Aura visibility")
struct AuraVisibilityTests {
    /// The two menu bars the aura has to be seen on. The light one is measured
    /// off a real screen in Light mode — 234 grey — not chosen.
    static let darkBar = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let lightBar = Color(red: 234.0 / 255, green: 234.0 / 255, blue: 234.0 / 255)
    static let islandWidth: CGFloat = 160
    static let islandHeight: CGFloat = 32
    /// Wide enough that the 18pt blur has somewhere to go on every side.
    static let canvas = CGSize(width: islandWidth + 96, height: islandHeight + 64)

    /// The shipping modifier chain, in the shipping order — `.clipShape` then
    /// `.shadow` then `.frame`. Copying the order matters: a `.shadow` applied
    /// before its `.frame` is a different render from one applied after.
    @MainActor
    static func island(auraOpacity: Double, light: Bool = false,
                       tintOverride: RGBA? = nil) -> some View {
        let tint = tintOverride
            ?? AuraTint(accent: IslandState.waiting.accent, onLightBackdrop: light).colour
        return ZStack {
            light ? lightBar : darkBar
            IslandShape()
                .fill(Color(islandGroundColour))            // derived, never restated
                .clipShape(IslandShape())
                .shadow(color: Color(tint).opacity(auraOpacity), radius: 18, x: 0, y: 2)
                .frame(width: islandWidth, height: islandHeight)
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    /// Mean colour of a band just outside the island's left edge — where a
    /// glow shows and the island itself does not.
    @MainActor
    static func haloMean(auraOpacity: Double, light: Bool = false) throws -> (r: Double, g: Double, b: Double) {
        let raster = try rasterise(island(auraOpacity: auraOpacity, light: light), scale: 2)
        let edge = Int((canvas.width - islandWidth) / 2 * 2)     // island's left edge, in pixels
        let top = Int((canvas.height - islandHeight) / 2 * 2)
        return raster.meanColour(x: edge - 24, y: top, width: 22, height: Int(islandHeight * 2))
    }

    /// Summed absolute deviation from an unlit render — the same figure the
    /// on-screen measurement produced, so the two are directly comparable.
    @MainActor
    static func haloDelta(auraOpacity: Double, light: Bool = false) throws -> Double {
        let lit = try haloMean(auraOpacity: auraOpacity, light: light)
        let unlit = try haloMean(auraOpacity: 0, light: light)
        return abs(lit.r - unlit.r) + abs(lit.g - unlit.g) + abs(lit.b - unlit.b)
    }

    /// A glow nobody can see is not a glow. The floor is 24 — four times the 6
    /// that shipped, and about 8 levels per channel at the brightest point of
    /// the bloom, which is a visible lift rather than dither.
    ///
    /// **On both backdrops**, which is the point. The first version of this
    /// test only checked the dark one, passed, and shipped an aura that a
    /// real screen in Light mode lifted by 8.
    @MainActor @Test func theAuraIsVisibleAtItsPeakOnEitherMenuBar() throws {
        for light in [false, true] {
            let tint = AuraTint(accent: IslandState.waiting.accent, onLightBackdrop: light)
            let delta = try Self.haloDelta(auraOpacity: tint.peakOpacity, light: light)
            #expect(delta >= 24,
                    "\(light ? "light" : "dark") menu bar: the peak lifts the halo by only \(Int(delta)) levels summed across RGB")
        }
    }

    /// Equal *perceived* strength, not equal numbers. Two backdrops with one
    /// opacity is exactly what produced 26 on dark and 8 on light.
    @MainActor @Test func bothBackdropsGetAComparableBloom() throws {
        let onDark = try Self.haloDelta(
            auraOpacity: AuraTint(accent: IslandState.waiting.accent, onLightBackdrop: false).peakOpacity)
        let onLight = try Self.haloDelta(
            auraOpacity: AuraTint(accent: IslandState.waiting.accent, onLightBackdrop: true).peakOpacity,
            light: true)
        #expect(abs(onDark - onLight) < 12,
                "dark lifts \(Int(onDark)) and light lifts \(Int(onLight)) — the two backdrops are not getting comparable blooms")
    }

    /// The accent's own colour, unchanged, on a dark bar — §4.3 is not being
    /// bent, only its luminance on light where there is no other direction.
    @Test func theDarkBackdropGlowIsTheAccentItself() {
        let accent = IslandState.waiting.accent
        #expect(AuraTint(accent: accent, onLightBackdrop: false).colour == accent)
        let light = AuraTint(accent: accent, onLightBackdrop: true).colour
        #expect(light != accent)
        // Deepened, not re-hued: the ratios between channels survive.
        #expect(abs(light.r / accent.r - light.g / accent.g) < 0.001)
        #expect(abs(light.g / accent.g - light.b / accent.b) < 0.001)
    }

    /// The other half of "leaves nothing behind": at the ends of the curve the
    /// halo must be indistinguishable from no aura at all.
    @MainActor @Test func theAuraLeavesNothingBehind() throws {
        #expect(try Self.haloDelta(auraOpacity: 0) == 0)
        #expect(try Self.haloDelta(auraOpacity: 0, light: true) == 0)
    }

    /// A sweep, for choosing the constant rather than guessing it — numbers to
    /// stdout, and a strip of candidates to look at, because the question
    /// "is this visible" is not settled by arithmetic:
    ///
    ///     VIBECAT_AURA_SWEEP=/tmp/aura.png swift test --filter auraOpacitySweep
    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAT_AURA_SWEEP"] != nil))
    func auraOpacitySweep() throws {
        for light in [false, true] {
            print(light ? "--- light menu bar (234 grey), deepened accent ---"
                        : "--- dark menu bar (26 grey), accent as-is ---")
            for step in stride(from: 0.0, through: 0.60, by: 0.05) {
                let mean = try Self.haloMean(auraOpacity: step, light: light)
                let delta = try Self.haloDelta(auraOpacity: step, light: light)
                print(String(format: "opacity %.2f  halo %5.1f,%5.1f,%5.1f  Δ%5.1f",
                             step, mean.r, mean.g, mean.b, delta))
            }
        }
        let path = ProcessInfo.processInfo.environment["VIBECAT_AURA_SWEEP"]!
        guard path.hasSuffix(".png") else { return }
        let candidates = [0.14, 0.24, 0.34, 0.44]
        let strip = VStack(spacing: 0) {
            ForEach(candidates, id: \.self) { Self.island(auraOpacity: $0) }
        }
        #expect(try rasterise(strip, scale: 2).writePNG(to: path))
    }
}
