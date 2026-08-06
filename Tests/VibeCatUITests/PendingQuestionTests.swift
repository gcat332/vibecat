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

// MARK: - parking (Plan 9 Task 1)
//
// These live here rather than in the `ParkedQuestionTests.swift` the plan named,
// and the reason is worth one line: every other assertion about this type's gate
// discipline is in this file, including `lapsingTwiceDoesNotDoubleSignal`'s
// wall-clock idiom that the first test below reuses. Splitting parking out would
// put two halves of one type's contract in two files. `ParkedQuestionTests.swift`
// takes Tasks 2–3's model- and island-level assertions instead.

/// **The whole point of parking, and the one way to get it catastrophically
/// wrong.** `park()` must not signal the gate. A `park()` written by copying
/// `lapse()` would release the waiting hook — the agent is told to carry on, the
/// island still draws the question, and every UI-level test still passes. The
/// person then answers a question nobody is listening to.
///
/// Detected the way `lapsingTwiceDoesNotDoubleSignal` detects a leaked signal:
/// an unsignalled `await()` must ride out its full deadline, so bound the wall
/// clock from *below*. Nothing but a signal can make it return early — `expiry`
/// is absolute, so even a waiter that starts late still returns at ~0.3s.
@Test func parkingDoesNotReleaseTheWaitingHook() async throws {
    let p = PendingQuestion(event: question(), deadline: 0.3)
    let start = Date()
    let waiter = Task.detached { p.await() }
    try await Task.sleep(for: .milliseconds(20))
    p.park()
    #expect(p.isParked)
    let reply = await waiter.value
    #expect(reply == nil, "parking carries no answer")
    #expect(Date().timeIntervalSince(start) > 0.25,
            "park() signalled the gate, so the hook was released and the agent carried on")
}

/// The inverse, so the pair brackets the behaviour. Without this, a `park()`
/// that simply did nothing at all would pass the test above — and `lapse()`
/// losing its signal is a regression parking makes easy to introduce, since both
/// now live beside each other.
@Test func dismissingStillReleasesTheWaitingHookEvenAfterParking() async throws {
    let p = PendingQuestion(event: question(), deadline: 5)
    let start = Date()
    let waiter = Task.detached { p.await() }
    try await Task.sleep(for: .milliseconds(20))
    p.park()
    p.lapse()
    #expect(await waiter.value == nil)
    #expect(Date().timeIntervalSince(start) < 1.0,
            "lapse() on a parked question left the waiter parked")
}

/// Parking is why a question is worth keeping, so it must stay answerable.
@Test func aParkedQuestionCanStillBeResolved() {
    let p = PendingQuestion(event: question(), deadline: 5)
    p.park()
    #expect(p.resolve(Reply(id: "q1", choice: "allow")))
}

/// **Parking does not pause the clock**, and this is the assertion that stops
/// someone making it do so. The hook fixes its own wait against `expiry` before
/// anyone can park anything and knows nothing about parking, so a parked
/// question that stopped expiring would outlive the thread it belongs to: the
/// island would keep offering an answer the socket had already abandoned.
///
/// Settled well before the deadline would let `settled ||` do the work, so this
/// deliberately waits the clock out instead — the `instant >= expiry` branch is
/// the one under test.
@Test func aParkedQuestionStillExpires() {
    let now = Date()
    let p = PendingQuestion(event: question(), deadline: 5, now: now)
    p.park()
    #expect(!p.hasLapsed(at: now.addingTimeInterval(4)))
    #expect(p.hasLapsed(at: now.addingTimeInterval(6)),
            "parking stopped the expiry clock, so this question outlives its hook")
}

/// A question the hook has already given up on must not come back into the list.
/// Two ways this arrives: the person dismissed it, or it timed out while the
/// notch was collapsed. Either way `park()` after `settled` would redraw a
/// question the agent has already moved past.
@Test func aSettledQuestionCannotBeParked() {
    let p = PendingQuestion(event: question(), deadline: 5)
    p.lapse()
    p.park()
    #expect(!p.isParked, "a question that had already lapsed was parked back into the list")
}

