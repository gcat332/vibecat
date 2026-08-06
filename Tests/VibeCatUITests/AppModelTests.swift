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

/// Whole-branch review minor: this test's name and comment were Plan-2
/// stale ("Plan 2 cannot answer anything yet") — Task 3 gave `AppModel` a
/// real answering path below, so that is no longer true. What this actually
/// proves, and still does: `kind` alone never implies parking, only
/// `wantsReply` does. `event(_:session:)` never sets `wantsReply` or
/// `choices`, so even a `.permission`/`.question`-kind event — the two kinds
/// a real question arrives as — must return nil immediately here, the same
/// as an ordinary fire-and-forget event, rather than parking on `kind` alone.
@MainActor @Test func aPermissionOrQuestionKindWithoutWantsReplySetStillReturnsNilImmediately() {
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

/// Whole-branch review minor: `event.answerDeadline` is decoded off the wire
/// and used as-is otherwise — only reachable from a non-hook client speaking
/// the wire protocol directly on the 0600 socket (`HookRunner` always sends
/// its own already-clamped `client.answerDeadline`), so this is hardening
/// rather than a reachable production path, but `ingest` has no way to tell
/// the two apart. An absurd value near `Int64.max` nanoseconds (~1e12
/// seconds) would make `DispatchTime.now() + …` inside `PendingQuestion
/// .await()` saturate to `.distantFuture`, parking that thread permanently
/// — exactly what §2.3's fail-open guarantee forbids. Checks the computed
/// `expiry` directly, the same shape as `aMissingAnswerDeadlineFallsBack
/// ToTheSharedConstant` just above, rather than actually waiting out
/// anything near that deadline.
@MainActor @Test func anAbsurdAnswerDeadlineIsClampedRatherThanTrustedVerbatim() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let now = Date()
    let event = VibeEvent(id: "q1", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                          choices: [Choice(id: "allow", label: "Allow")],
                          wantsReply: true, answerDeadline: 1e12)
    let ingest = Task.detached { m.ingest(event, now: now) }
    try await Task.sleep(for: .milliseconds(50))
    let expiry = try #require(m.pending?.expiry)
    #expect(expiry <= now.addingTimeInterval(SocketClient.ceilingDeadline),
            "an answerDeadline of 1e12s reached PendingQuestion.expiry \(expiry.timeIntervalSince(now))s out — unclamped, DispatchTime arithmetic on this would saturate to distantFuture and park the thread forever")
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

// MARK: - several questions at once (Plan 9 Task 2)

private nonisolated func questionEvent(_ id: String, session: String,
                                       deadline: TimeInterval = 5) -> VibeEvent {
    VibeEvent(id: id, cli: "claude-code", kind: .permission, session: session, cwd: "/tmp/\(session)",
              choices: [Choice(id: "allow", label: "Allow")],
              wantsReply: true, answerDeadline: deadline)
}

/// **The defect this task removes.** Before Plan 9, `present(_:)` lapsed whatever
/// question was open when a new one arrived — correct with one slot, because a
/// displaced question's socket thread would otherwise block with nothing able to
/// wake it. But with two *different* agents asking at once it meant the first was
/// fail-opened without ever being seen: its terminal re-prompted and the island
/// never showed the question at all.
///
/// The wall-clock bound is the half that matters. `first.value == nil` alone is
/// satisfied by the old behaviour too — lapsing returns nil immediately. What
/// separates park from lapse is that a parked question's waiter is *still
/// waiting*, so it must not have returned at all yet.
@MainActor @Test func twoAgentsAskingAtOnceBothKeepTheirQuestions() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let first = Task.detached { m.ingest(questionEvent("q1", session: "alpha")) }
    try await Task.sleep(for: .milliseconds(50))
    let second = Task.detached { m.ingest(questionEvent("q2", session: "beta")) }
    try await Task.sleep(for: .milliseconds(50))

    #expect(m.questions.count == 2, "one of the two questions was discarded")
    #expect(m.pending?.id == "q2", "the newest question is the one the drawer shows")
    #expect(m.questions.first { $0.id == "q1" }?.isParked == true,
            "the displaced question was not parked")

    // Nothing has been answered, so neither hook may have been released. This is
    // the assertion that fails if `present` still lapses the displaced question.
    m.answer(Reply(id: "q2", choice: "allow"))
    #expect(await second.value?.choice == "allow")

    // **The whole point: the parked question is answered in place**, from the
    // block under its row, with no gesture that brings it back to the drawer
    // first. `pending` stays nil throughout — answering a parked question must
    // not disturb what the drawer is showing.
    #expect(m.pending == nil)
    m.answer(Reply(id: "q1", choice: "allow"))
    #expect(await first.value?.choice == "allow",
            "a parked question could not be answered where it sits")
    #expect(m.pending == nil, "answering a parked question changed the drawer")
    #expect(m.questions.isEmpty)
}

