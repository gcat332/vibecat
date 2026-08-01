import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif

/// Hover detection for a click-through window.
///
/// NSTrackingArea is unusable here: with ignoresMouseEvents = true the window
/// receives no mouse events at all, so a tracking area has nothing to observe.
/// Sampling the cursor position needs neither an event nor a permission.
@MainActor public final class HoverMonitor {
    /// How long the cursor must rest inside before this counts as hover. The
    /// cursor crosses the notch constantly on its way to the menu bar.
    public let dwell: TimeInterval

    public var frame: CGRect = .zero
    public var onChange: (@MainActor (Bool) -> Void)?
    public private(set) var isHovering = false

    private let cursor: @MainActor () -> CGPoint
    private let now: @MainActor () -> Date
    private var enteredAt: Date?
    private var timer: Timer?

    public init(dwell: TimeInterval = 0.30,
                cursor: @escaping @MainActor () -> CGPoint,
                now: @escaping @MainActor () -> Date) {
        self.dwell = dwell
        self.cursor = cursor
        self.now = now
    }

    #if canImport(AppKit)
    public convenience init(dwell: TimeInterval = 0.30) {
        self.init(dwell: dwell, cursor: { NSEvent.mouseLocation }, now: { Date() })
    }
    #endif

    /// Evaluate the cursor once. Called on a timer, and directly by tests.
    public func sample() {
        let inside = frame.contains(cursor())

        guard inside else {
            enteredAt = nil
            setHovering(false)     // leaving is immediate; only entering waits
            return
        }

        let entry = enteredAt ?? now()
        enteredAt = entry
        if now().timeIntervalSince(entry) >= dwell { setHovering(true) }
    }

    private func setHovering(_ value: Bool) {
        guard value != isHovering else { return }   // fire on edges only
        isHovering = value
        onChange?(value)
    }

    /// 30 Hz is well inside the budget and imperceptible for a hover gate.
    public func start() {
        stop()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        enteredAt = nil
    }
}