/// `unpark()` is how tapping a row brings the question back to the front, and it
/// has the same settled guard for the same reason.
@Test func unparkingReturnsAQuestionToTheFrontButNotFromTheDead() {
    let p = PendingQuestion(event: question(), deadline: 5)
    p.park()
    p.unpark()
    #expect(!p.isParked)

    let dead = PendingQuestion(event: question(), deadline: 5)
    dead.park()
    dead.lapse()
    dead.unpark()
    #expect(dead.hasLapsed(at: Date()), "unpark() revived a settled question")
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

// MARK: - Never (Plan 9 Task 7)
//
// `nil` means the notch holds this question for as long as the hook lives and the
// terminal is never prompted. The hazard the three tests below exist for is that
// `Never` and "a very long time" are indistinguishable *after* the arithmetic:
// `DispatchTime`'s `+` saturates instead of trapping, so `.now() + 6e10` — which is
// what `Date.distantFuture.timeIntervalSinceNow` would hand it — silently becomes
// `.distantFuture`. Deliberate in one named place is the opposite of that bug.

/// The one named place, and the proof nothing computes its way there.
///
/// The third assertion is the load-bearing one: it feeds `waitInstant` the exact
/// value someone would reach for if they spelled `Never` as an instant instead of
/// as its absence, and requires that it still comes back *finite*. Delete the
/// `min` against `ceilingDeadline` and it turns into `.distantFuture` — a thread
/// parked for the life of the process, which is what §2.3 forbids outright.
@Test func neverIsSpelledOutRatherThanArrivedAtByArithmetic() {
    #expect(PendingQuestion.waitInstant(until: nil) == .distantFuture,
            "the deliberate forever is not being produced")
    #expect(PendingQuestion.waitInstant(until: Date().addingTimeInterval(30)) < .distantFuture)
    #expect(PendingQuestion.waitInstant(until: .distantFuture) < .distantFuture,
            "a finite expiry saturated DispatchTime into .distantFuture — the accidental forever")
}

/// **A `Never` question must still be able to lapse, or `AppModel.prune` holds it
/// — and the row it draws — for the life of the app.** There is no clock to lapse
/// by, so settling is the only way out, and this is the assertion that fails if
/// `hasLapsed(at:)` grows a `nil`-expiry branch that answers "no" unconditionally.
///
/// A year out, not five seconds out, so no plausible wall-clock drift could be
/// what satisfies the first expectation.
@Test func aQuestionThatNeverHandsBackLapsesOnlyWhenItSettles() {
    let now = Date()
    let p = PendingQuestion(event: question(), deadline: nil, now: now)
    #expect(p.expiry == nil, "Never was stored as an instant rather than as no instant")
    #expect(!p.hasLapsed(at: now.addingTimeInterval(365 * 24 * 3600)),
            "a Never question lapsed by the clock, so the hook was let go while the notch still held its question")
    p.lapse()
    #expect(p.hasLapsed(at: now), "a settled Never question is unreclaimable — prune would keep it forever")
}

/// The wait itself, end to end: a `Never` question parks its waiter on
/// `.distantFuture` and is released by the answer alone. Distinct from
/// `anAnsweredQuestionHandsTheReplyBackToTheWaiter` at the top of this file, which
/// has a 5-second deadline that would also release the waiter on its own if the
/// gate signal went missing; here nothing but the signal can end the wait, so a
/// `park()`-shaped bug that failed to signal would hang this test rather than pass
/// it late.
@Test func aNeverQuestionIsReleasedByItsAnswerAndNothingElse() async throws {
    let p = PendingQuestion(event: question(), deadline: nil)
    let waiter = Task.detached { p.await() }
    try await Task.sleep(for: .milliseconds(20))
    #expect(p.resolve(Reply(id: "q1", choice: "allow")))
    #expect(await waiter.value?.choice == "allow")
}
