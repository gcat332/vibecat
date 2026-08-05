import AppKit
import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

// MARK: - A test fixture, not a vendor asset

/// A solid-filled square PNG built at runtime, in a per-test scratch
/// directory. **Never a committed file and never one of the owner's real
/// icons** — §3's Global Constraints make bundling a vendor logo a licence
/// problem, not merely a style one, and this is what the plan asks for
/// instead: "build a temporary image in the test."
///
/// Solid and square on purpose, not the owner's circular marks: a square
/// resized with no rotation has no internal edge to antialias, so a pixel
/// count against it is exact rather than fuzzy at its own boundary, and the
/// wrong-size test below needs an exact predicted box.
@MainActor
private func makeTempIcon(_ colour: NSColor, side: Int = 64) throws -> String {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("vibecat-sourceicon-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent("icon.png").path

    let rep = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    colour.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: side, height: side)).fill()
    NSGraphicsContext.restoreGraphicsState()
    let data = try #require(rep.representation(using: .png, properties: [:]))
    try data.write(to: URL(fileURLWithPath: path))
    return path
}

/// A colour no `CLIMark` path, no ink tier and no state accent produces —
/// checked against `IslandState.allCases`' own hexes below rather than
/// assumed, so "a colour only the icon can produce" is an actual property of
/// the fixture and not a guess at one.
private let iconMagenta = RGBA(r: 1, g: 0, b: 1)

@Test func iconMagentaIsNotAnyStateAccent() {
    for state in IslandState.allCases {
        #expect(state.accent != iconMagenta)
    }
}

@MainActor private func icon(path: String?, fallback: CLIMark = .codex, side: CGFloat = 16,
                             accent: Color = Color(IslandState.waiting.accent),
                             style: SourceIcon.Style = .tinted) -> some View {
    SourceIcon(path: path, fallback: fallback, side: side, accent: accent, style: style)
}

// MARK: - No icon draws the mark, silently, for every bad input

/// Built directly from `CLIMarkView`, **never by calling `SourceIcon` with a
/// `nil` path.** That distinction is load-bearing: a first version of this
/// file compared every bad-input render against `SourceIcon(path: nil, ...)`
/// instead, and every one of those comparisons shares `SourceIcon.body`'s own
/// `else` branch with the thing under test. Deleting that branch (rendering
/// nothing instead of the fallback) changed *both* sides of the comparison
/// together, so `differingPixelCount == 0` stayed true and all four bad-input
/// tests kept passing against code that fell back to a blank view — the
/// "cannot fail" trap this repo's standards name explicitly. This helper
/// renders `CLIMarkView` on its own, with no dependency on `SourceIcon` at
/// all, so mutating `SourceIcon`'s fallback branch can only move the left
/// side of the comparison.
@MainActor private func expectedFallbackRaster(fallback: CLIMark = .codex, side: CGFloat = 16,
                                               accent: Color = Color(IslandState.waiting.accent)) throws -> Raster {
    try rasterise(CLIMarkView(mark: fallback, side: side, colour: accent).frame(width: 16, height: 16))
}

@MainActor @Test func noIconDrawsTheGeometricMark() throws {
    let withNilPath = try rasterise(icon(path: nil).frame(width: 16, height: 16))
    #expect(withNilPath.differingPixelCount(from: try expectedFallbackRaster()) == 0,
            "a `nil` icon path did not render identically to `CLIMarkView` — the two must be the same render, since `nil` is the designed common case")
}

/// Mutation-verified: deleting the `else { CLIMarkView(...) }` branch from
/// `SourceIcon.body` (rendering `Color.clear` instead) makes this and the
/// next three fail — each would then render 0 opaque pixels against
/// `expectedFallbackRaster()`'s positive count. Confirmed by making that
/// exact change, running this file, and reverting: all four failed, with the
/// mismatched-pixel-count message quoted in the task report.
@MainActor @Test func aMissingPathFallsBackSilently() throws {
    let missing = "/tmp/vibecat-sourceicon-tests-does-not-exist-\(UUID().uuidString).png"
    let raster = try rasterise(icon(path: missing).frame(width: 16, height: 16))
    #expect(raster.differingPixelCount(from: try expectedFallbackRaster()) == 0,
            "a missing icon path rendered differently from the geometric mark — the fallback is not silent")
}

@MainActor @Test func aDirectoryPathFallsBackSilently() throws {
    let directory = FileManager.default.temporaryDirectory.path
    let raster = try rasterise(icon(path: directory).frame(width: 16, height: 16))
    #expect(raster.differingPixelCount(from: try expectedFallbackRaster()) == 0,
            "a directory given as the icon path rendered differently from the geometric mark — the fallback is not silent")
}

@MainActor @Test func aZeroByteFileFallsBackSilently() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("vibecat-sourceicon-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent("empty.png").path
    #expect(FileManager.default.createFile(atPath: path, contents: Data()))

    let raster = try rasterise(icon(path: path).frame(width: 16, height: 16))
    #expect(raster.differingPixelCount(from: try expectedFallbackRaster()) == 0,
            "a zero-byte file rendered differently from the geometric mark — the fallback is not silent")
}

