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

/// Polls `condition` until it holds, bounded by **main-actor turns rather than
/// by wall-clock seconds**.
///
/// The unit is the whole point, and it is what `aLapsedQuestionClosesTheDrawer`
/// got wrong. That test already polled, with a 2s wall-clock ceiling — the
/// condition-based shape `0ed9932` established — and still failed roughly 1
/// full-suite run in 4, reading `.drawer(height: 288.0)` where `.rest` was
/// expected. A wall-clock ceiling is the wrong bound for this failure, because
/// wall-clock time is precisely what the failure consumes. `setQuestion`'s lapse
/// `Task` is created in a `@MainActor` context, so it inherits the main actor:
/// both its sleep's resumption and its `dismissQuestion()` need a main-actor
/// turn. A full-suite run has dozens of other `@MainActor` tests taking long
/// *synchronous* stretches of that same actor — every `rasterise` call is one —
/// so two seconds can elapse having granted the lapse `Task` almost no turns at
/// all. Raising the ceiling would only move the odds; it is the same mistake in
/// a larger number.
///
/// Counting turns instead makes the bound scale with load rather than compete
/// with it: each iteration yields the main actor and comes back, so the ceiling
/// is denominated in the resource that is actually scarce. 300 turns is ~3s idle
/// and proportionally longer under load, which is the desired behaviour.
///
/// Deliberately not applied to this file's other poll loops. They wait on a
/// detached `Thread` doing real socket work rather than on a starved main-actor
/// continuation, so the argument above does not transfer, and none of them has
/// been observed to flake. They are the next candidates if one ever does.
///
/// Returns nothing on purpose: the caller still asserts the condition itself, so
/// a lapse that never happens still fails the test rather than being absorbed
/// here.
@MainActor private func waitForMainActorTurns(_ turns: Int = 300,
                                              each: Duration = .milliseconds(10),
                                              until condition: () -> Bool) async {
    for _ in 0..<turns {
        if condition() { return }
        try? await Task.sleep(for: each)
    }
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

@MainActor @Test func theTierStartsAtRestAndHoverMovesIt() {
    // Repointed from a deleted `NotchController.tier`, which only ever held
    // `.hover` or `.rest` — never `.drawer` — so it was a `Bool` wearing an
    // `IslandTier`: `setHovering(_:)` took a `Bool`, stored it as a tier, and
    // `reflow()` converted it straight back. `IslandModel.tier` is the real one
    // and is computed, so there was nothing to keep in step.
    //
    // Asserting the *transition* rather than only the initial value, because the
    // old test could not fail against the wiring it lived next to: `.rest` is what
    // a model with no drawer and no hover computes anyway, so it held whether or
    // not `setHovering` reached the model at all. This version fails if it does not.
    let (c, _) = controller { mbp14 }
    #expect(c.model.tier == .rest)
    c.setHovering(true)
    #expect(c.model.tier == .hover, "setHovering did not reach the model")
    c.setHovering(false)
    #expect(c.model.tier == .rest, "the hover never came back off")
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

/// §6.1's own table: a click opens "question, **or session list**" — not
/// only a question. Before this, `reflow()`'s `acceptsClicks` gate read
/// `model.question != nil` alone, which left the panel permanently
/// click-through whenever sessions were pending with no question — this
/// plan's entire routing (`IslandModel.face`/`.tier` correctly computing
/// `.sessionList`/`.drawer`) was unreachable by a real click as a result.
///
/// Driven through a real `AppModel.ingest`, not `setQuestion` — unlike the
/// test above, there is no bypass-`AppModel` seam for sessions the way
/// `aQuestion()` gives `setQuestion` for a question: `model.sessions` is
/// only ever assigned by `render()`, reading `appModel.store
/// .mostUrgentFirst`, so a real `AppModel`/ingest is what actually populates
/// it here.
@MainActor @Test func thePanelTakesClicksWithSessionsPendingEvenWithoutAQuestion() throws {
    let model = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    let c = NotchController(model: model, metrics: { mbp14 })
    c.refreshGeometry()
    c.present()
    let panel = try #require(c.panelForTesting)

    c.setHovering(true)
    #expect(panel.acceptsClicks == false,
            "setup: nothing pending yet — hovering must not swallow a menu bar click with neither a question nor a session")

    model.ingest(VibeEvent(id: "e1", cli: "claude-code", kind: .running,
                           session: "s1", cwd: "/dev/a"), now: t0)
    #expect(panel.acceptsClicks,
            "a session is pending with no question, but the panel still refuses clicks — the session list is unreachable by a real click")

    c.setHovering(false)
    #expect(panel.acceptsClicks == false,
            "the pointer is nowhere near the island, but the panel accepted clicks anyway")
    c.dismiss()
}