/// Parking empties the drawer without losing the question. `pending == nil` is
/// what reaches `NotchController.setQuestion(nil)` and sends the drawer to the
/// session list; `questions` is what the list draws from.
@MainActor @Test func parkingTheOnlyQuestionEmptiesTheDrawerAndKeepsTheQuestion() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let waiter = Task.detached { m.ingest(questionEvent("q1", session: "alpha")) }
    try await Task.sleep(for: .milliseconds(50))
    #expect(m.pending?.id == "q1")

    m.parkQuestion()
    #expect(m.pending == nil, "a parked question still owns the drawer")
    #expect(m.questions.count == 1, "parking discarded the question")
    #expect(m.questions[0].isParked)

    m.answer(Reply(id: "q1", choice: "allow"))
    #expect(await waiter.value?.choice == "allow")
    #expect(m.questions.isEmpty)
}

/// **No auto-promotion, deliberately.** Answering the frontmost question leaves
/// the drawer empty rather than pulling the next parked question forward. Two
/// reasons: a drawer that swapped in a new question under the cursor invites
/// answering the wrong one by reflex, and choosing among several is exactly what
/// the session list exists for.
@MainActor @Test func answeringOneQuestionDoesNotPullAParkedOneForward() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let first = Task.detached { m.ingest(questionEvent("q1", session: "alpha")) }
    try await Task.sleep(for: .milliseconds(50))
    let second = Task.detached { m.ingest(questionEvent("q2", session: "beta")) }
    try await Task.sleep(for: .milliseconds(50))

    m.answer(Reply(id: "q2", choice: "allow"))
    #expect(await second.value?.choice == "allow")
    #expect(m.pending == nil, "answering promoted a parked question into the drawer")
    #expect(m.questions.map(\.id) == ["q1"], "the answered question stayed in the list")

    m.answer(Reply(id: "q1", choice: "allow"))
    _ = await first.value
}

/// **Rewritten by ruling C, and the old version asserted what Task 2 shipped.**
///
/// It was `pruneDropsAParkedQuestionWhoseHookHasAlreadyGivenUp`, and its reasoning was
/// sound at the time: `NotchController.setQuestion(nil)` cancels `lapseCheck`, so a
/// parked question has nothing watching its expiry, and a question nobody is listening
/// to should not sit in the list offering an answer.
///
/// What changed is that the list gained something useful to say about it. The
/// handed-back block draws the *command* — what someone needs to read before walking to
/// a terminal to approve it — so the question stays, and `prune` is where a question
/// whose wait is genuinely over gets cleared instead. That rule is
/// `aHandedBackQuestionGoesOnceItsSessionStopsWaiting` below.
///
/// What this still pins is the half that did not change: `prune` is the only thing
/// watching a parked question at all, so it must not leave one live forever either.
@MainActor @Test func pruneIsWhatWatchesAParkedQuestionSinceNothingElseDoes() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let waiter = Task.detached { m.ingest(questionEvent("q1", session: "alpha", deadline: 0.05)) }
    try await Task.sleep(for: .milliseconds(20))
    m.parkQuestion()
    #expect(m.questions.count == 1)

    _ = await waiter.value                            // the hook times out on its own
    m.prune(now: Date().addingTimeInterval(1))
    // Kept, because the session is still `.waiting` — the terminal has it now, and the
    // row says so. Dropped only once that stops being true.
    #expect(m.questions.count == 1, "a handed-back question was discarded before its wait ended")
    #expect(m.questions[0].hasLapsed(at: Date()))

    _ = m.ingest(event(.running, session: "alpha"))
    m.prune(now: Date().addingTimeInterval(2))
    #expect(m.questions.isEmpty, "prune never cleared a question whose wait was over")
}

