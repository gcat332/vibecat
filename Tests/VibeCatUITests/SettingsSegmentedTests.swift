import Testing
import SwiftUI
@testable import VibeCatUI
import VibeCatCore

/// `SettingsSegmented` (`SettingsSegmented.swift`) — `.seg`, the control
/// primitive Plan 6.6 needs five times and had none of before this task.
///
/// **Deliberately three cases of unequal label length** (`Alpha`/`Beta`/
/// `Gammas`, not `A`/`B`/`C`), so each segment's own box has to be predicted
/// from its own label's rendered width rather than a coincidental equal split
/// — the same discipline `SettingsSelect`'s box-fidelity test uses. Each box
/// is counted on its own, never the whole render: the pressed fill `#4A4A50`
/// and the container `#1F1F22` are close in luminance, and `CLAUDE.md` records
/// a mid-grey once drawing 111 phantom hits when counted whole-image.
@Suite("Settings segmented control")
struct SettingsSegmentedTests {
    enum Seg3: Hashable, CaseIterable {
        case alpha, beta, gamma
    }

    static func label(_ value: Seg3) -> String {
        switch value {
        case .alpha: "Alpha"
        case .beta: "Beta"
        case .gamma: "Gammas"
        }
    }

    /// A segment's own box, predicted from the exact primitives
    /// `SettingsSegmented` draws with (`SettingsSegmentedMetrics`) — not a
    /// number copied out by hand. Each button is its own label's `Text` at
    /// `12pt` plus `5/11` padding; the container adds `2pt` on every side and a
    /// `2pt` gap between buttons.
    @MainActor
    static func predictedBoxes(_ labels: [String]) throws -> [(x: Int, y: Int, width: Int, height: Int)] {
        var boxes: [(x: Int, y: Int, width: Int, height: Int)] = []
        var x = Int(SettingsSegmentedMetrics.containerPadding)
        for label in labels {
            let replica = Text(label)
                .font(.system(size: SettingsSegmentedMetrics.fontSize))
                .padding(.vertical, SettingsSegmentedMetrics.buttonVerticalPadding)
                .padding(.horizontal, SettingsSegmentedMetrics.buttonHorizontalPadding)
            let raster = try rasterise(replica)
            boxes.append((x: x, y: Int(SettingsSegmentedMetrics.containerPadding),
                          width: raster.width, height: raster.height))
            x += raster.width + Int(SettingsSegmentedMetrics.gap)
        }
        return boxes
    }

    /// `pixelCount(near:)` restricted to a rectangle — the same technique
    /// `SettingsSidebarTests`' own `count(in:box:near:)` uses, generalised from
    /// a square to a rectangle because these boxes are not square.
    private static func count(in raster: Raster, box: (x: Int, y: Int, width: Int, height: Int),
                              near colour: RGBA, tolerance: Int = 6) -> Int {
        let target = Raster.Pixel(colour)
        var n = 0
        for y in box.y..<(box.y + box.height) where y >= 0 && y < raster.height {
            for x in box.x..<(box.x + box.width) where x >= 0 && x < raster.width {
                let p = raster[x, y]
                if p.a > 0
                    && abs(Int(p.r) - Int(target.r)) <= tolerance
                    && abs(Int(p.g) - Int(target.g)) <= tolerance
                    && abs(Int(p.b) - Int(target.b)) <= tolerance {
                    n += 1
                }
            }
        }
        return n
    }

