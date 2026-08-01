import Foundation

/// Light blooms out of the island in the new state's colour and leaves nothing
/// behind. Design §9.2 — a glow that stayed lit would be a second indicator
/// competing with the cat, so this fires on change and only on change.
public struct AuraTrigger: Sendable, Equatable {
    public static let duration: TimeInterval = 0.9

    /// Measured, not chosen. At the design's original 0.14 the bloom fired
    /// perfectly and could not be seen: sampling the screen 24 times across a
    /// real state change produced the exact `sin(phase · π)` hump, ~960ms
    /// wide, whose peak lifted the band outside the island by **6 levels
    /// summed across R, G and B** — two per channel. Plan 2's follow-up called
    /// this before it was measured: "if it looks absent, check
    /// `AuraTrigger.peakOpacity` before suspecting the trigger."
    ///
    /// Halo lift is linear in this value at about 76 levels per unit, so 0.34
    /// buys ~26 — four times what shipped. Rendered side by side against 0.24
    /// and 0.44 (see `auraOpacitySweep`), it is the first one that reads as a
    /// glow rather than as dither, and stops short of shouting. A bloom that
    /// only touches its peak for an instant needs the headroom.
    public static let peakOpacity: Double = 0.34

    private var lastState: IslandState?
    private var firedAt: Date?

    public init() {}

    /// Returns true when this observation started a bloom. The very first
    /// observation never does: launching the app is not a state change.
    public mutating func observe(_ state: IslandState, now: Date) -> Bool {
        defer { lastState = state }
        guard let previous = lastState else { return false }
        guard previous != state else { return false }
        firedAt = now
        return true
    }

    /// Whether a bloom is in flight. The view uses this to decide if it needs
    /// per-frame redraws — an idle machine must not animate. True from the
    /// instant it fires, even though opacity is 0 there.
    ///
    /// Compares `Date`s directly rather than reconstructing elapsed seconds
    /// via `timeIntervalSince` and comparing to `duration`: at these
    /// magnitudes (~1e9s from the reference date), that subtraction loses
    /// enough precision that a boundary instant built as `firedAt + duration`
    /// comes back as `0.8999999761…`, not `0.9` — the exclusive bound would
    /// silently admit it. `firedAt.addingTimeInterval(duration)` performed
    /// here and performed by a caller building the same boundary are the same
    /// floating-point operation on the same inputs, so they land bit-identical.
    public func isBlooming(at instant: Date) -> Bool {
        guard let firedAt else { return false }
        return instant >= firedAt && instant < firedAt.addingTimeInterval(Self.duration)
    }

    /// A symmetric rise and fall. Zero at both ends, so nothing is left behind.
    public func opacity(at instant: Date) -> Double {
        guard isBlooming(at: instant), let firedAt else { return 0 }
        let phase = instant.timeIntervalSince(firedAt) / Self.duration     // 0…1
        return Self.peakOpacity * sin(phase * .pi)
    }
}
