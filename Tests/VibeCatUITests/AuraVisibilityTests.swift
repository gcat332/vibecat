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
    /// A dark menu bar with a lit island on it — the situation the aura has to
    /// be visible against, and the least favourable one.
    static let backdrop = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let islandWidth: CGFloat = 160
    static let islandHeight: CGFloat = 32
    /// Wide enough that the 18pt blur has somewhere to go on every side.
    static let canvas = CGSize(width: islandWidth + 96, height: islandHeight + 64)

    /// The shipping modifier chain, in the shipping order — `.clipShape` then
    /// `.shadow` then `.frame`. Copying the order matters: a `.shadow` applied
    /// before its `.frame` is a different render from one applied after.
    @MainActor
    static func island(auraOpacity: Double) -> some View {
        ZStack {
            backdrop
            IslandShape()
                .fill(Color(RGBA(hex: "#05070B")!))          // islandGroundColour
                .clipShape(IslandShape())
                .shadow(color: Color(IslandState.waiting.accent).opacity(auraOpacity),
                        radius: 18, x: 0, y: 2)
                .frame(width: islandWidth, height: islandHeight)
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    /// Mean colour of a band just outside the island's left edge — where a
    /// glow shows and the island itself does not.
    @MainActor
    static func haloMean(auraOpacity: Double) throws -> (r: Double, g: Double, b: Double) {
        let raster = try rasterise(island(auraOpacity: auraOpacity), scale: 2)
        let edge = Int((canvas.width - islandWidth) / 2 * 2)     // island's left edge, in pixels
        let top = Int((canvas.height - islandHeight) / 2 * 2)
        return raster.meanColour(x: edge - 24, y: top, width: 22, height: Int(islandHeight * 2))
    }

    /// Summed absolute deviation from an unlit render — the same figure the
    /// on-screen measurement produced, so the two are directly comparable.
    @MainActor
    static func haloDelta(auraOpacity: Double) throws -> Double {
        let lit = try haloMean(auraOpacity: auraOpacity)
        let dark = try haloMean(auraOpacity: 0)
        return abs(lit.r - dark.r) + abs(lit.g - dark.g) + abs(lit.b - dark.b)
    }

    /// A glow nobody can see is not a glow. The floor is 24 — four times the 6
    /// that shipped, and about 8 levels per channel at the brightest point of
    /// the bloom, which is a visible lift on a dark bar rather than dither.
    @MainActor @Test func theAuraIsVisibleAtItsPeak() throws {
        let delta = try Self.haloDelta(auraOpacity: AuraTrigger.peakOpacity)
        #expect(delta >= 24,
                "the aura's peak lifts the halo by only \(Int(delta)) levels summed across RGB — at 0.14 that figure was 6, and it could not be seen on real hardware")
    }

    /// The other half of "leaves nothing behind": at the ends of the curve the
    /// halo must be indistinguishable from no aura at all.
    @MainActor @Test func theAuraLeavesNothingBehind() throws {
        #expect(try Self.haloDelta(auraOpacity: 0) == 0)
    }

    /// A sweep, for choosing the constant rather than guessing it — numbers to
    /// stdout, and a strip of candidates to look at, because the question
    /// "is this visible" is not settled by arithmetic:
    ///
    ///     VIBECAT_AURA_SWEEP=/tmp/aura.png swift test --filter auraOpacitySweep
    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAT_AURA_SWEEP"] != nil))
    func auraOpacitySweep() throws {
        for step in stride(from: 0.0, through: 0.60, by: 0.05) {
            let mean = try Self.haloMean(auraOpacity: step)
            let delta = try Self.haloDelta(auraOpacity: step)
            print(String(format: "opacity %.2f  halo %5.1f,%5.1f,%5.1f  Δ%5.1f",
                         step, mean.r, mean.g, mean.b, delta))
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
