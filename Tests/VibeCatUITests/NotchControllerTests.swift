import Foundation
import Testing
import CoreGraphics
import SwiftUI
import VibeCatCore
@testable import VibeCatUI

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private let mbp14 = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
    safeAreaTop: 32,
    auxLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
    auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))

private let externalDisplay = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
    visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415),
    safeAreaTop: 0, auxLeft: nil, auxRight: nil)

/// A mutable box for the metrics closure below. A plain captured `var` works
/// at runtime, but Swift 6 flags "mutated after capture by sendable closure"
/// on a local var reassigned after an escaping closure captures it — even
/// though everything here runs on the main actor. A reference type sidesteps
/// the diagnostic: the closure captures the box itself, never reassigned;
/// only its stored property changes.
@MainActor private final class MetricsBox {
    var value: ScreenMetrics
    init(_ value: ScreenMetrics) { self.value = value }
}

@MainActor private func controller(_ metrics: @escaping @MainActor () -> ScreenMetrics?)
    -> (NotchController, AppModel) {
    let model = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    return (NotchController(model: model, metrics: metrics), model)
}

/// A controller with real geometry and a real panel already up — what every
/// test below needs before it can read `c.panel` or drive `setHovering`/
/// `setQuestion`/`click`. `AppModel` is discarded rather than returned:
/// these tests drive the state machine directly through `NotchController`'s
/// own entry points, deliberately bypassing `AppModel` — see `aQuestion`'s
/// own comment on why.
@MainActor private func makeController() -> NotchController {
    let (c, _) = controller { mbp14 }
    c.refreshGeometry()
    c.present()
    return c
}

@MainActor private var questionSerial = 0

/// A `PendingQuestion` to hand `setQuestion` directly. Not routed through
/// `AppModel.ingest` — that would park the calling thread inside
/// `PendingQuestion.await()` until answered or expired, which on the main
/// actor (every test here is `@MainActor`) is a deadlock, not a test. This is
/// also why `reflow()` reads `model.question` for the clicks rule rather
/// than `appModel.pending`: these tests never touch `AppModel` at all, so
/// only the model side is reachable from here.
@MainActor private func aQuestion(deadline: TimeInterval = 5) -> PendingQuestion {
    questionSerial += 1
    let event = VibeEvent(id: "q\(questionSerial)", cli: "claude-code", kind: .permission,
                          session: "s", cwd: "/tmp/proj",
                          choices: [Choice(id: "allow", label: "Allow once")],
                          wantsReply: true)
    return PendingQuestion(event: event, deadline: deadline)
}

@MainActor @Test func itAdoptsTheCurrentScreensGeometry() {
    let (c, _) = controller { mbp14 }
    c.refreshGeometry()
    #expect(c.geometry?.notch.width == 185)
    #expect(c.geometry?.isFallbackPill == false)
}

/// Design §16: recompute from the API, never cache across a display change.
@MainActor @Test func aDisplayChangeSwitchesToTheFallbackPill() {
    let current = MetricsBox(mbp14)
    let (c, _) = controller { current.value }
    c.refreshGeometry()
    #expect(c.geometry?.isFallbackPill == false)

    current.value = externalDisplay
    c.refreshGeometry()
    #expect(c.geometry?.isFallbackPill == true)
}

@MainActor @Test func noScreenAtAllLeavesTheControllerIdleRatherThanCrashing() {
    let (c, _) = controller { nil }
    c.refreshGeometry()
    #expect(c.geometry == nil)
    c.present()      // must not trap
    c.dismiss()
}

@MainActor @Test func theTierStartsAtRest() {
    let (c, _) = controller { mbp14 }
    #expect(c.tier == .rest)
}

/// The island tracks the store: an event moves it off dormant.
@MainActor @Test func ingestingAnEventDrivesTheControllersState() {
    let (c, model) = controller { mbp14 }
    c.refreshGeometry()
    #expect(model.islandState == .dormant)
    model.ingest(VibeEvent(id: "e1", cli: "claude-code", kind: .running,
                           session: "a", cwd: "/dev/a"), now: t0)
    #expect(model.islandState == .running)
}

