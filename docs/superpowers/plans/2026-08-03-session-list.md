# Plan 5 — The Session List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build §11's session list as the drawer's second face, fill §9.1's hover reveal with the name and elapsed time it has always promised, and fix the 150pt sliver that shares that mechanism.

**Architecture:** The reveal and the sliver are one problem. `IslandBody` paints its silhouette as a **single** rect at `restingWidth + hoverRevealWidth` spanning the *whole* body height — and since Task 8 that height includes an open drawer, while `DrawerView` on top is hover-independent. Splitting that silhouette into a collapsed part (hover-coupled) and a drawer part (hover-independent) fixes the sliver *and* is the change that makes room for the reveal's content. The list itself is a new `DrawerFace` plus three presentational views, reading `Session` — which already carries every field §11 needs, so **nothing changes in `VibeCatCore`**.

**Tech Stack:** Swift 6, SwiftUI with AppKit interop, swift-testing, `ImageRenderer` for rendered assertions. No external dependencies.

## Global Constraints

- **Swift 6, macOS 14 floor, no external dependencies.** Do not add a package.
- **Fail-open (§2.3) is untouchable.** Nothing in this plan touches the socket, but no change may introduce an unbounded wait.
- **The notch is a hole (§5.1).** No content in the cutout's columns, ever. The list lives in the drawer, below the notch line.
- **Colour means state, and only state (§4.3).** Rows use `IslandState.accent` for state and `boneColour`/`hazeColour` for text. **No new hue.**
- **Text tones and type ladder come from Plan 4.5's tokens:** `boneColour` (#EDEFF4) primary, `hazeColour` (#8A93A6) secondary, `hairlineOpacity` (0.09) for dividers. Sizes from the prototype's ladder — 11, 11.5, 12.5 for list content.
- **The island must stay idle when the machine is idle.** The resting cost is ~12% of a core and that figure is already accepted; **this plan must not raise it.** Task 8 measures whether it did.
- **A test that cannot fail is not a test.** Before each assertion, name the production change that would break it. Rendered claims get rendered assertions via `rasterise`.
- **Every commit message states the insight, not the diff.** Keep the `Co-Authored-By:` trailer consistent with history.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/VibeCatUI/IslandView.swift` (modify) | Split the silhouette; add the reveal's content to the right flank |
| `Sources/VibeCatUI/RevealContent.swift` (create) | The hover reveal's name + elapsed line, and its elapsed formatter |
| `Sources/VibeCatUI/IslandGeometry.swift` (modify) | `DrawerFace.sessionList` at 420pt |
| `Sources/VibeCatUI/IslandModel.swift` (modify) | Which face the drawer shows; the sorted session list it reads |
| `Sources/VibeCatUI/Drawer/SessionRow.swift` (create) | §11's three lines for one session |
| `Sources/VibeCatUI/Drawer/SessionBlocks.swift` (create) | §11's Tasks and Agents blocks, and the collapse rule |
| `Sources/VibeCatUI/Drawer/SessionListFace.swift` (create) | The scrolling list, most urgent first |
| `Sources/VibeCatUI/Drawer/DrawerView.swift` (modify) | Route to whichever face the model names |
| `Sources/VibeCatCore/SessionStore.swift` (modify) | A most-urgent-first ordering |
| `Sources/VibeCatApp/BadgeCPUProbe.swift` (modify) | A multi-session row for Task 8's measurement |

---

## Task 1: Split the silhouette so hover stops widening the drawer

**Files:**
- Modify: `Sources/VibeCatUI/IslandView.swift` — `IslandBody.body`, the `.frame(width: restingWidth + hoverRevealWidth, height: body.height)` line and its two `.animation` modifiers
- Test: `Tests/VibeCatUITests/Drawer/DrawerGoldenTests.swift`

**Interfaces:**
- Consumes: `IslandBody.restingWidth`, `.hoverRevealWidth`, `model.drawerWidth`, `model.geometry.notch.height`, `IslandShape`, `IslandMotion.response/widthDamping`
- Produces: nothing new. `restingWidth`/`hoverRevealWidth` keep their names and their read-counters, so `IslandViewTests`' existing spring-wiring tests still apply.

**Why this is first:** it is a visible defect — a 150pt opaque rectangle over ~92% of the open drawer's height, appearing and disappearing with hover — and Task 2 puts content inside the same mechanism. Doing them in the other order means tuning twice.

- [ ] **Step 1: Write the failing test**

```swift
/// The sliver `theDrawersContentDoesNotShiftWhenOnlyHoverChanges` records as a
/// known residual: `IslandBody` paints one silhouette rect at the hover-coupled
/// width across the *whole* body height, and since Task 8 that height includes
/// an open drawer — while `DrawerView` on top is hover-independent. So hovering
/// paints 150pt of island ground down the right of the drawer.
///
/// What would have to break for this to fail: the assertion samples a column
/// that is outside the drawer's own width but inside the silhouette's
/// hover-widened one, at a y well below the notch line. With one rect it is
/// ground; with the silhouette split it is transparent.
@MainActor @Test func hoverDoesNotPaintASliverBesideTheOpenDrawer() throws {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.state = .idle
    model.sessionCount = 3
    model.question = QuestionModel(event: threeChoices(multi: false))
    model.drawerOpen = true
    model.hovering = true

    let raster = try rasterise(IslandView(model: model))
    let drawerRight = Int(model.drawerWidth.rounded(.up)) + 2
    let wellBelowTheNotch = Int(model.geometry.notch.height) + 60
    #expect(drawerRight < raster.width, "setup: the reveal must widen past the drawer for this to test anything")

    let sampled = raster[drawerRight, wellBelowTheNotch]
    #expect(sampled.isTransparent,
            "\(sampled) at column \(drawerRight), \(wellBelowTheNotch)pt down — that is beside the drawer, not part of it: the hover reveal is painting a sliver of island there")
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter hoverDoesNotPaintASliverBesideTheOpenDrawer`
Expected: FAIL, reporting the ground colour `#07080A@255` where transparency was required.

