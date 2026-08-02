import Foundation
import Testing
import VibeCatCore
@testable import VibeCatUI

private func question(id: String = "q1") -> VibeEvent {
    VibeEvent(id: id, cli: "claude-code", kind: .permission, session: "s1", cwd: "/tmp/proj",
              choices: [Choice(id: "allow", label: "Allow once"),
                        Choice(id: "deny", label: "Deny")],
              wantsReply: true)
}

@Test func anAnsweredQuestionHandsTheReplyBackToTheWaiter() async throws {
    let p = PendingQuestion(event: question(), deadline: 5)
    let start = Date()
    let waiter = Task.detached { p.await() }
    // Resolve from another thread, as the UI will.
    try await Task.sleep(for: .milliseconds(20))
    #expect(p.resolve(Reply(id: "q1", choice: "allow")))
    let reply = await waiter.value
    #expect(reply?.choice == "allow")
    // await() re-derives its return value from locked state even on its
    // timeout path, so a dropped gate.signal() would still hand back
    // "allow" here — just ~5s late instead of ~20ms. Bound the wall clock
    // so that failure mode goes red instead of quietly slow.
    #expect(Date().timeIntervalSince(start) < 1.0, "resolve() left the waiter parked")
}

@Test func anUnansweredQuestionTimesOutAndFailsOpen() {
    let p = PendingQuestion(event: question(), deadline: 0.05)
    let start = Date()
    let reply = p.await()
    #expect(reply == nil, "a question nobody answered must return nil so the CLI prompts itself")
    #expect(Date().timeIntervalSince(start) < 1.0, "await outran its deadline")
}

/// The hook has already given up and the CLI has printed its own prompt. An
/// answer given in the island after that point would be answering a question
/// nobody is listening to — and could differ from what the person then types
/// into the terminal.
@Test func aLapsedQuestionStopsBeingAnswerable() {
    let p = PendingQuestion(event: question(), deadline: 0.05)
    _ = p.await()                                   // let it time out
    #expect(p.hasLapsed(at: Date()))
    #expect(p.resolve(Reply(id: "q1", choice: "allow")) == false,
            "resolve() succeeded on a question that had already lapsed")
}

@Test func aReplyForADifferentQuestionIsRefused() {
    let p = PendingQuestion(event: question(id: "q1"), deadline: 5)
    #expect(p.resolve(Reply(id: "someone-elses", choice: "allow")) == false)
}

/// Two resolves race only in theory — the UI is main-actor — but the waiter
/// must be signalled exactly once either way, or the second signal leaks.
@Test func onlyTheFirstResolveWins() async throws {
    let p = PendingQuestion(event: question(), deadline: 5)
    let start = Date()
    let waiter = Task.detached { p.await() }
    try await Task.sleep(for: .milliseconds(20))
    #expect(p.resolve(Reply(id: "q1", choice: "allow")))
    #expect(p.resolve(Reply(id: "q1", choice: "deny")) == false)
    #expect(await waiter.value?.choice == "allow")
    // Same reasoning as anAnsweredQuestionHandsTheReplyBackToTheWaiter: a
    // dropped signal on the winning resolve() would still deliver "allow"
    // eventually via the timeout path, so bound the wait explicitly.
    #expect(Date().timeIntervalSince(start) < 1.0, "resolve() left the waiter parked")
}

/// lapse()'s other half of the contract: unblocking a parked await() is its
/// whole job, so — like resolve() — it needs its wall-clock time bounded. A
/// lapse() that forgot to signal would still return nil here eventually, via
/// the 5s timeout, and look green without this.
@Test func lapseUnblocksAParkedWaiterPromptly() async throws {
    let p = PendingQuestion(event: question(), deadline: 5)
    let start = Date()
    let waiter = Task.detached { p.await() }
    try await Task.sleep(for: .milliseconds(20))
    p.lapse()
    let reply = await waiter.value
    #expect(reply == nil, "lapse() carries no answer")
    #expect(Date().timeIntervalSince(start) < 1.0, "lapse() left the waiter parked")
}

/// No waiter parked here, on purpose: await() sets `settled` itself the
/// instant it wakes, for any reason, which would mask a broken lapse() that
/// forgot to settle. Calling lapse() with nobody waiting isolates lapse()'s
/// own bookkeeping from await()'s.
@Test func lapseClosesTheQuestionToFurtherActivity() {
    let p = PendingQuestion(event: question(), deadline: 5)
    p.lapse()
    #expect(p.hasLapsed(at: Date()))
    #expect(p.resolve(Reply(id: "q1", choice: "allow")) == false,
            "resolve() succeeded after lapse() had already closed the question")
}

/// Two lapses race only in theory, same as two resolves (see
/// onlyTheFirstResolveWins) — but a second signal with nobody left to
/// consume it is a leak either way.
@Test func lapsingTwiceDoesNotDoubleSignal() {
    let p = PendingQuestion(event: question(), deadline: 0.1)
    p.lapse()
    p.lapse()
    _ = p.await()                     // consumes the one legitimate signal
    let start = Date()
    let second = p.await()
    #expect(second == nil)
    // A leaked second signal would let this second await() return
    // immediately instead of riding out the deadline the way an
    // unsignalled wait must.
    #expect(Date().timeIntervalSince(start) > 0.08,
            "a second buffered signal let await() return without waiting")
}

/// aLapsedQuestionStopsBeingAnswerable only ever calls hasLapsed() after
/// wall-clock time has already passed `expiry`, so `instant >= expiry` alone
/// would satisfy it even with `settled ||` deleted. Settle minutes before
/// the deadline instead, so only the `settled` branch can be doing the work.
@Test func aResolvedQuestionHasLapsedWellBeforeItsDeadline() {
    let p = PendingQuestion(event: question(), deadline: 5)
    #expect(p.resolve(Reply(id: "q1", choice: "allow")))
    #expect(p.hasLapsed(at: Date()),
            "a settled question has lapsed however long remains on the clock")
}
