import Foundation
import Testing
import VibeCatCore
import VibeCatTransport
@testable import VibeCatUI

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func event(_ kind: Kind, session: String) -> VibeEvent {
    VibeEvent(id: "e-\(session)", cli: "claude-code", kind: kind,
              session: session, cwd: "/dev/\(session)")
}

/// Counts `onChange` firings. A reference type rather than a captured `var`,
/// matching HoverMonitorTests' `Fake` — a local `var` mutated from inside an
/// escaping closure and then read from outside it trips Swift 6's "mutated
/// after capture by sendable closure" diagnostic.
@MainActor private final class ChangeCounter {
    var count = 0
    func fire() { count += 1 }
}

@MainActor @Test func aFreshModelIsDormant() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    #expect(m.islandState == .dormant)
    #expect(m.sessionCount == 0)
}

@MainActor @Test func ingestingAnEventUpdatesTheIslandState() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    _ = m.ingest(event(.running, session: "a"), now: t0)
    #expect(m.islandState == .running)
    #expect(m.sessionCount == 1)

    _ = m.ingest(event(.permission, session: "b"), now: t0)
    #expect(m.islandState == .waiting)   // the worst state wins
    #expect(m.sessionCount == 2)
}

/// Plan 2 cannot answer anything yet, and nil is what makes the hook fall
/// through to the CLI's own prompt rather than hanging.
@MainActor @Test func everyEventIsAnsweredWithNoReplyForNow() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    #expect(m.ingest(event(.permission, session: "a"), now: t0) == nil)
    #expect(m.ingest(event(.question, session: "b"), now: t0) == nil)
}

@MainActor @Test func pruningDropsStaleFinishedSessionsOnly() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    _ = m.ingest(event(.done, session: "old"), now: t0)
    _ = m.ingest(event(.running, session: "busy"), now: t0)
    m.prune(now: t0.addingTimeInterval(AppModel.idleTTL + 1))
    #expect(m.sessionCount == 1)
    #expect(m.store.sessions.first?.id.session == "busy")
}

@MainActor @Test func theSameSessionUpdatesInPlace() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    _ = m.ingest(event(.running, session: "a"), now: t0)
    _ = m.ingest(event(.failed, session: "a"), now: t0.addingTimeInterval(1))
    #expect(m.sessionCount == 1)
    #expect(m.islandState == .failed)
}

/// `NotchController` re-renders off this callback rather than a
/// `withObservationTracking` bridge specifically because that bridge's
/// one-shot `onChange` can drop a second, closely-following mutation while
/// the re-arm is still in flight. This pins the behaviour it replaces.
@MainActor @Test func onChangeFiresOnEveryIngestIncludingTheSecond() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    let counter = ChangeCounter()
    m.onChange = { counter.fire() }

    _ = m.ingest(event(.running, session: "a"), now: t0)
    #expect(counter.count == 1)

    _ = m.ingest(event(.permission, session: "b"), now: t0)
    #expect(counter.count == 2)
}

@MainActor @Test func onChangeFiresOnPruneOnlyWhenSomethingWasActuallyRemoved() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    _ = m.ingest(event(.done, session: "old"), now: t0)
    _ = m.ingest(event(.running, session: "busy"), now: t0)

    let counter = ChangeCounter()
    m.onChange = { counter.fire() }

    // Neither session is stale yet — a no-op prune must not fire.
    m.prune(now: t0)
    #expect(counter.count == 0)

    // "old" is idle and past the TTL now; "busy" survives regardless of age.
    m.prune(now: t0.addingTimeInterval(AppModel.idleTTL + 1))
    #expect(counter.count == 1)
    #expect(m.sessionCount == 1)

    // Nothing left to remove — no further fire.
    m.prune(now: t0.addingTimeInterval(AppModel.idleTTL + 2))
    #expect(counter.count == 1)
}

// MARK: - Answering