/// F3 of the final whole-branch review: **a drawer that is open must always be
/// closable by a click.**
///
/// The gate above answers "is there something to open". That is not the same
/// question as "is there something open", and `setQuestion` only ever resets
/// `drawerOpen` when a *question* disappears — nothing resets it when the last
/// *session* does. So the list could be opened with one idle session in it and
/// then have that session pruned out from under it by `AppModel.prune`'s
/// 20-minute TTL, leaving `sessions.count == 0`, `drawerOpen == true`, and
/// `tier == .drawer(420)`: a 420pt empty black box under the notch, panel grown
/// to 476pt to cover it, refusing every click aimed at dismissing it. Escape was
/// the only way out, and whether Escape is even delivered is still an unmeasured
/// hardware question (Task 9).
///
/// This deliberately keeps hovering on throughout. `model.hovering` is true for
/// the whole life of an open drawer in production (see `revealWidth`'s doc
/// comment in IslandView.swift), so removing hover is not the state a person is
/// actually stuck in, and gating on `drawerOpen` alone regardless of hover would
/// make the island swallow menu bar clicks from across the screen. The
/// `hovering` half of the rule stays.
///
/// Driven through a real `AppModel` for the same reason as the test above:
/// `model.sessions` is only ever assigned by `render()` from
/// `appModel.store.mostUrgentFirst`, so a real ingest and a real `prune` are
/// what actually reproduce the emptying.
@MainActor @Test func anOpenDrawerStaysClickableAfterItsLastSessionIsPruned() throws {
    let model = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    let c = NotchController(model: model, metrics: { mbp14 })
    c.refreshGeometry()
    c.present()
    let panel = try #require(c.panelForTesting)

    // `.done`, not `.running`: `SessionStore.prune` only removes *idle*
    // sessions, so a running one would never leave and this test would pass
    // against the bug by never reaching the state that exhibits it.
    model.ingest(VibeEvent(id: "e1", cli: "claude-code", kind: .done,
                           session: "s1", cwd: "/dev/a"), now: t0)
    c.setHovering(true)
    #expect(panel.acceptsClicks, "setup: one session pending, hovering — the list has to be openable first")
    c.click()
    #expect(c.model.drawerOpen, "setup: the click did not open the drawer")
    guard case .drawer = c.model.tier else {
        Issue.record("setup: one idle session did not reach the drawer tier — this test proves nothing")
        return
    }

    model.prune(now: t0.addingTimeInterval(AppModel.idleTTL + 1))
    #expect(c.model.sessions.isEmpty, "setup: prune left the session in place — the emptying this test is about never happened")
    #expect(c.model.drawerOpen,
            "setup: something already resets drawerOpen when the sessions empty, so the state this test is about is unreachable and the assertion below is vacuous")

    #expect(panel.acceptsClicks,
            "an open drawer refuses clicks now that its last session is gone — a permanent empty box under the notch that cannot be clicked away")

    // And a click really does close it, rather than the panel merely accepting
    // one: the whole point is the way out, not the event.
    c.click()
    #expect(c.model.drawerOpen == false, "the click was accepted but did not close the drawer")
    #expect(c.model.tier == .hover,
            "the drawer closed but the tier did not come back down — the panel is still grown to cover a drawer that is not there")
    #expect(panel.acceptsClicks == false,
            "with the drawer closed and nothing left to open, the island is still swallowing menu bar clicks")
    c.dismiss()
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
    await waitForMainActorTurns(until: { c.model.tier == .rest })
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
/// **Updated by Plan 6.3 Task 1, and the update is the point.** This test used to
/// assert `panel.frame.width == collapsedFrame.width` — "the drawer should only
/// ever grow it downward". That was true only while the drawer had no width of its
/// own, and it is the one golden in the suite that pinned the old behaviour, so it
/// is where the change had to be argued rather than absorbed. §6.3 (corrected
/// 2026-08-05) gives the open island a flat 560pt; a panel held at the collapsed
/// ceiling would clip 137pt off the right of every drawer.
///
/// Safe to change because the invariant the old line was standing in for is not
/// "the width never moves" — it is §5.3's *left edge*, which has its own assertion
/// below and is unchanged. The equality is replaced by the stronger claim rather
/// than deleted: the panel grows sideways *by exactly the face's own width*, so a
/// panel that grew by some other amount now fails where before it passed.
@MainActor @Test func thePanelGrowsWhenTheDrawerOpensAndShrinksWhenItCloses() throws {
    let c = makeController()
    let panel = try #require(c.panelForTesting)
    let collapsedFrame = panel.frame

    c.setQuestion(aQuestion())
    c.click()
    #expect(c.model.tier != .rest, "the drawer never opened, so this test proves nothing")
    #expect(panel.frame.height > collapsedFrame.height,
            "the live panel did not grow to cover the open drawer")
    let face = try #require(c.model.question?.face)
    #expect(panel.frame.width == face.width + IslandGeometry.auraMargin * 2,
            "the live panel is \(panel.frame.width)pt wide around a \(face.width)pt drawer — it did not grow sideways to cover it")
    #expect(panel.frame.width > collapsedFrame.width,
            "the panel width did not move at all when the drawer opened")
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
@MainActor @Test func presentInstallsTheKeyMonitorAndDismissRemovesIt() {
    let c = makeController()
    #expect(c.keyMonitorForTesting != nil, "present() did not install the local keyDown monitor")

    c.dismiss()
    #expect(c.keyMonitorForTesting == nil, "dismiss() did not remove the local keyDown monitor")
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

/// A non-Escape key must never *dismiss*. Since Plan 6.1 Task 4 a digit does
/// something — it answers, through `answerOnNumberKey`/`handleKeyDown`, tested
/// in this file's own Task 4 section below — but `dismissOnEscape` itself stays
/// Escape-only, and that separation is what this pins: a digit routed here
/// must not abandon a question the hook is still parked on. Escape's dismiss is
/// a deliberate fail-open; an accidental one on the number key a person meant as
/// an answer would throw away their decision.
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
/// `IslandState`, `Int`, `Session?` and `[Session]` all are. This is why
/// `render()`'s `model.state`/`model.sessionCount`/`model.revealed`/
/// `model.sessions` assignments are plain, unguarded writes rather than the
/// explicit `if old != new` checks an earlier version of this task added: the
/// macro already does that check, and duplicating it only misleads a future
/// reader into thinking `render()` needs to.
///
/// **What this fact is load-bearing for, restated from the code as it stands
/// after `90a8253`** — four claims that used to live here were true only before
/// that commit and are now all false. It said the bloom-end nudge still *is* the
/// equal write `self?.model.aura = self?.model.aura ?? AuraTrigger()`, that it is
/// "currently dead code", that "Task 3.5 owns fixing that", and that "the nudge
/// needs its own fix". `90a8253` is that fix, already landed: `bloomEnd` now
/// calls `model.aura.endBloom()`, a `mutating` method that clears `firedAt`. That
/// changes what this test guards rather than removing it — a `mutating` call goes
/// through the macro's `_$observationRegistrar.withMutation` unconditionally,
/// with no `shouldNotifyObservers` gate at all, so the nudge no longer *depends*
/// on the value differing. This test now stands behind `render()`'s four plain
/// assignments alone. If it starts failing, those writes stopped deduplicating
/// and every one of them notifies on every `render()` — a cost question, not a
/// correctness one, and not a nudge question at all any more.
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
            "an equal write still notified — @Observable no longer deduplicates identical writes on this toolchain, which render()'s four plain assignments depend on")
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
/// A first draft of `AuraTrigger.endBloom()`'s own doc comment attributed the
/// fix to the resulting value differing from the one before it; that
/// comment has since been corrected (see its current text) to say what this
/// test actually measured: the fix works because it is a *mutating call*
/// through `_modify`, not because of anything about the value. Whether
/// `firedAt` ends up different only matters for §9.2's honesty (`intensity`
/// already reads 0 either way), never for whether the notification fires —
/// an assignment that also cleared `firedAt` would still route through the
/// gated `set` and silently reintroduce the bug. This test pins the measured
/// mechanism, not the assumed one.
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