/// `prune` runs every 60 seconds whether or not anything is stale, and
/// `@Observable` notifies on the write rather than on the change — so an
/// unconditional notify here costs a re-render every minute on an idle machine.
/// The existing `store != before` guard is the pattern; questions need their own.
@MainActor @Test func aPruneThatDropsNoQuestionDoesNotNotify() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let counter = ChangeCounter()
    let waiter = Task.detached { m.ingest(questionEvent("q1", session: "alpha", deadline: 60)) }
    try await Task.sleep(for: .milliseconds(50))
    m.parkQuestion()
    m.onChange = { counter.fire() }

    m.prune(now: t0)                              // nothing stale: the question has 60s left
    #expect(counter.count == 0, "a prune that removed nothing still notified")
    #expect(m.questions.count == 1)

    m.answer(Reply(id: "q1", choice: "allow"))
    _ = await waiter.value
}

/// The invariant that keeps `pending` and `questions` from disagreeing: every
/// question the model holds is either the one in the drawer or parked. A third
/// state — held, not shown, not parked — would be invisible to the list and to
/// the drawer both, which is a question nobody can answer.
@MainActor @Test func everyHeldQuestionIsEitherTheFrontmostOrParked() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let a = Task.detached { m.ingest(questionEvent("q1", session: "alpha")) }
    try await Task.sleep(for: .milliseconds(50))
    let b = Task.detached { m.ingest(questionEvent("q2", session: "beta")) }
    try await Task.sleep(for: .milliseconds(50))
    let c = Task.detached { m.ingest(questionEvent("q3", session: "gamma")) }
    try await Task.sleep(for: .milliseconds(50))

    for q in m.questions {
        #expect(q.isParked == (q !== m.pending),
                "\(q.id) is neither frontmost nor parked")
    }

    for id in ["q1", "q2", "q3"] {
        m.answer(Reply(id: id, choice: "allow"))
    }
    _ = await (a.value, b.value, c.value)
}

/// **Rewritten 2026-08-06, and the old version asserted a defect.**
///
/// This was `asecondQuestionLapsesTheFirst`: two `wantsReply` events from session
/// `"s"`, asserting the first fails open. That was right when `AppModel` had one
/// question slot — a displaced question's socket thread would otherwise block with
/// nothing able to wake it — and it stayed right through Plan 9 Task 2's first
/// draft, which kept one slot *per session* on the reasoning that a session can
/// only be blocked on one tool call at a time.
///
/// **That reasoning is false.** Claude Code issues independent tool calls in
/// parallel and `PreToolUse` fires per call, so several hooks from one session
/// block concurrently; subagents share the parent's `session_id` as well. An agent
/// asking for three permissions at once had two of them silently fail open —
/// appearing in the terminal while the island showed only the third.
///
/// So the behaviour under test is now the opposite: **both survive, and a person
/// answers them in whichever order they like.** The old assertion is kept in
/// spirit one test down, where it belongs: a retry of the *same* `event.id`.
@MainActor @Test func twoQuestionsFromOneSessionBothSurviveAndAreAnsweredInAnyOrder() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let first = Task.detached { m.ingest(questionEvent("q1", session: "s")) }
    try await Task.sleep(for: .milliseconds(50))
    let second = Task.detached { m.ingest(questionEvent("q2", session: "s")) }
    try await Task.sleep(for: .milliseconds(50))

    #expect(m.questions.count == 2, "a parallel tool call's question was discarded")
    #expect(m.pending?.id == "q2")
    #expect(m.questions.first { $0.id == "q1" }?.isParked == true)

    // Deliberately out of arrival order: nothing forces A before B.
    m.answer(Reply(id: "q1", choice: "allow"))
    #expect(await first.value?.choice == "allow")
    #expect(m.pending?.id == "q2", "answering a parked question disturbed the drawer")

    m.answer(Reply(id: "q2", choice: "deny"))
    #expect(await second.value?.choice == "deny")
    #expect(m.questions.isEmpty)
}

