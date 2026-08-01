import Foundation

/// Light blooms out of the island in the new state's colour and leaves nothing
/// behind. Design §9.2 — a glow that stayed lit would be a second indicator
/// competing with the cat, so this fires on change and only on change.
public struct AuraTrigger: Sendable, Equatable {
    public static let duration: TimeInterval = 0.9
    public static let peakOpacity: Double = 0.14

    private var lastState: IslandState?
    private var firedAt: Date?
    private var firedColour: RGBA?

    public init() {}

    /// Returns true when this observation started a bloom. The very first
    /// observation never does: launching the app is not a state change.
    public mutating func observe(_ state: IslandState, now: Date) -> Bool {
        defer { lastState = state }
        guard let previous = lastState else { return false }
        guard previous != state else { return false }
        firedAt = now
        firedColour = state.accent
        return true
    }

    public var colour: RGBA? { firedColour }

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
