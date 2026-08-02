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