- [ ] **Step 3: Split the silhouette**

Replace the single `IslandShape()` fill in `IslandBody.body` with two, stacked. The collapsed part keeps the hover reveal; the drawer part does not.

```swift
// One silhouette rect could not express this once Task 8 made `body.height`
// include an open drawer: the reveal widens the collapsed island, and Plan 4
// deliberately made the drawer's own width hover-independent, so a single
// hover-coupled rect spanning both painted 150pt of ground down the right of
// the drawer. Two rects, each at its own width.
VStack(spacing: 0) {
    IslandShape()
        .fill(Color(islandGroundColour))
        .overlay(alignment: .topLeading) { content(cell: cell) }
        .clipShape(IslandShape())
        .frame(width: restingWidth + hoverRevealWidth,
               height: model.geometry.notch.height)
        .animation(.spring(response: IslandMotion.response,
                           dampingFraction: IslandMotion.widthDamping),
                   value: restingWidth)
        .animation(.easeInOut(duration: CollapsedLayout.hoverRevealDuration),
                   value: hoverRevealWidth)
    if model.drawerOpen {
        IslandShape()
            .fill(Color(islandGroundColour))
            .frame(width: model.drawerWidth,
                   height: max(0, body.height - model.geometry.notch.height))
    }
}
.shadow(color: Color(auraTint.colour)
            .opacity(model.aura.opacity(at: now, tint: auraTint)),
        radius: 18, x: 0, y: 2)
.offset(x: localOrigin.x, y: localOrigin.y)
```

The `.shadow` moves **outward**, onto the stack: §9.2 requires the aura to trace the whole rendered alpha "including the fillets", and it "follows the panel down for free when the drawer opens". Applied per-rect it would trace two separate shapes and draw a seam between them.

- [ ] **Step 4: Run the test, then the whole suite**

Run: `swift test --filter hoverDoesNotPaintASliverBesideTheOpenDrawer` → PASS
Run: `swift test` → all pass. Expect `theDrawersContentDoesNotShiftWhenOnlyHoverChanges` to now hold with a **much smaller** differing count than its `<= 30` allowance; tighten that allowance to `<= 10` and update its comment, since the residual it was tolerating is the thing this task removed.

- [ ] **Step 5: Look at it**

Run: `VIBECAT_CONTACT_SHEET=/tmp/sheet.png swift test --filter contactSheet` and open the PNG. Three plans shipped artwork nobody looked at; two of the three defects that found were invisible to a green suite.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/IslandView.swift Tests/VibeCatUITests/Drawer/DrawerGoldenTests.swift
git commit -m "fix: one silhouette rect could not carry two different widths"
```

---

## Task 2: Fill the hover reveal with §9.1's promised name and elapsed time

**Files:**
- Create: `Sources/VibeCatUI/RevealContent.swift`
- Modify: `Sources/VibeCatUI/IslandView.swift` — `content(cell:)`'s right flank
- Test: `Tests/VibeCatUITests/RevealContentTests.swift`

**Interfaces:**
- Consumes: `Session`, `boneColour`, `hazeColour`, `CollapsedLayout.hoverReveal`
- Produces:
  - `struct RevealContent: View { init(session: Session?, now: Date) }`
  - `static func RevealContent.elapsed(_ interval: TimeInterval) -> String`

**Design decision to record in the source:** elapsed is measured from `updatedAt`, not `startedAt`. §1's whole premise is "an agent that asked a question five minutes ago has been idle for five minutes" — time *in the current state* is the number that matters, not total session age.

- [ ] **Step 1: Write the failing test for the formatter**

```swift
/// The reveal has 150pt for a project name *and* a duration, so the duration
/// has to be short: "5m", never "5 minutes ago". Boundaries are the whole test
/// — a formatter that reads well at 90s and lies at 3600s is the usual failure.
@Test func elapsedIsCompactAtEveryBoundary() {
    #expect(RevealContent.elapsed(0) == "0s")
    #expect(RevealContent.elapsed(59) == "59s")
    #expect(RevealContent.elapsed(60) == "1m")
    #expect(RevealContent.elapsed(3599) == "59m")
    #expect(RevealContent.elapsed(3600) == "1h")
    #expect(RevealContent.elapsed(86_399) == "23h")
    #expect(RevealContent.elapsed(86_400) == "1d")
}