/// `present()` wires `model.onChange` so the panel re-renders off the
/// model's own mutations rather than off a one-shot Observation bridge, and
/// `dismiss()` must clear it — otherwise a dismissed controller (or its
/// closure's captured state) could still react to events after the panel is
/// gone.
///
/// A bare `!= nil` / `== nil` check on the closure never proves it *does*
/// anything, and this closure being a no-op is exactly the defect that made
/// the whole app non-functional (events updating the store while the island
/// never redrew). Task 9 also fixes the panel's frame at its maximum for as
/// long as the island is collapsed (see `thePanelDoesNotResizeAsTheIslandGrows`
/// below), so unlike before Task 9, `panel.frame` no longer distinguishes
/// "wired" from "not wired" — it holds at the same value either way. This
/// asserts the property that can still be false: ingesting an event changes
/// `c.model`'s own state, and after `dismiss()` a further ingest does not.
@MainActor @Test func presentingWiresTheModelsOnChangeAndDismissingClearsIt() throws {
    let (c, model) = controller { mbp14 }
    #expect(model.onChange == nil)

    c.refreshGeometry()   // present() needs geometry to have somewhere to go
    c.present()
    #expect(model.onChange != nil)
    let panel = try #require(c.panelForTesting)

    // The panel is created once, at its widest possible collapsed frame —
    // built independently here, not read back off the controller, so this
    // doesn't compare the implementation to itself. Width only, with a
    // sub-point tolerance: a real NSPanel's `setFrame` aligns to the window
    // server's backing store, so a fractional input (the digit's measured
    // advance is ~8.117pt, not a whole number) comes back snapped rather
    // than bit-identical to the pure geometry maths — the same discrepancy
    // this test's pre-Task-9 version already discovered.
    let geometry = IslandGeometry(screen: mbp14)
    let maxFrame = geometry.maxCollapsedFrames().panel
    let afterPresent = panel.frame
    #expect(afterPresent.origin == maxFrame.origin)
    #expect(afterPresent.height == maxFrame.height)
    #expect(abs(afterPresent.width - maxFrame.width) < 1.0)
    #expect(c.model.sessionCount == 0)

    model.ingest(VibeEvent(id: "e1", cli: "claude-code", kind: .running,
                           session: "a", cwd: "/dev/a"), now: t0)
    // The wiring is real, not merely non-nil: the ingest reached c.model.
    #expect(c.model.sessionCount == 1)
    #expect(c.model.state == .running)
    // The panel — fixed at its maximum for as long as the island is
    // collapsed, Task 9's whole point — did not move for it. Compared
    // against its own prior frame, not re-derived, so this check has no
    // rounding tolerance to hide behind.
    #expect(panel.frame == afterPresent)

    c.dismiss()
    #expect(model.onChange == nil)

    // A second session would change model.sessionCount to 2, and thus
    // c.model.sessionCount, if anything were still listening. Nothing is:
    // c.model (kept alive here only because this test still holds `c`) must
    // not have moved — compared against its own prior value, not re-derived.
    model.ingest(VibeEvent(id: "e2", cli: "claude-code", kind: .running,
                           session: "b", cwd: "/dev/b"), now: t0)
    #expect(c.model.sessionCount == 1)
    #expect(panel.frame == afterPresent)
}

/// The spike's fourth finding: the hosting root must be assigned once, not
/// rebuilt per change.
///
/// `panel.contentView === first` is kept as one signal, but it is not the
/// whole proof: the pre-Task-9 code's dominant path, once a hosting view
/// already existed, was `hosting.rootView = view` — a fresh `IslandView`
/// assigned to an *existing* hosting view's `rootView`, leaving
/// `contentView`'s own identity completely untouched. A test that checks
/// only `contentView` would pass against exactly that regression. So this
/// also counts actual `IslandView` constructions via `IslandView.buildCount`
/// — reset to 0 here so ordering against other tests cannot make it flaky —
/// and asserts it stays at 1 across several ingests. That is the literal
/// constraint: the root is assigned once, not merely "the hosting view
/// object is the same."
@MainActor @Test func theHostingRootIsAssignedOnceAndSurvivesStateChanges() throws {
    IslandView.buildCount = 0
    let model = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    let c = NotchController(model: model, metrics: { mbp14 })
    c.refreshGeometry()
    c.present()
    #expect(IslandView.buildCount == 1)

    let panel = try #require(c.panelForTesting)
    let first = try #require(panel.contentView)
    // buildCount == 1 proves an IslandView was constructed; contentView ===
    // first (below) proves it did not later change. Neither proves it was
    // ever *installed* — `_ = IslandView(model: model)` with the result
    // discarded would pass both, leaving `contentView` as whatever AppKit's
    // NSPanel init assigned by default. This is what actually pins
    // installation.
    #expect(panel.contentView is NSHostingView<IslandView>)
    model.ingest(VibeEvent(id: "e1", cli: "claude-code", kind: .running,
                           session: "a", cwd: "/dev/a"), now: t0)
    model.ingest(VibeEvent(id: "e2", cli: "claude-code", kind: .permission,
                           session: "b", cwd: "/dev/b"), now: t0)
    #expect(panel.contentView === first, "the hosting view was replaced")
    #expect(IslandView.buildCount == 1, "IslandView was rebuilt instead of the model being mutated")
    c.dismiss()
}

/// The panel is created once at its widest and never resized while collapsed.
@MainActor @Test func thePanelDoesNotResizeAsTheIslandGrows() throws {
    let model = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    let c = NotchController(model: model, metrics: { mbp14 })
    c.refreshGeometry()
    c.present()

    let panel = try #require(c.panelForTesting)
    let before = panel.frame
    model.ingest(VibeEvent(id: "e1", cli: "claude-code", kind: .running,
                           session: "a", cwd: "/dev/a"), now: t0)
    #expect(panel.frame == before, "the panel resized; content should animate instead")
    c.dismiss()
}