/// **The one case that still replaces — and it is unreachable from a real hook.**
/// `ClaudeCodeAdapter` sets `id: UUID().uuidString` per invocation, so no hook
/// sends the same question id twice. What this defends is `answer(_:)`, which
/// finds its question by id: two questions sharing one would make that lookup
/// pick arbitrarily and leave the other's thread waiting for a reply that can
/// never reach it. The socket is `0600` and reachable by anything running as this
/// user, so "no hook does this" is not the same as "nothing does this".
///
/// The earlier instance is lapsed rather than parked because parking it would
/// leave a block in the list offering an answer to a connection nothing can route
/// to.
///
/// The wall-clock bound is what separates lapse from park: a lapsed waiter returns
/// the moment it is displaced, a parked one only via its own 5s deadline.
@MainActor @Test func aRetryOfTheSameQuestionIdReplacesAndReleasesTheEarlierOne() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let first = Task.detached { m.ingest(questionEvent("q1", session: "s")) }
    try await Task.sleep(for: .milliseconds(50))
    let start = Date()
    let second = Task.detached { m.ingest(questionEvent("q1", session: "s")) }
    try await Task.sleep(for: .milliseconds(50))

    #expect(m.questions.count == 1, "a retried question was held twice")
    #expect(await first.value == nil, "the replaced instance did not fail open")
    #expect(Date().timeIntervalSince(start) < 1.0,
            "the replaced instance was parked, not lapsed — it fell through to its own 5s deadline")

    m.answer(Reply(id: "q1", choice: "allow"))
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

// MARK: - the hand-back (Plan 9 Task 5, ruling C)

/// **Ruling C reverses what Task 2 shipped, and this is the assertion that pins the
/// reversal.** Task 2's `prune` dropped any question whose hook had given up. But the
/// handed-back block draws that question's *command* — the thing someone needs to read
/// before walking to a terminal to approve it — so dropping it leaves nothing to draw.
///
/// A question the hook has abandoned therefore stays, and `hasLapsed(at:)` is what
/// distinguishes the block's two states. No new flag on `PendingQuestion`: settled
/// already means "the terminal has this now".
@MainActor @Test func aHandedBackQuestionStaysInTheListSoItsCommandCanStillBeRead() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let waiter = Task.detached { m.ingest(questionEvent("q1", session: "alpha", deadline: 0.05)) }
    _ = await waiter.value                            // let the hook time out
    m.handBackQuestion()

    #expect(m.questions.count == 1, "the handed-back question was discarded")
    #expect(m.questions[0].hasLapsed(at: Date()), "it should read as handed back, not answerable")
    #expect(m.pending == nil, "a handed-back question still owns the drawer")

    // And a prune does not undo it, which is the exact behaviour Task 2 had.
    m.prune(now: Date().addingTimeInterval(1))
    #expect(m.questions.count == 1, "prune dropped a handed-back question")
}

/// It does not stay forever. The session is still `.waiting` while the terminal holds
/// the question; answering there runs the tool, `PostToolUse` fires, and the session
/// leaves `.waiting` — which is the signal that the block has nothing left to say.
@MainActor @Test func aHandedBackQuestionGoesOnceItsSessionStopsWaiting() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let waiter = Task.detached { m.ingest(questionEvent("q1", session: "alpha", deadline: 0.05)) }
    _ = await waiter.value
    m.handBackQuestion()
    m.prune(now: Date())
    #expect(m.questions.count == 1, "setup: it should still be here while the session waits")

    // The agent proceeding — the person answered in the terminal.
    _ = m.ingest(event(.running, session: "alpha"))
    m.prune(now: Date())
    #expect(m.questions.isEmpty, "the handed-back question outlived the wait it described")
}

/// **The safety half of that rule, and the reason it is not simply "drop questions
/// whose session is not waiting".** A *live* question — one whose hook is still
/// blocked — must be kept whatever the store says, because the store's state comes
/// from whatever event arrived last and a session can be reported `.running` while one
/// of its parallel tool calls is still blocked on a permission. Dropping that question
/// would strand its hook with nothing able to answer it.
@MainActor @Test func pruneKeepsALiveQuestionEvenWhenItsSessionIsNotWaiting() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    let waiter = Task.detached { m.ingest(questionEvent("q1", session: "alpha", deadline: 30)) }
    try await Task.sleep(for: .milliseconds(50))
    // A second, later event puts the session into `.running` while the question's hook
    // is still parked — exactly the parallel-tool-call case.
    _ = m.ingest(event(.running, session: "alpha"))
    #expect(m.store.sessions.first?.state == .running, "setup: the session must not be waiting")

    m.prune(now: Date())
    #expect(m.questions.count == 1, "a live question was dropped because its session had moved on")

    m.answer(Reply(id: "q1", choice: "allow"))
    #expect(await waiter.value?.choice == "allow")
}