/// Never a negative or an absurd string from a clock that went backwards — the
/// hook's `now` and the app's are two different clocks, and a session whose
/// `updatedAt` is a moment in this render's future is not a bug worth showing
/// a person "-0s" over.
@Test func elapsedNeverGoesBackwards() {
    #expect(RevealContent.elapsed(-5) == "0s")
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter elapsedIsCompact`
Expected: FAIL to compile — `RevealContent` does not exist.

- [ ] **Step 3: Write `RevealContent`**

```swift
import SwiftUI
import VibeCatCore

/// §5.2's "name and timings on hover", and §9.1's reveal content — promised
/// since the design doc and, until Plan 5, revealed as 150pt of empty ground.
struct RevealContent: View {
    let session: Session?
    let now: Date

    /// Measured from `updatedAt`, not `startedAt`: §1's premise is that "an
    /// agent that asked a question five minutes ago has been idle for five
    /// minutes", so time *in the current state* is the number that matters.
    /// Clamped at zero because the hook's clock and this process's are not the
    /// same clock.
    static func elapsed(_ interval: TimeInterval) -> String {
        let s = Int(max(0, interval))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86_400 { return "\(s / 3600)h" }
        return "\(s / 86_400)d"
    }

    var body: some View {
        if let session {
            HStack(spacing: 6) {
                Text(session.project)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color(boneColour))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Self.elapsed(now.timeIntervalSince(session.updatedAt)))
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(Color(hazeColour))
            }
        }
    }
}
```

- [ ] **Step 4: Run the formatter tests**

Run: `swift test --filter elapsed` → PASS

- [ ] **Step 5: Write the failing rendered test**

```swift
/// The reveal must actually *reveal*: revealing nothing is the state this has
/// been in since Plan 2. Two renders differing only in `hovering`, and the
/// hovered one has to draw more.
@MainActor @Test func hoveringRevealsTheProjectNameAndElapsedTime() throws {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.state = .running
    model.sessionCount = 1
    model.revealed = Session(event: VibeEvent(id: "e", cli: "claude-code", kind: .running,
                                              session: "s", cwd: "/Users/dev/api"),
                             now: Date(timeIntervalSince1970: 1_000_000))

    model.hovering = false
    let atRest = try rasterise(IslandBody(model: model, now: Date(timeIntervalSince1970: 1_000_030)))
    model.hovering = true
    let hovered = try rasterise(IslandBody(model: model, now: Date(timeIntervalSince1970: 1_000_030)))

    #expect(hovered.pixelCount(near: boneColour) > atRest.pixelCount(near: boneColour) + 100,
            "hovering added only \(hovered.pixelCount(near: boneColour) - atRest.pixelCount(near: boneColour)) --bone pixels — the reveal is still empty ground")
}
```

- [ ] **Step 6: Run it, watch it fail, then wire it**

Run: `swift test --filter hoveringRevealsTheProjectNameAndElapsedTime` → FAIL (`model.revealed` does not exist).

Add to `IslandModel`:

```swift
/// The session the hover reveal names. §4.2's most urgent one, assigned by
/// `NotchController.render()` alongside `state` — the island reports the most
/// urgent session, so the reveal names that same one rather than a second
/// notion of "current".
public var revealed: Session?
```

Then in `IslandView.content(cell:)`'s right flank, inside the hover-revealed width:

```swift
RevealContent(session: model.revealed, now: now)
    .frame(width: model.hovering ? CollapsedLayout.hoverReveal : 0, alignment: .leading)
    .clipped()
    .opacity(model.hovering ? 1 : 0)
```

`.clipped()` is load-bearing: §5.1 forbids content in the cutout, and an unclipped `Text` at width 0 still paints.

- [ ] **Step 7: Run the whole suite, then look at the PNG**

Run: `swift test` → all pass
Run: `VIBECAT_CONTACT_SHEET=/tmp/sheet.png swift test --filter contactSheet`

- [ ] **Step 8: Commit**

```bash
git add Sources/VibeCatUI/RevealContent.swift Sources/VibeCatUI/IslandView.swift \
        Sources/VibeCatUI/IslandModel.swift Tests/VibeCatUITests/RevealContentTests.swift
git commit -m "feat: the hover reveal names the session it has been promising since Plan 2"
```

---

## Task 3: Stop `render()` notifying when nothing changed

**Files:**
- Modify: `Sources/VibeCatUI/NotchController.swift` — `render()`
- Test: `Tests/VibeCatUITests/NotchControllerTests.swift`

**Interfaces:**
- Consumes: `IslandModel.state`, `.sessionCount`, `.revealed`
- Produces: nothing new.

**Why now:** `@Observable` notifies on the *write*, not on a change, so `render()`'s unconditional assignments invalidate the body two or three times per hook event when nothing differs. Harmless at Plan 4's rates. Task 5 puts a scrolling list of rows on the other end of those invalidations, and Task 2 just added a third assigned property.

- [ ] **Step 1: Write the failing test**

```swift
/// `@Observable` notifies on the write, not on a change. `IslandView.buildCount`
/// cannot see this (the root view is assigned once — that is what that counter
/// exists to prove), so the observable read-counters are the instrument: a
/// second identical ingest must not touch the model at all.
@MainActor @Test func anIdenticalEventDoesNotRewriteTheModel() {
    let model = AppModel(socketPath: "/dev/null/unused.sock")
    let controller = NotchController(model: model, metrics: { IslandGoldenTests.mbp14 })
    let event = VibeEvent(id: "e", cli: "claude-code", kind: .running,
                          session: "s", cwd: "/Users/dev/api")
    model.ingest(event)
    controller.render()

    let before = (state: controller.model.state,
                  count: controller.model.sessionCount)
    IslandBody.restingWidthReadCount = 0
    controller.render()

    #expect(controller.model.state == before.state && controller.model.sessionCount == before.count,
            "setup: the second render must be a no-op in value terms")
    #expect(IslandBody.restingWidthReadCount == 0,
            "a re-render with nothing changed still invalidated the body \(IslandBody.restingWidthReadCount) times — @Observable notified on the write")
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter anIdenticalEventDoesNotRewriteTheModel`
Expected: FAIL with a non-zero read count.

- [ ] **Step 3: Guard each write**

```swift
// `@Observable` notifies on the write, not on a change, so an unconditional
// assignment invalidates the body even when the value is identical — two or
// three times per hook event. Harmless at Plan 4's rates; Plan 5 is what
// raises them, by putting a scrolling list on the other end.
if model.state != state { model.state = state }
if model.sessionCount != count { model.sessionCount = count }
if model.revealed != revealed { model.revealed = revealed }
```

- [ ] **Step 4: Run the test and the suite**

Run: `swift test --filter anIdenticalEventDoesNotRewriteTheModel` → PASS
Run: `swift test` → all pass

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatUI/NotchController.swift Tests/VibeCatUITests/NotchControllerTests.swift
git commit -m "perf: @Observable notifies on the write, so render() has to compare first"
```