// MARK: - Plan 6.1 Task 4: §10.1's number keys, and the key status they need

/// Three real choices — `allow`, `deny`, `always` — so "a digit past the last
/// row" has somewhere past to be, and the badge/digit mapping has a middle row
/// that an off-by-one would land on. Same direct-`setQuestion` convention (and
/// same reason) as `aQuestion` above; `aDestructiveEvent` below is the variant
/// for the tests that need a real parked `PendingQuestion`.
@MainActor private func aThreeChoiceQuestion(body: String? = nil, multi: Bool = false,
                                             deadline: TimeInterval = 5) -> PendingQuestion {
    PendingQuestion(event: threeChoiceEvent(body: body, multi: multi), deadline: deadline)
}

@MainActor private func threeChoiceEvent(id: String? = nil, body: String? = nil,
                                         multi: Bool = false) -> VibeEvent {
    questionSerial += 1
    return VibeEvent(id: id ?? "q\(questionSerial)", cli: "claude-code", kind: .permission,
                     session: "s", cwd: "/tmp/proj", body: body,
                     choices: [Choice(id: "allow", label: "Allow once"),
                               Choice(id: "deny", label: "Deny"),
                               Choice(id: "always", label: "Always allow")],
                     multi: multi, wantsReply: true, answerDeadline: 5)
}

/// What the *hook* side of `ingest` was handed — the actual return value of the
/// blocking call a real `vibecat-hook` makes, captured off the thread it runs
/// on. Locked rather than `nonisolated(unsafe)`: it is written on a detached
/// `Thread` and read on the main actor, which is exactly the case a lock is for.
/// Same shape as `PipelineTests.OutputBox`.
private final class ReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Reply?
    private var _isDone = false
    func set(_ v: Reply?) { lock.lock(); _value = v; _isDone = true; lock.unlock() }
    var value: Reply? { lock.lock(); defer { lock.unlock() }; return _value }
    var isDone: Bool { lock.lock(); defer { lock.unlock() }; return _isDone }
}