    @Test @MainActor func thePressedSegmentDrawsTheFillAtItsOwnBoxAndNoOtherSegmentDoes() throws {
        // The core colour assertion, and the one this control's own doc
        // comment warns is easy to get wrong by counting too broadly: `#4A4A50`
        // must appear inside `beta`'s own predicted box when `beta` is
        // selected, and nowhere inside `alpha`'s or `gamma`'s.
        let labels = ["Alpha", "Beta", "Gammas"]
        let boxes = try Self.predictedBoxes(labels)
        let raster = try rasterise(SettingsSegmented(.constant(Seg3.beta), label: Self.label))

        // Sanity check on the prediction itself: if the composed control's own
        // size does not match what its own metrics predict, the boxes below
        // are measuring the wrong rectangle entirely.
        let expectedWidth = boxes.last!.x + boxes.last!.width + Int(SettingsSegmentedMetrics.containerPadding)
        let expectedHeight = boxes[0].height + Int(SettingsSegmentedMetrics.containerPadding) * 2
        #expect(abs(raster.width - expectedWidth) <= 1 && abs(raster.height - expectedHeight) <= 1,
                "the control drew \(raster.width)x\(raster.height), its own metrics predict \(expectedWidth)x\(expectedHeight)")

        // Thresholds, not `> 0` / `== 0`: an unpressed box still shows its own
        // `haze`-on-`#1F1F22` label, and a glyph edge's antialiasing blends
        // through a range of intermediate greys that can land inside
        // `tolerance: 6` of `#4A4A50` purely as a rendering artefact — measured
        // on this exact render at 4-19 phantom hits per unpressed box, out of
        // 946-976 for the box that is actually filled. `100`/`30` sit in the
        // gap between those two populations with room either side, so this
        // still fails the instant a real rectangle of fill appears in the
        // wrong box, which is what every mutation below actually does.
        #expect(Self.count(in: raster, box: boxes[1], near: SettingsSegmentedMetrics.pressed) > 100,
                "beta's own box shows no pressed fill although beta is selected")
        #expect(Self.count(in: raster, box: boxes[0], near: SettingsSegmentedMetrics.pressed) < 30,
                "alpha's box shows the pressed fill although beta, not alpha, is selected")
        #expect(Self.count(in: raster, box: boxes[2], near: SettingsSegmentedMetrics.pressed) < 30,
                "gamma's box shows the pressed fill although beta, not gamma, is selected")
    }

    @Test @MainActor func theControlReflectsItsBindingRatherThanAllCasesFirst() throws {
        // The defect this catches: a control that always marks `allCases
        // .first` as pressed regardless of the binding, which looks correct
        // exactly once — when the default happens to be first — and is wrong
        // for every other case. Binds to `.gamma`, the *last* case, and checks
        // both ends: gamma's own box must carry the pressed fill and bone
        // text, alpha's box must carry neither. "Differs from the alpha-
        // selected render" would not be enough — a control that always drew
        // *some* segment pressed, but the wrong one, would also differ; this
        // pins down which box and which colour.
        let labels = ["Alpha", "Beta", "Gammas"]
        let boxes = try Self.predictedBoxes(labels)
        let raster = try rasterise(SettingsSegmented(.constant(Seg3.gamma), label: Self.label))

        // Same `100`/`30` thresholds as the previous test, for the same
        // measured reason: an unpressed box's own antialiased label can land a
        // handful of phantom hits inside `#4A4A50`'s tolerance band, orders of
        // magnitude below an actually-filled box.
        #expect(Self.count(in: raster, box: boxes[2], near: SettingsSegmentedMetrics.pressed) > 100,
                "gamma's own box shows no pressed fill although gamma is selected")
        #expect(Self.count(in: raster, box: boxes[0], near: SettingsSegmentedMetrics.pressed) < 30,
                "alpha's box shows the pressed fill although gamma is selected — looks like allCases.first hardcoded")

        // The rendered *label*, not just a background fill: gamma's own box
        // must carry bone (pressed) text and alpha's own box must carry haze
        // (unpressed) text — tying the assertion to which segment's rendered
        // content took the pressed styling, not merely that some pixel changed
        // somewhere in the frame.
        #expect(Self.count(in: raster, box: boxes[2], near: SettingsPalette.bone, tolerance: 10) > 0,
                "gamma's own label is not drawn in bone although gamma is selected")
        #expect(Self.count(in: raster, box: boxes[0], near: SettingsPalette.haze, tolerance: 10) > 0,
                "alpha's own label is not drawn in haze although gamma, not alpha, is selected")
    }
}