---

## Task 4: `DrawerFace.sessionList` and the ordering it displays

**Files:**
- Modify: `Sources/VibeCatUI/IslandGeometry.swift` — `DrawerFace`
- Modify: `Sources/VibeCatCore/SessionStore.swift`
- Test: `Tests/VibeCatUITests/IslandGeometryTests.swift`, `Tests/VibeCatCoreTests/SessionStoreTests.swift`

**Interfaces:**
- Produces:
  - `DrawerFace.sessionList` with `height == 420`
  - `SessionStore.mostUrgentFirst: [Session]`

- [ ] **Step 1: Write both failing tests**

```swift
/// §6.3's table: "Session list — 420pt, rows scroll."
@Test func theSessionListFaceIsTheHeightTheDesignGivesIt() {
    #expect(DrawerFace.sessionList.height == 420)
}

/// §11: "Sort order defaults to most urgent first" — the same
/// `waiting > failed > running > idle` §4.2 gives the island, so the list and
/// the island agree about which session matters.
///
/// The fixture is deliberately in the *opposite* order and includes two
/// sessions of one state, because a sort that merely reverses, or one that is
/// unstable within a state, both satisfy a weaker assertion.
@Test func theListPutsTheMostUrgentSessionFirst() {
    var store = SessionStore()
    let now = Date(timeIntervalSince1970: 1_000_000)
    for (session, kind) in [("a", VibeEvent.Kind.idle), ("b", .running),
                            ("c", .running), ("d", .failed), ("e", .permission)] {
        store.apply(VibeEvent(id: session, cli: "claude-code", kind: kind,
                              session: session, cwd: "/tmp/\(session)"), now: now)
    }
    let order = store.mostUrgentFirst.map(\.id.session)
    #expect(order == ["e", "d", "b", "c", "a"],
            "got \(order) — expected waiting, failed, then the two running in the order they arrived, then idle")
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter theSessionListFaceIsTheHeight` and `--filter theListPutsTheMostUrgent`
Expected: both FAIL to compile.

- [ ] **Step 3: Implement**

In `DrawerFace`, add `case sessionList` and `case .sessionList: 420` to `height`. The enum is `CaseIterable`, so any exhaustive switch elsewhere becomes a compile error — fix those rather than adding a `default`.

In `SessionStore`:

```swift
/// §11: most urgent first, using §4.2's own ordering so the list and the
/// island never disagree about which session matters. A **stable** sort, so
/// two sessions of one state keep the order they arrived in rather than
/// shuffling on every render — `sorted(by:)` is not documented as stable, so
/// the index is part of the comparator rather than trusted to be preserved.
public var mostUrgentFirst: [Session] {
    sessions.enumerated()
        .sorted {
            $0.element.state.urgency == $1.element.state.urgency
                ? $0.offset < $1.offset
                : $0.element.state.urgency < $1.element.state.urgency
        }
        .map(\.element)
}
```

**`urgency` is *lower is more urgent*** — `waiting` is 0 and `idle` is 3, as
`SessionState`'s own comment says. So the comparator is `<`, not `>`. The first
draft of this plan had it backwards, which would have put the idle sessions on
top and passed any test that only checked "the order changed".

- [ ] **Step 4: Run both tests and the suite**

Run: `swift test` → all pass

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatUI/IslandGeometry.swift Sources/VibeCatCore/SessionStore.swift \
        Tests/VibeCatUITests/IslandGeometryTests.swift Tests/VibeCatCoreTests/SessionStoreTests.swift
git commit -m "feat: the list's order is the island's own, so the two cannot disagree"
```

---

## Task 5: `SessionRow` — §11's three lines

**Files:**
- Create: `Sources/VibeCatUI/Drawer/SessionRow.swift`
- Test: `Tests/VibeCatUITests/Drawer/SessionRowTests.swift`

**Interfaces:**
- Consumes: `Session`, `RevealContent.elapsed`, `boneColour`, `hazeColour`
- Produces:
  - `struct SessionRow: View { init(session: Session, now: Date, options: SessionRow.Options = .all) }`
  - `struct SessionRow.Options: OptionSet` with `.activity`, `.lastMessage`, `.tasks`, `.agents`, `.subagents`, and `.all`

**Why `Options` now:** §11 says "Every line is individually switchable in Settings". Settings is Plan 6, but the *switch points* have to exist here or Plan 6 rewrites this view. Defaults to `.all`, so nothing is user-visible yet.

- [ ] **Step 1: Write the failing tests**

```swift
private func session(_ state: VibeEvent.Kind, project: String = "api") -> Session {
    var e = VibeEvent(id: "e", cli: "claude-code", kind: state, session: "s",
                      cwd: "/Users/dev/\(project)")
    e.worktree = "auth-hardening"
    e.model = "Opus 4.8"
    e.effort = "high"
    e.title = "Asking to run"
    e.body = "rm -rf build/"
    return Session(event: e, now: Date(timeIntervalSince1970: 1_000_000))
}

/// §11's line 1 carries "Project, worktree, state" — and the state is carried
/// by colour (§4.3), so the row must paint the accent of the state it is in and
/// not of any other.
@MainActor @Test func theRowWearsItsOwnStatesAccent() throws {
    for (kind, state) in [(VibeEvent.Kind.permission, IslandState.waiting),
                          (.failed, .failed), (.running, .running)] {
        let raster = try rasterise(SessionRow(session: session(kind),
                                              now: Date(timeIntervalSince1970: 1_000_030))
            .frame(width: 388))
        #expect(raster.pixelCount(near: state.accent) > 0,
                "\(kind): no \(state) accent in the row at all")
        for other in IslandState.allCases where other != state && other != .dormant {
            #expect(raster.pixelCount(near: other.accent) == 0,
                    "\(kind): the row also painted \(other)'s accent — colour must mean one state")
        }
    }
}

