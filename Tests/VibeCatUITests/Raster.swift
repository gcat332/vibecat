import AppKit
import SwiftUI
import Testing
@testable import VibeCatUI

// MARK: - The escaped-inout note
//
// Why every bitmap context in this file is built inside a
// `withUnsafeMutableBytes` closure rather than from `&someArray`.
//
// `CGContext(data: &bytes, …)` compiles, and all four bitmap contexts in this
// file were originally written that way. It is undefined behaviour. Swift's
// inout-to-pointer conversion guarantees the pointer only for the duration of
// the call it appears in; `CGContext` stores it and writes through it later,
// when something draws into the context. Nothing warns.
//
// This is not a theoretical objection — it is directly observable, with no
// concurrency and no load. Create a context over `&bytes`, take a plain `let`
// copy of `bytes`, *then* draw: the copy changes. A `let` copy of a value type
// mutating because of a later, unrelated statement is impossible in Swift's
// model, which is exactly the point — the write is landing in memory the
// language believes is exclusively owned by that copy. Measured here,
// deterministically, first attempt.
//
// **It was not, however, the cause of the blank-render flake**, which was worth
// establishing before assuming it: in a full-suite run that reproduced the bad
// reading, a correctly allocated buffer that provably outlived its context read
// exactly the same wrong value (474) as the `&bytes` version did. The corruption
// was upstream of the buffer, inside `ImageRenderer` — see `rasterise`. Both
// defects were real; only one of them was that one.

/// A SwiftUI view rasterised offscreen, as raw sRGB bytes.
///
/// `ImageRenderer` draws with no window server involved, so this works
/// headlessly — including on a locked machine, which two earlier plans
/// wrongly recorded as blocking visual verification.
///
/// It is also the only tool in this test suite that sees *rendered output*
/// rather than proving a property was merely read. Three `#if DEBUG` counters
/// exist in `IslandView` because an `@escaping` closure — `Canvas`'s renderer,
/// `TimelineView`'s content — never runs during `.body` access. It does run
/// for a render, so anything asserted here is asserted against pixels that
/// SwiftUI actually produced.
struct Raster: Sendable {
    let width: Int
    let height: Int
    /// RGBA, four bytes per pixel, sRGB, alpha last.
    let bytes: [UInt8]

    struct Pixel: Hashable, Sendable, CustomStringConvertible {
        let r: UInt8, g: UInt8, b: UInt8, a: UInt8
        var isTransparent: Bool { a == 0 }
        var description: String { String(format: "#%02X%02X%02X@%d", r, g, b, a) }
    }

    subscript(x: Int, y: Int) -> Pixel {
        precondition(x >= 0 && x < width && y >= 0 && y < height,
                     "(\(x),\(y)) outside \(width)x\(height)")
        let i = (y * width + x) * 4
        return Pixel(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: bytes[i + 3])
    }

    /// Every pixel, row-major. Convenient for counting.
    var pixels: [Pixel] {
        stride(from: 0, to: bytes.count, by: 4).map {
            Pixel(r: bytes[$0], g: bytes[$0 + 1], b: bytes[$0 + 2], a: bytes[$0 + 3])
        }
    }

    var opaquePixelCount: Int { pixels.count { !$0.isTransparent } }

    /// Distinct opaque colours. A coat that repaints nothing shows up here as
    /// the same count as the coat it was meant to differ from.
    var distinctColours: Set<Pixel> { Set(pixels.filter { !$0.isTransparent }) }

    /// How many pixels sit within `tolerance` of `colour` on every channel.
    ///
    /// Exact equality is the wrong test against a rendered image: colour
    /// management, antialiasing and premultiplication all move a value by a
    /// level or two. A small tolerance keeps "this specific colour was drawn"
    /// answerable without pretending the pipeline is lossless.
    func pixelCount(near colour: RGBA, tolerance: Int = 6) -> Int {
        let target = (Int((colour.r * 255).rounded()),
                      Int((colour.g * 255).rounded()),
                      Int((colour.b * 255).rounded()))
        return pixels.count { p in
            p.a > 0
                && abs(Int(p.r) - target.0) <= tolerance
                && abs(Int(p.g) - target.1) <= tolerance
                && abs(Int(p.b) - target.2) <= tolerance
        }
    }

    /// How many pixels differ from `other`. Rasters of different sizes are
    /// reported as wholly different rather than compared elementwise.
    func differingPixelCount(from other: Raster) -> Int {
        guard width == other.width, height == other.height else {
            return max(width * height, other.width * other.height)
        }
        return zip(pixels, other.pixels).count { $0 != $1 }
    }