/// The controller's model must actually track the app model.
@MainActor @Test func ingestingAnEventUpdatesTheIslandModel() {
    let model = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    let c = NotchController(model: model, metrics: { mbp14 })
    c.refreshGeometry()
    c.present()
    #expect(c.model.state == .dormant)
    model.ingest(VibeEvent(id: "e1", cli: "claude-code", kind: .running,
                           session: "a", cwd: "/dev/a"), now: t0)
    #expect(c.model.state == .running)
    #expect(c.model.sessionCount == 1)
    c.dismiss()
}

/// The region the aura's backdrop is measured from covers the menu bar strip
/// and stops there.
///
/// The first version used the panel's height, which runs `auraMargin` past the
/// bottom of the island into whatever window is below the bar. On this machine
/// that window was at luminance 236 against a menu bar at 27, and it was 41% of
/// the sampled area — enough to carry the mean over the threshold, so the
/// sampler reported `.light` while the bar behind the island was black. The
/// aura then deepened when it should have brightened, which is the exact fault
/// the sampler was added to fix.
@MainActor @Test func theBackdropRegionStopsAtTheMenuBar() {
    let (c, _) = controller({ mbp14 })
    c.refreshGeometry()
    let region = c.backdropRegion()
    let frames = c.model.frames

    #expect(region.height == frames.body.height,
            "the sampled strip is \(region.height)pt tall against a \(frames.body.height)pt island — it reaches past the menu bar into whatever is below it")
    #expect(region.height < frames.panel.height,
            "the sampled strip is the whole panel, aura margin included")
    // Width follows the panel: the glow spreads sideways, and the surface it
    // spreads onto is part of the question.
    #expect(region.width == frames.panel.width)
    // ScreenCaptureKit's origin is top-left; AppKit's is bottom-left. Getting
    // this backwards would sample the bottom of the screen.
    #expect(region.minY == mbp14.frame.maxY - frames.body.maxY)
    #expect(region.minY == 0, "the island is at the top of the screen, so the strip starts at row 0")
}

/// The property `theBackdropRegionStopsAtTheMenuBar` above pins, at the one
/// tier that could newly break it: `model.frames`/`model.panelFrames` now
/// grow with an open drawer (`IslandModel.tier`), so `backdropRegion()` has
/// to recompute its own `.rest`-tiered frame rather than read `model.frames`
/// directly, or the aura would start sampling down through the drawer's own
/// screen area the moment one was open — reintroducing the exact
/// too-tall-a-strip bug the type-level comment above already describes once.
@MainActor @Test func theBackdropRegionStaysAtTheMenuBarEvenWithTheDrawerOpen() {
    let c = makeController()
    c.setQuestion(aQuestion())
    c.click()
    #expect(c.model.tier != .rest, "the drawer never actually opened, so this test proves nothing")

    let region = c.backdropRegion()
    // Independently recomputed at .rest, not read off c.model.frames (which
    // is deliberately tier-aware now) — this is the collapsed body's own
    // height, whatever the drawer is doing.
    let collapsedHeight = IslandGeometry(screen: mbp14).frames(rightFlank: 0, tier: .rest).body.height
    #expect(region.height == collapsedHeight,
            "the sampled strip is \(region.height)pt tall with the drawer open, against \(collapsedHeight)pt at rest — it reached into the drawer")
}

// MARK: - Task 8: click to open, and the round trip end to end

