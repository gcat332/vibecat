import Foundation
import Testing
@testable import VibeCatUI

private let t0 = Date(timeIntervalSince1970: 1_000_000)

@Test func theFirstObservationDoesNotFire() {
    var a = AuraTrigger()
    #expect(a.observe(.running, now: t0) == false)
    #expect(a.intensity(at: t0) == 0)
}

@Test func aChangeFires() {
    var a = AuraTrigger()
    _ = a.observe(.idle, now: t0)
    // `== true` (rather than a bare call) sidesteps a swift-testing macro
    // limitation: #expect's diagnostic expansion for direct method calls
    // captures the receiver by `let`, which cannot host a mutating call.
    #expect(a.observe(.waiting, now: t0.addingTimeInterval(1)) == true)
}

/// The same state arriving again is not news.
@Test func repeatingTheSameStateDoesNotFire() {
    var a = AuraTrigger()
    _ = a.observe(.running, now: t0)
    #expect(a.observe(.running, now: t0.addingTimeInterval(1)) == false)
    #expect(a.observe(.running, now: t0.addingTimeInterval(2)) == false)
}

/// Rises, peaks at 14%, and is gone by 900ms. Design §9.2.
@Test func theEnvelopeRisesToThePeakThenReturnsToZero() {
    var a = AuraTrigger()
    _ = a.observe(.idle, now: t0)
    let fired = t0.addingTimeInterval(1)
    _ = a.observe(.waiting, now: fired)

    #expect(a.intensity(at: fired) == 0)
    let peak = a.intensity(at: fired.addingTimeInterval(AuraTrigger.duration / 2))
    #expect(abs(peak - 1.0) < 0.001, "the curve should peak at 1 — its strength is AuraTint's to scale")
    #expect(a.intensity(at: fired.addingTimeInterval(AuraTrigger.duration)) == 0)
    #expect(a.intensity(at: fired.addingTimeInterval(AuraTrigger.duration + 5)) == 0)
}

/// It is punctuation, not a status light — nothing is left behind.
@Test func itLeavesNothingBehind() {
    var a = AuraTrigger()
    _ = a.observe(.idle, now: t0)
    _ = a.observe(.failed, now: t0.addingTimeInterval(1))
    let after = t0.addingTimeInterval(1 + AuraTrigger.duration + 0.001)
    #expect(a.intensity(at: after) == 0)
}

/// Drives whether the view needs per-frame redraws. True across the whole
/// window including its zero-opacity start, so the first frame is not skipped.
@Test func isBloomingCoversTheWholeWindowIncludingTheZeroStart() {
    var a = AuraTrigger()
    #expect(a.isBlooming(at: t0) == false)          // never fired
    _ = a.observe(.idle, now: t0)
    let fired = t0.addingTimeInterval(1)
    _ = a.observe(.waiting, now: fired)

    #expect(a.isBlooming(at: fired))                              // opacity is 0 here
    #expect(a.isBlooming(at: fired.addingTimeInterval(0.45)))
    #expect(a.isBlooming(at: fired.addingTimeInterval(AuraTrigger.duration)) == false)
}

@Test func aSecondChangeRestartsTheEnvelope() {
    var a = AuraTrigger()
    _ = a.observe(.idle, now: t0)
    _ = a.observe(.running, now: t0.addingTimeInterval(1))
    let second = t0.addingTimeInterval(1.4)         // mid-bloom
    _ = a.observe(.waiting, now: second)
    #expect(a.intensity(at: second) == 0)
}

/// §9.2: the aura "leaves nothing behind". Once the bloom's duration has elapsed
/// it is over, and `endBloom()` has to actually clear it rather than leave
/// `firedAt` standing.
///
/// This test operates on a bare `AuraTrigger` value, with no `@Observable`
/// property in the picture at all, so `aura != before` here is a fact about
/// the struct, not about notification. Whether the value differs is *not*
/// why `NotchController`'s real call notifies — that is decided by call
/// shape (a mutating method call routes through the generated `_modify`
/// accessor, which notifies unconditionally) rather than by whether anything
/// changed; see `AuraTrigger.endBloom()`'s own comment and
/// `aMutatingCallThroughAnObservablePropertyNotifiesUnconditionally` for that
/// measurement. What this test pins is narrower and still worth having:
/// `endBloom()` produces a value that is honestly different, not just one
/// that happens to look inert because `intensity` is already 0.
@Test func endingABloomStopsItBlooming() {
    let fired = Date(timeIntervalSince1970: 1_000_000)
    var aura = AuraTrigger()
    _ = aura.observe(.idle, now: fired)          // first observation never blooms
    // `== true` (rather than a bare call) sidesteps the swift-testing macro
    // limitation `aChangeFires` documents: #expect's diagnostic expansion for
    // direct method calls captures the receiver by `let`, which cannot host a
    // mutating call.
    #expect(aura.observe(.running, now: fired) == true, "setup: a real change must bloom")
    #expect(aura.isBlooming(at: fired))

    let before = aura
    aura.endBloom()

    #expect(!aura.isBlooming(at: fired), "the bloom survived endBloom()")
    #expect(aura != before,
            "endBloom() left the value equal to what it was — not honest per §9.2, even though a mutating call would still have notified regardless")
}