/// A controller with a real `AppModel` and a genuinely parked question, drawer
/// already open — the setup the number-key tests that care about *the reply the
/// hook receives* need, as opposed to the ones that only need `model.question`.
/// Mirrors `theAnswerCallbackReachesAppModelAnswer`'s own pattern: `ingest`
/// parks its calling thread until answered or expired, so it runs on a real
/// `Thread`, never `Task.detached`.
@MainActor private func withAParkedQuestion(body: String? = nil) async throws
    -> (NotchController, AppModel, ReplyBox) {
    let (c, appModel) = controller { mbp14 }
    c.refreshGeometry()
    c.present()

    let event = threeChoiceEvent(body: body)
    let box = ReplyBox()
    Thread.detachNewThread { box.set(appModel.ingest(event)) }

    let arrived = Date().addingTimeInterval(2)
    while appModel.pending == nil, Date() < arrived {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(appModel.pending?.id == event.id, "setup: the question never reached the model")
    c.click()
    #expect(c.model.tier != .rest, "setup: the drawer never opened, so nothing below proves anything")
    return (c, appModel, box)
}

/// §10.1: "A number badge marks each row and the matching number key picks it."
/// Digit `2` names `rows[1]`, whose badge reads `2` (`ChoiceRow.index + 1`), and
/// the reply that comes back out of the *hook's own blocking call* names that
/// row's id — not the first row's, and not a fabricated one.
///
/// Driven through `handleKeyDown`, the whole of what the local monitor's closure
/// does, so this covers the dispatch as well as the handler: deleting the digit
/// branch from that dispatch fails here.
@MainActor @Test func theNumberKeyAnswersTheRowItsBadgeNamesAndTheHookGetsThatChoice() async throws {
    let (c, appModel, box) = try await withAParkedQuestion()

    #expect(c.handleKeyDown(charactersIgnoringModifiers: "2"),
            "a digit naming a visible row must be consumed rather than passed on")

    let answered = Date().addingTimeInterval(2)
    while !box.isDone, Date() < answered {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(box.value?.choice == "deny",
            "the hook received \(String(describing: box.value?.choice)) — digit 2 must name rows[1]")
    #expect(appModel.pending == nil, "the question is still parked after being answered")
    c.dismiss()
}

/// The most important assertion in this task. §10.3: a destructive command asks
/// twice, and the keyboard must not be the way around that.
///
/// The first press picks and *nothing reaches the hook* — `appModel.pending`
/// clears synchronously inside `AppModel.answer`, so its still being non-nil
/// immediately afterwards is a direct reading of "the hook has not been
/// answered", not a race. Mutation 1 of this task's own list (build a `Reply`
/// from `KeyRouting.pick`'s returned id instead of going through
/// `QuestionModel.pick`/`.reply()`) fails exactly here: a fabricated reply is
/// not gated by `needsConfirmation`, so `pending` would clear on the first press.
///
/// Key status must survive the first press too, or the second one is
/// unpressable — releasing on "answered" without checking that anything was
/// actually answered would make a destructive question unanswerable from the
/// keyboard rather than merely unsafe.
@MainActor @Test func aDestructiveCommandStillAsksTwiceOnTheNumberKey() async throws {
    let (c, appModel, box) = try await withAParkedQuestion(body: "rm -rf build/")
    let question = try #require(c.model.question)
    #expect(question.needsConfirmation == false, "setup: nothing is picked yet")

    #expect(c.handleKeyDown(charactersIgnoringModifiers: "1"))

    #expect(question.selected == ["allow"], "the first press must still pick the row")
    #expect(question.needsConfirmation, "§10.3's second ask never appeared for a destructive body")
    #expect(appModel.pending != nil,
            "the number key answered a destructive command on the first press — §10.3 was bypassed")
    #expect(box.isDone == false, "the hook already has an answer after one press")
    #expect(c.holdsKeyStatus, "key status was released before the confirming press could be typed")

    #expect(c.handleKeyDown(charactersIgnoringModifiers: "1"))

    let answered = Date().addingTimeInterval(2)
    while !box.isDone, Date() < answered {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(box.value?.choice == "allow", "the second press did not confirm and send the picked row")
    #expect(appModel.pending == nil)
    c.dismiss()
}

/// A digit is the same gesture as a tap on the row that digit names, including
/// what a *second* press of the same one means (§10.3's banner: "tap the
/// highlighted choice again to confirm"). `answerOnNumberKey` duplicates
/// `QuestionFace.tapped(_:)`'s single-select branch rather than sharing it — the
/// two live in different layers — so this pins them against drifting apart:
/// the same two presses through each path must leave the same state and produce
/// the same reply.
@MainActor @Test func theNumberKeyAndTheTapAgreeOnWhatASecondPressMeans() throws {
    let c = makeController()
    c.setQuestion(aThreeChoiceQuestion(body: "rm -rf build/"))
    c.click()
    let viaKeys = try #require(c.model.question)

    // The tap path, on its own model, driven through the real view's own entry
    // point — see QuestionFaceTests for why calling `tapped(_:)` directly is the
    // only way to exercise a tap in this suite.
    let tapModel = QuestionModel(event: threeChoiceEvent(body: "rm -rf build/"))
    nonisolated(unsafe) var tapped: [Reply] = []
    let face = QuestionFace(question: tapModel, accent: .orange, onAnswer: { tapped.append($0) })

    c.handleKeyDown(charactersIgnoringModifiers: "1")
    face.tapped("allow")
    #expect(viaKeys.selected == tapModel.selected, "the first press and the first tap picked differently")
    #expect(viaKeys.needsConfirmation == tapModel.needsConfirmation,
            "only one of the two paths raised §10.3's second ask")
    #expect(tapped.isEmpty, "control: the tap path must not answer a destructive command on the first tap")

    c.handleKeyDown(charactersIgnoringModifiers: "1")
    face.tapped("allow")
    #expect(viaKeys.isConfirming == tapModel.isConfirming,
            "the second press and the second tap disagree about what confirms")
    #expect(tapped.map(\.choice) == ["allow"], "control: the tap path answers on the second tap")
    #expect(viaKeys.reply()?.choice == "allow",
            "the keyboard path's own model would not produce the reply the tap path did")
}