    /// The mean of a rectangle, as Doubles so small differences survive.
    /// Transparent pixels contribute their premultiplied value, which is what
    /// a viewer compositing over black would see.
    func meanColour(x: Int, y: Int, width w: Int, height h: Int) -> (r: Double, g: Double, b: Double) {
        var sum = (0.0, 0.0, 0.0)
        var n = 0.0
        for py in y..<(y + h) where py >= 0 && py < height {
            for px in x..<(x + w) where px >= 0 && px < width {
                let p = self[px, py]
                sum = (sum.0 + Double(p.r), sum.1 + Double(p.g), sum.2 + Double(p.b))
                n += 1
            }
        }
        guard n > 0 else { return (0, 0, 0) }
        return (sum.0 / n, sum.1 / n, sum.2 / n)
    }

    /// Writes a PNG. Used by the contact sheet, and worth reaching for by hand
    /// when a golden assertion fails and you want to see what it saw.
    @discardableResult
    func writePNG(to path: String) -> Bool {
        // `withUnsafeMutableBytes`, not `&copy`: see the escaped-inout note at
        // the top of this file. Everything that reads through the pointer —
        // `makeImage` included, since a bitmap context's image can share its
        // backing store — happens inside the closure, so the pointer provably
        // outlives every use of it.
        var copy = bytes
        return copy.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let image = ctx.makeImage(),
                  let dst = CGImageDestinationCreateWithURL(
                    URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)
            else { return false }
            CGImageDestinationAddImage(dst, image, nil)
            return CGImageDestinationFinalize(dst)
        }
    }
}

/// Encodes a sequence of rasters as an animated GIF.
///
/// A filmstrip shows which frames differ; this shows what the motion actually
/// looks like, which is a different question and the one an eye answers. Used
/// only by the env-gated preview tools — nothing asserts on a GIF.
@discardableResult
func writeAnimatedGIF(_ frames: [Raster], secondsPerFrame: Double, to path: String) -> Bool {
    guard let first = frames.first,
          let dst = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL, "com.compuserve.gif" as CFString,
            frames.count, nil)
    else { return false }
    _ = first
    CGImageDestinationSetProperties(dst, [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
    ] as CFDictionary)
    for f in frames {
        // `withUnsafeMutableBytes`, not `&bytes`: see the escaped-inout note at the top of this file.
        var bytes = f.bytes
        let added = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: f.width, height: f.height,
                                      bitsPerComponent: 8, bytesPerRow: f.width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let image = ctx.makeImage() else { return false }
            CGImageDestinationAddImage(dst, image, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: secondsPerFrame]
            ] as CFDictionary)
            return true
        }
        guard added else { return false }
    }
    return CGImageDestinationFinalize(dst)
}

extension Raster.Pixel {
    /// An `RGBA` as it renders: 8-bit per channel, fully opaque.
    ///
    /// Exists so a test can say `Raster.Pixel(islandGroundColour)` rather than
    /// restate the value. Four tests used to hardcode
    /// `Raster.Pixel(r: 5, g: 7, b: 11, a: 255)` with `// islandGroundColour`
    /// beside it, and when that constant turned out to be two levels a channel
    /// off the prototype's own `--void` (Plan 4.5), every one of them pinned the
    /// wrong value precisely rather than catching it. **A test that restates a
    /// constant cannot be evidence about that constant.**
    init(_ colour: RGBA) {
        self.init(r: UInt8((colour.r * 255).rounded()),
                  g: UInt8((colour.g * 255).rounded()),
                  b: UInt8((colour.b * 255).rounded()),
                  a: 255)
    }
}

enum RasterError: Error, CustomStringConvertible {
    case renderProducedNothing
    case contextUnavailable
    var description: String {
        switch self {
        case .renderProducedNothing:
            "ImageRenderer returned no image — the view probably resolved to zero size"
        case .contextUnavailable:
            "could not create an sRGB bitmap context"
        }
    }
}

