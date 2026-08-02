# The Drawer and Answering — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Click the island, see the question your agent is asking, answer it there, and have the agent act on that answer.

**Architecture:** The hook side is already finished — `HookRunner` handles `wantsReply`, calls `sendExpectingReply`, checks the reply id, and formats claude-code's `permissionDecision`. What is missing is entirely on the app side. `SocketServer` already invokes its handler on a fresh thread per connection, so that thread is where a question waits: `AppModel.ingest` parks it, the UI resolves it, and the handler returns a real `Reply` instead of today's `nil`. The drawer is a second face of the same `NSPanel`, which grows to hold it and takes mouse events only while there is something to click.

**Tech Stack:** Swift 6.3 strict concurrency · SwiftUI · AppKit `NSPanel` · swift-testing · `DispatchSemaphore` for the cross-thread park · `ImageRenderer` for visual assertions

---

## Global Constraints

- **swift-testing only.** `@Test`, `#expect`, `#require`. Never XCTest.
- **Fail-open is the single most important property in the design (§2.3).** Every new failure path returns the CLI's own default. A question that is never answered, an app that crashes mid-question, a reply for the wrong id — all end with the hook printing nothing and exiting 0.
- **The cutout is a hole (§5.1).** The drawer hangs *below* the notch line. Nothing may be drawn inside the cutout's columns at any tier.
- **The left edge is fixed (§5.3).** Opening the drawer must not move it.
- **Colour means state, and only state (§4.3).** The drawer's accent is the island's accent. No new hues; a recommended answer is *tinted, not filled* (§10.1).
- **`isFloatingPanel` clobbers `level`.** Any new panel configuration keeps `level = .statusBar` assigned *after* it. Pinned by `theLevelIsStatusBar`.
- **Motion:** drawer height spring `0.42/0.78` (§9.1). It has had nothing to animate until now.
- **On this toolchain (swift-testing 1902)** a bare `!` wrapped directly around `.contains(_:)` mis-evaluates when the receiver holds optionals. Use `== false`.
- **Never `ps %cpu`** for any CPU claim. `getrusage(RUSAGE_SELF)`, or two `ps -o time=` samples ≥30s apart.
- **Assert on rendered pixels where the claim is visual.** `Raster`/`rasterise` in `Tests/VibeCatUITests/Raster.swift` render headlessly; `ContactSheet.swift` shows how to dump a PNG to look at. A read-counter is the fallback, not the first move.

---

## Two decisions this plan makes, and why

Both are places the spec does not reach, and both change what gets built. Read them before Task 1.

### The answer deadline is not 300ms

§2.3 fixes the hook's deadline at 300ms and calls fail-open the most important safety property in the design. A human cannot answer a permission prompt in 300ms, so taken literally, answering can never work.

The resolution is that **300ms is the right bound for delivery and the wrong bound for an answer**, and they are different events:

- A fire-and-forget event (`idle`, `running`, `done`, `failed`) buys the terminal nothing by waiting. Any delay there is pure cost, and 300ms stands.
- A `wantsReply` event is one where **the CLI would otherwise block on its own prompt indefinitely.** A bounded wait is not a regression against that — it is strictly better. The terminal is not being hung by VibeCat; it is waiting for the person, which is what it was going to do anyway, with a ceiling it did not previously have.

So `wantsReply` gets its own longer deadline, defaulting to **20 seconds**, still bounded, still failing open. `SocketClient.ceilingDeadline` is already 60s and is not raised.

**The consequence that must be handled:** once the hook gives up, the CLI prints its own prompt. If the island is still showing the question, the person can answer a question nobody is listening to — and worse, answer it *differently* from the terminal prompt now in front of them. The pending question therefore carries its own expiry, mirroring the hook's, and the drawer closes itself when it lapses. Task 1 owns this; `aLapsedQuestionStopsBeingAnswerable` is the test.

### The panel takes mouse events only when there is something to open

Plan 3 sized the panel to the widest collapsed island and left it there, which is safe *only* because the island is click-through — an oversized transparent window intercepts nothing. `IslandGeometry.maxCollapsedFrames()` says so in a comment. The drawer breaks that: it must be clicked.

Rather than make the island permanently clickable, `ignoresMouseEvents` is false exactly when **the pointer is over the island and there is something a click would do**. Hover is already cursor-polled at 30Hz by `HoverMonitor`, so both facts are known. Everywhere else, and at every other moment, the menu bar underneath stays clickable.

This also keeps a promise Plan 2 could not check: click-through is still unverified on hardware (`NSWindow.windowNumber(at:)` cannot test it from another process — it returns 0 for windows outside the caller, so even a control point reads 0). Task 4 is the first task that can confirm it, because it is the first task where a click is supposed to land somewhere.

---

## Deliberately out of scope

Each is named so a later plan does not rediscover it as a bug:

| Not here | Where | Why |
|---|---|---|
| The session list (§11) | Plan 5 | The drawer has one face in this plan: the question. |
| The panel footer's mute and settings controls (§6.4) | Plan 6 | Both are settings-domain; a button that opens nothing is worse than no button. The drawer leaves the footer's 44pt unclaimed so Plan 6 slots into it without a relayout. |
| Sound cues (§12) | Plan 6 | A question that arrives silently is still answerable. |
| Jump to terminal (§13) | Plan 6 | |
| Adapters other than claude-code (§3) | Later | `HookRunner.stdout(for:reply:)` already switches on `cli` and returns nil for the rest. |
| `IslandBody.phase` bypassing `MotionPreference` | Plan 6, **inside it** | Recorded in the cat-and-motion follow-ups: with motion `off` the cat freezes at a random cycle point, ~8% of the time mid-blink. Inert until Plan 6 ships the control. |

---

## File Structure

**Create**

| File | Responsibility |
|---|---|
| `Sources/VibeCatUI/PendingQuestion.swift` | One unanswered question: its event, its deadline, and the one-shot channel the socket thread parks on. Knows nothing about SwiftUI. |
| `Sources/VibeCatUI/QuestionModel.swift` | What the drawer shows and what the person has selected so far. `@Observable`. Single/multi/text selection state and whether Send is allowed. |
| `Sources/VibeCatUI/Drawer/DrawerView.swift` | The drawer's frame: ground, corner treatment, footer reservation. Face-agnostic so Plan 5 adds a second face beside the first. |
| `Sources/VibeCatUI/Drawer/QuestionFace.swift` | Title, body, and the rows. |
| `Sources/VibeCatUI/Drawer/ChoiceRow.swift` | One answer: number badge or checkbox, label, recommended tint. |
| `Sources/VibeCatUI/Drawer/DestructiveGuard.swift` | The `rm -rf` / `git push --force` / `drop table` match, and the second ask. Pure, testable, no UI. |
| `Tests/VibeCatUITests/PendingQuestionTests.swift` | |
| `Tests/VibeCatUITests/QuestionModelTests.swift` | |
| `Tests/VibeCatUITests/Drawer/DrawerGeometryTests.swift` | |
| `Tests/VibeCatUITests/Drawer/DestructiveGuardTests.swift` | |
| `Tests/VibeCatUITests/Drawer/DrawerGoldenTests.swift` | Rendered assertions, using `Raster`. |

**Modify**