/// The rule from "The panel takes mouse events only when there is something to
/// open". Both halves matter: a permanently clickable island swallows menu bar
/// clicks, and an island that never takes them cannot be answered.
@MainActor @Test func thePanelTakesClicksOnlyWhenHoveredWithAQuestionWaiting() throws {
    let c = makeController()
    let panel = try #require(c.panelForTesting)

    c.setHovering(false); c.setQuestion(nil)
    #expect(panel.acceptsClicks == false)
    c.setHovering(true); c.setQuestion(nil)
    #expect(panel.acceptsClicks == false, "hovering an island with nothing to open swallowed a menu bar click")
    c.setHovering(false); c.setQuestion(aQuestion())
    #expect(panel.acceptsClicks == false, "a question the pointer is nowhere near swallowed a menu bar click")
    c.setHovering(true); c.setQuestion(aQuestion())
    #expect(panel.acceptsClicks)
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
    let panel = try #require(c.panelForTesting)

    c.setQuestion(aQuestion(deadline: 0.05))
    c.click()
    #expect(c.model.tier != .rest)
    // Polled, not a single fixed sleep: the lapse Task's own 50ms sleep
    // finishes on schedule regardless, but its continuation still has to be
    // scheduled onto Swift's small shared cooperative pool, which every
    // other concurrently-running test in a full-suite run is also
    // contending for — confirmed directly: a single 400ms sleep here passed
    // every filtered run but failed a full-suite run with `tier` still
    // `.drawer`. Loose 2s ceiling, same shape as this codebase's other
    // cross-thread waits (e.g. PipelineTests.waitUntil).
    let ceiling = Date().addingTimeInterval(2)
    while c.model.tier != .rest, Date() < ceiling {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(c.model.tier == .rest, "the drawer is still showing a question the hook has abandoned")
    #expect(panel.acceptsClicks == false)
}

/// Whole-branch review minor: `setQuestion`'s lapse `Task` calls
/// `appModel.dismissQuestion()` once its own sleep elapses, which — without
/// the `currentPending` identity guard this pins — lapses whatever question
/// happens to be current at that moment, not necessarily the one the Task
/// was scheduled for. `lapseCheck?.cancel()` already retires a displaced
/// question's Task immediately in the ordinary flow, so this test alone
/// cannot distinguish "the guard saved this" from "the cancellation already
/// did" — both present, this passes either way. Confirmed directly:
/// disabling `cancel()` *and* the guard together reproduced the bug (the
/// second question dismissed ~0.1s early, `appModel.pending` going back to
/// `nil`); re-enabling only the guard, with `cancel()` still disabled,
/// stayed green — the guard alone is sufficient.
///
/// The guard compares against `currentPending` (`NotchController`'s own
/// bookkeeping, updated by `setQuestion` itself), not `appModel.pending` —
/// an earlier version of this fix used `appModel.pending` directly and it
/// broke `aLapsedQuestionClosesTheDrawer` above: that test, like most in
/// this file, drives `setQuestion(_:)` directly rather than through a real
/// `AppModel`, so `appModel.pending` never matches `pending` there and the
/// guard would silently swallow every lapse this file's own tests exist to
/// prove happens.
@MainActor @Test func aDisplacedQuestionsLapseCheckNeverDismissesTheReplacement() async throws {
    let (c, appModel) = controller { mbp14 }
    c.refreshGeometry()
    c.present()

    let short = VibeEvent(id: "q-short", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                          choices: [Choice(id: "allow", label: "Allow")],
                          wantsReply: true, answerDeadline: 0.1)
    Thread.detachNewThread { _ = appModel.ingest(short) }
    let arrivedShort = Date().addingTimeInterval(2)
    while appModel.pending?.id != "q-short", Date() < arrivedShort {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(appModel.pending?.id == "q-short", "setup: the first question never reached the model")

    // Displace it with a second, longer-lived question well before the
    // first's own 0.1s deadline elapses.
    let long = VibeEvent(id: "q-long", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                         choices: [Choice(id: "allow", label: "Allow")],
                         wantsReply: true, answerDeadline: 5)
    Thread.detachNewThread { _ = appModel.ingest(long) }
    let arrivedLong = Date().addingTimeInterval(2)
    while appModel.pending?.id != "q-long", Date() < arrivedLong {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(appModel.pending?.id == "q-long", "setup: the second question never displaced the first")

    // Long enough for the first question's own 0.1s deadline to have
    // elapsed, whether or not its lapse Task was actually cancelled.
    try await Task.sleep(for: .milliseconds(400))
    #expect(appModel.pending?.id == "q-long",
            "the first question's own lapse check dismissed the second, unrelated question")
    c.dismiss()
}

/// `drawerOpen` must not survive past the question it was opened for.
/// Otherwise a *second*, later question inherits the first one's "clicked
/// open" and appears already open — the same violation
/// `aQuestionDoesNotOpenTheDrawerOnItsOwn` exists to catch for a single
/// question, but reachable a different way: not by opening a drawer with no
/// question, but by a new question arriving after an old, already-opened one
/// closed. None of the three tests the brief itself gives ever sets a
/// *second* question after answering or lapsing the first, so this gap
/// survived unnoticed until mutated: deleting `setQuestion`'s
/// `if pending == nil { model.drawerOpen = false }` left every test above
/// green.
@MainActor @Test func aNewQuestionDoesNotInheritAnOlderOnesOpenDrawer() {
    let c = makeController()
    c.setQuestion(aQuestion())
    c.click()
    #expect(c.model.tier != .rest, "the drawer never opened, so this test proves nothing")

    c.setQuestion(nil)                // answered or dismissed
    c.setQuestion(aQuestion())        // a second, later question arrives
    #expect(c.model.tier == .rest,
            "a new question inherited the previous one's open drawer")
}

/// "When the tier changes, re-apply the panel frame" — the actual, live
/// `NSPanel`, not merely `model.tier`'s own value. Every assertion above
/// reads `c.model.tier`, which is computed straight off `drawerOpen`/
/// `question`/`hovering` and would report `.drawer` correctly even if
/// nothing ever touched the real panel — confirmed by mutating the
/// resize-comparison in `reflow()` to never call `panel.apply(_:)` at all
/// and finding the whole suite still green. This is the test that actually
/// exercises the panel.
@MainActor @Test func thePanelGrowsWhenTheDrawerOpensAndShrinksWhenItCloses() throws {
    let c = makeController()
    let panel = try #require(c.panelForTesting)
    let collapsedFrame = panel.frame

    c.setQuestion(aQuestion())
    c.click()
    #expect(c.model.tier != .rest, "the drawer never opened, so this test proves nothing")
    #expect(panel.frame.height > collapsedFrame.height,
            "the live panel did not grow to cover the open drawer")
    #expect(panel.frame.width == collapsedFrame.width,
            "the panel resized sideways — the drawer should only ever grow it downward")
    #expect(panel.frame.minX == collapsedFrame.minX,
            "the left edge moved — design §5.3's one fixed invariant")

    c.setQuestion(nil)
    #expect(panel.frame == collapsedFrame,
            "the panel did not shrink back to its collapsed size once the drawer closed")
}

