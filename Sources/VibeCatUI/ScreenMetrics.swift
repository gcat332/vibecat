import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif

/// A snapshot of everything the island needs to know about a display.
///
/// Value type on purpose: the geometry maths is the part worth testing, and it
/// should not need a window server to run. This is the only file in VibeCatUI
/// that touches NSScreen.
public struct ScreenMetrics: Sendable, Equatable {
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let safeAreaTop: CGFloat
    public let auxLeft: CGRect?
    public let auxRight: CGRect?

    public init(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat,
                auxLeft: CGRect?, auxRight: CGRect?) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxLeft = auxLeft
        self.auxRight = auxRight
    }

    /// The cutout, in screen coordinates. `nil` on any display that does not
    /// report one — an external monitor, or a machine reporting partially.
    public var notch: CGRect? {
        guard safeAreaTop > 0, let l = auxLeft, let r = auxRight, r.minX > l.maxX
        else { return nil }
        return CGRect(x: l.maxX,
                      y: frame.maxY - safeAreaTop,
                      width: r.minX - l.maxX,
                      height: safeAreaTop)
    }

    public var hasNotch: Bool { notch != nil }
}

#if canImport(AppKit)
extension ScreenMetrics {
    public init(_ screen: NSScreen) {
        self.init(frame: screen.frame,
                  visibleFrame: screen.visibleFrame,
                  safeAreaTop: screen.safeAreaInsets.top,
                  auxLeft: screen.auxiliaryTopLeftArea,
                  auxRight: screen.auxiliaryTopRightArea)
    }

    /// The built-in display if it has a notch, otherwise the main display.
    @MainActor public static func current() -> ScreenMetrics? {
        let notched = NSScreen.screens.first {
            $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil
        }
        guard let screen = notched ?? NSScreen.main else { return nil }
        return ScreenMetrics(screen)
    }
}
#endif