| File | Change |
|---|---|
| `Sources/VibeCatUI/AppModel.swift` | `ingest` parks `wantsReply` events instead of returning nil; `resolve`/`lapse` complete them. |
| `Sources/VibeCatUI/IslandGeometry.swift` | §6.3 drawer heights; `frames(tier:)` already takes `.drawer(height:)`. |
| `Sources/VibeCatUI/NotchPanel.swift` | `ignoresMouseEvents` driven by "pointer over it and something to open". |
| `Sources/VibeCatUI/NotchController.swift` | Panel resizes for the drawer; click opens it. |
| `Sources/VibeCatUI/IslandModel.swift` | Holds the `QuestionModel` and the open tier. |
| `Sources/VibeCatUI/IslandView.swift` | Renders the drawer below the collapsed body. |
| `Sources/VibeCatTransport/SocketClient.swift` | A second, longer deadline for `wantsReply`. |
| `Sources/VibeCatHookKit/HookRunner.swift` | Uses it. |

---

## Task 1: PendingQuestion — parking the socket thread

**Files:**
- Create: `Sources/VibeCatUI/PendingQuestion.swift`
- Test: `Tests/VibeCatUITests/PendingQuestionTests.swift`

**Interfaces:**
- Consumes: `VibeEvent`, `Reply` from `VibeCatCore`.
- Produces: `PendingQuestion(event:deadline:)`, `.await() -> Reply?`, `.resolve(_ reply: Reply) -> Bool`, `.lapse()`, `.hasLapsed(at:) -> Bool`, `.id`. Task 2 and Task 5 both use these names.

This is the whole mechanism, and it is deliberately not `async`. `SocketServer` calls its handler on a fresh thread per connection and takes a synchronous `Reply?` back; that thread has nothing else to do, so parking it is correct and costs one blocked thread per outstanding question.

- [ ] **Step 1: Write the failing tests**

```swift
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
    let waiter = Task.detached { p.await() }
    // Resolve from another thread, as the UI will.
    try await Task.sleep(for: .milliseconds(20))
    #expect(p.resolve(Reply(id: "q1", choice: "allow")))
    let reply = await waiter.value
    #expect(reply?.choice == "allow")
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
    let waiter = Task.detached { p.await() }
    try await Task.sleep(for: .milliseconds(20))
    #expect(p.resolve(Reply(id: "q1", choice: "allow")))
    #expect(p.resolve(Reply(id: "q1", choice: "deny")) == false)
    #expect(await waiter.value?.choice == "allow")
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter PendingQuestion`
Expected: FAIL — `cannot find 'PendingQuestion' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation
import VibeCatCore

/// One question the island is showing and a socket thread is waiting on.
///
/// Not `async`, on purpose. `SocketServer` invokes its handler on a fresh
/// thread per connection and takes a synchronous `Reply?` back, so that thread
/// is exactly the right place to wait: it has nothing else to do, and parking
/// it costs one blocked thread per outstanding question. Bridging to
/// `async`/`await` here would mean the handler returning before the answer
/// existed, which the socket's request/response shape cannot express.
public final class PendingQuestion: @unchecked Sendable {
    public let id: String
    public let event: VibeEvent
    /// When the *hook* gives up. Mirrored here so the island can close a
    /// question that nobody is listening to any more.
    public let expiry: Date

    private let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var reply: Reply?
    private var settled = false

    public init(event: VibeEvent, deadline: TimeInterval, now: Date = Date()) {
        self.id = event.id
        self.event = event
        self.expiry = now.addingTimeInterval(deadline)
    }

    /// Blocks the calling thread until answered or expired. `nil` means fail
    /// open: the hook prints nothing and the CLI falls back to its own prompt.
    public func await() -> Reply? {
        _ = gate.wait(timeout: .now() + max(0, expiry.timeIntervalSinceNow))
        lock.lock()
        defer { lock.unlock() }
        // Settle even on the timeout path, so a late answer cannot be sent
        // down a connection the hook has already abandoned.
        settled = true
        return reply
    }

    /// Returns false if this reply is for another question or the question has
    /// already settled. Both are fail-open: nothing is sent.
    @discardableResult
    public func resolve(_ reply: Reply) -> Bool {
        lock.lock()
        guard reply.id == id, !settled else { lock.unlock(); return false }
        self.reply = reply
        settled = true
        lock.unlock()
        gate.signal()
        return true
    }

    /// Settle with no answer — the person dismissed it, or it aged out of the
    /// UI before the socket thread noticed.
    public func lapse() {
        lock.lock()
        guard !settled else { lock.unlock(); return }
        settled = true
        lock.unlock()
        gate.signal()
    }

    public func hasLapsed(at instant: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return settled || instant >= expiry
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter PendingQuestion`
Expected: PASS, 5 tests.

- [ ] **Step 5: Prove the lapse guard is load-bearing**

Delete `settled = true` from `await()`, re-run. Expected: `aLapsedQuestionStopsBeingAnswerable` FAILS — without it, a timed-out question stays answerable and a late answer is written to a dead connection. Restore it.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/PendingQuestion.swift Tests/VibeCatUITests/PendingQuestionTests.swift
git commit -m "feat: park a socket thread on an unanswered question"
```

---

## Task 2: The answer deadline

**Files:**
- Modify: `Sources/VibeCatTransport/SocketClient.swift`
- Modify: `Sources/VibeCatHookKit/HookRunner.swift`
- Test: `Tests/VibeCatTransportTests/SocketClientTests.swift`, `Tests/VibeCatTransportTests/HookRunnerTests.swift`

**Interfaces:**
- Produces: `SocketClient.init(path:deadline:answerDeadline:)`, `SocketClient.answerDeadline`. `HookRunner` passes `answerDeadline` to `sendExpectingReply`.

Read "The answer deadline is not 300ms" above before starting. The 300ms delivery deadline does not change.

- [ ] **Step 1: Write the failing tests**

```swift
/// §2.3's 300ms is the right bound for delivery and the wrong one for a human
/// answer. They are separate deadlines because they bound separate things.
@Test func theAnswerDeadlineIsSeparateFromTheDeliveryDeadline() {
    let c = SocketClient(path: "/tmp/x.sock")
    #expect(c.deadline == 0.3)
    #expect(c.answerDeadline == 20)
    #expect(c.answerDeadline > c.deadline)
}

/// Bounded, still. A hook that waits forever is a hook that hangs a terminal,
/// which is the one thing §2.3 forbids outright.
@Test func theAnswerDeadlineIsClampedLikeTheOther() {
    #expect(SocketClient(path: "/tmp/x.sock", answerDeadline: 9999).answerDeadline
            == SocketClient.ceilingDeadline)
    #expect(SocketClient(path: "/tmp/x.sock", answerDeadline: -1).answerDeadline
            == SocketClient.floorDeadline)
}