/// Not image data at all — the shape of a corrupted download, as opposed to
/// the empty file above.
@MainActor @Test func anUnparsableFileFallsBackSilently() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("vibecat-sourceicon-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent("garbage.png").path
    try Data("this is not a png".utf8).write(to: URL(fileURLWithPath: path))

    let raster = try rasterise(icon(path: path).frame(width: 16, height: 16))
    #expect(raster.differingPixelCount(from: try expectedFallbackRaster()) == 0,
            "an unparsable file rendered differently from the geometric mark — the fallback is not silent")
}

// MARK: - A valid icon draws something the mark never does

/// Plan 6.4's own warning: "differs" is not "differs in the right direction."
/// So this asserts a colour only the icon's own pixels can produce — never
/// drawn by any `CLIMark` path, any ink tier or any state accent — rather than
/// merely that two renders differ.
@MainActor @Test func aValidIconInBrandColourDrawsItsOwnHueUntouched() throws {
    let path = try makeTempIcon(.magenta)
    let raster = try rasterise(icon(path: path, style: .brandColour).frame(width: 16, height: 16))
    #expect(raster.pixelCount(near: iconMagenta) > 100,
            "a valid icon in `.brandColour` drew none of its own magenta — the icon did not load, or its colour was discarded")
    #expect(try expectedFallbackRaster().pixelCount(near: iconMagenta) == 0,
            "the geometric mark itself produced the icon's magenta — the fixture colour collides with something CLIMark already draws")
}

// MARK: - `.tinted` really is a mask, not a second copy of `.brandColour`

/// The tint test the plan calls out by name: "ignore the state accent if you
/// chose template (the tint test must fail)." `.tinted` has to replace the
/// icon's own hue with the accent's, via `Image.renderingMode(.template)` —
/// not merely render the same pixels a second time.
///
/// Mutation-verified: changing `SourceIcon.body`'s `.tinted` case to draw the
/// same way `.brandColour` does (dropping `.renderingMode(.template)`) makes
/// the second `#expect` fail — magenta shows up where only the accent should.
@MainActor @Test func aValidIconInTintedStyleWearsTheAccentNotItsOwnHue() throws {
    let accent = IslandState.waiting.accent
    let path = try makeTempIcon(.magenta)
    let raster = try rasterise(icon(path: path, accent: Color(accent), style: .tinted)
        .frame(width: 16, height: 16))

    #expect(raster.pixelCount(near: accent) > 100,
            "a `.tinted` icon drew none of the state accent — it is not being masked by `.renderingMode(.template)`")
    #expect(raster.pixelCount(near: iconMagenta) == 0,
            "a `.tinted` icon still shows its own magenta — the tint is decorative rather than replacing the icon's hue, so §4.3 does not actually hold at this call site")
}

/// The same icon, the two styles, one accent: they must not render alike, or
/// the `Style` parameter is dead and every caller gets the same picture
/// regardless of which one it asked for.
@MainActor @Test func brandColourAndTintedRenderDifferently() throws {
    let path = try makeTempIcon(.magenta)
    let accent = Color(IslandState.waiting.accent)
    let brand = try rasterise(icon(path: path, accent: accent, style: .brandColour)
        .frame(width: 16, height: 16))
    let tinted = try rasterise(icon(path: path, accent: accent, style: .tinted)
        .frame(width: 16, height: 16))
    #expect(brand.differingPixelCount(from: tinted) > 0,
            "`.brandColour` and `.tinted` rendered the same icon identically — the style parameter has no effect")
}

// MARK: - The icon draws inside the box it was asked for, and nowhere else

/// "Draw the icon at the wrong size (assert the box you predicted)" —
/// rendered inside a canvas larger than the requested `side`, aligned to the
/// top-left corner, so a wrong-sized icon has somewhere to overflow *into*
/// that this test can see.
///
/// Mutation-verified: hardcoding `SourceIcon.body`'s inner `.frame` to
/// `width: 24, height: 24` regardless of `side` — while this test asks for
/// `side: 16` inside a 40×40 canvas — puts opaque pixels in the 16..<24 band
/// this test predicts must be empty, and the first `#expect` fails. Before:
/// 0 outside the box, passes. After: nonzero, fails.
@MainActor @Test func theIconDrawsExactlyInsideItsRequestedSide() throws {
    let path = try makeTempIcon(.magenta)
    let side = 16
    let canvas = 40
    let raster = try rasterise(
        icon(path: path, side: CGFloat(side), style: .brandColour)
            .frame(width: CGFloat(canvas), height: CGFloat(canvas), alignment: .topLeading))

    var outsideBox = 0
    var insideBox = 0
    for y in 0..<canvas {
        for x in 0..<canvas {
            let opaque = !raster[x, y].isTransparent
            if x < side, y < side {
                if opaque { insideBox += 1 }
            } else if opaque {
                outsideBox += 1
            }
        }
    }
    #expect(outsideBox == 0,
            "\(outsideBox) opaque pixels landed outside the requested \(side)×\(side) box — the icon drew at the wrong size")
    #expect(insideBox > (side * side) / 2,
            "only \(insideBox) of \(side * side) pixels inside the requested box were opaque — the icon barely drew at all")
}