@MainActor @Test func aQuestionEventParksUntilItIsAnswered() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let event = VibeEvent(id: "q1", cli: "claude-code", kind: .permission,
                          session: "s1", cwd: "/tmp/proj",
                          choices: [Choice(id: "allow", label: "Allow once")],
                          wantsReply: true, answerDeadline: 5)
    let ingest = Task.detached { m.ingest(event) }
    // The question must reach the UI without the socket thread being unblocked.
    try await Task.sleep(for: .milliseconds(50))
    #expect(m.pending?.id == "q1")
    m.answer(Reply(id: "q1", choice: "allow"))
    let reply = await ingest.value
    #expect(reply?.choice == "allow")
    #expect(m.pending == nil, "the drawer is still showing an answered question")
}

/// Fire-and-forget events must not park. This is the common case and any
/// delay in it is pure cost.
@MainActor @Test func anEventThatWantsNoReplyReturnsImmediately() {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let start = Date()
    let reply = m.ingest(VibeEvent(id: "e", cli: "claude-code", kind: .running, session: "s", cwd: "/tmp/proj"))
    #expect(reply == nil)
    #expect(Date().timeIntervalSince(start) < 0.1)
    #expect(m.pending == nil)
}

/// Every other `wantsReply` test above sets `answerDeadline` explicitly, so
/// none of them reach `ingest`'s `?? SocketClient.defaultAnswerDeadline`
/// fallback — the whole point of which, per its own comment, is to track the
/// hook's real deadline rather than a second constant that could drift from
/// it. Checks the computed `expiry` directly (`now` is threaded through
/// unchanged from `ingest` to `PendingQuestion.init`, so the arithmetic is
/// exact) rather than waiting out a real 20-second timeout to observe the
/// fallback indirectly.
@MainActor @Test func aMissingAnswerDeadlineFallsBackToTheSharedConstant() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let now = Date()
    let event = VibeEvent(id: "q1", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                          choices: [Choice(id: "allow", label: "Allow")], wantsReply: true)
    let ingest = Task.detached { m.ingest(event, now: now) }
    try await Task.sleep(for: .milliseconds(50))
    #expect(m.pending?.expiry == now.addingTimeInterval(SocketClient.defaultAnswerDeadline))
    m.answer(Reply(id: "q1", choice: "allow"))
    _ = await ingest.value
}

/// `wantsReply` alone is not enough: a question with nothing to click would
/// show an un-answerable drawer and then fail open anyway once its deadline
/// passed, having cost the person nothing but confusion in between. Distinct
/// from `anEventThatWantsNoReplyReturnsImmediately` above — this event *does*
/// want a reply, isolating the `choices` half of `ingest`'s guard from the
/// `wantsReply` half.
@MainActor @Test func aWantsReplyEventWithNoChoicesDoesNotPark() {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let start = Date()
    let reply = m.ingest(VibeEvent(id: "q1", cli: "claude-code", kind: .permission,
                                   session: "s", cwd: "/tmp/proj", wantsReply: true))
    #expect(reply == nil)
    #expect(Date().timeIntervalSince(start) < 0.1)
    #expect(m.pending == nil)
}

/// A second question while one is open replaces it, and the first fails open
/// rather than being left parked forever.
@MainActor @Test func asecondQuestionLapsesTheFirst() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    // `nonisolated`: a local function nested in a @MainActor test inherits
    // that isolation by default, but this one is called from inside
    // Task.detached below — a plain value-building helper with no actor
    // affinity of its own, so it must opt back out explicitly or the calls
    // at lines below become cross-actor and fail to compile without `await`.
    nonisolated func q(_ id: String) -> VibeEvent {
        VibeEvent(id: id, cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                  choices: [Choice(id: "allow", label: "Allow")],
                  wantsReply: true, answerDeadline: 5)
    }
    let first = Task.detached { m.ingest(q("q1")) }
    try await Task.sleep(for: .milliseconds(50))
    let start = Date()
    let second = Task.detached { m.ingest(q("q2")) }
    try await Task.sleep(for: .milliseconds(50))
    #expect(m.pending?.id == "q2")
    #expect(await first.value == nil, "the displaced question did not fail open")
    // Loose bound against the 5s deadline, not a fitted number: correct code
    // wakes `first` the moment `second` displaces it (well under 1s); a
    // missing `lapse()` only resolves `first` via its own 5s timeout, which
    // this bound is tight enough to catch and loose enough not to flake.
    #expect(Date().timeIntervalSince(start) < 1.0,
            "the first question was not woken by the displacement — it fell through to its own 5s deadline instead")
    m.answer(Reply(id: "q2", choice: "allow"))
    #expect(await second.value?.choice == "allow")
}