/// The mechanism, not just the constant: a server that never answers must
/// return nil after roughly the answer deadline, not after the 300ms one.
@Test func waitingForAnAnswerOutlastsTheDeliveryDeadline() throws {
    let path = "/tmp/vibecat-answer-\(UUID().uuidString).sock"
    let server = SocketServer(path: path)
    // Accept, then never reply.
    try server.start { _ in Thread.sleep(forTimeInterval: 1.0); return nil }
    defer { server.stop() }

    let c = SocketClient(path: path, deadline: 0.3, answerDeadline: 0.8)
    let line = try WireCodec.encode(VibeEvent(id: "q", cli: "claude-code",
                                              kind: .permission, session: "s", cwd: "/tmp/proj",
                                              wantsReply: true))
    let start = Date()
    let out = c.sendExpectingReply(line, deadline: c.answerDeadline)
    let elapsed = Date().timeIntervalSince(start)
    #expect(out == nil, "no reply came, so this must fail open")
    #expect(elapsed > 0.5, "gave up after \(elapsed)s — it used the 300ms delivery deadline, not the answer deadline")
    #expect(elapsed < 2.0, "waited \(elapsed)s — the answer deadline is not bounding it")
}
```

- [ ] **Step 2: Run and watch them fail**

Run: `swift test --filter "AnswerDeadline|waitingForAnAnswer"`
Expected: FAIL — no `answerDeadline` member.

- [ ] **Step 3: Implement**

In `SocketClient`, add the stored property and make the reply path take an explicit deadline:

```swift
    public let deadline: TimeInterval
    /// The bound on a *human* answer, not on delivery. §2.3 fixes delivery at
    /// 300ms and calls fail-open the most important property in the design; a
    /// person cannot answer a permission prompt in 300ms, so taken literally
    /// answering could never work.
    ///
    /// These bound different things. Waiting buys a fire-and-forget event
    /// nothing, so 300ms stands there. A `wantsReply` event is one where the
    /// CLI would *otherwise block on its own prompt indefinitely* — a bounded
    /// wait is not a regression against that, it is a ceiling that did not
    /// previously exist. Clamped by the same floor and ceiling, so a hook
    /// still cannot be made to wait forever.
    public let answerDeadline: TimeInterval

    public init(path: String, deadline: TimeInterval = 0.3,
                answerDeadline: TimeInterval = 20) {
        self.path = path
        self.deadline = Swift.min(Self.ceilingDeadline,
                                  Swift.max(Self.floorDeadline, deadline))
        self.answerDeadline = Swift.min(Self.ceilingDeadline,
                                        Swift.max(Self.floorDeadline, answerDeadline))
    }

    public func sendExpectingReply(_ line: Data,
                                   deadline: TimeInterval? = nil) -> Data? {
        // Delivery keeps the short deadline even when the answer gets a long
        // one: a socket that will not accept bytes is dead, and waiting 20s to
        // learn that is 20s of hung terminal for nothing.
        let writeExpiry = Date().addingTimeInterval(self.deadline)
        let readExpiry = Date().addingTimeInterval(deadline ?? self.deadline)
        guard let fd = connectSocket() else { return nil }
        defer { close(fd) }
        guard writeAll(fd, line, expiry: writeExpiry) else { return nil }
        return readLine(fd, expiry: readExpiry)
    }
```

In `HookRunner.run`, the one call site:

```swift
        guard let data = client.sendExpectingReply(line, deadline: client.answerDeadline),
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter VibeCatTransportTests`
Expected: PASS. Every existing `SocketClient` test still passes — the new parameter is defaulted.

- [ ] **Step 5: Prove the split is load-bearing**

**The snippet above is not sufficient on its own, and this step is how that was
found.** `SO_RCVTIMEO` is set once in `connectSocket`, from `deadline`, and
nothing above changes that — so the read still times out at 300ms whatever the
wall clock says, and Step 4 fails at ~0.302s. The read deadline has to be
threaded into `connectSocket`/`setTimeout` as well.

Once it is: the mutation that reproduces the ~0.3s failure is reverting *that*
threading, not the wall-clock line. Confirmed both ways during implementation
(commit `b6de1f5`).

Also missing from the snippet: `SocketClientTests.swift` needs
`import VibeCatCore`.

And one interface line in this task had no test behind it — "HookRunner passes
`answerDeadline` to `sendExpectingReply`" could be reverted with all 265 tests
still green. `aReplySlowerThanDeliveryButWithinTheAnswerDeadlineIsStillHonoured`
now covers it.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatTransport/SocketClient.swift Sources/VibeCatHookKit/HookRunner.swift Tests/VibeCatTransportTests/
git commit -m "feat: bound a human answer separately from delivery"
```

---

## Task 3: AppModel answers

**Files:**
- Modify: `Sources/VibeCatUI/AppModel.swift`
- Test: `Tests/VibeCatUITests/AppModelTests.swift`

**Interfaces:**
- Consumes: `PendingQuestion` (Task 1).
- Produces: `AppModel.pending: PendingQuestion?` (main-actor), `AppModel.answer(_ reply: Reply)`, `AppModel.dismissQuestion()`, `AppModel.onQuestion: (@MainActor (PendingQuestion?) -> Void)?`. Task 6 calls `answer`; Task 4 reads `pending`.

`ingest` is called on the socket thread. `pending` is read and written on the main actor. The hop must not deadlock: `ingest` publishes the question to the main actor **without waiting**, then parks on the `PendingQuestion` itself.

- [ ] **Step 1: Write the failing tests**

```swift
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

/// A second question while one is open replaces it, and the first fails open
/// rather than being left parked forever.
@MainActor @Test func asecondQuestionLapsesTheFirst() async throws {
    let m = AppModel(socketPath: "/tmp/unused.sock")
    func q(_ id: String) -> VibeEvent {
        VibeEvent(id: id, cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                  choices: [Choice(id: "allow", label: "Allow")],
                  wantsReply: true, answerDeadline: 5)
    }
    let first = Task.detached { m.ingest(q("q1")) }
    try await Task.sleep(for: .milliseconds(50))
    let second = Task.detached { m.ingest(q("q2")) }
    try await Task.sleep(for: .milliseconds(50))
    #expect(m.pending?.id == "q2")
    #expect(await first.value == nil, "the displaced question did not fail open")
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
    m.dismissQuestion()
    #expect(await ingest.value == nil)
    #expect(m.pending == nil)
}
```

`VibeEvent` gains `answerDeadline: TimeInterval?` in this task — the app must honour the deadline the *hook* is using, not a second constant that can drift from it. Add it to `VibeEvent`, its `init`, its `Decodable` (`decodeIfPresent`, default nil) and `Encodable`, and to the wire doc comment. `HookRunner` sets it from `client.answerDeadline` before encoding.

- [ ] **Step 2: Run and watch them fail**

Run: `swift test --filter "aQuestionEventParks|anEventThatWantsNoReply|asecondQuestion|dismissingAQuestion"`
Expected: FAIL — no `pending` member.

- [ ] **Step 3: Implement**