/// A digit naming no row does nothing at all, and — because there is no row it
/// could be about — is not consumed either. `rows` has three entries, so `4` is
/// the first digit past the end; `KeyRouting.pick` returns `nil` and the handler
/// must stop there rather than clamping to the last row.
@MainActor @Test func aDigitPastTheLastRowPicksNothing() throws {
    let c = makeController()
    c.setQuestion(aThreeChoiceQuestion())
    c.click()
    let question = try #require(c.model.question)

    #expect(c.handleKeyDown(charactersIgnoringModifiers: "4") == false,
            "a digit that names no row must fall through rather than be swallowed")
    #expect(question.selected.isEmpty, "a digit past the last row picked something anyway")
    #expect(c.model.question != nil, "the question must still be open")
    #expect(c.model.tier != .rest, "the drawer must still be open")
}

/// `0` is not a badge. `ChoiceRow` numbers from `index + 1`, so the lowest
/// visible numeral is `1` — a `0` that picked `rows[0]` would answer a question
/// using a key the interface never showed anyone.
@MainActor @Test func zeroNamesNoRowBecauseBadgesNumberFromOne() throws {
    let c = makeController()
    c.setQuestion(aThreeChoiceQuestion())
    c.click()
    let question = try #require(c.model.question)

    #expect(c.handleKeyDown(charactersIgnoringModifiers: "0") == false,
            "`0` was consumed, so some row is reachable by a key with no badge")
    #expect(question.selected.isEmpty, "`0` picked a row")
}

/// §10.2: multi select is distinguished *by the control* — a checkbox, not a
/// number badge — and "a number badge means the click is the answer; a checkbox
/// means it is not." So there is no digit on screen to press, and pressing one
/// must fall through rather than be swallowed by a panel holding key
/// exclusively. (`QuestionModel.pick` would refuse anyway; this is about the
/// keystroke not being eaten.)
@MainActor @Test func aMultiSelectQuestionHasNoBadgesSoADigitIsNotConsumed() throws {
    let c = makeController()
    c.setQuestion(aThreeChoiceQuestion(multi: true))
    c.click()
    let question = try #require(c.model.question)

    #expect(c.handleKeyDown(charactersIgnoringModifiers: "1") == false,
            "a digit was consumed on a multi-select question, which shows checkboxes and no numerals")
    #expect(question.selected.isEmpty, "a digit toggled a checkbox §10.2 says it must not")
}

/// `Other…`'s field is for typing, and `2` in "port 8082" is a character, not a
/// choice. Plan 6.1 Task 5 restores the row; this guard has to be here before it
/// does, or the field it opens is silently undigitable.
@MainActor @Test func aDigitWhileTheReplyFieldIsUpIsTextRatherThanAChoice() throws {
    let c = makeController()
    c.setQuestion(aThreeChoiceQuestion())
    c.click()
    let question = try #require(c.model.question)
    question.beginOther()

    #expect(c.handleKeyDown(charactersIgnoringModifiers: "1") == false,
            "a digit meant for the reply field was consumed as a choice")
    #expect(question.selected.isEmpty, "a digit typed into the reply field picked a row")
    #expect(question.isWritingOther, "the reply field was closed by a keystroke meant for it")
}

/// A digit with the drawer shut names nothing visible — there are no badges on a
/// collapsed island — so it must not answer. This is the guard that keeps a `1`
/// typed into a terminal from authorising a command whose choices are not on
/// screen, and it mirrors `dismissOnEscape`'s own `.drawer` gate.
@MainActor @Test func aDigitWithTheDrawerShutAnswersNothing() throws {
    let c = makeController()
    c.setQuestion(aThreeChoiceQuestion())
    #expect(c.model.tier == .rest, "setup: a question alone must not open the drawer")
    let question = try #require(c.model.question)

    #expect(c.handleKeyDown(charactersIgnoringModifiers: "1") == false,
            "a digit answered a question whose badges were not on screen")
    #expect(question.selected.isEmpty, "a digit picked a row nobody could see")
}