/// Finding 3 of the final whole-branch review: `reflow()`'s `hover?.frame =
/// model.frames.body` is the one line that makes the drawer clickable at
/// all. `acceptsClicks = model.hovering && model.question != nil`, and
/// `model.hovering` only ever flips true because `HoverMonitor.sample()`
/// finds the cursor inside `hover.frame` — so if that rect stayed pinned to
/// the collapsed body alone, moving the cursor down from the island onto a
/// drawer row would fall outside it, `hovering` would clear, and the drawer
/// would go click-through while still open and still unanswered. Nothing
/// before this test read `hover.frame` at all; pinning `reflow()`'s
/// assignment to a `.rest`-tiered frame (confirmed below) left every
/// existing test green.
///
/// The expected height is derived independently — the notch's own height
/// plus the open question's face height, the same arithmetic
/// `IslandGeometry.frames` uses for `body.height` at the `.drawer` tier —
/// rather than read back off `c.model.frames.body` itself, which is exactly
/// the value under test.
@MainActor @Test func theHoverRectGrowsToCoverTheOpenDrawer() throws {
    let c = makeController()
    let hover = try #require(c.hoverForTesting)
    let geometry = try #require(c.geometry)

    let question = aQuestion()
    let restHeight = hover.frame.height
    #expect(restHeight == geometry.notch.height,
            "setup: the hover rect should start at the collapsed body's own height")

    c.setQuestion(question)
    c.click()
    #expect(c.model.tier != .rest, "setup: the drawer never opened, so this test proves nothing")

    let expected = geometry.notch.height + QuestionModel(event: question.event).face.height
    #expect(hover.frame.height == expected,
            "hover.frame is \(hover.frame.height)pt tall with the drawer open, expected \(expected) — moving the cursor onto a row would clear hovering and make the drawer click-through")
}

// MARK: - Fix round 1: wiring the click

/// `model.onIslandClick` is what a real tap on the collapsed island would
/// invoke (`IslandBody`'s own `.onTapGesture`, untestable directly — see
/// this test's own use of the callback instead of a synthesised `NSEvent`).
/// This confirms `present()` actually wires it to `click()`, the same way
/// `presentingWiresTheModelsOnChangeAndDismissingClearsIt` confirms
/// `appModel.onChange` reaches `reflow()`.
@MainActor @Test func theIslandClickCallbackReachesClick() {
    let c = makeController()
    c.setQuestion(aQuestion())
    #expect(c.model.tier == .rest, "setup: a question alone must not open the drawer")

    c.model.onIslandClick?()

    #expect(c.model.tier != .rest, "model.onIslandClick did not reach click()")
}

/// Finding 4 of the final whole-branch review: `click()` used to set
/// `model.drawerOpen = true` unconditionally, so the only way to close an
/// opened drawer was `dismissOnEscape` — and that depends on the panel
/// becoming key, Task 9's own still-open hardware question. A second click
/// now closes the drawer again, and a third reopens it — but it must not
/// touch the underlying question at all: closing the drawer this way is not
/// the same decision as Escape's deliberate, fail-open dismiss, so the
/// question stays parked rather than being lapsed early just because a
/// person clicked the island twice.
@MainActor @Test func clickTogglesTheDrawerOpenAndClosedWithoutAnsweringOrDismissing() {
    let c = makeController()
    c.setQuestion(aQuestion())
    #expect(c.model.tier == .rest, "setup: a question alone must not open the drawer")

    c.click()
    #expect(c.model.tier != .rest, "the first click must open the drawer")

    c.click()
    #expect(c.model.tier == .rest, "the second click must close the drawer again")
    #expect(c.model.question != nil,
            "a second click discarded the question instead of merely closing the drawer")

    c.click()
    #expect(c.model.tier != .rest, "a third click did not reopen the same, still-pending question")
}

/// `dismiss()` must clear `onIslandClick` the same way it already clears
/// `appModel.onChange`/`.onQuestion` — otherwise a click reaching a stale
/// closure after the controller is torn down would still mutate `model`
/// (harmless here only because `model` itself is retained by this test, not
/// because the wiring is correct).
@MainActor @Test func dismissClearsTheIslandClickCallback() {
    let c = makeController()
    c.dismiss()
    #expect(c.model.onIslandClick == nil)
    #expect(c.model.onAnswer == nil)
}