```swift
    /// The question the island is showing, if any. Main actor: the UI reads it
    /// every render.
    public private(set) var pending: PendingQuestion?
    public var onQuestion: (@MainActor (PendingQuestion?) -> Void)?

    /// Returns the reply to hand back to the hook.
    ///
    /// Called on `SocketServer`'s per-connection thread. For a `wantsReply`
    /// event this blocks *that thread* until the person answers or the
    /// question expires — which is the point, and why the question is
    /// published to the main actor without waiting for it. Hopping
    /// synchronously here would deadlock the moment the main actor tried to
    /// read anything this thread holds.
    @discardableResult
    public func ingest(_ event: VibeEvent, now: Date = Date()) -> Reply? {
        store.apply(event, now: now)
        onChange?()
        guard event.wantsReply, event.choices?.isEmpty == false else { return nil }

        let question = PendingQuestion(
            event: event,
            // The hook's own deadline, carried on the event. A second constant
            // here would drift from it, and the island would keep showing a
            // question the hook had already abandoned.
            deadline: event.answerDeadline ?? SocketClient.defaultAnswerDeadline,
            now: now)
        Task { @MainActor [weak self] in self?.present(question) }
        return question.await()
    }

    @MainActor private func present(_ question: PendingQuestion) {
        // One question at a time. The displaced one fails open rather than
        // leaving a socket thread parked with nothing that can ever wake it.
        pending?.lapse()
        pending = question
        onQuestion?(question)
    }

    @MainActor public func answer(_ reply: Reply) {
        guard let pending, pending.id == reply.id else { return }
        pending.resolve(reply)
        clearQuestion()
    }

    @MainActor public func dismissQuestion() {
        pending?.lapse()
        clearQuestion()
    }

    @MainActor private func clearQuestion() {
        pending = nil
        onQuestion?(nil)
    }
```

Add `public static let defaultAnswerDeadline: TimeInterval = 20` to `SocketClient` and use it as the `init` default, so the number lives in one place.

- [ ] **Step 4: Run the tests**

Run: `swift test --filter VibeCatUITests`
Expected: PASS.

- [ ] **Step 5: Prove the no-wait hop is load-bearing**

**Do not mutate this one by making it deadlock.** The obvious mutation —
swapping the `Task { @MainActor … }` for a synchronous hop — hangs the test
process rather than failing it, and swift-testing has no sub-minute time limit
to catch that. A test run that never returns is worse than no mutation test.

Prove it the safe way instead: add a test that the question reaches the UI
*while the socket thread is still parked*, which is the property the async hop
exists for and which a synchronous hop could not satisfy.

```swift
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
    #expect(await ingest.value != nil)
}
```

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/AppModel.swift Sources/VibeCatCore/VibeEvent.swift Sources/VibeCatHookKit/HookRunner.swift Tests/
git commit -m "feat: hold a question open until it is answered"
```

---

## Task 4: The drawer's geometry, and a panel that can be clicked

**Files:**
- Modify: `Sources/VibeCatUI/IslandGeometry.swift`, `Sources/VibeCatUI/NotchPanel.swift`, `Sources/VibeCatUI/NotchController.swift`
- Test: `Tests/VibeCatUITests/Drawer/DrawerGeometryTests.swift`

**Interfaces:**
- Produces: `DrawerFace` enum with `.question`, `.questionWithReply`, `.questionMulti` and a `height` (§6.3: 288 / 184 / 300; `.sessionList` at 420 is Plan 5's and is **not** added here). `IslandGeometry.drawerWidth`. `NotchPanel.acceptsClicks` (set, not computed from `ignoresMouseEvents`).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func drawerHeightsAreTheDesignsExactly() {
    #expect(DrawerFace.question.height == 288)
    #expect(DrawerFace.questionWithReply.height == 184)
    #expect(DrawerFace.questionMulti.height == 300)
}

/// §6.3: "the drawer follows its content — opening the reply field shrinks it
/// back rather than leaving dead space." Stated as a relation, so it survives
/// the numbers being retuned.
@Test func openingTheReplyFieldShrinksTheDrawer() {
    #expect(DrawerFace.questionWithReply.height < DrawerFace.question.height)
}

/// §5.3. The one invariant the whole layout is built on.
@Test func openingTheDrawerDoesNotMoveTheLeftEdge() {
    let g = IslandGeometry(screen: mbp14)
    let collapsed = g.frames(rightFlank: 35, tier: .rest)
    let open = g.frames(rightFlank: 35, tier: .drawer(height: DrawerFace.question.height))
    #expect(open.body.minX == collapsed.body.minX)
    #expect(open.panel.minX == collapsed.panel.minX)
}

/// §5.1, at the tier that could break it: the drawer hangs below the notch
/// line, so its own top edge starts at the cutout's bottom, never inside it.
@Test func theDrawerHangsBelowTheNotchLine() {
    let g = IslandGeometry(screen: mbp14)
    let open = g.frames(rightFlank: 35, tier: .drawer(height: 288))
    #expect(open.body.maxY == g.notch.maxY)
    #expect(open.body.height == g.notch.height + 288)
}

/// Plan 3 sized the panel once and never resized it, which is safe only while
/// the island is click-through. The drawer is not, so the panel has to cover
/// exactly what takes clicks — no more.
@Test func thePanelGrowsToHoldTheDrawer() {
    let g = IslandGeometry(screen: mbp14)
    let open = g.frames(rightFlank: 35, tier: .drawer(height: 288))
    #expect(open.panel.height >= open.body.height)
    #expect(open.panel.minY <= open.body.minY)
}

@MainActor @Test func thePanelOnlyTakesClicksWhenAskedTo() {
    let panel = NotchPanel(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
    #expect(panel.ignoresMouseEvents, "a collapsed island must stay click-through")
    panel.acceptsClicks = true
    #expect(panel.ignoresMouseEvents == false)
    panel.acceptsClicks = false
    #expect(panel.ignoresMouseEvents)
    #expect(panel.level == .statusBar, "toggling clicks moved the window level")
}
```

- [ ] **Step 2: Run and watch them fail**

Run: `swift test --filter "Drawer|thePanelOnlyTakesClicks"`
Expected: FAIL — no `DrawerFace`.

- [ ] **Step 3: Implement**

```swift
/// What the drawer is showing, and how tall that makes it. Design §6.3.
///
/// The heights are the design's, verbatim. `questionWithReply` being *shorter*
/// than `question` is not a typo: opening the reply field replaces the list of
/// choices with a field, and §6.3 says the drawer follows its content rather
/// than leaving dead space.
///
/// `.sessionList` (420pt) is Plan 5's and is deliberately absent — adding a
/// case nothing constructs would be an unreachable branch, which this project
/// has shipped once already.
public enum DrawerFace: Sendable, Equatable, CaseIterable {
    case question, questionWithReply, questionMulti

    public var height: CGFloat {
        switch self {
        case .question:          288
        case .questionWithReply: 184
        case .questionMulti:     300
        }
    }
}
```

`IslandGeometry.frames` already handles `.drawer(height:)` through `tier.extraHeight`; confirm the panel's `auraMargin` inflation still leaves `panel.maxY == body.maxY` (no top margin) and extends downward. In `NotchPanel`:

```swift
    /// Whether a click lands on the island or passes through to the menu bar.
    ///
    /// False at rest, always: an oversized transparent panel that intercepts
    /// nothing is what makes Plan 3's fixed-size panel safe. The drawer needs
    /// clicks, so this is turned on exactly while the pointer is over the
    /// island *and* there is something a click would do — see
    /// `NotchController.reflow`.
    public var acceptsClicks: Bool {
        get { !ignoresMouseEvents }
        set { ignoresMouseEvents = !newValue }
    }
```

(The property already exists in this shape under a different name; rename it and its uses rather than adding a second spelling.)