/// Rasterises a view at `scale` device pixels per point.
///
/// SwiftUI draws straight into a bitmap context this function allocates and
/// zeroes, via `ImageRenderer.render(rasterizationScale:renderer:)`. It
/// deliberately does **not** ask for `renderer.cgImage`, for a reason that cost
/// this suite four wrong readings and one wrong diagnosis:
///
/// **`ImageRenderer.cgImage` can hand back a recycled backing store, and a view
/// that paints nothing does not clear it.** Measured, single-threaded, under
/// `--filter`, with no concurrency anywhere: render `SessionBlocks(options:
/// .agents)` in a 388×80 frame (474 opaque pixels), then render
/// `SessionBlocks(options: [])` in the *identical* frame, which must be blank.
/// The blank render reads **474 opaque pixels, twelve times out of twelve** —
/// the previous render's pixels, verbatim. The first blank render in a fresh
/// process reads 0, because nothing has occupied that block yet.
///
/// Two things follow, and both contradict what this project's plan register
/// recorded when the symptom was first seen as a full-suite flake:
///
/// 1. `--filter` is **not** a trustworthy mode for a golden reading. It is only
///    ever *quieter*, because a filtered run has fewer prior renders to inherit.
/// 2. `.serialized` would **not** have fixed it. There is no race to serialise;
///    the reproduction above is entirely sequential.
///
/// Rendering into our own zeroed buffer removes the shared store from the
/// picture altogether. It also subsumes the reason the old code re-drew the
/// `CGImage` into an explicit sRGB context — that image's colour space and byte
/// order are not contractual, and reading components off an unknown colour
/// space is what crashed the pixel profiler during the animation spike — since
/// the context SwiftUI draws into is now sRGB by construction. Measured against
/// the old two-step path on a content-filled render: identical dimensions,
/// identical opaque-pixel count, identical top/bottom ink distribution, and a
/// maximum per-channel difference of **2** levels, which is antialiasing and
/// well inside this file's own `tolerance: 6` convention.
@MainActor
func rasterise(_ view: some View, scale: CGFloat = 1) throws -> Raster {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale

    var outcome: Result<Raster, RasterError> = .failure(.renderProducedNothing)
    renderer.render(rasterizationScale: scale) { size, draw in
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        // A view that resolves to zero size gives nothing to measure. The old
        // `cgImage` path reported that as a nil image; this reports it the same
        // way, which `eachBlockOptionGatesOnlyItsOwnBlock` relies on when it
        // explains why its frame is pinned.
        guard w > 0, h > 0 else { return }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        outcome = bytes.withUnsafeMutableBytes { raw -> Result<Raster, RasterError> in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return .failure(.contextUnavailable) }
            ctx.scaleBy(x: scale, y: scale)
            draw(ctx)
            // Built here, inside the closure, so the bytes are copied out while
            // the pointer is still provably alive.
            return .success(Raster(width: w, height: h, bytes: Array(raw)))
        }
    }
    return try outcome.get()
}

/// Rasterises a view through **AppKit's own** rendering path — `NSHostingView`
/// laid out inside an offscreen `NSWindow`, captured with
/// `cacheDisplay(in:to:)` — rather than through `ImageRenderer`.
///
/// **This exists because `ImageRenderer` cannot render a `ScrollView`.** It
/// paints its content as fully transparent: measured, a bare `Text` in a fixed
/// frame gives 165 opaque pixels and the identical `Text` inside a `ScrollView`
/// gives **0**. That is what made §11's assembled session list — the one thing
/// on this branch nobody had ever looked at — unrenderable, and Plan 5 shipped
/// `SessionListFace` with a vacuous test and no visual fixture as a result. This
/// route renders it correctly, and still headlessly: no window is ever ordered
/// on screen, so it works on a locked machine exactly as `rasterise` does.
///
/// Why the window, given the hosting view could be laid out on its own: an
/// unattached `NSView`'s `bitmapImageRepForCachingDisplay` is 1× and the text
/// comes out too coarse to read line by line, which is this fixture's whole
/// purpose. A window supplies a `backingScaleFactor`, and the rep then matches
/// the real display's.
///
/// Still deliberately **not** the default for the assertions in this suite.
/// `ImageRenderer` is a pure function of a view value; this is a live AppKit
/// view hierarchy with a window behind it, and the failure modes that brings
/// (layout timing, backing-store scale varying with the machine) are exactly
/// what a golden test does not want. Use `rasterise` unless the thing under the
/// lens is a `ScrollView`.
@MainActor
func rasteriseHosted(_ view: some View, size: CGSize) throws -> Raster {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = CGRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.contentView = hosting
    // Layout has to complete before the capture: `cacheDisplay` draws whatever
    // the layer tree currently holds, and an un-laid-out `ScrollView` holds
    // nothing.
    hosting.layoutSubtreeIfNeeded()
    window.displayIfNeeded()

    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        throw RasterError.renderProducedNothing
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    guard let image = rep.cgImage else { throw RasterError.renderProducedNothing }

    // Same explicit sRGB redraw as `rasterise`, for the same reason: the rep's
    // own colour space and byte order are not contractual, and reading
    // components off an unknown colour space is what crashed the pixel profiler
    // during the animation spike.
    let w = image.width, h = image.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    // `withUnsafeMutableBytes`, not `&bytes`: see the escaped-inout note at the top of this file.
    let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
        guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    guard drawn else { throw RasterError.contextUnavailable }
    return Raster(width: w, height: h, bytes: bytes)
}

