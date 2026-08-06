# Parking a Question in the Session List — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status: done, 8/8 tasks, 940 tests.** See "Carried findings" at the foot of
> this file for what is still open and what this plan got wrong about itself.
> The three review passes behind that section are
> `.superpowers/sdd/2026-08-06-parking-questions/task-6-review.md`,
> `fidelity-report.md` and `test-premise-report.md` — read them for the
> mutation-by-mutation detail; this file's section is the folded summary.

**Goal:** Let a question be *set aside* rather than given up on. ESC or collapsing
the notch parks it; it then renders **inline beneath its own session row** in the
session list, where it can be answered later — and the hook keeps waiting the
whole time.

**Architecture:** `PendingQuestion` gains a parked state that does **not** signal
its gate, so the blocked hook thread stays blocked. `AppModel` moves from one
`pending` to one per session, which is the change that makes a *list* of parked
questions meaningful. The question renders as a `.rblock` under its row — the
prototype's own idiom for "the session's own internals, one indent deeper" — and
the row's jump hit-region narrows to its header so answering never jumps.

**Tech Stack:** Swift 6, SwiftUI + AppKit interop, `swift-testing`, no external
dependencies.

## Global Constraints

- **No external dependencies.**
- **The prototype is the authority on appearance.**
  `docs/superpowers/prototypes/island-motion.html`. The elements this plan
  touches, by name and line:
  - `.row` `:345-349` — the session card. `cursor:pointer` is on the **whole
    row** today, which Task 6 deliberately narrows.
  - `.rbody` `:350`, `.rtop` `:351`, `.rproj` `:352-353`, `.rstate` `:354`,
    `.rmid` `:355`
  - **`.rblock` `:370`** and `.rblock .bh` `:371-372` — the nested block. Already
    implemented in Swift: `SessionBlocks.swift:79-107`, whose `panel(_:)` and
    `blockHeader(_:detail:)` are what a question block must reuse rather than
    re-derive.
  - `renderRows()` `:839-856`, `tasksHTML` `:822-828`, `agentsHTML` `:830-838`
  - **`:832` is the load-bearing citation for this whole plan:**
    `/* hidden subagents collapse to a count — approvals and questions would stay */`
  **Open the file.** Plan 5 shipped eight tasks against §11's ASCII diagram
  without one implementer opening this file, and six divergences went unnoticed.
- **Colour means state, and only state (§4.3).** A parked question does not get a
  colour of its own. The session stays `waiting` and stays `#FFA63C`, because it
  *is* still waiting on you. Parking is a UI position, not a state.
- **Worst state wins (§4.2)** and **the session list is a view, not a state.**
  Parking must not change what the island reports. This is the invariant most at
  risk here and Task 3 has the assertion for it.
- **Fail open (§2.3) stays true, and the two deadlines stay separate.**
  **Delivery keeps its hard `300ms`** — that is what makes a crashed or absent
  island harmless, together with socket EOF. The *answer* deadline is the
  hand-back to the terminal (ruling C) and is the only one this plan moves.
- **`Scripts/test.sh`**, not bare `swift test`.
- **Concurrency reasoning goes next to the code.** `PendingQuestion` is the most
  thread-sensitive type in the repo: it is touched from `SocketServer`'s
  per-connection thread and from the main actor, and it parks a real thread on a
  `DispatchSemaphore`. Read `AppModel.ingest` and `applyAndNotify` before
  starting. Dispatch `concurrency-auditor` on Tasks 1, 2 and 7.

## Why this is a new feature and not a §14 row

Nothing in the spec or either prototype renders a question inside a session row.
§11 draws the session list without one; `island-motion.html` renders
`tasksHTML` and `agentsHTML` into `.rblock`s and nothing else.

**But `:832` says the author expected it.** *"approvals and questions would
stay"* — written about what survives collapsing subagents to a count. So the
design was anticipated in the mockup's own source and never built. This plan
completes that intent rather than inventing against it, and Task 8 adds the spec
section that has been missing.

## The two things this fixes that were not asked for

Worth stating because they change how the work should be judged.

**1. A second question silently discards the first.** `AppModel.swift:280-281`:

```swift
pending?.lapse()
pending = question
```

Two agents asking at once means the first is fail-opened without anyone seeing
it — the terminal re-prompts and the island never showed the question at all.
Moving to one pending question per session removes that, and is why Task 2 is the
bulk of this plan rather than a two-line change.

**2. ESC currently throws a question away.** `NotchController.swift:865` guards
on Escape and `:893` calls `appModel.dismissQuestion()`, which is
`pending?.lapse()`. A person pressing ESC to get the panel out of the way loses
the question. After this plan ESC parks, and giving up becomes explicit.

## What the hook protocol actually allows — measured 2026-08-06

The owner asked whether the timeout could be removed so a question waits
indefinitely, and whether a question could be answerable at the notch **and** in
the terminal at once. Both were settled by measurement rather than by reasoning
from §2.3, and the results changed this plan's design.

**Method.** A scratch project with a `PreToolUse` hook on `Bash` that logged its
entry time, wrote a marker to stderr, slept 3s, logged its exit, and returned no
decision. Driven with `claude -p 'Run exactly this with the Bash tool …'
--allowedTools Bash` (Claude Code 2.1.223), twice — once with
`--output-format json`, once plain — with every output line timestamped.

| Question | Result |
|---|---|
| Does the CLI wait for the hook? | **Yes.** Nothing appeared between `+3.06s` and `+17.02s` while the hook slept; the tool's output followed the hook's exit. |
| Is the hook's stderr shown? | **No.** The marker reached neither stream, on `exit 0` or `exit 1`. |
| Are the hook's stdout/stderr ttys? | No — pipes. Parent process `claude`. |
| Can a question be retracted? | **No.** Payload keys are `hook_event_name`, `tool_name`, `tool_input`, `tool_use_id`, `transcript_path`, `prompt_id`, `session_id`, `permission_mode`, `cwd`, `effort`. Nothing cancels an in-flight ask. |

**Unmeasured, and abandoned rather than chased.** Whether a hook can write to
`/dev/tty` was **not** established: both attempts ran from a shell with no
controlling terminal (`tty` → `not a tty`, `ps -o tty=` → `??`), so
`/dev/tty write: FAILED` says nothing about a real Terminal session. Dropped on
reasoning rather than on a result: Claude Code's TUI redraws continuously, so an
unsolicited write would be overwritten or garble a frame. Labelled as reasoning.

### What follows