- [ ] **Step 4: Run the tests**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Add a rendered check**

```swift
@MainActor @Test func nothingIsDrawnInsideTheCutoutWithTheDrawerOpen() throws {
    // Same assertion as IslandGoldenTests.nothingIsDrawnInsideTheCutout, at the
    // tier that could newly break it.
}
```

Model it on `nothingIsDrawnInsideTheCutout` in `Tests/VibeCatUITests/IslandGoldenTests.swift` — same ground-colour comparison, same panel-relative column arithmetic, with the model's tier set to the open drawer.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/ Tests/VibeCatUITests/Drawer/
git commit -m "feat: give the drawer a size and the panel a way to be clicked"
```

---

## Task 5: QuestionModel — what is selected

**Files:**
- Create: `Sources/VibeCatUI/QuestionModel.swift`
- Test: `Tests/VibeCatUITests/QuestionModelTests.swift`

**Interfaces:**
- Produces: `QuestionModel(event:)`, `.face: DrawerFace`, `.rows: [Choice]`, `.isMulti`, `.selected: Set<String>`, `.toggle(_ id:)`, `.pick(_ id:)`, `.canSend: Bool`, `.reply() -> Reply?`, `.isWritingOther`, `.otherText`. Task 6 renders these; Task 3's `answer` takes `reply()`.

Pure state, no view. Everything the drawer needs to decide what to draw, decided here where it can be tested without rendering.

- [ ] **Step 1: Write the failing tests**

```swift
private func event(multi: Bool, choices: [String] = ["allow", "always", "deny"]) -> VibeEvent {
    VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
              title: "Bash command", body: "rm -rf build/",
              choices: choices.map { Choice(id: $0, label: $0.capitalized) },
              multi: multi, wantsReply: true)
}

/// §10.2: "distinguished by the control, not by a label."
@Test func multiSelectIsDrivenByTheEventNotByGuesswork() {
    #expect(QuestionModel(event: event(multi: false)).isMulti == false)
    #expect(QuestionModel(event: event(multi: true)).isMulti)
}

@Test func theFaceFollowsTheMode() {
    #expect(QuestionModel(event: event(multi: false)).face == .question)
    #expect(QuestionModel(event: event(multi: true)).face == .questionMulti)
}

/// §10.1: picking is the answer. One tap, one reply, no Send button.
@Test func singleSelectRepliesTheMomentSomethingIsPicked() {
    let m = QuestionModel(event: event(multi: false))
    #expect(m.reply() == nil, "nothing is picked yet")
    m.pick("always")
    #expect(m.reply()?.choice == "always")
    #expect(m.reply()?.choices == nil, "a single-select reply must not carry a choices array")
}

/// §10.2: "Send is disabled at zero, so a half-made selection can never be
/// committed by reflex."
@Test func multiSelectCannotBeSentEmpty() {
    let m = QuestionModel(event: event(multi: true))
    #expect(m.canSend == false)
    m.toggle("allow")
    #expect(m.canSend)
    m.toggle("allow")
    #expect(m.canSend == false, "unticking the last box left Send enabled")
}

@Test func multiSelectRepliesWithEveryTickedChoice() {
    let m = QuestionModel(event: event(multi: true))
    m.toggle("allow"); m.toggle("deny")
    let reply = m.reply()
    #expect(reply?.choices?.sorted() == ["allow", "deny"])
    #expect(reply?.choice == nil, "a multi-select reply must not also carry a single choice")
}

/// §10.1: "`Other…` is the last row; clicking it collapses the list into a
/// text field and shrinks the drawer to match."
@Test func choosingOtherShrinksTheDrawerAndRepliesWithText() {
    let m = QuestionModel(event: event(multi: false))
    m.beginOther()
    #expect(m.isWritingOther)
    #expect(m.face == .questionWithReply)
    #expect(m.face.height < DrawerFace.question.height)
    #expect(m.reply() == nil, "an empty field is not an answer")
    m.otherText = "  "
    #expect(m.reply() == nil, "whitespace is not an answer")
    m.otherText = "use pnpm instead"
    #expect(m.reply()?.text == "use pnpm instead")
}

/// The reply's id is the last checkpoint before a destructive command is
/// authorised; HookRunner refuses a mismatch, and it must never see one.
@Test func everyReplyCarriesTheQuestionsOwnId() {
    let m = QuestionModel(event: event(multi: false))
    m.pick("deny")
    #expect(m.reply()?.id == "q")
}
```

- [ ] **Step 2: Run and watch them fail**

Run: `swift test --filter QuestionModel`
Expected: FAIL — no `QuestionModel`.

- [ ] **Step 3: Implement**

```swift
import Foundation
import Observation
import VibeCatCore

/// What the drawer is showing and what has been chosen so far.
///
/// Deliberately free of SwiftUI: every rule §10 states — one tap answers a
/// single select, Send is dead at zero, `Other…` shrinks the drawer — is
/// decided here, where it can be tested without a render.
@Observable
@MainActor
public final class QuestionModel {
    public let event: VibeEvent
    public private(set) var selected: Set<String> = []
    public private(set) var isWritingOther = false
    public var otherText = ""

    public init(event: VibeEvent) { self.event = event }

    public var rows: [Choice] { event.choices ?? [] }
    public var isMulti: Bool { event.multi }

    public var face: DrawerFace {
        if isWritingOther { return .questionWithReply }
        return isMulti ? .questionMulti : .question
    }

    /// Single select: the click *is* the answer (§10.1), so this both records
    /// the pick and makes `reply()` non-nil.
    public func pick(_ id: String) {
        guard !isMulti else { return }
        selected = [id]
    }