@MainActor @Test func dismissingAQuestionFailsOpen() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let event = VibeEvent(id: "q1", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                          choices: [Choice(id: "deny", label: "Deny")],
                          wantsReply: true, answerDeadline: 5)
    let ingest = Task.detached { m.ingest(event) }
    try await Task.sleep(for: .milliseconds(50))
    let start = Date()
    m.dismissQuestion()
    #expect(await ingest.value == nil)
    // Same loose-bound shape as asecondQuestionLapsesTheFirst: correct code
    // wakes the parked thread the moment dismissQuestion lapses it; a missing
    // lapse() only resolves it via the question's own 5s deadline.
    #expect(Date().timeIntervalSince(start) < 1.0,
            "dismissQuestion did not wake the parked thread promptly — it fell through to its own 5s deadline instead")
    #expect(m.pending == nil)
}

/// `PendingQuestion.resolve` already refuses a mismatched id on its own (Task
/// 1), but `answer`'s own guard is what stands between that refusal and
/// `clearQuestion()` — without it, a stray reply for some other id would
/// still fall through to clearing `pending`, hiding a live question from the
/// UI (and from any future correctly-addressed answer) while the socket
/// thread it belongs to stays parked on its own timeout.
@MainActor @Test func aMismatchedReplyLeavesTheRealQuestionParked() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let event = VibeEvent(id: "q1", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                          choices: [Choice(id: "allow", label: "Allow")],
                          wantsReply: true, answerDeadline: 5)
    let ingest = Task.detached { m.ingest(event) }
    try await Task.sleep(for: .milliseconds(50))

    m.answer(Reply(id: "not-q1", choice: "allow"))
    #expect(m.pending?.id == "q1", "a mismatched reply must not clear the real question")

    m.answer(Reply(id: "q1", choice: "allow"))
    #expect(await ingest.value?.choice == "allow")
}

/// The obvious mutation for this property — swapping the async main-actor hop
/// for a synchronous one — hangs the test process instead of failing it
/// (swift-testing has no sub-minute time limit to catch that), so this proves
/// the hop is load-bearing the safe way: the question must be visible on the
/// main actor *while the socket thread is still parked*, which a synchronous
/// hop could not satisfy without deadlocking right here.
@MainActor @Test func theQuestionIsVisibleBeforeTheSocketThreadIsReleased() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let event = VibeEvent(id: "q1", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                          choices: [Choice(id: "allow", label: "Allow")],
                          wantsReply: true, answerDeadline: 5)
    let ingest = Task.detached { m.ingest(event) }
    try await Task.sleep(for: .milliseconds(50))
    #expect(m.pending != nil, "the question never reached the main actor")
    #expect(ingest.isCancelled == false)
    // Still parked: nothing has answered it, so ingest has not returned.
    m.answer(Reply(id: "q1", choice: "allow"))
    // Checked against the actual choice just sent, not merely non-nil: a
    // broken `ingest` that skipped `.await()` entirely and returned some
    // canned reply immediately (never truly parking at all) would still
    // satisfy `!= nil` and would still leave `m.pending` non-nil 50ms in
    // (the fire-and-forget `present` above does not depend on `.await()`
    // being reached) — confirmed by deleting the `return question.await()`
    // line and hard-coding a distinct canned choice in its place: this
    // exact test kept passing until the value was checked for content.
    #expect(await ingest.value?.choice == "allow")
}
