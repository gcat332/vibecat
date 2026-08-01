import Foundation
import Testing
import CoreGraphics
@testable import VibeCatUI

@MainActor private final class Fake {
    var point = CGPoint(x: 0, y: 0)
    var clock = Date(timeIntervalSince1970: 1_000_000)
    var changes: [Bool] = []

    func monitor(dwell: TimeInterval = 0.30) -> HoverMonitor {
        let m = HoverMonitor(dwell: dwell,
                             cursor: { self.point },
                             now: { self.clock })
        m.frame = CGRect(x: 100, y: 100, width: 200, height: 32)
        m.onChange = { self.changes.append($0) }
        return m
    }

    func tick(_ seconds: TimeInterval) { clock += seconds }
}

@MainActor @Test func aCursorPassingThroughDoesNotTriggerHover() {
    let f = Fake()
    let m = f.monitor()
    f.point = CGPoint(x: 150, y: 110)   // inside
    m.sample()
    f.tick(0.1)
    f.point = CGPoint(x: 900, y: 500)   // gone again before the dwell elapses
    m.sample()
    #expect(m.isHovering == false)
    #expect(f.changes.isEmpty)
}

@MainActor @Test func restingForTheDwellTriggersHoverExactlyOnce() {
    let f = Fake()
    let m = f.monitor()
    f.point = CGPoint(x: 150, y: 110)
    m.sample()
    f.tick(0.31)
    m.sample()
    m.sample()
    m.sample()
    #expect(m.isHovering)
    #expect(f.changes == [true])
}

@MainActor @Test func leavingEndsHoverImmediatelyWithNoDwell() {
    let f = Fake()
    let m = f.monitor()
    f.point = CGPoint(x: 150, y: 110)
    m.sample()
    f.tick(0.31)
    m.sample()
    f.point = CGPoint(x: 900, y: 500)
    m.sample()
    #expect(m.isHovering == false)
    #expect(f.changes == [true, false])
}

@MainActor @Test func reEnteringRestartsTheDwell() {
    let f = Fake()
    let m = f.monitor()
    f.point = CGPoint(x: 150, y: 110)
    m.sample()
    f.tick(0.2)
    f.point = CGPoint(x: 900, y: 500)   // left at 0.2, short of the dwell
    m.sample()
    f.point = CGPoint(x: 150, y: 110)   // straight back in
    m.sample()
    f.tick(0.2)                          // 0.4 total inside, but only 0.2 since re-entry
    m.sample()
    #expect(m.isHovering == false)
    f.tick(0.15)
    m.sample()
    #expect(m.isHovering)
}

@MainActor @Test func movingTheFrameOutFromUnderTheCursorEndsHover() {
    let f = Fake()
    let m = f.monitor()
    f.point = CGPoint(x: 150, y: 110)
    m.sample()
    f.tick(0.31)
    m.sample()
    #expect(m.isHovering)
    m.frame = CGRect(x: 800, y: 100, width: 200, height: 32)
    m.sample()
    #expect(m.isHovering == false)
}

@MainActor @Test func aZeroDwellTriggersOnTheFirstSampleInside() {
    let f = Fake()
    let m = f.monitor(dwell: 0)
    f.point = CGPoint(x: 150, y: 110)
    m.sample()
    #expect(m.isHovering)
}

// start()/stop() wire up a real, wall-clock-driven Timer, so a test cannot
// deterministically observe it actually firing (or having stopped firing)
// without depending on real timer scheduling — which is exactly what the
// injected cursor/clock exist to let us avoid. These two tests cover what
// remains deterministic: start()+stop() introduce no side effects of their
// own outside of an explicit sample() call, and stop() clears the in-flight
// dwell entry rather than merely silencing the timer, so a cursor that was
// partway through its dwell before stop() does not get credit for that time
// afterwards.

@MainActor @Test func startingThenStoppingProducesNoAutomaticHoverChanges() {
    let f = Fake()
    let m = f.monitor()
    m.start()
    m.stop()
    f.point = CGPoint(x: 150, y: 110)   // inside; would eventually hover if sampled
    f.tick(0.31)                          // well past the dwell, if anything were sampling
    #expect(m.isHovering == false)
    #expect(f.changes.isEmpty)
}

@MainActor @Test func stopClearsTheInFlightDwellEntryRatherThanJustTheTimer() {
    let f = Fake()
    let m = f.monitor()
    m.start()
    f.point = CGPoint(x: 150, y: 110)   // inside; dwell begins accumulating
    m.sample()
    f.tick(0.2)                          // short of the 0.30s dwell
    m.stop()
    f.tick(0.2)                          // if the entry survived stop(), 0.4s total would clear the dwell
    m.sample()
    #expect(m.isHovering == false)
    #expect(f.changes.isEmpty)
}