    public func toggle(_ id: String) {
        guard isMulti else { return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    public func beginOther() {
        isWritingOther = true
        selected = []
    }

    /// Only ever consulted for multi select — a single select has no Send.
    public var canSend: Bool { isMulti && !selected.isEmpty }

    public var tally: Int { selected.count }

    public func reply() -> Reply? {
        if isWritingOther {
            let text = otherText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return Reply(id: event.id, text: text)
        }
        if isMulti {
            guard !selected.isEmpty else { return nil }
            return Reply(id: event.id, choices: selected.sorted())
        }
        guard let one = selected.first else { return nil }
        return Reply(id: event.id, choice: one)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter QuestionModel`
Expected: PASS, 7 tests.

- [ ] **Step 5: Prove the exclusivity is load-bearing**

Change `reply()`'s multi branch to also set `choice: selected.first`. Expected: `multiSelectRepliesWithEveryTickedChoice` FAILS. This matters because `HookRunner.stdout` reads `reply.choice` first and would silently honour one arbitrary tick as the whole answer. Restore.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/QuestionModel.swift Tests/VibeCatUITests/QuestionModelTests.swift
git commit -m "feat: decide what a question's answer is, without a view"
```

---

## Task 6: The destructive guard

**Files:**
- Create: `Sources/VibeCatUI/Drawer/DestructiveGuard.swift`
- Test: `Tests/VibeCatUITests/Drawer/DestructiveGuardTests.swift`

**Interfaces:**
- Produces: `DestructiveGuard.matches(_ body: String?) -> Bool`, `QuestionModel.needsConfirmation`, `.confirm()`, `.isConfirming`.

§10.3: "Anything matching `rm -rf`, `git push --force` or `drop table` asks twice. On by default."

- [ ] **Step 1: Write the failing tests**

```swift
@Test func theThreeNamedPatternsAskTwice() {
    #expect(DestructiveGuard.matches("rm -rf build/"))
    #expect(DestructiveGuard.matches("git push --force origin main"))
    #expect(DestructiveGuard.matches("DROP TABLE users;"))
}

/// Case and spacing are the attacker here, and the attacker is a person typing
/// naturally. `-rf`, `-fr`, `-r -f` and `--force` all mean the same thing.
@Test func theMatchSurvivesOrdinaryVariation() {
    #expect(DestructiveGuard.matches("RM -RF /tmp/x"))
    #expect(DestructiveGuard.matches("rm  -fr  node_modules"))
    #expect(DestructiveGuard.matches("git push  --force-with-lease"))
    #expect(DestructiveGuard.matches("drop   table  if exists t"))
}

/// A guard that fires on everything is a guard nobody reads.
@Test func ordinaryCommandsDoNotAskTwice() {
    for safe in ["ls -la", "rm build/one.o", "git push origin main",
                 "swift test", "SELECT * FROM users", "npm run drop-shadow-demo"] {
        #expect(DestructiveGuard.matches(safe) == false, "\(safe) was flagged as destructive")
    }
}

@Test func aQuestionWithNoBodyIsNotDestructive() {
    #expect(DestructiveGuard.matches(nil) == false)
    #expect(DestructiveGuard.matches("") == false)
}

/// The guard has to gate the *reply*, not just light up the UI.
@MainActor @Test func aDestructiveAnswerIsNotAnAnswerUntilConfirmed() {
    let e = VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                      title: "Bash command", body: "rm -rf build/",
                      choices: [Choice(id: "allow", label: "Allow once")],
                      wantsReply: true)
    let m = QuestionModel(event: e)
    m.pick("allow")
    #expect(m.needsConfirmation)
    #expect(m.reply() == nil, "a destructive answer was returned before it was confirmed")
    m.confirm()
    #expect(m.reply()?.choice == "allow")
}

/// Denying something destructive is not itself destructive.
@MainActor @Test func refusingADestructiveCommandNeedsNoConfirmation() {
    let e = VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                      body: "rm -rf build/",
                      choices: [Choice(id: "deny", label: "Deny")], wantsReply: true)
    let m = QuestionModel(event: e)
    m.pick("deny")
    #expect(m.reply()?.choice == "deny")
}
```

- [ ] **Step 2: Run and watch them fail**

Run: `swift test --filter Destructive`
Expected: FAIL — no `DestructiveGuard`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Design §10.3: `rm -rf`, `git push --force` and `drop table` ask twice.
///
/// Three patterns, not a general danger heuristic. A guard that fires on
/// everything is one nobody reads, so `rm build/one.o` and `git push origin
/// main` pass straight through — the tests name the ones that must.
public enum DestructiveGuard {
    private static let patterns = [
        // rm with a recursive AND a force flag, in either order, together or
        // apart: -rf, -fr, -r -f, --recursive --force.
        #"\brm\b(?=(?:\s+-{1,2}\w+)*\s+-{0,2}\w*[rR])(?=(?:\s+-{1,2}\w+)*\s+-{0,2}\w*[fF])"#,
        #"\bgit\s+push\b(?=.*--force)"#,
        #"\bdrop\s+table\b"#,
    ]

    public static func matches(_ body: String?) -> Bool {
        guard let body, !body.isEmpty else { return false }
        return patterns.contains { pattern in
            body.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    /// The answers that actually carry the danger. Refusing a destructive
    /// command is not itself destructive, so it is not gated.
    public static func isPermissive(_ choiceID: String) -> Bool {
        choiceID == "allow" || choiceID == "always"
    }
}
```

In `QuestionModel`:

```swift
    public private(set) var isConfirming = false

    /// True once a *permissive* answer has been picked for a body §10.3 names.
    public var needsConfirmation: Bool {
        guard DestructiveGuard.matches(event.body) else { return false }
        guard !isConfirming else { return false }
        return selected.contains(where: DestructiveGuard.isPermissive)
    }

    public func confirm() { isConfirming = true }
```

and `reply()` gains, as its first line:

```swift
        guard !needsConfirmation else { return nil }
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter Destructive`
Expected: PASS, 6 tests.

- [ ] **Step 5: Prove the gate is on the reply**

Delete the `guard !needsConfirmation` line from `reply()`. Expected: `aDestructiveAnswerIsNotAnAnswerUntilConfirmed` FAILS. A guard that only lights up the UI is decoration; this is the assertion that makes it a gate. Restore.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/Drawer/DestructiveGuard.swift Sources/VibeCatUI/QuestionModel.swift Tests/VibeCatUITests/Drawer/DestructiveGuardTests.swift
git commit -m "feat: ask twice before rm -rf, force-push or drop table"
```

---

## Task 7: The drawer, drawn

**Files:**
- Create: `Sources/VibeCatUI/Drawer/DrawerView.swift`, `Sources/VibeCatUI/Drawer/QuestionFace.swift`, `Sources/VibeCatUI/Drawer/ChoiceRow.swift`
- Modify: `Sources/VibeCatUI/IslandView.swift`, `Sources/VibeCatUI/IslandModel.swift`
- Test: `Tests/VibeCatUITests/Drawer/DrawerGoldenTests.swift`

**Interfaces:**
- Consumes: `QuestionModel` (Task 5), `DrawerFace` (Task 4), `Raster`/`rasterise` (existing).
- Produces: `DrawerView(question:accent:width:)`, `IslandModel.question: QuestionModel?`.

§10.1's rules are visual and belong in rendered assertions, not read counters: choices run top to bottom one per row; the recommended answer is *tinted, not filled*; a number badge marks each row.

- [ ] **Step 1: Write the failing tests**

```swift
/// §10.1: "Choices run top to bottom, one per row, so a label like 'Allow all
/// pnpm commands in ~/dev/api for this session' stays readable instead of
/// being truncated." Real permission prompts have labels this long, so the
/// test uses one.
@MainActor @Test func longLabelsGetTheirOwnRowAndAreNotTruncated() throws {
    let long = "Allow all pnpm commands in ~/dev/api for this session"
    let e = VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                      title: "Bash command", body: "pnpm install",
                      choices: [Choice(id: "allow", label: "Allow once"),
                                Choice(id: "always", label: long),
                                Choice(id: "deny", label: "Deny")],
                      wantsReply: true)
    let m = QuestionModel(event: e)
    let raster = try rasterise(DrawerView(question: m, accent: IslandState.waiting.accent,
                                          width: 420))
    // Rows are horizontal bands of content separated by bands of pure ground.
    // Three choices means three bands.
    #expect(contentBands(raster).count >= 3,
            "expected one band per choice; found \(contentBands(raster).count)")
}

/// §10.1: "The recommended answer is tinted, not filled — a wide block of
/// solid colour shouts." A filled row is a wide run of accent pixels; a tinted
/// one is not.
@MainActor @Test func theRecommendedRowIsTintedRatherThanFilled() throws {
    let m = QuestionModel(event: recommendedEvent())
    let raster = try rasterise(DrawerView(question: m, accent: IslandState.waiting.accent,
                                          width: 420))
    let accentPixels = raster.pixelCount(near: IslandState.waiting.accent)
    let total = raster.opaquePixelCount
    #expect(Double(accentPixels) / Double(total) < 0.15,
            "the recommended row is \(accentPixels * 100 / total)% solid accent — that is a fill, not a tint")
    #expect(accentPixels > 0, "the recommended row carries no accent at all")
}

/// §10.2: "a checkbox instead of a number badge. A number badge means the
/// click is the answer; a checkbox means it is not." The two must not render
/// the same.
@MainActor @Test func multiSelectRowsDoNotLookLikeSingleSelectRows() throws {
    let single = try rasterise(DrawerView(question: QuestionModel(event: threeChoices(multi: false)),
                                          accent: IslandState.waiting.accent, width: 420))
    let multi = try rasterise(DrawerView(question: QuestionModel(event: threeChoices(multi: true)),
                                         accent: IslandState.waiting.accent, width: 420))
    #expect(single.differingPixelCount(from: multi) > 200,
            "single and multi select rendered near-identically — the control is not carrying the distinction")
}

/// §10.2: "Send is disabled at zero." Disabled has to look disabled.
@MainActor @Test func sendLooksDifferentWhenItCannotBePressed() throws {
    let m = QuestionModel(event: threeChoices(multi: true))
    let dead = try rasterise(DrawerView(question: m, accent: IslandState.waiting.accent, width: 420))
    m.toggle("allow")
    let live = try rasterise(DrawerView(question: m, accent: IslandState.waiting.accent, width: 420))
    #expect(dead.differingPixelCount(from: live) > 50)
}

/// The drawer is the island's, so it wears the island's colour (§4.3).
@MainActor @Test func theDrawerWearsTheStatesAccent() throws {
    for state in [IslandState.waiting, .failed] {
        let raster = try rasterise(DrawerView(question: QuestionModel(event: threeChoices(multi: false)),
                                              accent: state.accent, width: 420))
        #expect(raster.pixelCount(near: state.accent) > 0, "\(state): no accent anywhere in the drawer")
    }
}
```

`contentBands(_:)` is a helper in this file: scan rows, group consecutive rows that hold any non-ground pixel, return the groups. Write it beside the tests, not in `Raster` — it is specific to "this layout is a vertical list".

- [ ] **Step 2: Run and watch them fail**

Run: `swift test --filter DrawerGolden`
Expected: FAIL — no `DrawerView`.

- [ ] **Step 3: Implement the three views**

`ChoiceRow`: an `HStack` of leading control (number badge or checkbox), then the label as `Text` with `.fixedSize(horizontal: false, vertical: true)` so a long label wraps rather than truncating — that is what `longLabelsGetTheirOwnRowAndAreNotTruncated` is checking. Recommended rows get `.background(accent.opacity(0.14))` and a `1pt` accent border; **never** a solid accent fill.

`QuestionFace`: title in the right-flank font's weight, body in a monospaced face (it is a command), then `ForEach(question.rows)`. `Other…` is appended as the final row when the event is single-select.

`DrawerView`: ground `#05070B` matching the island, the §6.3 height for `question.face`, `IslandShape`-consistent bottom corners, and **44pt of unclaimed space reserved at the bottom for Plan 6's footer** (§6.4) so adding it does not force a relayout. Comment that reservation, or a later reader will delete it as dead space.

In `IslandView`, the drawer hangs below the collapsed body inside the same panel, with the §9.1 drawer spring:

```swift
                .animation(.spring(response: 0.42, dampingFraction: 0.78),
                           value: drawerHeight)
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter DrawerGolden`
Expected: PASS, 5 tests.

- [ ] **Step 5: Look at it**

Extend `ContactSheet.swift` with a drawer sheet — single select with a long label, multi select mid-selection, the reply field open, and the destructive confirmation — and render it:

```bash
VIBECAT_CONTACT_SHEET=/tmp/drawer.png swift test --filter contactSheet
```

Open the PNG. Three plans shipped artwork nobody had looked at; two of the three defects that found were invisible to passing tests. Do not skip this step, and say in the task report what the render showed.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/Drawer/ Sources/VibeCatUI/IslandView.swift Sources/VibeCatUI/IslandModel.swift Tests/VibeCatUITests/Drawer/
git commit -m "feat: draw the question"
```

---

## Task 8: Click to open, and the round trip end to end

**Files:**
- Modify: `Sources/VibeCatUI/NotchController.swift`
- Test: `Tests/VibeCatUITests/NotchControllerTests.swift`, `Tests/VibeCatTransportTests/PipelineTests.swift`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Write the failing tests**

```swift
/// The rule from "The panel takes mouse events only when there is something to
/// open". Both halves matter: a permanently clickable island swallows menu bar
/// clicks, and an island that never takes them cannot be answered.
@MainActor @Test func thePanelTakesClicksOnlyWhenHoveredWithAQuestionWaiting() {
    let c = makeController()
    c.setHovering(false); c.setQuestion(nil)
    #expect(c.panel.acceptsClicks == false)
    c.setHovering(true); c.setQuestion(nil)
    #expect(c.panel.acceptsClicks == false, "hovering an island with nothing to open swallowed a menu bar click")
    c.setHovering(false); c.setQuestion(aQuestion())
    #expect(c.panel.acceptsClicks == false, "a question the pointer is nowhere near swallowed a menu bar click")
    c.setHovering(true); c.setQuestion(aQuestion())
    #expect(c.panel.acceptsClicks)
}

/// A question arriving must not open the drawer by itself — that would steal
/// the screen from whatever the person is doing. It changes the cat and waits.
@MainActor @Test func aQuestionDoesNotOpenTheDrawerOnItsOwn() {
    let c = makeController()
    c.setQuestion(aQuestion())
    #expect(c.model.tier == .rest)
}

@MainActor @Test func aLapsedQuestionClosesTheDrawer() async throws {
    let c = makeController()
    c.setQuestion(aQuestion(deadline: 0.05))
    c.click()
    #expect(c.model.tier != .rest)
    try await Task.sleep(for: .milliseconds(200))
    #expect(c.model.tier == .rest, "the drawer is still showing a question the hook has abandoned")
    #expect(c.panel.acceptsClicks == false)
}
```

And the end-to-end, in `PipelineTests` beside the existing hook round-trip:

```swift
/// The whole point of the plan, over a real socket: a permission event goes in
/// as JSON, the island answers it, and claude-code's own decision shape comes
/// back out.
@Test func aPermissionAnsweredInTheIslandReachesTheCLI() async throws { … }

/// And the property that outranks it: nobody answers, and the CLI still gets
/// its own prompt rather than a hung terminal.
@Test func anUnansweredPermissionFailsOpen() async throws { … }
```

- [ ] **Step 2: Run and watch them fail**

Run: `swift test --filter "NotchController|Pipeline"`
Expected: FAIL.

- [ ] **Step 3: Implement**

`reflow()` gains the clicks rule and the tier:

```swift
        // Clicks are taken only where a click would do something. Everywhere
        // else the menu bar underneath stays clickable — which is what makes
        // Plan 3's oversized fixed panel safe (see maxCollapsedFrames).
        panel.acceptsClicks = model.hovering && appModel.pending != nil
```

`onQuestion` sets `model.question`, re-renders, and schedules a lapse check at the question's expiry that closes the drawer. Cancel it the way `bloomEnd` is cancelled — the same `Task` + `cancel()` shape, for the same reason.

When the tier changes, re-apply the panel frame. This is the first thing since Plan 2 that resizes the panel, and Plan 3's comment on `maxCollapsedFrames` says exactly this must happen; delete that comment's "Plan 4 must" wording once it has.

- [ ] **Step 4: Run the tests**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Run it on hardware, unlocked**

```bash
VIBECAT_SOCKET=/tmp/vibecat-dev.sock swift run vibecat &
echo '{"hook_event_name":"PreToolUse","session_id":"dev-1","cwd":"'"$PWD"'","tool_name":"Bash","tool_input":{"command":"rm -rf build/"}}' | swift run vibecat-hook claude-code
```

The hook should block. Click the island, answer, and the hook should print claude-code's `permissionDecision` JSON and exit 0. Then repeat and answer nothing: after the answer deadline the hook should print nothing and exit 0, and the drawer should close itself.

**Click-through is already settled — do not re-test it, and do not synthesise clicks on the menu bar.** It was confirmed on 2026-08-02: the *panel* spans x 581…1069 while the island ends at 863, a status item sat at 1046…1079, and a click at 1060 activated that item. It also made a menu bar app request keychain access, which is why this says don't.

What Task 4 changes is the other direction, and it is worth a look here: with clicks turned on while hovering, that same ~200pt of panel to the right of the island starts intercepting. Hover the island and check whether a status item under the panel has become unclickable. If it has, that is a finding for the report — the panel may need to shrink to what it actually draws.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/NotchController.swift Tests/
git commit -m "feat: click the island, answer the question"
```

---

## Task 9: Number keys

**Files:**
- Modify: `Sources/VibeCatUI/NotchPanel.swift`, `Sources/VibeCatUI/NotchController.swift`
- Test: `Tests/VibeCatUITests/KeyRoutingTests.swift`

§10.1: "A number badge marks each row and the matching number key picks it."

**This task carries a genuine unknown, and it is the last task for that reason.** Everything above works without it.

- [ ] **Step 1: Answer the unknown, on an unlocked machine**

Can a `.nonactivatingPanel` at `.statusBar` become key and receive `keyDown` **without taking focus from the terminal the agent is running in**? Nobody knows. An attempt on 2026-08-02 was void: the probe reported `frontmost: loginwindow`, i.e. the screen was locked, so no window could become key regardless. Do not repeat that mistake — **print `NSWorkspace.shared.frontmostApplication` before and after, and abandon the measurement if it is `loginwindow`.**

Write a throwaway probe that builds the panel exactly as `NotchPanel` does (`isFloatingPanel` then `level = .statusBar`, in that order), calls `makeKeyAndOrderFront`, and reports: `panel.isKeyWindow`, `NSApp.isActive`, and whether `frontmostApplication` changed. Record the answer in the task report.

- [ ] **Step 2: Take the path the answer selects**

**Path A — the panel can become key without stealing focus.** Override `keyDown(with:)` on `NotchPanel`, map `1`–`9` to `question.rows` by index, `Return` to Send when `canSend`, and `Escape` to dismiss. Only while the drawer is open; forward everything else with `super.keyDown`.

**Path B — it cannot.** Do not fight it. A key that steals focus mid-answer is worse than no key: the terminal loses its cursor at the exact moment the person is deciding something destructive. Implement `Escape`-to-dismiss only, via a local monitor while the drawer is open, and record the outcome in the follow-ups with the measurement that decided it. `NSEvent.addGlobalMonitorForEvents` is **not** the fallback — it needs Accessibility, which this app does not otherwise require, and asking for it to save one keystroke is a bad trade.

- [ ] **Step 3: Write the tests for whichever path was taken**

Route keys through a testable function, not through `keyDown` directly, so the mapping is checkable without a window:

```swift
@MainActor @Test func numberKeysPickTheMatchingRow() {
    let m = QuestionModel(event: threeChoices(multi: false))
    #expect(KeyRouting.pick(character: "2", in: m) == "always")
    #expect(KeyRouting.pick(character: "9", in: m) == nil, "there is no ninth row")
    #expect(KeyRouting.pick(character: "0", in: m) == nil, "rows are 1-indexed, as the badges are")
}

/// A destructive answer must not be reachable by one keystroke — §10.3's
/// second ask is the whole point, and a keyboard path around it is a hole.
@MainActor @Test func aNumberKeyStillCannotSkipTheSecondAsk() {
    let m = QuestionModel(event: destructiveEvent())
    _ = KeyRouting.pick(character: "1", in: m)
    #expect(m.reply() == nil)
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatUI/ Tests/VibeCatUITests/KeyRoutingTests.swift
git commit -m "feat: pick an answer with the matching number key"
```

---

## Self-review

**Spec coverage.** §6.3 drawer heights → Task 4. §6.4 footer → deferred to Plan 6, with its 44pt reserved in Task 7 so the deferral costs nothing later. §10.1 single select, one row per choice, tinted-not-filled, number badges, `Other…` → Tasks 5, 7, 9. §10.2 multi select, checkbox not label, Send and tally, dead at zero → Tasks 5, 7. §10.3 destructive → Task 6. §2.2 wire protocol → unchanged; `Reply` already carries `choice`, `choices` and `text`, and this plan fills all three. §2.3 fail-open → Tasks 1, 2, 3, and the end-to-end in Task 8. §9.1 drawer spring `0.42/0.78` → Task 7, the first thing in the project with a drawer to animate.

**One place the plan overrides the spec, deliberately and visibly:** §2.3's flat 300ms. The reasoning is at the top under "The answer deadline is not 300ms", and the consequence it creates — a question outliving the hook that asked it — is handled in Task 1 and tested by `aLapsedQuestionStopsBeingAnswerable`. If that reasoning is wrong, Task 2 is where to change it and nothing downstream moves.

**Types.** `DrawerFace` is Task 4's and used by Tasks 5 and 7. `PendingQuestion` is Task 1's and used by Tasks 3 and 8. `QuestionModel` is Task 5's and used by 6, 7, 9. `DestructiveGuard` is Task 6's and used by 5's `reply()` — Task 6 modifies a Task 5 file, which is why it comes after. `VibeEvent.answerDeadline` is added in Task 3 and produced by Task 2's `HookRunner`; if Task 3 runs first, that field is nil and the `SocketClient.defaultAnswerDeadline` fallback covers it.

**Two risks carried into execution.** The keyboard unknown is real and isolated to Task 9, which is last so it can be dropped without touching anything. And **one blocked thread per outstanding question** is a real cost: `SocketServer` detaches a thread per connection and Task 1 parks it for up to 20 seconds. One at a time it is nothing; a CLI that fires many `wantsReply` events at once would pile threads up. Task 3's "one question at a time" lapses the displaced question, which unparks its thread — that is the mitigation, and `asecondQuestionLapsesTheFirst` is what proves it works.
