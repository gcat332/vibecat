import Foundation
import Testing
@testable import VibeCatUI

private let t0 = Date(timeIntervalSince1970: 1_000_000)

@Test func theFirstObservationDoesNotFire() {
    var a = AuraTrigger()
    #expect(a.observe(.running, now: t0) == false)
    #expect(a.opacity(at: t0) == 0)
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

@Test func itBloomsInTheNewStatesColour() {
    var a = AuraTrigger()
    _ = a.observe(.idle, now: t0)
    _ = a.observe(.failed, now: t0.addingTimeInterval(1))
    #expect(a.colour == IslandState.failed.accent)
}

/// Rises, peaks at 14%, and is gone by 900ms. Design §9.2.
@Test func theEnvelopeRisesToThePeakThenReturnsToZero() {
    var a = AuraTrigger()
    _ = a.observe(.idle, now: t0)
    let fired = t0.addingTimeInterval(1)
    _ = a.observe(.waiting, now: fired)

    #expect(a.opacity(at: fired) == 0)
    let peak = a.opacity(at: fired.addingTimeInterval(AuraTrigger.duration / 2))
    #expect(abs(peak - AuraTrigger.peakOpacity) < 0.001)
    #expect(a.opacity(at: fired.addingTimeInterval(AuraTrigger.duration)) == 0)
    #expect(a.opacity(at: fired.addingTimeInterval(AuraTrigger.duration + 5)) == 0)
}

/// It is punctuation, not a status light — nothing is left behind.
@Test func itLeavesNothingBehind() {
    var a = AuraTrigger()
    _ = a.observe(.idle, now: t0)
    _ = a.observe(.failed, now: t0.addingTimeInterval(1))
    let after = t0.addingTimeInterval(1 + AuraTrigger.duration + 0.001)
    #expect(a.opacity(at: after) == 0)
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
    #expect(a.opacity(at: second) == 0)
    #expect(a.colour == IslandState.waiting.accent)
}