/// The spike's hazard, and the narrowest window that still lets a keystroke mean
/// anything: key status is taken only once a drawer the person clicked open is
/// actually on screen.
///
/// The middle assertion is the narrowing that matters and it is unchanged by Task
/// 6's widening — the plan said "take key on open", and a question that has
/// arrived but whose drawer nobody opened is exactly the state the spike warns
/// about: delivery is exclusive, `frontmostApplication` never changes, so the
/// terminal looks focused while its keystrokes vanish — with no badge on screen to
/// press in exchange. See `takeKeyStatusIfADrawerIsOpen`'s own doc comment.
@MainActor @Test func keyStatusIsTakenOnlyWhileAClickedOpenDrawerIsOnScreen() {
    let c = makeController()
    #expect(c.holdsKeyStatus == false, "an island at rest must never hold key status")

    c.setQuestion(aThreeChoiceQuestion())
    #expect(c.holdsKeyStatus == false,
            "key status was taken while the question's badges were still off screen")

    c.click()
    #expect(c.holdsKeyStatus, "an open drawer showing a question cannot receive a keystroke without key status")
}

/// **Reversed in Plan 6.1 Task 6, deliberately.** This test used to be
/// `theSessionListTakesNoKeyStatus` and asserted the opposite, on the reasoning
/// that the list has nothing to answer so key status buys nothing. Task 4's own
/// report named the consequence as Task 6 territory: with no key status the local
/// monitor never sees a `keyDown` at all, so **Escape could not close the session
/// list on hardware** — leaving a 420pt panel whose only exit was clicking the
/// island again.
///
/// So the list does take key now, and the two assertions below are the whole
/// bargain: it takes key *and* Escape closes it. If a future change decides the
/// swallowed-keystroke cost is not worth the dismissal, both of these must be
/// reversed together — a version of this file with the first assertion flipped and
/// the second still passing is not reachable.
@MainActor @Test func theSessionListTakesKeyStatusSoEscapeCanCloseIt() {
    let (c, appModel) = controller { mbp14 }
    c.refreshGeometry()
    c.present()
    _ = appModel.ingest(VibeEvent(id: "e1", cli: "claude-code", kind: .running,
                                  session: "s", cwd: "/tmp/proj"))
    c.click()
    #expect(c.model.face == .sessionList, "setup: this must be the session list, not a question")
    #expect(c.model.tier != .rest, "setup: the drawer never opened")

    #expect(c.holdsKeyStatus,
            "the session list holds no key status, so a real Escape is never delivered to it")

    #expect(c.handleKeyDown(charactersIgnoringModifiers: "\u{1b}"),
            "Escape must report the keystroke as handled while the list is open")
    #expect(c.model.tier == .rest, "Escape did not close the session list")
    #expect(c.holdsKeyStatus == false,
            "a closed session list left the panel key — everything typed next is swallowed")
    c.dismiss()
}

/// The other half of the widening: a digit is inert with no question. §10.2's rule
/// is that a badge means the click is the answer, and the session list has no
/// badges — so `answerOnNumberKey` reports the keystroke unhandled and nothing at
/// all happens to any session.
///
/// **What this cannot claim:** that the digit reaches the terminal. It does not.
/// While the panel is key, delivery is exclusive (the spike), so an unconsumed
/// digit falls through to the panel's own responder chain, which does nothing with
/// it. "Inert" here means it changes no state and answers nothing — not that it
/// gets out.
@MainActor @Test func aDigitDoesNothingWhileTheSessionListIsOpen() {
    let (c, appModel) = controller { mbp14 }
    c.refreshGeometry()
    c.present()
    _ = appModel.ingest(VibeEvent(id: "e1", cli: "claude-code", kind: .running,
                                  session: "s", cwd: "/tmp/proj"))
    c.click()
    #expect(c.model.face == .sessionList, "setup: this must be the session list, not a question")

    #expect(c.handleKeyDown(charactersIgnoringModifiers: "1") == false,
            "a digit was consumed by a drawer with no rows to pick")
    #expect(c.model.tier != .rest, "a digit closed the session list")
    #expect(c.model.sessions.count == 1, "a digit changed the session list")
    c.dismiss()
}

/// Ending one of three: answered. Released by `answer(_:)`, which both the
/// number key and `model.onAnswer` (a tap on a row or on Send) go through.
@MainActor @Test func answeringWithTheNumberKeyGivesKeyStatusBack() {
    let c = makeController()
    c.setQuestion(aThreeChoiceQuestion())
    c.click()
    #expect(c.holdsKeyStatus, "setup: nothing to release, so this proves nothing")

    #expect(c.handleKeyDown(charactersIgnoringModifiers: "2"))

    #expect(c.holdsKeyStatus == false,
            "the panel is still key after answering — everything the person types next is swallowed")
}