/// `model.onAnswer` is what a real tap on a drawer row/Send would invoke
/// (`QuestionFace.tapped(_:)`/`.sendTapped()`, see `QuestionFaceTests`).
/// This confirms `present()` wires it all the way to `appModel.answer(_:)` —
/// checked via `appModel.pending` actually clearing, which only `.answer(_:)`
/// resolving a *real*, id-matched question can do. `AppModel.ingest` parks
/// its calling thread until answered, so it runs on a real `Thread` here
/// (mirroring `PipelineTests`' own end-to-end tests), never `Task.detached`.
@MainActor @Test func theAnswerCallbackReachesAppModelAnswer() async throws {
    let (c, appModel) = controller { mbp14 }
    c.refreshGeometry()
    c.present()

    let event = VibeEvent(id: "q-onanswer", cli: "claude-code", kind: .permission,
                          session: "s", cwd: "/tmp/proj",
                          choices: [Choice(id: "allow", label: "Allow once")],
                          wantsReply: true, answerDeadline: 5)
    Thread.detachNewThread { _ = appModel.ingest(event) }

    let arrived = Date().addingTimeInterval(2)
    while appModel.pending == nil, Date() < arrived {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(appModel.pending?.id == "q-onanswer", "the question never reached the model")

    c.model.onAnswer?(Reply(id: "q-onanswer", choice: "allow"))

    let resolved = Date().addingTimeInterval(2)
    while appModel.pending != nil, Date() < resolved {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(appModel.pending == nil,
            "model.onAnswer did not reach appModel.answer — the question is still parked")
    c.dismiss()
}

// MARK: - Task 9: Escape dismisses; number keys wait on the hardware question

/// Finding 4 of the final whole-branch review: every behavioural Escape test
/// below drives `dismissOnEscape(_:)` directly, which is correct — there is
/// no window server in `swift test` to deliver a real `NSEvent` — but that
/// also means none of them notice if `present()` stopped installing the
/// monitor that would ever call it for a real keystroke. Deleting that
/// installation block failed no test before this one. `dismiss()` must
/// remove it for the same reason it removes the screen-parameters observer
/// just above it in `NotchController.swift` — a monitor left behind after
/// teardown would keep calling into a controller nothing else references.
@MainActor @Test func presentInstallsTheEscapeMonitorAndDismissRemovesIt() {
    let c = makeController()
    #expect(c.escapeMonitorForTesting != nil, "present() did not install the local Escape monitor")

    c.dismiss()
    #expect(c.escapeMonitorForTesting == nil, "dismiss() did not remove the local Escape monitor")
}

/// Escape while the drawer is open dismisses the question without answering
/// it. Driven directly through `dismissOnEscape`, the same way
/// `QuestionFaceTests` calls `tapped(_:)` directly rather than through a
/// synthesised `NSEvent` — there is no window server in `swift test`, and
/// this is exactly what a real Escape `keyDown` would eventually call (see
/// `present()`'s own local monitor installation).
@MainActor @Test func escapeDismissesTheOpenDrawerWithoutAnswering() {
    let c = makeController()
    c.setQuestion(aQuestion())
    c.click()
    #expect(c.model.tier != .rest, "setup: the drawer never opened, so this test proves nothing")

    let consumed = c.dismissOnEscape(charactersIgnoringModifiers: "\u{1b}")

    #expect(consumed, "Escape must report the keystroke as handled while the drawer is open")
    #expect(c.model.tier == .rest, "Escape did not close the drawer")
}

@MainActor @Test func escapeDoesNothingWhileTheDrawerIsClosed() {
    let c = makeController()
    #expect(c.model.tier == .rest, "setup: nothing should be open yet")

    let consumed = c.dismissOnEscape(charactersIgnoringModifiers: "\u{1b}")

    #expect(consumed == false, "there is nothing to dismiss, so this must not report the keystroke as handled")
}

/// A non-Escape key must never dismiss — and, per Task 9's own still-open
/// hardware question, must not do anything else either. Number keys are not
/// wired at all this round (see `dismissOnEscape`'s own doc comment on why
/// Escape alone is safe to wire before that question is answered), so a
/// digit reaching this same entry point must be a complete no-op.
@MainActor @Test func aNonEscapeKeyNeverDismissesEvenWithTheDrawerOpen() {
    let c = makeController()
    c.setQuestion(aQuestion())
    c.click()
    #expect(c.model.tier != .rest, "setup: the drawer never opened, so this test proves nothing")

    let consumed = c.dismissOnEscape(charactersIgnoringModifiers: "1")

    #expect(consumed == false, "a number key must not be reported as handled")
    #expect(c.model.tier != .rest, "a number key must not have closed the drawer either")
}

/// The full real path, mirroring `theAnswerCallbackReachesAppModelAnswer`'s
/// own pattern: a genuinely parked `PendingQuestion` actually unblocks with a
/// `nil` reply when Escape dismisses it — the same fail-open guarantee
/// Task 1/3 already cover for a lapse, reached here through
/// `dismissOnEscape` instead of a timeout, and via `appModel.dismissQuestion()`
/// rather than a second, ad-hoc "close the drawer" mechanism.
@MainActor @Test func escapeFailsOpenTheSameWayALapseDoes() async throws {
    let (c, appModel) = controller { mbp14 }
    c.refreshGeometry()
    c.present()

    let event = VibeEvent(id: "q-escape", cli: "claude-code", kind: .permission,
                          session: "s", cwd: "/tmp/proj",
                          choices: [Choice(id: "allow", label: "Allow once")],
                          wantsReply: true, answerDeadline: 5)
    Thread.detachNewThread { _ = appModel.ingest(event) }

    let arrived = Date().addingTimeInterval(2)
    while appModel.pending == nil, Date() < arrived {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(appModel.pending?.id == "q-escape", "the question never reached the model")
    c.click()
    #expect(c.model.tier != .rest, "setup: the drawer never opened, so this test proves nothing")

    c.dismissOnEscape(charactersIgnoringModifiers: "\u{1b}")

    let resolved = Date().addingTimeInterval(2)
    while appModel.pending != nil, Date() < resolved {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(appModel.pending == nil,
            "Escape did not reach appModel.dismissQuestion — the question is still parked")
    #expect(c.model.tier == .rest, "Escape did not close the drawer")
    c.dismiss()
}

// MARK: - Task 3 (Plan 5): characterizing @Observable's own dedupe

/// Characterizes a fact about this toolchain's `@Observable` macro, pinned
/// here because a later task's correctness (and `render()`'s own shape)
/// silently depends on it: an assignment to an `Equatable`-conforming
/// `@Observable` property that does not actually change the value never
/// notifies observers. Confirmed directly (`-Xfrontend
/// -dump-macro-expansions`): the macro's generated setter guards
/// `withMutation` behind `shouldNotifyObservers(old, new)`, which resolves
/// (by overload) to `old != new` for any `Equatable` type — which
/// `IslandState`, `Int`, and `Session?` all are. This is why `render()`'s
/// `model.state`/`model.sessionCount`/`model.revealed` assignments below are
/// plain, unguarded writes rather than the explicit `if old != new` checks an
/// earlier version of this task added: the macro already does that check, and
/// duplicating it only misleads a future reader into thinking `render()`
/// needs to.
///
/// The opposite dependency lives right below `render()`'s three assignments:
/// the `bloomEnd` Task's `self?.model.aura = self?.model.aura ?? AuraTrigger()`
/// nudge exists specifically to force a notification once a bloom ends, and
/// `AuraTrigger` is *also* `Equatable` — so that reassignment is exactly the
/// "equal write" this test pins as a no-op, meaning the nudge is currently
/// dead code on this toolchain. Task 3.5 owns fixing that; this test is the
/// fact both sides of that disagreement stand on. If this test ever starts
/// failing, the macro stopped deduplicating and the nudge silently starts
/// working again; as long as it keeps passing, the nudge needs its own fix.
@MainActor @Test func anEqualWriteToAnObservablePropertyDoesNotNotify() {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(systemWantsReduced: false))

    // `nonisolated(unsafe)`, not a plain `var`: `withObservationTracking`'s
    // `onChange` is `@Sendable`, so it cannot capture a mutable local without
    // this — the same "Swift 6 flags a capture the main actor makes
    // perfectly safe" situation `MetricsBox` above exists for, just on a
    // local rather than a stored property. Safe here for the same reason:
    // everything in this function runs on the main actor, and `onChange`
    // fires synchronously within the same call, never on another thread
    // concurrently with the read below.
    func fires(_ body: () -> Void) -> Bool {
        nonisolated(unsafe) var fired = false
        withObservationTracking {
            _ = model.state
        } onChange: {
            fired = true
        }
        body()
        return fired
    }

    // Each flag is read immediately after its own mutation, not at the end of
    // the test. A `withObservationTracking` registration is one-shot, but
    // it's only *consumed* by a write that actually notifies — an equal
    // write leaves it armed, still listening for the next real change. A
    // first version of this investigation read every flag at the end of the
    // test, after a later, genuinely different write, and got
    // `equalWrite == true`: not evidence @Observable had stopped
    // deduplicating, but that later write retroactively tripping a
    // registration the equal write never consumed.

    // Positive control: a genuinely different value must fire, or the
    // equal-write assertion below would pass just as well against a broken
    // instrument that never fires at all.
    #expect(fires { model.state = .running },
            "a write that changed the value did not notify — the instrument is broken, so the equal-write assertion below would be vacuous")

    #expect(!fires { model.state = .running },
            "an equal write still notified — @Observable no longer deduplicates identical writes on this toolchain, which both render()'s plain assignments and the bloomEnd nudge's opposite assumption depend on")
}

/// The bug itself, at the level it actually bites: a still mood with a bloom in
/// flight needs a timeline, and must stop needing one the moment the bloom ends.
/// Nothing asserted this before, which is why an 8fps timeline could run forever.
@MainActor @Test func aStillMoodStopsNeedingATimelineOnceTheBloomEnds() {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.state = .dormant
    let now = Date()
    _ = model.aura.observe(.dormant, now: now)
    // `== true`, same swift-testing macro limitation `aChangeFires` documents
    // in AuraTriggerTests.swift: #expect's diagnostic expansion for a direct
    // method call captures the receiver by `let`, which cannot host a
    // mutating call.
    #expect(model.aura.observe(.idle, now: now) == true, "setup: a real change must bloom")
    model.state = .idle
    #expect(!model.activeProfile.isContinuous,
            "setup: idle's mood must be still, or this tests the wrong branch")
    #expect(model.needsTimeline, "setup: a bloom in flight needs a timeline")

    model.aura.endBloom()

    #expect(!model.needsTimeline,
            "the island still wants a timeline after the bloom ended — this is ~3.3% of a core running forever in the state §6.1 says must look idle")
}

