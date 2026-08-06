# Parking a Question in the Session List — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

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
- **Fail open (§2.3).** Every wait stays bounded. Parking extends how long a
  person has, never to forever — see "Why not unbounded" below.
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

## Why not unbounded ("รอเสมอ")

The owner asked whether an empty timeout could mean wait forever. Three
scenarios, and the third is why the answer is no:

| Situation | Is the hook released? |
|---|---|
| Island alive, person answers or dismisses | Yes — `resolve` / `lapse` signals the gate |
| Island **crashes** while parked | Yes — the socket closes, `read()` returns `0`, and `SocketClient.readLine` falls through to `return nil` (`SocketClient.swift:202-204`) |
| Island **wedged** — process alive, main actor deadlocked | **No.** No EOF, and the UI cannot process ESC |

A hung SwiftUI app is more likely than a crashed one, and in that case the
deadline is the only thing that returns the terminal. `SocketClient.swift:96-99`
already says this in its own words: an unbounded read expiry lets *"a peer that
trickles at least one byte before every `SO_RCVTIMEO` window closes ride that
forever — the unbounded wait §2.3 forbids outright."*

**So: minutes, with a real ceiling.** Task 7 raises the answer clamp to
`0.05…60` **minutes** and an empty field means the ceiling, not infinity.

---

## The two rulings, given 2026-08-06

### A. Scope: **one parked question per session**

Task 2 is in. `AppModel.pending` becomes one slot per session, and the
silent-discard defect at `AppModel.swift:280-281` goes with it.

The owner was told this is the larger half of the work and that it touches the
repo's most concurrency-sensitive object, and chose it anyway. The reason it is
right: the point of putting a question in the session list is to choose among
several. With one at a time the list gives a new location and no new capability.

### B. Giving up on purpose: **a `Dismiss` in the session list**

Not a second ESC press. The control carries the meaning (§10.2) and a hidden
second-press is the opposite of that rule.

**Where it lands:** in the question block's `.bh` header line, right-aligned, in
`--dim` — quiet and present. The block is rendered inside the session list under
its own row and is always visible, so "in the session list" and "in the block's
header" are the same place; there is no expand step between them.

Recorded because the owner's words were *"Dismiss ให้กดที่ session list"* and a
later reader could reasonably ask whether that meant a control on the **row**,
outside the block. It does not: one Dismiss, in the block that shows the question
it dismisses, so the thing being given up on is on screen when you give up on it.
Putting it on the row would let someone dismiss a question they had not read,
which is the same failure `.truncationMode(.middle)` exists to prevent — being
asked to decide about something you cannot see.

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
| `Sources/VibeCatTransport/SocketClient.swift` | the answer clamp's ceiling moves to 60 minutes |
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

Collapsing the notch (mouse leave, outside click, whatever `:719-746` already
routes) must park too, for the same reason: the person moved on, they did not
answer.

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

**Files:**
- Create: `Sources/VibeCatUI/Drawer/QuestionBlock.swift`
- Test: `Tests/VibeCatUITests/Drawer/QuestionBlockTests.swift`

**Interfaces:**
- Consumes: `SessionBlocks.swift:89`'s `panel(_:)` and `:102`'s
  `blockHeader(_:detail:)` — extract them to be reachable rather than
  re-deriving the chrome; `ChoiceRow` (`:92` already has `onTapGesture`);
  `DestructiveGuard`; `QuestionModel`.
- Produces: `QuestionBlock(question:, onAnswer:, onDismiss:)`.

**`onDismiss` is ruling B's control** — right-aligned in the `.bh` header
(`island-motion.html:371-372`), `--dim`. It is the only way to fail a question
open on purpose once Task 4 makes Escape park, so it is not optional and it is
not a follow-up.

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

**Interfaces:** consumes Task 5. Produces `SessionRow(… onJump:)` and the
row's hit-region split.

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

The pair is the point: either test alone is satisfied by a broken
implementation.

- [ ] **Step 2: Run, watch both fail.** — [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, watch pass, mutate** — put the tap back on the whole row and
      confirm the first test goes red.
- [ ] **Step 5: Commit**

---

### Task 7: The answer deadline in minutes

**Files:**
- Modify: `Sources/VibeCatTransport/SocketClient.swift`
- Test: `Tests/VibeCatTransportTests/SocketClientTests.swift`

**Interfaces:** produces a changed `clamped` range. Consumed by Plan 6.7's
`hookReplyTimeout` field, which is why that field was held back until this plan.

**What changes:** `SocketClient.clamped` bounds `0.02…60` **seconds** today
(`:47`). Parking means a question can sit for as long as a person is away, so the
ceiling becomes **60 minutes** — `0.05…3600` seconds. The floor rises from `0.02`
to `0.05` for the same reason 6.7's delivery clamp does: 20ms is not a deadline
anyone chose.

**The delivery deadline does not change.** It stays `300ms` and it is what makes
a crashed island harmless. Two deadlines bounding two different things is §2.3's
own structure; this task moves one of them and must not blur them.

**Check the saturation hazard explicitly.** CLAUDE.md records that *"an absurd
value saturates a `DispatchTime` into `.distantFuture`, parking a thread
forever."* 3600 seconds is far from that boundary, but the check belongs in the
test rather than in a reader's confidence.

- [ ] **Step 1: Write the failing test**

```swift
/// The new ceiling, and that it is still a ceiling.
@Test func theAnswerDeadlineReachesAnHourAndStopsThere() {
    #expect(SocketClient.clamped(3600) == 3600)
    #expect(SocketClient.clamped(3601) == 3600)
    #expect(SocketClient.clamped(86_400) == 3600, "a day-long deadline was honoured")
    #expect(SocketClient.clamped(0.001) == 0.05)
}

/// An hour, converted the way the socket converts it, is still a real instant
/// and not `.distantFuture` — the saturation CLAUDE.md warns about.
@Test func anHourLongDeadlineIsAFiniteDispatchTime() {
    let t = DispatchTime.now() + SocketClient.clamped(3600)
    #expect(t < .distantFuture)
}
```

- [ ] **Step 2: Run, watch fail.** — [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the whole suite.** Every existing test asserting the `60`
      ceiling will fail; each one is either updated to `3600` or is asserting
      something this plan deliberately changed. **Read each before editing it** —
      a test that was pinning "a deadline cannot be absurd" still needs to pin
      that, at the new bound.
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