/// The same ending reached by a mouse tap instead: `model.onAnswer` is what
/// `QuestionFace.tapped(_:)` calls, and it must release for the same reason.
/// Separate from the number-key case above because they are separate call sites
/// and only one of them is the keyboard.
@MainActor @Test func answeringWithATapGivesKeyStatusBackToo() {
    let c = makeController()
    let pending = aThreeChoiceQuestion()
    c.setQuestion(pending)
    c.click()
    #expect(c.holdsKeyStatus, "setup: nothing to release, so this proves nothing")

    c.model.onAnswer?(Reply(id: pending.id, choice: "deny"))

    #expect(c.holdsKeyStatus == false, "a tap-answered question left the panel holding key status")
}

/// Ending two of three: dismissed. Driven through `handleKeyDown` rather than
/// `dismissOnEscape` so the dispatch's Escape branch is covered here as well.
@MainActor @Test func escapeGivesKeyStatusBack() {
    let c = makeController()
    c.setQuestion(aThreeChoiceQuestion())
    c.click()
    #expect(c.holdsKeyStatus, "setup: nothing to release, so this proves nothing")

    #expect(c.handleKeyDown(charactersIgnoringModifiers: "\u{1b}"))

    #expect(c.model.tier == .rest, "setup: Escape did not dismiss, so the release below is not the one under test")
    #expect(c.holdsKeyStatus == false, "a dismissed question left the panel holding key status")
}

/// Ending three of three: lapsed. The one nobody chooses — the hook gave up and
/// the drawer closed itself — and the one where a leaked key status would be
/// hardest to notice, because the person never touched the island at all.
@MainActor @Test func aLapsedQuestionGivesKeyStatusBack() async throws {
    let c = makeController()
    c.setQuestion(aThreeChoiceQuestion(deadline: 0.05))
    c.click()
    #expect(c.holdsKeyStatus, "setup: nothing to release, so this proves nothing")

    await waitForMainActorTurns(until: { c.model.tier == .rest })

    #expect(c.model.tier == .rest, "setup: the question never lapsed")
    #expect(c.holdsKeyStatus == false, "a lapsed question left the panel holding key status")
}

/// Not one of the three endings — the question stays parked (see `click()`) —
/// but the badges are off screen, so holding key past it is the spike's hazard
/// with nothing gained. And it must come back on the next click, or a person who
/// closes and reopens the drawer can no longer answer with the keyboard.
@MainActor @Test func closingTheDrawerByClickingGivesKeyStatusBackAndReopeningTakesItAgain() {
    let c = makeController()
    c.setQuestion(aThreeChoiceQuestion())
    c.click()
    #expect(c.holdsKeyStatus, "setup: nothing to release, so this proves nothing")

    c.click()
    #expect(c.model.question != nil, "setup: the click abandoned the question instead of closing the drawer")
    #expect(c.holdsKeyStatus == false, "a closed drawer left the panel holding key status")

    c.click()
    #expect(c.holdsKeyStatus, "reopening the drawer left the number keys undeliverable")
}

/// Teardown ends the window as finally as any answer does. `dismiss()` orders
/// the panel out, so AppKit has already resigned key by then — this is about
/// this object not going on believing otherwise, which a later `present()` would
/// read as "already held" and never re-take.
@MainActor @Test func dismissGivesKeyStatusBack() {
    let c = makeController()
    c.setQuestion(aThreeChoiceQuestion())
    c.click()
    #expect(c.holdsKeyStatus, "setup: nothing to release, so this proves nothing")

    c.dismiss()

    #expect(c.holdsKeyStatus == false, "a torn-down controller still believes it holds key status")
}

// MARK: - parking (Plan 9 Task 3)
//
// These live here, not in the `ParkedQuestionTests.swift` the plan named, because
// they are integration tests through a real `NotchController` and this file owns
// the `controller(_:)` and `mbp14` fixtures. Duplicating a controller fixture to
// honour a filename would be the worse trade.

/// **Task 3 required no production change, and that is the finding — but it needs
/// this test more than a hand-written change would.**
///
/// `IslandModel.face` is `question?.face ?? .sessionList` (`IslandModel.swift:170`),
/// and `AppModel.parkQuestion()` sets `pending = nil` and fires `onQuestion?(nil)`,
/// which `NotchController.setQuestion(nil)` turns into `model.question = nil`. So
/// the drawer already falls through to the session list when a question parks; the
/// design made it free. What nothing enforces is that it *stays* free, and this is
/// the assertion that notices if a later edit routes parking anywhere else.
@MainActor @Test func parkingSendsTheDrawerToTheSessionList() async throws {
    let (c, m) = controller { mbp14 }
    c.refreshGeometry()
    // `present()`, not just `refreshGeometry()`: `appModel.onQuestion` is wired
    // *in* `present()` (`NotchController.swift:334`), so without it this drives a
    // controller that `AppModel` cannot reach — which is what the first run of
    // this test measured, reading `.sessionList` before anything was parked.
    c.present()
    let event = VibeEvent(id: "q1", cli: "claude-code", kind: .permission, session: "s",
                          cwd: "/tmp/proj", choices: [Choice(id: "allow", label: "Allow")],
                          wantsReply: true, answerDeadline: 5)
    // `Task.detached`: `ingest` blocks its calling thread on `PendingQuestion
    // .await()`, which on the main actor is a deadlock rather than a test — see
    // `aQuestion(deadline:)`'s own doc comment above.
    let waiter = Task.detached { m.ingest(event) }
    try await Task.sleep(for: .milliseconds(50))
    #expect(c.model.face == .question, "the question never reached the drawer")

    m.parkQuestion()
    #expect(c.model.question == nil)
    #expect(c.model.face == .sessionList, "a parked question still owns the drawer")

    m.answer(Reply(id: "q1", choice: "allow"))
    _ = await waiter.value
}

