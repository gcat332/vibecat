import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import VibeCatUI

/// The sampler's own capture path needs a screen and a permission, so it is
/// not what these test. What they test is everything around it: the threshold,
/// the luminance arithmetic, and — the part that actually went wrong — that a
/// missing measurement falls back rather than defaulting.
@Suite("Backdrop")
struct BackdropSamplerTests {
    @Test func luminanceSplitsAtMidGrey() {
        #expect(Backdrop(meanLuminance: 0) == .dark)
        #expect(Backdrop(meanLuminance: 48) == .dark, "the wallpaper measured on a real machine")
        #expect(Backdrop(meanLuminance: 127) == .dark)
        #expect(Backdrop(meanLuminance: 128) == .light)
        #expect(Backdrop(meanLuminance: 234) == .light, "the light menu bar measured on a real machine")
        #expect(Backdrop(meanLuminance: 255) == .light)
    }

    /// Raw sRGB bytes, and the mean has to be the mean — an off-by-one in the
    /// stride would read every fourth pixel's alpha as a colour.
    @MainActor @Test func meanLuminanceReadsTheActualPixels() throws {
        for grey in [0, 64, 128, 255] {
            let raster = try rasterise(
                Color(red: Double(grey) / 255, green: Double(grey) / 255, blue: Double(grey) / 255)
                    .frame(width: 12, height: 8))
            var bytes = raster.bytes
            let ctx = CGContext(data: &bytes, width: raster.width, height: raster.height,
                                bitsPerComponent: 8, bytesPerRow: raster.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let image = try #require(ctx.makeImage())
            let measured = try #require(BackdropSampler.meanLuminance(of: image))
            #expect(abs(measured - grey) <= 2, "grey \(grey) measured as \(measured)")
        }
    }

    /// The whole point of `Backdrop?` being optional. A sampler that reported
    /// `.dark` when it had not measured anything would silently deepen every
    /// aura on machines that never granted the permission — which is most of
    /// them, since nothing ever asks.
    @MainActor @Test func anUnmeasuredBackdropLeavesTheViewOnItsFallback() {
        let sampler = BackdropSampler()
        #expect(sampler.current == nil)
        let model = IslandModel(geometry: IslandGeometry(screen: mbp14ForBackdrop),
                                motion: MotionPreference(chosen: .full, systemWantsReduced: false))
        #expect(model.backdrop == nil, "the model must start unmeasured, not dark")
    }

    /// A measurement outranks the system's guess, and the two really can
    /// disagree: measured on a real machine, an auto-hidden menu bar over a
    /// dark wallpaper captured at luminance 48 while the system reported Light.
    @MainActor @Test func aMeasurementDecidesTheTintRegardlessOfAppearance() throws {
        let model = IslandModel(geometry: IslandGeometry(screen: mbp14ForBackdrop),
                                motion: MotionPreference(chosen: .full, systemWantsReduced: false))
        model.state = .waiting

        model.backdrop = .dark
        let onDark = IslandBody(model: model, now: Date()).auraTint
        model.backdrop = .light
        let onLight = IslandBody(model: model, now: Date()).auraTint

        #expect(onDark.colour == IslandState.waiting.accent)
        #expect(onLight.colour != onDark.colour)
        #expect(onLight.peakOpacity != onDark.peakOpacity)
    }

    /// Never prompts unless told to. A launch-time whole-screen permission
    /// dialog to improve the colour of a glow is out of all proportion, and
    /// this is the line that keeps it from happening by accident.
    @MainActor @Test func nothingPromptsWithoutTheExplicitOptIn() {
        // With the variable absent the answer is just "whatever is already
        // granted" — and crucially, no prompt is reachable from here.
        let quiet = BackdropSampler.requestAccessIfAskedTo(env: [:])
        #expect(quiet == BackdropSampler.isAvailable)
        let wrongValue = BackdropSampler.requestAccessIfAskedTo(
            env: ["VIBECAT_REQUEST_SCREEN_RECORDING": "yes"])
        #expect(wrongValue == BackdropSampler.isAvailable)
    }
}

private let mbp14ForBackdrop = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
    safeAreaTop: 32,
    auxLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
    auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))
