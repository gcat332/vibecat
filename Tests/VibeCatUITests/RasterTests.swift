import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

/// Tests of the measuring instrument itself.
///
/// Everything golden in this suite is only as trustworthy as `rasterise`, and
/// for the length of Plan 5 it was not trustworthy at all: `ImageRenderer`'s
/// `cgImage` returned a recycled backing store, so a view that painted nothing
/// measured as the previous render's pixels. Four full-suite readings were
/// wrong before anyone caught it, and it was first written up as a concurrency
/// race — it is not one. These tests pin the instrument.
@Suite struct RasterHarness {
    /// A view that paints nothing must measure as nothing, **including when a
    /// render of the same size has already happened in this process.**
    ///
    /// That second clause is the whole test. Rendering a blank frame on its own
    /// passed throughout, which is why `--filter` looked clean and the bug read
    /// as a full-suite race. Ordering matters here and the loop is not
    /// decoration: on `ImageRenderer.cgImage` this reads 0 on the very first
    /// blank render and 474 on every one after the rich render, twelve times out
    /// of twelve — so a single-iteration version of this test would pass against
    /// the broken instrument roughly half the time depending on where it ran.
    @MainActor @Test func aViewThatPaintsNothingDoesNotInheritTheLastRender() throws {
        var e = VibeEvent(id: "e", cli: "claude-code", kind: .running, session: "s", cwd: "/tmp/api")
        e.tasks = [TaskItem(title: "Audit authentication flow", status: .doing),
                   TaskItem(title: "Add regression coverage", status: .open)]
        e.agents = [AgentItem(name: "Explore (Search API endpoints)", elapsed: "8s", model: "Sonnet 4.6")]
        let s = Session(event: e, now: Date(timeIntervalSince1970: 1_000_000))
        let accent = Color(IslandState.running.accent)

        // One fixed frame for both, so the blank render is the same size as the
        // rich one — a different size would allocate a different block and the
        // bug would not show.
        func draw(_ options: SessionRow.Options) throws -> Raster {
            try rasterise(SessionBlocks(session: s, options: options, accent: accent)
                .frame(width: 388, height: 80, alignment: .topLeading))
        }

        for i in 0..<6 {
            let rich = try draw(.agents)
            #expect(rich.opaquePixelCount > 0,
                    "the rich render drew nothing at pass \(i) — this test can no longer tell a clean blank frame from an uninherited one, because there is nothing to inherit")

            let blank = try draw([])
            #expect(blank.opaquePixelCount == 0,
                    "a blank 388x80 frame measured \(blank.opaquePixelCount) opaque pixels at pass \(i), after a render of the same size drew \(rich.opaquePixelCount) — the raster is inheriting a backing store it did not paint")
            #expect(blank.distinctColours.isEmpty,
                    "a blank 388x80 frame measured \(blank.distinctColours.count) distinct colours at pass \(i) — it is showing content from somewhere else")
        }
    }

    /// `scale` still means device pixels per point, and still scales the drawing
    /// rather than only the canvas.
    ///
    /// Guards the move off `cgImage`: `render(rasterizationScale:renderer:)`
    /// hands back a size in *points* and leaves the caller to set the CTM, so a
    /// missing `scaleBy` would produce a correctly sized canvas with the drawing
    /// stranded in one quarter of it. Sixteen tests pass `scale: 2`.
    @MainActor @Test func scaleEnlargesTheDrawingAndNotJustTheCanvas() throws {
        let view = Text("Ay").font(.system(size: 20)).frame(width: 60, height: 30)
        let one = try rasterise(view, scale: 1)
        let two = try rasterise(view, scale: 2)

        #expect((one.width, one.height) == (60, 30))
        #expect((two.width, two.height) == (120, 60))

        // Ink must grow with the canvas. If the CTM were left at identity the
        // glyphs would stay their 1x size in a 4x canvas, so the ratio would sit
        // near 1 rather than well above it.
        #expect(one.opaquePixelCount > 0, "the 1x render drew nothing, so the ratio below means nothing")
        let ratio = Double(two.opaquePixelCount) / Double(one.opaquePixelCount)
        #expect(ratio > 2.0,
                "2x drew \(two.opaquePixelCount) against 1x's \(one.opaquePixelCount) (ratio \(ratio)) — the canvas grew but the drawing did not, so `scale` is not being applied to the context")
    }

    /// A view that resolves to zero size is reported, not measured.
    ///
    /// `eachBlockOptionGatesOnlyItsOwnBlock` pins its frame *because* of this
    /// behaviour and says so in a comment, so it is load-bearing rather than
    /// incidental.
    @MainActor @Test func aZeroSizedViewThrowsRatherThanMeasuringNothing() throws {
        #expect(throws: RasterError.renderProducedNothing) {
            try rasterise(VStack {}.frame(width: 0, height: 0))
        }
    }
}