/// **§4.2: the session list is a view, not a state.** Parking moves a question
/// into the list, and the tempting mistake is to let the island go calm because
/// the drawer is showing something else now. It must not: the session is still
/// waiting, so the cat, the badge and the count must all read exactly as they did.
///
/// Structurally this is already safe — `render()` takes `state` and `sessionCount`
/// from `appModel.islandState`/`sessionCount`, which are derived from `store`, and
/// parking never touches `store`. The test is the guard against an edit that
/// changes that, which is the only way this invariant can break.
///
/// Compares the reported values, not a rendered colour count: a render with the
/// badge emptied still produces eighty-odd colours from everything else and would
/// pass a count.
@MainActor @Test func parkingChangesWhereAQuestionIsDrawnAndNothingElse() async throws {
    let (c, m) = controller { mbp14 }
    c.refreshGeometry()
    // `present()`, not just `refreshGeometry()`: `appModel.onQuestion` is wired
    // *in* `present()` (`NotchController.swift:334`), so without it this drives a
    // controller that `AppModel` cannot reach — which is what the first run of
    // this test measured, reading `.sessionList` before anything was parked.
    c.present()
    let event = VibeEvent(id: "q1", cli: "claude-code", kind: .permission, session: "s",
                          cwd: "/tmp/proj", choices: [Choice(id: "allow", label: "Allow")],
                          wantsReply: true, answerDeadline: 5)
    let waiter = Task.detached { m.ingest(event) }
    try await Task.sleep(for: .milliseconds(50))
    c.render()

    let state = c.model.state
    let count = c.model.sessionCount
    let badge = c.model.badge
    let mood = c.model.mood
    let revealed = c.model.revealed?.id
    #expect(state == .waiting, "the fixture is not exercising the case this test is about")

    m.parkQuestion()
    c.render()

    #expect(c.model.state == state, "the island's state changed because a question was parked")
    #expect(c.model.sessionCount == count, "the session count changed")
    #expect(c.model.badge == badge, "the badge changed")
    #expect(c.model.mood == mood, "the cat's mood changed")
    #expect(c.model.revealed?.id == revealed, "the hover reveal moved to a different session")

    m.answer(Reply(id: "q1", choice: "allow"))
    _ = await waiter.value
}

/// The other half of the pair, and the reason the one above is not vacuous:
/// **answering** a question *does* change what the island reports, once the agent's
/// next event lands. Without this, a `parkQuestion()` that silently discarded the
/// question would satisfy the §4.2 test — nothing changed, after all.
@MainActor @Test func aParkedQuestionIsStillCountedAsWaitingByTheIsland() async throws {
    let (c, m) = controller { mbp14 }
    c.refreshGeometry()
    // `present()`, not just `refreshGeometry()`: `appModel.onQuestion` is wired
    // *in* `present()` (`NotchController.swift:334`), so without it this drives a
    // controller that `AppModel` cannot reach — which is what the first run of
    // this test measured, reading `.sessionList` before anything was parked.
    c.present()
    let event = VibeEvent(id: "q1", cli: "claude-code", kind: .permission, session: "s",
                          cwd: "/tmp/proj", choices: [Choice(id: "allow", label: "Allow")],
                          wantsReply: true, answerDeadline: 5)
    let waiter = Task.detached { m.ingest(event) }
    try await Task.sleep(for: .milliseconds(50))
    m.parkQuestion()
    c.render()
    #expect(c.model.state == .waiting, "a parked question stopped being reported as waiting")

    // The agent proceeding is what calms the island — not the UI moving a question
    // around. Derived from the rule rather than measured: `render()` reads
    // `appModel.islandState`, which is `IslandState(store:)`, and only an event
    // changes `store`.
    m.answer(Reply(id: "q1", choice: "allow"))
    _ = await waiter.value
    _ = m.ingest(VibeEvent(id: "e2", cli: "claude-code", kind: .running, session: "s", cwd: "/tmp/proj"))
    c.render()
    #expect(c.model.state == .running, "the island stayed amber after the agent moved on")
}