/// §11's own switch points. Turning a line off has to remove ink, not merely
/// stop reading a property — the failure this catches is an `Options` that is
/// threaded through and then ignored by the view.
@MainActor @Test func turningALineOffRemovesItsInk() throws {
    let s = session(.permission)
    let now = Date(timeIntervalSince1970: 1_000_030)
    let all = try rasterise(SessionRow(session: s, now: now, options: .all).frame(width: 388))
    let bare = try rasterise(SessionRow(session: s, now: now, options: [])
        .frame(width: 388))
    #expect(bare.opaquePixelCount < all.opaquePixelCount,
            "switching every optional line off drew the same ink (\(bare.opaquePixelCount) against \(all.opaquePixelCount)) — Options is threaded through and then ignored")
    #expect(bare.opaquePixelCount > 0,
            "switching the optional lines off erased the row entirely — line 1 is not optional in §11")
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter theRowWearsItsOwnStatesAccent` → FAIL to compile.

- [ ] **Step 3: Write `SessionRow`**

```swift
import SwiftUI
import VibeCatCore

/// §11: three lines per row, most urgent information first.
///
/// ```
/// ✳  api  ⑂ auth-hardening                       Needs you ●
///    ▶ Asking to run rm -rf build/         iTerm2 · Opus 4.8 · high
///    │ clean the build and rebuild from scratch
/// ```
struct SessionRow: View {
    /// §11: "Every line is individually switchable in Settings." Settings is
    /// Plan 6; the switch points have to exist here or Plan 6 rewrites this
    /// view. Line 1 is deliberately not switchable — a row with no project and
    /// no state is not a row.
    struct Options: OptionSet, Sendable {
        let rawValue: Int
        static let activity = Options(rawValue: 1 << 0)
        static let lastMessage = Options(rawValue: 1 << 1)
        static let tasks = Options(rawValue: 1 << 2)
        static let agents = Options(rawValue: 1 << 3)
        /// §11: when Subagents are hidden the block collapses to a count rather
        /// than vanishing, "because approvals and questions from a child agent
        /// still need to surface".
        static let subagents = Options(rawValue: 1 << 4)
        static let all: Options = [.activity, .lastMessage, .tasks, .agents, .subagents]
    }

    let session: Session
    let now: Date
    var options: Options = .all

