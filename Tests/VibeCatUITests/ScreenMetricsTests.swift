import Testing
import CoreGraphics
@testable import VibeCatUI

/// Measured on a 14" M3 Pro, macOS 26.5.2. See docs/superpowers/spikes/.
private let mbp14 = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
    safeAreaTop: 32,
    auxLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
    auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))

private let externalDisplay = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
    visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415),
    safeAreaTop: 0, auxLeft: nil, auxRight: nil)

@Test func derivesTheNotchFromTheAuxiliaryAreas() throws {
    let notch = try #require(mbp14.notch)
    #expect(notch == CGRect(x: 663, y: 950, width: 185, height: 32))
}

@Test func aDisplayWithoutANotchReportsNone() {
    #expect(externalDisplay.notch == nil)
    #expect(externalDisplay.hasNotch == false)
}

/// The notch is not centred: 663pt of flank on the left, 664 on the right.
/// Anything positioned from screen.midX drifts half a point.
@Test func theNotchIsNotCentredOnTheScreen() throws {
    let notch = try #require(mbp14.notch)
    #expect(notch.midX == 755.5)
    #expect(mbp14.frame.midX == 756)
    #expect(notch.midX != mbp14.frame.midX)
}

/// The menu bar is 33pt but the notch is 32pt. Sizing the island from
/// menu bar height would make it a point too tall.
@Test func theMenuBarIsOnePointTallerThanTheNotch() {
    #expect(mbp14.frame.maxY - mbp14.visibleFrame.maxY == 33)
    #expect(mbp14.safeAreaTop == 32)
}

/// safeAreaTop > 0 but a missing auxiliary area must not produce a garbage rect.
@Test func aPartialReportYieldsNoNotchRatherThanNonsense() {
    let broken = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
        safeAreaTop: 32, auxLeft: nil, auxRight: nil)
    #expect(broken.notch == nil)
}