**Only one party holds the decision at a time.** The CLI's prompt does not appear
until the hook returns, so "answerable at the notch and in the terminal
simultaneously" is not a preference to choose — it is unavailable. The only
alternative would be typing into the terminal for the user, which §2.3's framing
rejects outright: replying through the hook is exact *because* it is not simulated
keystrokes.

**So the deadline is not a safety net — it is the hand-back mechanism.** Without it
the terminal never gets a prompt at all.

**That inverts what an earlier draft of this section argued.** It claimed waiting
forever was "identical to the CLI's own behaviour, which has no timeout." Wrong,
and the correction is the useful part: the CLI's prompt also waits forever, but it
is **visible** the whole time. A blocked hook is invisible — the terminal looks
idle. Same duration, opposite discoverability.

**And one line of the prototype's copy is false.** `settings.html:291` reads *"How
long the hook waits before letting the agent carry on without you."* The agent does
not carry on without you; measured, the CLI asks you itself. Task 7 fixes it.

---

## The three rulings, given 2026-08-06

### A. Scope: **one parked question per session**

Task 2 is in. `AppModel.pending` becomes one slot per session, and the
silent-discard defect at `AppModel.swift:280-281` goes with it.

The owner was told this is the larger half of the work and that it touches the
repo's most concurrency-sensitive object, and chose it anyway. The reason it is
right: the point of putting a question in the session list is to choose among
several. With one at a time the list gives a new location and no new capability.

### B. Giving up on purpose: **a `Dismiss` on the session row's header**

Not a second ESC press. The control carries the meaning (§10.2) and a hidden
second-press is the opposite of that rule.

**Where it lands: in `.rtop`** (`island-motion.html:351`) — the session row's own
header, beside `.rstate`. Note `.rstate` carries `margin-left:auto`, so it is
already the right-aligned end of that line; Task 5 decides which side of it the
Dismiss sits on and the answer comes from the prototype's spacing, not from
preference.

**A first draft of this ruling put it inside the question block's `.bh` header
and argued the row was the wrong place** — that someone could dismiss a question
they had not read, the same failure `.truncationMode(.middle)` exists to prevent.
**That argument does not hold and the record should say why rather than quietly
dropping it.** The block renders inline beneath the header and is always visible;
there is no expand step. So the question *is* on screen while the header's
Dismiss is being pressed, and the concern it was guarding against cannot arise.

