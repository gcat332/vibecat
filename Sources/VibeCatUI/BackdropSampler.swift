import AppKit
import CoreGraphics
import ScreenCaptureKit

/// How light whatever is actually behind the island is.
///
/// The system appearance is a guess at this, and on a real machine it was
/// measured wrong: with the menu bar auto-hidden the island sits over the
/// wallpaper, and a dark wallpaper under a Light system reported light. The
/// captured strip came back at luminance 48 while `colorScheme` said `.light`.
public enum Backdrop: Sendable, Equatable {
    case light, dark

    /// Mid-grey. The aura's two tints are tuned against 26 and 234, so
    /// anything near the middle is a coin toss either way and the exact
    /// threshold is not load-bearing.
    static let lightnessThreshold = 128

    init(meanLuminance: Int) {
        self = meanLuminance >= Self.lightnessThreshold ? .light : .dark
    }
}

/// Looks at the pixels behind the island, when it is allowed to.
///
/// **Never prompts.** Screen recording is a large permission and this uses it
/// for the colour of a glow; a launch-time dialog asking for it would be out
/// of all proportion. It reads the grant if one exists and otherwise reports
/// nothing, leaving the caller on its `colorScheme` fallback. Design §15 does
/// not list this permission, and until Settings (Plan 6) offers it as a choice
/// the only way to turn it on is System Settings plus
/// `VIBECAT_REQUEST_SCREEN_RECORDING=1`, which shows the prompt once.
///
/// **Not cheap.** Measured on an M3 Pro: 94ms for the first capture and ~35ms
/// after. That is fine on a state change, which happens a few times a minute,
/// and ruinous per frame. `refresh` is async and never called from a draw.
@MainActor
public final class BackdropSampler {
    /// Nil until a successful sample. The caller keeps its own fallback rather
    /// than being handed a default that looks like a measurement.
    public private(set) var current: Backdrop?

    /// Off unless the permission is already granted — see the type comment.
    public static var isAvailable: Bool { CGPreflightScreenCaptureAccess() }

    public init() {}

    /// Shows the system prompt, once, if the permission is not already held.
    /// Only called behind an explicit opt-in; returns whether it is now held.
    @discardableResult
    public static func requestAccessIfAskedTo(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard env["VIBECAT_REQUEST_SCREEN_RECORDING"] == "1" else { return isAvailable }
        guard !isAvailable else { return true }
        return CGRequestScreenCaptureAccess()
    }

    /// Samples `region` (screen points, top-left origin) and updates `current`.
    /// Leaves `current` untouched on any failure — a missed sample is a stale
    /// answer, which is better than a wrong one.
    public func refresh(region: CGRect) async {
        guard Self.isAvailable, region.width >= 1, region.height >= 1 else { return }
        guard let luminance = await Self.meanLuminance(of: region) else { return }
        current = Backdrop(meanLuminance: luminance)
    }

    private static func meanLuminance(of region: CGRect) async -> Int? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return nil }

            // Excluding ourselves is the whole trick: the island covers the
            // strip we are asking about, so without this we would measure our
            // own ground colour and always conclude "dark". Matched on process
            // id rather than bundle identifier so it still works for an
            // unbundled `swift run vibecat`, which has no identifier at all.
            let me = ProcessInfo.processInfo.processIdentifier
            let ours = content.windows.filter { $0.owningApplication?.processID == me }
            let filter = SCContentFilter(display: display, excludingWindows: ours)

            let cfg = SCStreamConfiguration()
            cfg.sourceRect = region
            cfg.width = Int(region.width)
            cfg.height = Int(region.height)
            cfg.showsCursor = false
            cfg.captureResolution = .nominal

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: cfg)
            return Self.meanLuminance(of: image)
        } catch {
            return nil
        }
    }

    /// Raw sRGB bytes, never `NSColor` components — reading those off an
    /// unknown colour space is what crashed the pixel profiler during the
    /// animation spike.
    static func meanLuminance(of image: CGImage) -> Int? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0
        for i in stride(from: 0, to: buf.count, by: 4) {
            sum += (Int(buf[i]) + Int(buf[i + 1]) + Int(buf[i + 2])) / 3
        }
        return sum / (w * h)
    }
}
