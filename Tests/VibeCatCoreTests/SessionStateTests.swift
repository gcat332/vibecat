import Testing
@testable import VibeCatCore

@Test func waitingOutranksFailed() {
    // A waiting agent is idling on you right now; a failed one has already stopped.
    #expect(SessionState.mostUrgent([.failed, .waiting]) == .waiting)
}

@Test func theWholeOrderingHolds() {
    #expect(SessionState.mostUrgent([.idle, .running, .failed, .waiting]) == .waiting)
    #expect(SessionState.mostUrgent([.idle, .running, .failed]) == .failed)
    #expect(SessionState.mostUrgent([.idle, .running]) == .running)
    #expect(SessionState.mostUrgent([.idle]) == .idle)
}

@Test func mostUrgentOfNothingIsNil() {
    #expect(SessionState.mostUrgent([]) == nil)
}

@Test func kindsMapOntoStates() {
    #expect(SessionState(kind: .permission) == .waiting)
    #expect(SessionState(kind: .question)   == .waiting)
    #expect(SessionState(kind: .running)    == .running)
    #expect(SessionState(kind: .failed)     == .failed)
    #expect(SessionState(kind: .done)       == .idle)
    #expect(SessionState(kind: .idle)       == .idle)
}
