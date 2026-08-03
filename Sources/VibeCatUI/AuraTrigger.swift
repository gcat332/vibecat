import Foundation

/// Light blooms out of the island in the new state's colour and leaves nothing
/// behind. Design §9.2 — a glow that stayed lit would be a second indicator
/// competing with the cat, so this fires on change and only on change.
public struct AuraTrigger: Sendable, Equatable {
    public static let duration: TimeInterval = 0.9

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

    /// A symmetric rise and fall, normalised to 0…1. Zero at both ends, so
    /// nothing is left behind.
    ///
    /// The *shape* of the bloom only. How strong it actually is depends on the
    /// menu bar it lands on, and `AuraTint` owns that — one peak for both
    /// backdrops is what left the aura invisible in Light mode.
    public func intensity(at instant: Date) -> Double {
        guard isBlooming(at: instant), let firedAt else { return 0 }
        let phase = instant.timeIntervalSince(firedAt) / Self.duration     // 0…1
        return sin(phase * .pi)
    }

    /// The rendered opacity for one backdrop: the curve, scaled by that
    /// backdrop's measured peak.
    public func opacity(at instant: Date, tint: AuraTint) -> Double {
        intensity(at: instant) * tint.peakOpacity
    }

    /// Ends the bloom, and does it with a `mutating func`, not an assignment.
    ///
    /// The distinction is the whole point, and it is *not* about the value
    /// differing. `NotchController` used to "nudge" `model.aura` by assigning
    /// it its own current value (`model.aura = model.aura ?? AuraTrigger()`).
    /// That is a plain assignment, and on this toolchain an `@Observable`
    /// property's generated `set` accessor is gated behind
    /// `shouldNotifyObservers(old, new)` — `old != new` for an `Equatable`
    /// type — so assigning an equal value notifies nothing (measured,
    /// `anEqualWriteToAnObservablePropertyDoesNotNotify`). The nudge notified
    /// nothing, `IslandView.body` was never re-evaluated, and its `if model
    /// .needsTimeline` branch kept a `TimelineView` alive forever after the
    /// first state change into a still mood — about 3.3% of a core,
    /// permanently, per the animation spike's own 3.61%-against-0.35%
    /// figures.
    ///
    /// A *mutating method call* through the same property — `model.aura
    /// .endBloom()`, what `NotchController` calls now — does not go through
    /// that gate at all: it desugars to the generated `_modify` accessor,
    /// which calls `willSet`/`didSet` unconditionally, with no equality check
    /// (measured by dumping macro expansions, pinned by
    /// `aMutatingCallThroughAnObservablePropertyNotifiesUnconditionally`).
    /// So this fix works because it is a mutating call, not because clearing
    /// `firedAt` happens to produce a different value — rewriting this call
    /// site back into an assignment (even one that "clears" `firedAt`) would
    /// route through `set` again and silently reintroduce this exact bug.
    ///
    /// Clearing `firedAt` is still the right thing to clear, independent of
    /// notification: the bloom really is over, and `intensity` is already 0
    /// at that instant, so nothing about what gets painted changes either.
    public mutating func endBloom() {
        firedAt = nil
    }
}