**What the placement does create is a hit-region collision, and Task 6 owns it.**
`.rtop` is also the jump target (ruling from the owner: *"จะ Jump แค่เวลากดที่
หัวข้อของ session"*). So the header now contains both "jump to this terminal" and
"give up on this question", and a `Dismiss` that let its tap propagate would jump
*and* dismiss in one click. Task 6's `answeringInsideTheBlockDoesNotJump` gets a
sibling: `dismissingFromTheHeaderDoesNotJump`.

### C. The hand-back deadline: **1 minute by default, still settable**

Named for what it does rather than for its mechanism: the field is
`handBackToTerminalAfter`, not `hookReplyTimeout`.

**Default 1 minute, and the owner's reasoning is the right one:** *"ตอนแรกเข้าใจ
ว่าจะตอบตรงไหนก็ได้ ถ้าได้แค่ทีเดียวให้แค่ 1 นาทีพอ"* — if the notch monopolises
the decision, it should not monopolise it for long. A longer default was only on
the table while both channels looked simultaneously available, which the
measurements above ruled out.

**Still settable in Settings**, which is the point of §14's row: range `0.5…60`
minutes plus `Never`. `Never` means the notch holds the question for as long as the
hook lives and the terminal is never prompted — available, not the default.

### What the row shows after the hand-back

**The row does not change.** Still amber, still `Needs you`, still showing the
command — `island-motion.html:788-789`'s own vocabulary, with `metaLine`
(`:816-821`) already naming the terminal. All of it is still true: the agent still
needs the person, just somewhere else. No new state and no new colour, so §4.3 is
untouched.

**The block changes.** Choices and `Dismiss` disappear — the hook is gone, so there
is nothing here left to answer or to give up on — and one line takes their place:
`Waiting for you in iTerm2 ↗`. The command stays, per *never truncate away the
thing being decided*: someone about to walk to a terminal still needs to know what
they are approving. The only useful action left is jumping, which is already what
the header does.

It clears itself. Answering in the terminal runs the tool, `PostToolUse` fires, and
the session leaves `.waiting`.

**Task 2 shipped the opposite and needs amending**, which is recorded in its own
section below: its `prune` *removes* a question whose hook has given up, and a
removed question leaves nothing to draw this state from.

### Ordering constraint

**Task 5 must land before Task 7.** Task 5 is what renders a parked question at
all; Task 7 is what lengthens how long one can be parked. In the other order a
question can be invisible for up to an hour with nowhere to answer it. The plan is
ordered correctly — this is written down because plan order gets reshuffled.


---

## File Structure

**Created:**

| File | Responsibility |
|---|---|
| `Sources/VibeCatUI/Drawer/QuestionBlock.swift` | the question rendered as a `.rblock` under its row |
| `Tests/VibeCatUITests/ParkedQuestionTests.swift` | parking, unparking, and what the island reports |
| `Tests/VibeCatUITests/Drawer/QuestionBlockTests.swift` | |
| `Tests/VibeCatUITests/Drawer/RowHitRegionTests.swift` | jump vs answer |

**Modified:**

| File | Change |
|---|---|
| `Sources/VibeCatUI/PendingQuestion.swift` | `park()` / `unpark()` / `isParked`, without signalling the gate |
| `Sources/VibeCatUI/AppModel.swift` | `pending` becomes one per session; `parkQuestion` / `resumeQuestion` |
| `Sources/VibeCatUI/IslandModel.swift` | `face` resolves to `.sessionList` when every question is parked |
| `Sources/VibeCatUI/NotchController.swift` | ESC parks (`:865`, `:893`); the question-face wiring at `:698` |
| `Sources/VibeCatUI/Drawer/SessionRow.swift` | hosts a `QuestionBlock`; the jump hit-region narrows to the header |
| `Sources/VibeCatUI/Drawer/SessionListFace.swift` | rows grow, so the face's height stops being one constant |
| `Sources/VibeCatUI/IslandGeometry.swift` | `DrawerFace.sessionList`'s `420` becomes a floor, not a fixed height |
| `Sources/VibeCatTransport/SocketClient.swift` | `clampedAnswer` spans 30s–60min; `deadlineInstant(minutes:)` makes `Never` explicit |
| `Sources/VibeCatCore/Preferences.swift` | `handBackToTerminalAfter: Double?` |
| `docs/superpowers/specs/2026-07-31-vibecat-design.md` | a §11 section for parking, and a dated §2.3 correction |

---

### Task 1: `PendingQuestion` learns to be parked

**Files:**
- Modify: `Sources/VibeCatUI/PendingQuestion.swift`
- Test: `Tests/VibeCatUITests/ParkedQuestionTests.swift`

**Interfaces:**
- Consumes: the existing `lock`, `settled`, `gate`, `reply`, `id`, `expiry`,
  `resolve(_:) -> Bool`, `lapse()`, `hasLapsed(at:) -> Bool`.
- Produces: `park()`, `unpark()`, `var isParked: Bool`.

**The one property that matters:** parking must **not** signal `gate`. `lapse()`
signals it, which is how a dismissed question releases the blocked hook thread;
parking is the opposite of that. A `park()` that copied `lapse()`'s shape and
signalled would fail open on every ESC while *appearing* to work in the UI — the
question would still be drawn, and the agent would already have been told to
carry on. That is the defect this task's first test exists to catch.

`isParked` is separate from `settled`, not a fourth case of it: a parked question
can still be resolved, can still lapse on expiry, and `hasLapsed(at:)` must keep
returning `settled || instant >= expiry` unchanged. **Parking does not pause the
clock.** If it did, a parked question could outlive the hook's own read expiry
and the two would disagree about whether the agent is still waiting.

- [ ] **Step 1: Write the failing tests**

```swift
/// The whole task in one assertion. A `park()` that signalled the gate would
/// release the hook thread — the agent carries on, the UI still shows the
/// question, and nothing in a UI-level test would notice.
@Test func parkingDoesNotReleaseTheWaitingHook() throws {
    let q = PendingQuestion(/* the suite's existing fixture shape */)
    q.park()
    #expect(q.isParked)
    // The gate must still be closed. Wait with a real but tiny timeout: a
    // signalled semaphore returns `.success` immediately, an unsignalled one
    // returns `.timedOut`.
    #expect(q.waitForTesting(timeout: .now() + .milliseconds(20)) == .timedOut,
            "park() signalled the gate, so the hook was released and the agent carried on")
}

/// The inverse, so the pair brackets the behaviour: dismissing must still
/// release it. Without this, a `park()` that replaced `lapse()`'s body would
/// pass the test above.
@Test func dismissingStillReleasesTheWaitingHook() throws {
    let q = PendingQuestion(/* … */)
    q.lapse()
    #expect(q.waitForTesting(timeout: .now() + .milliseconds(20)) == .success)
}

/// Parking does not pause the clock. Derived from the rule: the hook's own read
/// expiry is fixed when it starts waiting and knows nothing about parking, so a
/// parked question that stopped expiring would outlive the thread it belongs to.
@Test func aParkedQuestionStillExpires() {
    let q = PendingQuestion(/* … expiry 1s from a fixed instant … */)
    q.park()
    #expect(q.hasLapsed(at: <the instant + 2s>))
}

/// A parked question is still answerable — that is the point of parking.
@Test func aParkedQuestionCanStillBeResolved() {
    let q = PendingQuestion(/* … */)
    q.park()
    #expect(q.resolve(Reply(/* matching id */)) == true)
}
```

`waitForTesting` does not exist — add it as a non-`public` hook exposing the
existing `gate.wait(timeout:)`, with the doc comment
`SettingsButton.actionForTesting` already carries. **Read `PendingQuestion.swift`
in full before writing any of this**: the initialiser's real signature, the
`Reply` type's real shape, and how the existing tests build a fixture. Four
predecessor plans shipped invented signatures here.

- [ ] **Step 2: Run, watch all four fail** — `Scripts/test.sh --filter Parked`.
      Expected: compile failure, no `park()`.

- [ ] **Step 3: Implement.** Under `lock`, like every other mutation on this
      type. `park()` and `unpark()` must both be no-ops when `settled` — a
      resolved question that got parked would redraw in the list after the agent
      already moved on.

- [ ] **Step 4: Run, watch pass, then mutate.** Add `gate.signal()` to `park()`
      and confirm `parkingDoesNotReleaseTheWaitingHook` goes red. **Verify the
      edit applied before reporting the colour.**

- [ ] **Step 5: Dispatch `concurrency-auditor`** on this file's diff.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: a question can be parked without releasing the hook waiting on it"
```

---

### Task 2: One pending question per session

**Files:**
- Modify: `Sources/VibeCatUI/AppModel.swift`
- Test: `Tests/VibeCatUITests/AppModelTests.swift`

**Interfaces:**
- Consumes: Task 1's `park()`/`unpark()`/`isParked`; the existing `ingest`,
  `applyAndNotify`, `answer(_:)`, `dismissQuestion()`, `clearQuestion()`,
  `onQuestion`.
- Produces: `pendingBySession: [String: PendingQuestion]` (or the equivalent
  ordered shape — see below), `parkQuestion(id:)`, `resumeQuestion(id:)`, and a
  changed `onQuestion` contract.

**Ruled in: one pending question per session** (ruling A).

> **Amended after Task 2 shipped, by rulings B and C.** Two things in this section
> are now wrong and the corrections live with the tasks that own them:
>
> 1. **Keyed by session is wrong** — one session can have several outstanding
>    questions, because parallel tool calls each fire their own `PreToolUse` hook and
>    subagents share the parent's `session_id`. Fixed in `576fe20`: keyed by question
>    id, nothing displaced but an exact duplicate.
> 2. **`prune` must stop removing a question whose hook has given up.** Ruling C's
>    handed-back row draws its command from that question; removing it leaves nothing
>    to draw. The rule becomes: `answer` removes, `Dismiss` removes, **a hand-back
>    keeps** — and `hasLapsed(at:)` is what distinguishes the block's two states, so
>    no new flag is needed on `PendingQuestion`. A kept-and-settled question is
>    removed when its session leaves `.waiting`. Do this in Task 5, beside the view
>    that depends on it, rather than as a lone `prune` edit whose reason lives
>    elsewhere.

**The current shape and what has to change.** `AppModel.swift:157` is
`public private(set) var pending: PendingQuestion?`, and `:280-281` lapses the old
one when a new arrives. That line is not a bug someone left behind — with one
slot it is the only correct thing to do, because a displaced question's hook
thread would otherwise block forever with nothing able to answer it. **So the
lapse must not simply be deleted; it must become unnecessary**, which it is once
every session has its own slot.

**Ordering matters and a dictionary does not have it.** The session list is
ordered, and which question the island shows when the drawer is closed must be
stable — otherwise the face flickers between two questions on unrelated
redraws. Either key by session id and derive order from `SessionStore`'s own
ordering, or hold an array. Whichever is chosen, write down *why* in the
declaration: a future reader will otherwise "simplify" it back to a dictionary.

**`onQuestion` changes meaning.** Today `clearQuestion()` sets `pending = nil`
and calls `onQuestion?(nil)`, and `NotchController.swift:698` maps that to
`model.question = pending.map { QuestionModel(event: $0.event) }`. With several
questions the callback must carry *which* question is frontmost, and parking must
notify without clearing — an ESC that fired `onQuestion?(nil)` would drop the
question out of the model entirely and the list would have nothing to draw.

**`@Observable` notifies on the write, not the change.** Guard every write here
the way `prune` does. Parking a question that is already parked must not
invalidate the island's body.

- [ ] **Step 1: Write the failing tests**

```swift
/// The defect this task removes, asserted directly. Today the first question is
/// lapsed — its hook is told to carry on and the person never saw it.
@Test @MainActor func aSecondQuestionDoesNotDiscardTheFirst() async throws {
    let m = AppModel(/* the suite's fixture */)
    // Two `wantsReply` events from *different* sessions.
    // …ingest both…
    #expect(m.pendingBySession.count == 2)
    // And the first one's hook is still waiting — the assertion that would fail
    // if `pending?.lapse()` survived the refactor.
    #expect(first.waitForTesting(timeout: .now() + .milliseconds(20)) == .timedOut)
}

/// Two questions from the *same* session still replace, because a session can
/// only be blocked on one tool call at a time — and the replaced one's hook must
/// be released, or its thread parks forever with nothing able to reach it.
@Test @MainActor func asecondQuestionFromTheSameSessionReplacesAndReleasesTheFirst() async throws {
    // …ingest two `wantsReply` events with the same session id…
    #expect(m.pendingBySession.count == 1)
    #expect(first.waitForTesting(timeout: .now() + .milliseconds(20)) == .success)
}
```

The second test is the one that keeps this task honest: "never lapse anything" is
the wrong lesson to draw from the first.

- [ ] **Step 2: Run, watch fail.**

- [ ] **Step 3: Implement.** `ingest` runs on `SocketServer`'s per-connection
      thread and *must* be able to park it — read its existing comments before
      touching it, and do not move work onto the main actor that is not already
      there. `DispatchQueue.main.sync` from a `Task.detached` deadlocks under
      full-suite load; that is measured, with an empty `sync {}` body.

- [ ] **Step 4: Run the whole suite three times, serially.**

- [ ] **Step 5: Dispatch `concurrency-auditor`.** This is the diff it exists for.

- [ ] **Step 6: Commit**

---

### Task 3: `IslandModel.face` respects parking — and the island's report does not change

> **Done. It required no production change — the design made it free.**
> `IslandModel.face` is `question?.face ?? .sessionList` and `parkQuestion()` already
> fires `onQuestion?(nil)`, so the drawer falls through to the session list on its
> own. What the task delivered is the three tests that notice if a later edit routes
> parking anywhere else, and they live in `NotchControllerTests.swift` because that
> file owns the `controller(_:)`/`mbp14` fixtures this needs.
>
> **One thing the first run caught that is worth keeping:** `appModel.onQuestion` is
> wired inside `present()` (`NotchController.swift:334`), not in `init`. A test that
> only called `refreshGeometry()` drove a controller `AppModel` could not reach, and
> read `.sessionList` before anything had been parked — passing the "after" assertion
> for the wrong reason. The `#expect(face == .question)` *before* parking is what
> exposed it.

**Files:**
- Modify: `Sources/VibeCatUI/IslandModel.swift`
- Test: `Tests/VibeCatUITests/ParkedQuestionTests.swift`

**Interfaces:**
- Consumes: Tasks 1–2. Produces: a changed `face`.

`IslandModel.swift:170` is today:

```swift
public var face: DrawerFace { question?.face ?? .sessionList }
```

So a question always wins the face and the list can only appear when there is
none. Parking has to invert that for parked questions only: **a parked question
resolves to `.sessionList`, an unparked one still wins.**

**The invariant at risk, and it is a stated one.** §4.2: *"The session list is a
view, not a state — opening it must not change what the island reports."*
Parking moves a question into the list, and the temptation is to let the island
go calm because the drawer is now showing something else. It must not: the
session is still `waiting`, still `#FFA63C`, still counted. Parking is a
position, not a state.

- [ ] **Step 1: Write the failing tests**

```swift
/// The face moves.
@Test @MainActor func aParkedQuestionSendsTheDrawerToTheSessionList() {
    let m = IslandModel(/* … one question … */)
    #expect(m.face != .sessionList)
    // …park it…
    #expect(m.face == .sessionList)
}

/// And nothing else does. This is the §4.2 assertion, and it is the one worth
/// having: it fails if someone "helpfully" calms the island when a question is
/// parked. Compare the *reported state*, not a rendered colour count — a render
/// with the badge emptied still produces eighty-odd colours and passes a count.
@Test @MainActor func parkingChangesWhereAQuestionIsDrawnAndNothingElse() {
    let m = IslandModel(/* … one waiting session with a question … */)
    let before = (m.state, m.waitingCount, m.badge)   // read the real property names
    // …park it…
    #expect(m.state == before.0, "the island's state changed because a question was parked")
    #expect(m.waitingCount == before.1)
    #expect(m.badge == before.2)
}
```

Grep `IslandModel.swift` for the real property names before writing the second
test; do not assume `waitingCount` or `badge` exist under those spellings.

- [ ] **Step 2: Run, watch fail.** — [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, watch pass, mutate** — make `state` calm when parked and
      confirm the second test goes red.
- [ ] **Step 5: Commit**

---

### Task 4: ESC parks, and collapsing parks

**Files:**
- Modify: `Sources/VibeCatUI/NotchController.swift`
- Test: `Tests/VibeCatUITests/NotchControllerTests.swift`

**Interfaces:** consumes Tasks 1–3.

`NotchController.swift:865` guards `case .drawer = model.tier` and
`KeyRouting.isEscape(...)`; `:893` calls `appModel.dismissQuestion()`. Change the
call, not the guard. Read `:836` and `:874`'s existing comments first — they
explain why one line sufficed and that reasoning is about to stop holding.

**Correction, made while implementing: there is no collapse-on-mouse-leave path to
change.** This plan said `:719-746` routed one; it does not — that range is the
`lapseCheck` `Task`. Grepped: exactly three things close the drawer, and
`model.drawerOpen = false` appears once, inside `setQuestion(nil)`. The other two
callers are this method and the expiry `Task`. Auto-collapse on mouse leave is a
Plan 6.7 *preference* with nothing behind it yet (its declared-inert list), so
there is nothing here to park from. **So Task 4 is Escape only.**

**The expiry `Task` at `:737` is deliberately left calling `dismissQuestion()`.**
That is the hand-back path, and ruling C changes what it should do — keep the
question, do not forget it — together with the second block state that draws it.
Both are Task 5's, so that they can be reviewed as one change rather than as a lone
edit whose reason lives in another task.

**The deliberate-dismiss path is a control, not a key** (ruling B), so it is
Task 5's — not this task's. Nothing here dismisses anything: after this task,
Escape parks and only parks.

- [ ] **Step 1: Write the failing test**

```swift
/// The behaviour change, at the layer a person actually touches.
@Test @MainActor func escapeParksTheQuestionRatherThanAnsweringForYou() throws {
    let (controller, model) = /* the suite's existing controller fixture */
    // …put a question up, open the drawer…
    _ = controller.handleEscapeForTesting()   // read the real helper's name
    #expect(question.isParked)
    #expect(question.waitForTesting(timeout: .now() + .milliseconds(20)) == .timedOut,
            "escape released the hook, so the agent was answered by a keypress")
    #expect(model.face == .sessionList)
}
```

- [ ] **Step 2: Run, watch fail.** — [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, watch pass.** Check `:719-746`'s displaced-question guard
      still holds — `fix: guard the lapse Task against dismissing a displaced
      question` is in this file's history and parking gives that Task a second
      way to be wrong.
- [ ] **Step 5: Commit**

---

### Task 5: `QuestionBlock` — the question under its own row

> **Done, in four commits.** `RBlock`/`RBlockHeader` extracted so the container's
> metrics have one home; `QuestionBlock` with ruling C's two states;
> `handBackQuestion()` plus `prune`'s new rule; then the wiring
> `AppModel.questions` → `IslandModel.questions` → `SessionRow` → `QuestionBlock`.
>
> **Two more plan overstatements found while implementing.**
> `DrawerFace.sessionList`'s 420pt does **not** need to become a floor —
> `SessionListFace` already scrolls, so a taller row scrolls inside a fixed drawer
> and `IslandGeometry` is untouched. And the answering semantics did not need
> duplicating: `QuestionModel.tap(_:)`/`send()` were lifted out of `QuestionFace`
> so both views share one implementation, which is what keeps §10.3's second ask
> from being forgotten in one of them.
>
> **`QuestionModel` instances are cached in `NotchController`, by question id.**
> Rebuilding them per `render()` would discard a half-made multi-select selection
> on the next unrelated store change, and `render()` runs on every store change.
> `aQuestionsSelectionSurvivesARerender` asserts identity with `===`.

**Files:**
- Create: `Sources/VibeCatUI/Drawer/QuestionBlock.swift`
- Test: `Tests/VibeCatUITests/Drawer/QuestionBlockTests.swift`

**Interfaces:**
- Consumes: `SessionBlocks.swift:89`'s `panel(_:)` and `:102`'s
  `blockHeader(_:detail:)` — extract them to be reachable rather than
  re-deriving the chrome; `ChoiceRow` (`:92` already has `onTapGesture`);
  `DestructiveGuard`; `QuestionModel`.
- Produces: `QuestionBlock(question:, onAnswer:)` with **two states**, and the
  `prune` amendment ruling C requires.

**The block has two states and one of them has no controls** (ruling C):

| State | Test | Draws |
|---|---|---|
| answerable | `!question.hasLapsed(at: now)` | the command, the choices one per row, and the header's `Dismiss` |
| handed back | `question.hasLapsed(at: now)` | the command, and one line — `Waiting for you in <terminal> ↗` |

The command is in both, per *never truncate away the thing being decided*: someone
about to walk to a terminal still needs to know what they are approving. Nothing
else is: with the hook gone there is nothing here to answer or to give up on.

**The terminal's name comes from the row's own `metaLine`** — the prototype already
prints it (`island-motion.html:816-821`, `SESSIONS[0].term` is `'iTerm2'`), so read
it from the session rather than inventing a second source.

**Also this task: stop `prune` removing a handed-back question.** Task 2 shipped
`prune` dropping anything `hasLapsed`, which deletes exactly what the second state
draws from. Change it to remove a settled question when its session leaves
`.waiting` instead, and keep the guarded notify — `aPruneThatDropsNoQuestionDoesNotNotify`
already pins that and must stay green.

**`onDismiss` is *not* this view's** — ruling B puts the control on the session
row's header (`.rtop`, `island-motion.html:351`), which is `SessionRow`'s, so the
closure is threaded from there. `QuestionBlock` draws the question and its
choices and nothing else. It is still Task 5's job to *build* the control, and it
is the only way to fail a question open on purpose once Task 4 makes Escape park
— so it is not optional and not a follow-up.

**This is the visual task and the prototype is the authority.**
`.rblock` `:370` — `margin-top:6px`, `rgba(255,255,255,.035)`, `border-radius:7px`,
`padding:7px 9px`. `.rblock .bh` `:371-372` — `10.5px` in `--haze`, `padding-bottom:4px`,
`gap:6px`, and `.bh em` in `--dim`. `SessionBlocks.swift:79-107` already implements
exactly this; **reuse it, do not re-type the numbers**, or there will be two
places a fixed metric has to be fixed.

`:832`'s comment is the design authority for the block existing at all:
*"approvals and questions would stay."*

**Rules that already exist and apply here:**
- **Never truncate away the thing being decided.** `.truncationMode(.middle)` on
  the command body. `rm -rf /Users/dev/projects/vibe…` asks someone to authorise
  a target they cannot see, and that was measured at 0 differing pixels between
  two different destinations.
- **Choices run one per row, top to bottom** — real permission labels are
  sentences.
- **The recommended answer is tinted, not filled.**
- **Destructive answers ask twice** — `DestructiveGuard`, on by default. A parked
  question is *more* likely to be answered inattentively, not less, so this is
  not optional here.
- **The block is inside a `ScrollView`.** `ImageRenderer` cannot rasterise a
  `ScrollView`; use `rasteriseHosted` for anything that needs the scroll, and
  know that it is untrustworthy for flat fills.

- [ ] **Step 1: Write the failing tests**

```swift
/// The rule with a measured history behind it. Two commands sharing a long head
/// and differing only in their tail must render differently — with `.tail`
/// truncation they measured 0 differing pixels.
@Test @MainActor func aLongCommandInAParkedQuestionKeepsTheTargetVisible() throws {
    func render(_ cmd: String) throws -> Raster { /* … at the row's real width … */ }
    let a = try render("rm -rf /Users/dev/projects/vibe/build/cache/tmp")
    let b = try render("rm -rf /Users/dev/projects/vibe/build/cache/src")
    #expect(!(try a.samePixels(as: b)))
}

/// The block draws the `.rblock` ground, so it reads as the session's own
/// internals rather than as a floating card. Assert on the one colour only this
/// can emit at this opacity.
@Test @MainActor func theQuestionBlockUsesTheSessionsOwnBlockGround() throws {
    // `rgba(255,255,255,.035)` over the drawer's ground — compute the composited
    // value from the rule rather than reading it off a render and accepting it.
}
```

Grep `Tests/VibeCatUITests/Raster.swift` for the real comparison and colour
helpers first. `samePixels`, `contains(_:tolerance:)`, `measureHeight` and
`isTransparent(x:y:)` have all been invented in this repo's plans; at least one
of them does not exist.

- [ ] **Step 2: Run, watch fail.** — [ ] **Step 3: Implement.**
- [ ] **Step 4: Dispatch `render-evidence`** for a filmstrip of a row with the
      block open, closed, and with a destructive confirmation showing. Look at it.
- [ ] **Step 5: Commit**

---

### Task 6: The hit regions — the header jumps, the block answers

**Files:**
- Modify: `Sources/VibeCatUI/Drawer/SessionRow.swift`
- Modify: `Sources/VibeCatUI/Drawer/SessionListFace.swift`
- Modify: `Sources/VibeCatUI/IslandGeometry.swift`
- Test: `Tests/VibeCatUITests/Drawer/RowHitRegionTests.swift`

**Interfaces:** consumes Task 5. Produces `SessionRow(… onJump:, onDismiss:)`
and the row's hit-region split.

**The owner's rule:** answering never jumps; **jump fires only from the session's
header**. In prototype terms that is `.rtop` (`:351`) — the project name, the
worktree chip and the state — and not `.rmid`, not `.rsaid`, not any `.rblock`.

**This is a deliberate divergence and must be written down where it is met.**
`island-motion.html:345` puts `cursor:pointer` on the whole `.row`, so the
prototype's entire card is one jump target. Narrowing it is the owner's decision;
record it in `SessionRow`'s doc comment with the line number, not only in this
plan. A reviewer diffing against the prototype will find the row's hit area
smaller and needs the reason in the file.

**Nothing jumps yet.** §13's jump is Plan 6's and is unbuilt, so `onJump` is a
closure the row calls and the caller currently does nothing with. Say so in the
declaration — an unwired closure that looks wired is the failure Plan 6.7's
`declaredInert` list exists for.

**`DrawerFace.sessionList` is `420` today** (`IslandGeometry.swift:98`) and a row
that can grow makes a single constant wrong. It becomes a floor. The drawer's
height spring is `0.45/0.80` with a 30ms lag behind the width's `0.42/0.62`
(`IslandMotion`), and opening a block animates height — check that the reveal
does not fight the existing drawer-open animation.

- [ ] **Step 1: Write the failing tests**

```swift
/// The owner's rule, as an assertion. Tapping inside the question block must not
/// call `onJump` — and a naive implementation that puts one `.onTapGesture` on
/// the row and another on the block gets *both*, because SwiftUI tap gestures
/// propagate outward unless the inner one consumes.
@Test @MainActor func answeringInsideTheBlockDoesNotJump() {
    var jumped = false
    // …build a row with a parked question, onJump: { jumped = true }…
    // …invoke the block's answer path through its testing hook…
    #expect(jumped == false, "answering a parked question also jumped to the terminal")
}

/// And the header still jumps, so the first test is not passing because nothing
/// jumps at all.
@Test @MainActor func theHeaderStillJumps() {
    var jumped = false
    // …invoke the header's tap through its testing hook…
    #expect(jumped == true)
}
```

```swift
/// Ruling B's control lives in the same header that jumps, so a tap that
/// propagated would jump *and* give up on the question in one click — the worst
/// possible pair of outcomes to combine, since one of them is irreversible for
/// that question.
@Test @MainActor func dismissingFromTheHeaderDoesNotJump() {
    var jumped = false, dismissed = false
    // …build a row with a parked question, onJump/onDismiss both recording…
    // …invoke the Dismiss control's testing hook…
    #expect(dismissed == true)
    #expect(jumped == false, "dismissing a question also jumped to its terminal")
}
```

The three together are the point: any one alone is satisfied by a broken
implementation.

- [ ] **Step 2: Run, watch both fail.** — [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, watch pass, mutate** — put the tap back on the whole row and
      confirm the first test goes red.
- [ ] **Step 5: Commit**

---

### Task 7: The hand-back deadline, in minutes

**Files:**
- Modify: `Sources/VibeCatTransport/SocketClient.swift`
- Modify: `Sources/VibeCatCore/Preferences.swift`
- Test: `Tests/VibeCatTransportTests/SocketClientTests.swift`

**Interfaces:** produces `SocketClient.clampedAnswer` over a new range, and the
`handBackToTerminalAfter` preference Plan 6.7's Settings row binds to — which is
why that row was held back until this plan.

**Must not start before Task 5** (see the ordering constraint above).

**What this deadline is, in the words the measurements earned.** It is not a
timeout guarding against a hang — a crashed island is already handled by the 300ms
delivery deadline and by socket EOF. It is **the hand-back**: the only mechanism by
which the terminal ever gets a prompt, because measured, the CLI shows nothing of
its own while a hook is blocked. Name it for that:

| | |
|---|---|
| Preference | `handBackToTerminalAfter: Double?` — minutes; `nil` is `Never` |
| Default | **1 minute** (ruling C) |
| Range | `0.5…60` minutes, plus `Never` |
| Clamp | `SocketClient.clampedAnswer`, bounding `30…3600` seconds |
| Unchanged | the **delivery** deadline stays `300ms` |

**`Double?` rather than a sentinel.** `Never` is not a duration and spelling it as
a magic large number is how `IdleCleanup` in Plan 6.7 avoided the same trap. `nil`
maps to `.distantFuture` at the one place a `DispatchTime` is built, explicitly,
rather than by arithmetic that saturates — CLAUDE.md records that an absurd
interval saturating into `.distantFuture` is a way to park a thread by accident,
and doing it on purpose in one named place is the opposite of that bug.

- [ ] **Step 1: Write the failing tests**

```swift
/// The new range, and that it is still a range. `clamped`'s old ceiling was 60
/// *seconds*; a hand-back measured in minutes needs an hour of headroom and still
/// needs a floor no smaller than "long enough for a person to read a sentence".
@Test func theHandBackDeadlineSpansHalfAMinuteToAnHour() {
    #expect(SocketClient.clampedAnswer(30) == 30)
    #expect(SocketClient.clampedAnswer(3600) == 3600)
    #expect(SocketClient.clampedAnswer(3601) == 3600)
    #expect(SocketClient.clampedAnswer(86_400) == 3600, "a day-long hand-back was honoured")
    #expect(SocketClient.clampedAnswer(0.001) == 30)
}

/// The delivery deadline is a different bound and must not move with it. A single
/// clamp reused for both is the mistake this test exists to catch — 3600s of
/// *delivery* is §2.3 broken by arithmetic rather than by a switch.
@Test func theDeliveryDeadlineDidNotMoveWithIt() {
    #expect(SocketClient.defaultDeliveryDeadline == 0.300)
    #expect(SocketClient.clampedDelivery(3600) < 3.0)
}

/// `Never` is finite arithmetic's absence, not its extreme. Built in one named
/// place so nothing computes its way there by overflow.
@Test func neverBecomesDistantFutureExplicitlyAndNothingElseDoes() {
    #expect(SocketClient.deadlineInstant(minutes: nil) == .distantFuture)
    #expect(SocketClient.deadlineInstant(minutes: 60) < .distantFuture)
}
```

- [ ] **Step 2: Run, watch fail.**

- [ ] **Step 3: Implement**, and fix the copy while the reason is in hand. The
      prototype's caption (`settings.html:291`) says the agent will *"carry on
      without you"*, which the measurements show is false — it asks you itself.
      Plan 6.7's row takes: **"How long the notch holds the question before the
      terminal asks you instead."** Record it as a written prototype divergence in
      the pane's own doc comment, with the line number.

- [ ] **Step 4: Run the whole suite.** Every existing test asserting the `60`
      ceiling fails. **Read each before editing it** — one that was pinning "a
      deadline cannot be absurd" still needs to pin that, at the new bound. A test
      updated without being read is how a guard silently loses its point.

- [ ] **Step 5: Dispatch `concurrency-auditor`.**

- [ ] **Step 6: Commit**

---

### Task 8: The spec, and closing the plan

**Files:**
- Modify: `docs/superpowers/specs/2026-07-31-vibecat-design.md`
- Modify: `docs/superpowers/plans/README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add the §11 section for parking.** What it is, that ESC parks and
      does not dismiss, that a parked question renders as a `.rblock` under its
      row, that the header jumps and the block answers, and that the island's
      reported state does not change. Cite `island-motion.html:832` as the
      design's own anticipation of it.

- [ ] **Step 2: Add a dated §2.3 correction** in §5.5's form for the clamp's new
      range, saying which deadline moved and which did not, and why the ceiling
      exists at all — the wedged-app scenario from this plan's "Why not
      unbounded" table.

- [ ] **Step 3: Update `CLAUDE.md`'s fail-open bullet.** It currently reads
      *"answer `answerDeadline` (default 20s, clamped `0.02…60`)"*, which this
      plan makes wrong. That bullet is load-bearing documentation and a stale
      number in it is how the last round of confusion started.

- [ ] **Step 4: Run the whole suite three times, serially, zero warnings.**

- [ ] **Step 5: Dispatch `prototype-fidelity`.** Its brief must contain
      `docs/superpowers/prototypes/island-motion.html`, `renderRows()` at
      `:839-856`, `.row`/`.rtop`/`.rbody` at `:345-355`, `.rblock` at `:370-372`,
      `tasksHTML` at `:822-828`, `agentsHTML` at `:830-838`, and the comment at
      `:832`. Ask it to name what it compared.

- [ ] **Step 6: Dispatch `test-premise-auditor`** over every assertion added.

- [ ] **Step 7: Dispatch `plan-archivist`.**

- [ ] **Step 8: Commit, then stop.** A push publishes — ask first, every time.

---

## Out of scope, deliberately

- **§13's jump.** Task 6 defines the hit region and calls a closure; Plan 6 makes
  it do something.
- **Notifying about a parked question.** Plan 6.5's alert policy fires when a
  question arrives. Whether a question parked for ten minutes should re-alert is
  a real question and not this plan's.
- **A parked question surviving a restart.** The hook's thread dies with its
  process, so a parked question cannot outlive the app that holds it. Persisting
  it would be persisting something already gone.

## Self-review

**Spec coverage.** Nothing in §11 or §14 covers this — it is new, and Task 8 adds
the section rather than pretending a task implements existing prose. The only
existing text it touches is §2.3's clamp range and §4.2's "the session list is a
view, not a state", both of which have explicit tasks.

**Placeholders.** Fixture construction is left as `/* the suite's existing
fixture shape */` in six tests, deliberately: `PendingQuestion`'s initialiser,
`AppModel`'s test fixture and `NotchController`'s controller fixture are all real
APIs this plan must not guess at, and every such gap names the file to read. Four
predecessor plans shipped invented signatures for exactly these types.

**Type consistency.** `park()`/`unpark()`/`isParked` and `waitForTesting` are
defined in Task 1 and used in Tasks 2, 3, 4. `pendingBySession` is defined in
Task 2 and used in Task 3. `QuestionBlock(question:onAnswer:onDismiss:)` is
defined in Task 5 and consumed in Task 6. `onJump` is defined in Task 6 and
consumed by nothing, which is stated there and is correct.

**One thing this plan cannot check itself.** Whether a `.rblock`-sized question
actually fits and reads well inside a session row at the drawer's real width is a
judgement about pixels, not a property. Task 5's `render-evidence` dispatch and
Task 8's `prototype-fidelity` dispatch are that check, and neither is optional.

---

## Carried findings — closed 2026-08-06

All 8 tasks landed, at `d2529dd`. **940 tests, 17 suites, green** (`Scripts/test.sh`).
Three review passes sit behind this section —
`.superpowers/sdd/2026-08-06-parking-questions/task-6-review.md` (hit-region
review plus a scoped re-review, 7 findings, all closed),
`fidelity-report.md` (prototype diff) and `test-premise-report.md` (assertion
audit, 2 survivors of 30 mutations) — this is the folded summary, not a
replacement for reading them.

### Deferred, and genuinely open

- **`Dismiss` releases every same-session question, including one that arrived
  since the last render.** `AppModel.dismissQuestions(forSession:)`
  (`AppModel.swift:408`) filters live `questions` at call time, not what the row
  last painted — self-healing in practice (an arriving question reaches the view
  within a frame or two via `ingest → onChange → reflow`) and nothing is
  stranded, but it is marginally wider than ruling B's own wording, which argued
  from *the questions a row holds on screen*.
- **The narrowed pointing-hand cursor has a teardown, but a stuck `NSCursor` is
  process-wide state no headless test in this suite can observe.**
  `SessionRow.headline`'s `.onHover` (`SessionRow.swift:507-511`) pushes and pops
  `NSCursor.pointingHand` scoped to `hoveringHeader`, and `.onDisappear`
  (`:522-524`) pops it if the row disappears mid-hover. **Unmeasured**: whether
  `.onHover(false)` is actually delivered across `NotchController
  .dismissQuestions`'s panel churn (`orderOut` + `orderFrontRegardless`) while
  the pointer sits over the header it just dismissed from — `.onHover` never
  fires without a real pointer event, and no test here can synthesize one. Needs
  a hand test on real hardware (`Scripts/build-app.sh && open .build/VibeCat.app`),
  not a unit test.

### Accepted, not deferred

**Moving the header's tap gesture onto the whole row leaves every hit-region
test green** — confirmed by mutation (`test-premise-report.md`'s M18: all three
of `answeringInsideTheBlockDoesNotJump`, `dismissingFromTheHeaderDoesNotJump`,
`theHeaderStillJumps` stay green). There is no ViewInspector in this project and
none will be added, and a synthetic tap cannot reach a SwiftUI `.onTapGesture`
through this suite's headless render path —
`Tests/VibeCatUITests/Drawer/QuestionFaceTests.swift:6-14` documents that limit
already, for the same reason (`QuestionFace.tapped(_:)` is called directly
rather than through a rendered tap). What defends against the bug is
structural, not tested: `headline` and the question blocks are siblings under
one `VStack` (`SessionRow.swift:263,275`), never ancestor/descendant, so there
is no shared gesture recognizer for a tap to leak through. This is **accepted**,
not deferred — nobody is going to add the missing coverage, because the
dependency it would need is the thing being declined.

### A gap this plan closed that belonged to its own earlier task

`rowQuestions` could be dropped at any of three view hops
(`SessionRow → SessionListFace → DrawerView → IslandView → IslandModel`) with
the whole `VibeCatUITests` target still green — Task 5's own wiring
(`IslandView.swift:182` threads `rowQuestions: model.questions`), not Task 6's.
Found during Task 6's review, not invented there. Now pinned by
`aParkedQuestionSurvivesTheWholeViewTreeIntoARenderedBlock`
(`Tests/VibeCatUITests/IslandGoldenTests.swift:847`), which asserts
`differingPixelCount` rather than `opaquePixelCount` — the drawer's silhouette
fills its panel opaquely regardless of content, so a coverage count cannot see
content change inside it, and the first version of this test used the wrong
instrument.

### Three places this plan was wrong about itself

Recording these because a plan that admits its own overstatements is worth more
than one that reads as though it were right throughout.

- **`DrawerFace.sessionList`'s `420` (`IslandGeometry.swift:98`) never needed to
  become a floor.** `SessionListFace.list` is already a `ScrollView(.vertical)`
  (`SessionListFace.swift:129`), so a row that grows past the drawer's height
  scrolls inside a fixed drawer rather than needing the drawer itself to grow.
  `IslandGeometry` is untouched by this plan.
- **There was no collapse-on-mouse-leave path to change.** The plan's Task 4
  named `:719-746` as a mouse-leave collapse to redirect to parking; grepped,
  that range is `lapseCheck`, the expiry `Task` (`NotchController.swift:764`).
  Auto-collapse on mouse leave does not exist yet — it is a Plan 6.7 preference
  with nothing behind it — so Task 4 ended up Escape-only, which the plan's own
  text says but is worth restating here since it is a correction, not a choice.
- **The answer clamp was not meant to become `30…3600`.** An earlier version of
  Task 7 (and, transitively, of `docs/superpowers/plans
  /2026-08-06-general-and-integrations.md`) specified a floor of `30` seconds
  alongside the `3600` ceiling. Raising the floor would have made nine existing
  tests that observe a real answer timeout at `0.05s`/`0.6s`
  (`PendingQuestionTests`, `NotchControllerTests`) impossible rather than slow —
  `SocketClient.floorDeadline`'s own doc comment states this. The shipped floor
  is unchanged at `0.02` in both clamps.

### What Plan 6.7 now inherits

`Preferences.handBackToTerminalAfter` is persisted and clamped
(`UserDefaultsPreferenceStore.clampedHandBack`, `0.5…60` minutes) and **read by
nothing** — `grep -rn handBackToTerminalAfter Sources/` finds the field, its
clamp, and its two-key encoding, and no reader; `HookRunner` never mentions it.
This is the fourth persisted-but-unread preference in this project's history,
recorded as `"NOTHING YET"` in `everyPreferenceFieldHasANamedProductionReader`.
Plan 6.7's Integrations row writes it; Plan 6.7's own Task 7 is what teaches
`HookRunner` to read it. Until then, the hand-back that actually runs in
production is `NotchController.lapseCheck` timing out on `answerDeadline`, i.e.
the hook's own `SocketClient.answerDeadline` (default 20s).

**The clamp this plan actually shipped, for anyone wiring that reader.**
`d2529dd` ("split the deadline clamp by provenance") found that widening
`SocketClient.clamped`'s ceiling to `3600` was live *today* on the untrusted
`answerDeadline` `AppModel.ingest` decodes off the `0600` socket — a sixtyfold
widening of a fail-open bound for a benefit (a settable hand-back) that was not
yet reachable. So the clamp is split by the value's provenance, not by one
number: `SocketClient.clamped` (`:98`) is the wire bound, unchanged at
`0.02…60`; `SocketClient.clampedChosenByPerson` (`:94`) is new, for a value the
app's own `init` supplies, `0.02…3600`. `docs/superpowers/plans
/2026-08-06-general-and-integrations.md` named the wrong function
(`clampedAnswer`) and the wrong floor (`30`) for this — corrected in that file
2026-08-06, alongside this closeout, to `clampedChosenByPerson` and `0.02`.
