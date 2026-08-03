import AppKit
import SwiftUI
import Testing
@testable import VibeCatUI

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
        var copy = bytes
        guard let ctx = CGContext(data: &copy, width: width, height: height,
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
        var bytes = f.bytes
        guard let ctx = CGContext(data: &bytes, width: f.width, height: f.height,
                                  bitsPerComponent: 8, bytesPerRow: f.width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = ctx.makeImage() else { return false }
        CGImageDestinationAddImage(dst, image, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: secondsPerFrame]
        ] as CFDictionary)
    }
    return CGImageDestinationFinalize(dst)
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
/// The result is re-drawn into an explicit sRGB context rather than read
/// straight off `ImageRenderer`'s `CGImage`: that image's colour space and
/// byte order are not contractual, and reading components off an unknown
/// colour space is exactly what crashed the pixel profiler during the
/// animation spike.
@MainActor
func rasterise(_ view: some View, scale: CGFloat = 1) throws -> Raster {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let image = renderer.cgImage else { throw RasterError.renderProducedNothing }

    let w = image.width, h = image.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &bytes, width: w, height: h,
                              bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw RasterError.contextUnavailable }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return Raster(width: w, height: h, bytes: bytes)
}
