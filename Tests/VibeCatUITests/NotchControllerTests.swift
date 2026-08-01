import Foundation
import Testing
import CoreGraphics
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
