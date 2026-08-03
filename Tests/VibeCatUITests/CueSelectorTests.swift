import Testing
import Foundation
import VibeCatCore
@testable import VibeCatUI

// MARK: - CueSelector

// `VibeEvent.init` has no default for `id:`, and its label order is
// `v:id:cli:kind:session:cwd:`. Copied from the pattern at
// `Tests/VibeCatUITests/AppModelTests.swift:10` rather than invented.
private func session(_ id: String, _ kind: Kind) -> VibeEvent {
    VibeEvent(id: "e-\(id)", cli: "claude-code", kind: kind, session: id, cwd: "/tmp/\(id)")
}

private func store(_ events: [VibeEvent]) -> SessionStore {
    var s = SessionStore()
    let t = Date(timeIntervalSince1970: 1_800_000_000)
    for e in events { s.apply(e, now: t) }
    return s
}

@Test func aFirstQuestionAsks() {
    let before = store([session("a", .running)])
    let after  = store([session("a", .permission)])
    #expect(CueSelector.cue(for: session("a", .permission), before: before, after: after) == .ask)
}

@Test func aSecondQuestionFromAnotherSessionAsksAgainWithTheDoubledFigure() {
    // The case IslandState cannot express: both stores read `waiting`, so a
    // selector keyed on IslandState alone stays silent here and the second
    // agent waits unannounced.
    let before = store([session("a", .permission)])
    let after  = store([session("a", .permission), session("b", .question)])
    #expect(CueSelector.cue(for: session("b", .question), before: before, after: after) == .askMulti)
}

@Test func answeringOneOfTwoQuestionsIsSilent() {
    // The written divergence from the prototype: line 957 cues on any change of
    // presented state, so askmulti → ask beeps at you for having just answered.
    // Demand fell; that is not news.
    let before = store([session("a", .permission), session("b", .question)])
    let after  = store([session("a", .running), session("b", .question)])
    #expect(CueSelector.cue(for: session("a", .running), before: before, after: after) == nil)
}

@Test func aThirdQuestionDoesNotAskAThirdTime() {
    // Both sides are askMulti, so nothing changed in the presented state. The
    // prototype behaves the same way, and this pins it as chosen rather than
    // accidental.
    let before = store([session("a", .permission), session("b", .question)])
    let after  = store([session("a", .permission), session("b", .question),
                        session("c", .permission)])
    #expect(CueSelector.cue(for: session("c", .permission), before: before, after: after) == nil)
}

@Test func aFinishedRunComesFromTheEventBecauseTheStateThrowsItAway() {
    // `SessionState.init(kind:)` maps .done to .idle, so after the apply there
    // is no trace of anything having finished. A selector that only diffed
    // stores would be permanently silent here.
    let before = store([session("a", .running)])
    let after  = store([session("a", .done)])
    #expect(SessionState(kind: .done) == .idle, "the premise of this test")
    #expect(CueSelector.cue(for: session("a", .done), before: before, after: after) == .done)
}

@Test func aFinishWhileAnotherAgentWaitsStillAnnouncesItself() {
    // Worst-state-wins governs what the island *displays* (§4.2). It does not
    // govern what happened: a run finishing is news even while another session
    // is blocked, and the island's own state does not change here at all.
    let before = store([session("a", .running),  session("b", .permission)])
    let after  = store([session("a", .done),     session("b", .permission)])
    #expect(IslandState(store: before) == IslandState(store: after), "the premise")
    #expect(CueSelector.cue(for: session("a", .done), before: before, after: after) == .done)
}

@Test func aFailureErrors() {
    let before = store([session("a", .running)])
    let after  = store([session("a", .failed)])
    #expect(CueSelector.cue(for: session("a", .failed), before: before, after: after) == .error)
}

@Test func aFailureIsNotAnnouncedTwice() {
    let before = store([session("a", .failed)])
    let after  = store([session("a", .failed), session("b", .failed)])
    #expect(CueSelector.cue(for: session("b", .failed), before: before, after: after) == nil)
}

@Test func aFailureWhileSomeoneIsAlreadyWaitingIsSilentBecauseTheIslandNeverShowedIt() {
    // waiting beats failed (§4.2), so the island's state does not change and
    // there is nothing new to announce. Recorded as a consequence of the
    // ordering rather than as a gap.
    let before = store([session("a", .permission)])
    let after  = store([session("a", .permission), session("b", .failed)])
    #expect(CueSelector.cue(for: session("b", .failed), before: before, after: after) == nil)
}

@Test func startingAndFinishingWorkQuietly() {
    // A run beginning is not an interruption. Neither is going idle.
    let idle = store([session("a", .idle)])
    let running = store([session("a", .running)])
    #expect(CueSelector.cue(for: session("a", .running), before: idle, after: running) == nil)
    #expect(CueSelector.cue(for: session("a", .idle), before: running, after: idle) == nil)
    #expect(CueSelector.cue(for: session("a", .running),
                            before: SessionStore(), after: running) == nil)
}

@Test func aRepeatedEventOfTheSameKindIsSilent() {
    // Heartbeats. A CLI re-reporting `running` must not cue, and a second
    // `permission` from the *same* session leaves the count at one.
    let s = store([session("a", .permission)])
    #expect(CueSelector.cue(for: session("a", .permission), before: s, after: s) == nil)
}