/// Closes link 2 of endBloom()'s fix chain, which nothing above measures:
/// `aStillMoodStopsNeedingATimelineOnceTheBloomEnds` only proves the *value*
/// of `needsTimeline` ends up correct — it reads a plain computed property,
/// which recomputes fresh regardless of whether any notification ever fired.
///
/// First draft of this test assumed a mutating method call through an
/// `@Observable` property is gated the same way `anEqualWriteToAnObservable
/// PropertyDoesNotNotify` shows plain assignment is, and asserted a no-op
/// `endBloom()` call (no bloom in flight, so `firedAt` is already nil) would
/// not notify. It notified anyway. That is not a broken test — dumping macro
/// expansions (`-Xfrontend -dump-macro-expansions`, the same technique that
/// pinned the `set`-accessor characterization) shows why: a mutating call
/// desugars through a *different* generated accessor, `_modify`, and unlike
/// `set` — which does `guard shouldNotifyObservers(_aura, newValue) else {
/// return }` before touching the registrar — `_modify` calls
/// `willSet`/`didSet` unconditionally, with no equality gate at all:
///
/// ```swift
/// _modify {
///     access(keyPath: \.aura)
///     _$observationRegistrar.willSet(self, keyPath: \.aura)
///     defer { _$observationRegistrar.didSet(self, keyPath: \.aura) }
///     yield &_aura
/// }
/// ```
///
/// So `model.aura.endBloom()` — the exact call shape production's `bloomEnd`
/// Task uses — notifies regardless of whether `firedAt` actually changes.
/// That is a *stronger* guarantee than `AuraTrigger.endBloom()`'s own doc
/// comment claims ("the resulting value differs … so the observation
/// actually fires"): the value differing is what makes clearing `firedAt`
/// honest per §9.2, not what makes the notification fire. This test pins the
/// measured mechanism instead of the assumed one.
@MainActor @Test func aMutatingCallThroughAnObservablePropertyNotifiesUnconditionally() {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))

    // Same shape as anEqualWriteToAnObservablePropertyDoesNotNotify's own
    // `fires` helper, tracking `model.aura` instead of `model.state`.
    func fires(_ body: () -> Void) -> Bool {
        nonisolated(unsafe) var fired = false
        withObservationTracking {
            _ = model.aura
        } onChange: {
            fired = true
        }
        body()
        return fired
    }

    // Not vacuous: a plain equal-value assignment — the exact shape
    // anEqualWriteToAnObservablePropertyDoesNotNotify already pins as a
    // non-notifying `set` call — must not notify here either, or this
    // harness can't tell "fired" from "didn't" and nothing below means
    // anything.
    #expect(!fires { model.aura = model.aura },
            "an equal plain assignment notified — the harness is broken, so the readings below are vacuous")

    // The case endBloom() actually needs to work for: a real bloom in
    // flight, ended via the mutating call production uses. Read immediately
    // after its own mutation. If this doesn't fire, the fix does not work.
    let now = Date()
    _ = model.aura.observe(.idle, now: now)
    #expect(model.aura.observe(.running, now: now) == true, "setup: a real change must bloom")
    #expect(model.aura.isBlooming(at: now), "setup: bloom must actually be in flight")
    #expect(fires { model.aura.endBloom() },
            "endBloom() changed the value but did not notify — the fix's whole mechanism depends on this firing")

    // The surprising part, read immediately after its own mutation: calling
    // endBloom() again is now a genuine no-op (firedAt is already nil from
    // the call above), and it STILL notifies — confirming the dumped
    // `_modify` accessor has no equality gate, unlike `set`.
    #expect(fires { model.aura.endBloom() },
            "a no-op mutating call did not notify — _modify is gated after all, contradicting the dumped macro expansion")
}