    private var accent: Color { Color(IslandState(session.state).accent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            headline
            if options.contains(.activity), let activity = session.activity {
                secondLine(activity)
            }
            if options.contains(.lastMessage), let asked = session.lastUserMessage {
                Text("│ \(asked)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(hazeColour))
                    .lineLimit(2)
            }
            SessionBlocks(session: session, options: options, accent: accent)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headline: some View {
        HStack(spacing: 6) {
            Circle().fill(accent).frame(width: 6, height: 6)
            Text(session.project)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color(boneColour))
            if let worktree = session.worktree {
                Text("⑂ \(worktree)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(hazeColour))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(IslandState(session.state).label)
                .font(.system(size: 11))
                .foregroundStyle(accent)
        }
    }

    private func secondLine(_ activity: String) -> some View {
        HStack(spacing: 6) {
            Text("▶ \(activity)")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color(boneColour))
                .lineLimit(1)
                // The same reasoning as the drawer's command body: the end of a
                // command is its target, so never elide the end.
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text([session.origin.app.map(originName), session.model, session.effort]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 11))
                .foregroundStyle(Color(hazeColour))
                .lineLimit(1)
        }
    }
}
```

**Two symbols this row needs do not exist yet — checked, not assumed.**
`IslandState` has only `init(store:)`, and no `label`. Add both to
`Sources/VibeCatUI/IslandState.swift`:

```swift
/// One session's own state, for a row in §11's list. `init(store:)` answers a
/// different question — what the *island* reports, which is the most urgent
/// session plus `dormant` for "no sessions at all". A row is never dormant:
/// a row exists, so a session exists.
public init(_ state: SessionState) {
    switch state {
    case .idle:    self = .idle
    case .running: self = .running
    case .waiting: self = .waiting
    case .failed:  self = .failed
    }
}

/// §11's line 1 ends with the state in words as well as in colour — "Needs
/// you ●". The words are not redundant with the dot: §4.3 reserves colour for
/// state precisely so it can be read at a glance from the corner of an eye,
/// and a list is the one place a person is already reading.
public var label: String {
    switch self {
    case .dormant: "—"
    case .idle:    "Idle"
    case .running: "Running"
    case .waiting: "Needs you"
    case .failed:  "Failed"
    }
}
```

`originName` is new too — a small bundle-id map local to `SessionRow.swift`
(`com.googlecode.iterm2` → `iTerm2`, `com.apple.Terminal` → `Terminal`,
`com.microsoft.VSCode` → `VS Code`), falling back to the last dot-component so
an unknown app degrades to something readable rather than to a raw identifier.

- [ ] **Step 4: Run the tests, then the suite**

Run: `swift test` → all pass

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatUI/Drawer/SessionRow.swift Sources/VibeCatUI/IslandState.swift \
        Tests/VibeCatUITests/Drawer/SessionRowTests.swift
git commit -m "feat: a session row says what it is doing and where it lives"
```

---

## Task 6: The Tasks and Agents blocks, and the collapse rule

**Files:**
- Create: `Sources/VibeCatUI/Drawer/SessionBlocks.swift`
- Test: `Tests/VibeCatUITests/Drawer/SessionBlocksTests.swift`

**Interfaces:**
- Consumes: `Session.tasks`, `Session.agents`, `SessionRow.Options`
- Produces:
  - `struct SessionBlocks: View { init(session: Session, options: SessionRow.Options, accent: Color) }`
  - `static func SessionBlocks.taskSummary(_ tasks: [TaskItem]) -> String`

- [ ] **Step 1: Write the failing tests**

```swift
/// §11: "The agent's own checklist, with a done/doing/open summary."
@Test func theTaskSummaryCountsEachStatusSeparately() {
    let tasks = [TaskItem(title: "a", status: .done),
                 TaskItem(title: "b", status: .doing),
                 TaskItem(title: "c", status: .open),
                 TaskItem(title: "d", status: .open)]
    #expect(SessionBlocks.taskSummary(tasks) == "1 done, 1 in progress, 2 open")
}

/// A summary that only ever reports totals would pass a weaker test. Zero of a
/// status must not be printed as "0 done" — that is noise on the majority of
/// real sessions.
@Test func theTaskSummaryOmitsStatusesWithNothingInThem() {
    #expect(SessionBlocks.taskSummary([TaskItem(title: "a", status: .open)]) == "1 open")
    #expect(SessionBlocks.taskSummary([]) == "")
}

/// §11, and this is the rule that matters most: "When Subagents are hidden the
/// block does not vanish — it collapses to `Agents · 2 running`, because
/// approvals and questions from a child agent still need to surface."
@MainActor @Test func hidingSubagentsCollapsesTheBlockRatherThanRemovingIt() throws {
    var e = VibeEvent(id: "e", cli: "claude-code", kind: .running, session: "s", cwd: "/tmp/api")
    e.agents = [AgentItem(name: "Explore (Search API endpoints)", elapsed: "8s", model: "Sonnet 4.6"),
                AgentItem(name: "Explore (Read config files)", elapsed: "Done", model: "Sonnet 4.6",
                          finished: true)]
    let s = Session(event: e, now: Date(timeIntervalSince1970: 1_000_000))
    let accent = Color(IslandState.running.accent)

    let shown = try rasterise(SessionBlocks(session: s, options: .all, accent: accent)
        .frame(width: 388))
    let collapsed = try rasterise(SessionBlocks(session: s, options: [.tasks, .agents], accent: accent)
        .frame(width: 388))

    #expect(collapsed.opaquePixelCount > 0,
            "hiding subagents erased the Agents block — §11 says it collapses to a count, because a child agent's question still has to surface")
    #expect(collapsed.opaquePixelCount < shown.opaquePixelCount,
            "hiding subagents changed nothing (\(collapsed.opaquePixelCount) against \(shown.opaquePixelCount)) — the option is ignored")
    #expect(collapsed.height < shown.height,
            "the collapsed block is the same height as the expanded one, so it is not collapsed")
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter theTaskSummary` → FAIL to compile.

- [ ] **Step 3: Write `SessionBlocks`**

```swift
import SwiftUI
import VibeCatCore

/// §11's two optional blocks under a session's own three lines.
struct SessionBlocks: View {
    let session: Session
    let options: SessionRow.Options
    let accent: Color

    /// §11's "1 done, 1 in progress, 2 open". Statuses with nothing in them are
    /// omitted rather than printed as a zero — most real sessions have only one
    /// or two of the three, and "0 done, 0 in progress, 3 open" is noise.
    static func taskSummary(_ tasks: [TaskItem]) -> String {
        let counts = [("done", TaskItem.Status.done),
                      ("in progress", .doing),
                      ("open", .open)]
        return counts
            .map { (label, status) in (label, tasks.count { $0.status == status }) }
            .filter { $0.1 > 0 }
            .map { "\($0.1) \($0.0)" }
            .joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if options.contains(.tasks), !session.tasks.isEmpty {
                blockHeader("Tasks", detail: Self.taskSummary(session.tasks))
                ForEach(Array(session.tasks.enumerated()), id: \.offset) { _, task in
                    taskLine(task)
                }
            }
            if options.contains(.agents), !session.agents.isEmpty {
                if options.contains(.subagents) {
                    blockHeader("Agents", detail: "\(session.agents.count)")
                    ForEach(Array(session.agents.enumerated()), id: \.offset) { _, agent in
                        agentLine(agent)
                    }
                } else {
                    // §11: collapsed, never absent.
                    let running = session.agents.count { !$0.finished }
                    blockHeader("Agents", detail: "\(running) running")
                }
            }
        }
    }

    private func blockHeader(_ title: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Text("┌ \(title)").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hazeColour))
            Text(detail).font(.system(size: 11)).foregroundStyle(Color(hazeColour))
        }
    }

    private func taskLine(_ task: TaskItem) -> some View {
        HStack(spacing: 6) {
            Text(marker(task.status)).font(.system(size: 11)).foregroundStyle(
                task.status == .doing ? accent : Color(hazeColour))
            Text(task.title)
                .font(.system(size: 11.5))
                .foregroundStyle(task.status == .done ? Color(hazeColour) : Color(boneColour))
                .strikethrough(task.status == .done)
                .lineLimit(1)
        }
    }

    /// `doing` takes the accent and the filled marker: §11's diagram shows `●`
    /// for in-progress against `☐`/`☑`, and the accent is already this session's
    /// state colour, so no new hue enters (§4.3).
    private func marker(_ status: TaskItem.Status) -> String {
        switch status {
        case .doing: "●"
        case .open:  "☐"
        case .done:  "☑"
        }
    }

    private func agentLine(_ agent: AgentItem) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text("● \(agent.name)").font(.system(size: 11.5))
                    .foregroundStyle(Color(boneColour)).lineLimit(1)
                Spacer(minLength: 8)
                Text("\(agent.elapsed) · \(agent.model)").font(.system(size: 11))
                    .foregroundStyle(Color(hazeColour)).lineLimit(1)
            }
            if let activity = agent.activity {
                Text("  └ \(activity)").font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(hazeColour)).lineLimit(1)
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests and the suite**

Run: `swift test` → all pass

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatUI/Drawer/SessionBlocks.swift Tests/VibeCatUITests/Drawer/SessionBlocksTests.swift
git commit -m "feat: hiding subagents collapses the block, because a child's question still has to surface"
```

---

## Task 7: `SessionListFace` and routing the drawer to it

**Files:**
- Create: `Sources/VibeCatUI/Drawer/SessionListFace.swift`
- Modify: `Sources/VibeCatUI/Drawer/DrawerView.swift`, `Sources/VibeCatUI/IslandModel.swift`
- Test: `Tests/VibeCatUITests/Drawer/SessionListFaceTests.swift`

**Interfaces:**
- Consumes: `SessionRow`, `SessionStore.mostUrgentFirst`, `DrawerFace.sessionList`
- Produces:
  - `struct SessionListFace: View { init(sessions: [Session], now: Date, options: SessionRow.Options = .all) }`
  - `IslandModel.sessions: [Session]` and `IslandModel.face: DrawerFace`

**The routing rule:** a pending question wins. §4.2's reasoning applies — a waiting agent is idling on you right now, so a question must never be buried under a list. `face` is `question.face` when there is a question, `.sessionList` otherwise.

- [ ] **Step 1: Write the failing tests**

```swift
/// §11's rows scroll inside §6.3's fixed 420pt. The failure this catches is a
/// list that grows the drawer instead of scrolling inside it — which would push
/// §6.4's reserved footer off the bottom.
@MainActor @Test func manySessionsScrollRatherThanGrowingTheDrawer() throws {
    func face(_ n: Int) throws -> Raster {
        let sessions = (0..<n).map { i in
            Session(event: VibeEvent(id: "e\(i)", cli: "claude-code", kind: .running,
                                     session: "s\(i)", cwd: "/tmp/p\(i)"),
                    now: Date(timeIntervalSince1970: 1_000_000))
        }
        return try rasterise(SessionListFace(sessions: sessions,
                                             now: Date(timeIntervalSince1970: 1_000_030))
            .frame(width: 388, height: DrawerFace.sessionList.height))
    }
    #expect(try face(2).height == try face(20).height,
            "twenty sessions rendered a different height than two — the list is growing the drawer instead of scrolling inside it")
}

/// A question must never be buried under a list — §4.2's own reasoning: a
/// waiting agent is idling on you right now.
@MainActor @Test func aPendingQuestionOutranksTheSessionList() {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.sessions = [Session(event: VibeEvent(id: "e", cli: "claude-code", kind: .running,
                                               session: "s", cwd: "/tmp/api"),
                              now: Date(timeIntervalSince1970: 1_000_000))]
    #expect(model.face == .sessionList, "with no question the drawer shows the list")

    model.question = QuestionModel(event: threeChoices(multi: false))
    #expect(model.face == .question,
            "a pending question was buried under the session list")
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter manySessionsScrollRatherThanGrowingTheDrawer` → FAIL to compile.

- [ ] **Step 3: Write `SessionListFace` and the routing**

```swift
import SwiftUI
import VibeCatCore

/// §11's list. Face-level only: the ordering is `SessionStore.mostUrgentFirst`'s
/// and the row is `SessionRow`'s, so this file owns nothing but the scroll and
/// the dividers.
struct SessionListFace: View {
    let sessions: [Session]
    let now: Date
    var options: SessionRow.Options = .all

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sessions) { session in
                    SessionRow(session: session, now: now, options: options)
                    if session.id != sessions.last?.id {
                        Rectangle()
                            .fill(Color.white.opacity(hairlineOpacity))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, QuestionFace.leadingPadding)
        }
        // §6.3: "420pt, rows scroll" — a fixed height with the content scrolling
        // inside it, never a height that follows the content. Growing would push
        // §6.4's reserved footer off the bottom.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollIndicators(.never)
    }
}
```

In `IslandModel`:

```swift
/// The sessions the list shows, in §11's order. Assigned by
/// `NotchController.render()` from `store.mostUrgentFirst`.
public var sessions: [Session] = []

/// Which face the drawer shows. A pending question always wins: §4.2's own
/// reasoning is that a waiting agent is idling on you *right now*, so a
/// question must never be buried under a list.
public var face: DrawerFace { question?.face ?? .sessionList }
```

**`IslandModel.tier` has to be restructured, not just repointed.** It currently
reads:

```swift
public var tier: IslandTier {
    guard drawerOpen, let question else { return hovering ? .hover : .rest }
    return .drawer(height: question.face.height)
}
```

That `let question` binding makes `.drawer` unreachable without a question — so
an open session list would silently stay at `.rest` and the panel would never
grow. Replace it with:

```swift
public var tier: IslandTier {
    guard drawerOpen else { return hovering ? .hover : .rest }
    return .drawer(height: face.height)
}
```

Nothing else changes: `face` is `question?.face ?? .sessionList`, so with a
question open this returns exactly what it returned before.

In `DrawerView`, replace the unconditional `QuestionFace` with a switch on the face, keeping the footer reservation outside it so both faces sit above the same 44pt.

- [ ] **Step 4: Run the tests, the suite, and look at it**

Run: `swift test` → all pass
Run: `VIBECAT_CONTACT_SHEET=/tmp/sheet.png swift test --filter contactSheet`, then open the PNG and check the list against §11's diagram line by line.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatUI/Drawer/SessionListFace.swift Sources/VibeCatUI/Drawer/DrawerView.swift \
        Sources/VibeCatUI/IslandModel.swift Tests/VibeCatUITests/Drawer/SessionListFaceTests.swift
git commit -m "feat: the drawer's second face, and a question still outranks it"
```

---

## Task 8: Measure several sprites, which is what Plan 5 was owed for

**Files:**
- Modify: `Sources/VibeCatApp/BadgeCPUProbe.swift`
- Modify: `docs/superpowers/spikes/2026-08-03-badge-transform-cost.md`

**Why:** the badge spike accepted ~12% of a core as the island's resting cost on the strength of a **single-sprite** measurement, and named "several sprites at once" as one of three things that would reopen the decision. Plan 5 is the first thing that produces several. The marginal cost of a second *animation* measured ~0.75pp, but several separate rows each with their own state dot is not the same experiment.

- [ ] **Step 1: Add a multi-session row to the probe**

After the existing `running` row, open the drawer on a session list of twelve sessions across all four states and sample it the same way:

```swift
// Plan 5's own owed measurement. The badge spike accepted ~12% on
// single-sprite numbers and named several sprites as a condition that would
// reopen it. Twelve sessions, all four states, drawer open.
controller.model.sessions = (0..<12).map { i in
    Session(event: VibeEvent(id: "e\(i)", cli: "claude-code",
                             kind: [.permission, .failed, .running, .idle][i % 4],
                             session: "s\(i)", cwd: "/tmp/p\(i)"),
            now: Date(timeIntervalSince1970: 1_000_000))
}
controller.model.state = .running
controller.model.sessionCount = 12
controller.model.drawerOpen = true
await row("+ session list open, 12 sessions across all four states")
```

- [ ] **Step 2: Build the release bundle and run it**

```bash
swift build -c release --product vibecat -Xswiftc -DDEBUG
# assemble and sign as Scripts/build-app.sh does, then:
open -n --stdout /tmp/plan5-cpu.log --stderr /tmp/plan5-cpu.log \
     .build/VibeCatRelease.app --args --badge-cpu-probe
```

`-Xswiftc -DDEBUG` is what makes the `#if DEBUG` probe exist in a release build, so the figure is comparable with the spike's release numbers rather than a debug artefact.

- [ ] **Step 3: Record the result honestly, whichever way it goes**

Add the row to the spike's table and answer its own open question in its own words. If the list costs another ~10pp, say so plainly and say that the accepted 12% no longer describes the product with a list open — that is a finding, not a failure. Note the probe's own noise floor (±1.5pp on the dormant row; anything under ~2pp is not measurable with it).

- [ ] **Step 4: Commit**

```bash
git add Sources/VibeCatApp/BadgeCPUProbe.swift docs/superpowers/spikes/2026-08-03-badge-transform-cost.md
git commit -m "docs: what several sessions actually cost, which Plan 5 owed the badge spike"
```

---

## Deliberately out of scope

Recorded so nobody adds them mid-plan, and so the next reader knows they were considered:

- **Settings for the per-line switches.** §11's switches exist as `SessionRow.Options` and default to `.all`. Wiring them to a control is §14, Plan 6.
- **Jump on click (§13).** A row that focuses its terminal needs AppleScript and the Automation permission — Plan 6.
- **§6.2's configurable right flank.** `CollapsedLayout.RightContent.agentIcon` is still constructed by nothing. The missing part is the *choosing*, which is a setting — Plan 6.
- **`lastUserMessage` is never populated.** §11's line 3 renders it when present, and no adapter sets it: Claude Code's hook payloads on this branch do not carry the user's own prompt. Wiring it needs an adapter change, and possibly a hook event we do not currently subscribe to — Plan 7's territory, and it should be checked against a real payload before anyone designs for it.
- **`Other…`, number keys, and the reveal's keyboard affordances.** Unblocked by the key-input spike but owned by Plan 6.

---

## Self-review

**Spec coverage.** §11's five line types → Tasks 5 and 6. Its switchability → `Options` in Task 5, with the Settings half explicitly deferred. Its subagent-collapse rule → Task 6. Its sort order → Task 4. §6.3's 420pt scrolling face → Tasks 4 and 7. §9.1's hover reveal content → Task 2. The sliver and `render()`'s writes → Tasks 1 and 3. The owed multi-sprite measurement → Task 8. **One §11 line has no working task and is called out above: `lastUserMessage` renders but nothing populates it.**

**Type consistency.** `SessionRow.Options` is named identically in Tasks 5, 6 and 7. `SessionBlocks.taskSummary` and `RevealContent.elapsed` are both `static` and used only as such. `IslandModel.revealed` (Task 2), `.sessions` and `.face` (Task 7) are the three properties `render()` assigns in Task 3 — and Task 3's guard covers `revealed`, so **Task 7 must extend that guard to `sessions` and `face` when it adds them.** Flagged here because Task 7's implementer would not otherwise see Task 3's code.

**Placeholders.** None. Every step carries the code it needs.

**What the first pass of this review got wrong**, checked against the source
rather than assumed, and fixed above — recorded because a plan that quietly
corrects itself teaches the next reader nothing:

1. **The sort was backwards.** `SessionState.urgency` is *lower is more urgent*
   (`waiting` 0 … `idle` 3). The comparator used `>`, which would have put idle
   sessions on top — and passed any test that only checked "the order changed",
   which is why Task 4's fixture asserts the exact array.
2. **`IslandState(session.state)` did not exist.** `IslandState` has only
   `init(store:)`, which answers a different question (what the *island* reports,
   including `dormant`). Task 5 now defines the per-session init it needs.
3. **`IslandModel.tier` could not open a drawer without a question.** Its
   `guard drawerOpen, let question` makes `.drawer` unreachable for a session
   list, so the panel would never have grown — the list would have rendered into
   a `.rest`-sized panel and been invisible. Task 7 now restructures the guard
   rather than "pointing it at `face`".

All three would have surfaced as a compile error or a failing test during
execution. Two of them — the sort direction and the tier guard — would have
surfaced as *wrong behaviour that still compiled*, which is the kind this
project keeps paying for.
