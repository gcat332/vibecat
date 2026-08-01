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
/// never redrew). `present()` constructs a real `NSPanel` in this process
/// (see `panelForTesting`), so this asserts the actual, observable
/// consequence instead: ingesting an event changes the real panel's frame to
/// what the geometry independently says it should be, and after `dismiss()`
/// a further ingest does not move it.
@MainActor @Test func presentingWiresTheModelsOnChangeAndDismissingClearsIt() throws {
    let (c, model) = controller { mbp14 }
    #expect(model.onChange == nil)

    c.refreshGeometry()   // present() needs geometry to have somewhere to go
    c.present()
    #expect(model.onChange != nil)
    let panel = try #require(c.panelForTesting)

    let geometry = IslandGeometry(screen: mbp14)
    let dormantFrame = geometry.frames(rightFlank: 0, tier: .rest).panel
    #expect(panel.frame == dormantFrame)

    // Dormant has no right flank; one running session shows a session count
    // of 1, whose reserved width is the collapsed layout's padding plus one
    // digit's measured advance — built independently here, not read back off
    // the controller, so this doesn't compare the implementation to itself.
    model.ingest(VibeEvent(id: "e1", cli: "claude-code", kind: .running,
                           session: "a", cwd: "/dev/a"), now: t0)
    let frameAfterFirstIngest = panel.frame
    let oneSessionLayout = CollapsedLayout(right: .sessionCount(1), hovering: false)
    let expectedOneSessionFrame = geometry.frames(rightFlank: oneSessionLayout.rightFlankWidth,
                                                  tier: .rest).panel
    #expect(frameAfterFirstIngest.width > dormantFrame.width)
    #expect(frameAfterFirstIngest.origin == expectedOneSessionFrame.origin)
    #expect(frameAfterFirstIngest.height == expectedOneSessionFrame.height)
    // Width only, with a sub-point tolerance: a real NSPanel's `setFrame`
    // aligns to the window server's backing store, so a fractional input
    // (the digit's measured advance is ~8.117pt, not a whole number) comes
    // back snapped rather than bit-identical to the pure geometry maths —
    // discovered while writing this test, not assumed going in.
    #expect(abs(frameAfterFirstIngest.width - expectedOneSessionFrame.width) < 1.0)

    c.dismiss()
    #expect(model.onChange == nil)

    // A second session changes model.sessionCount to 2, which would widen
    // the right flank again if anything were still listening. Nothing is:
    // the panel (kept alive here only because this test still holds it) must
    // not have moved — compared against its own prior frame, not
    // re-derived, so this check has no rounding tolerance to hide behind.
    model.ingest(VibeEvent(id: "e2", cli: "claude-code", kind: .running,
                           session: "b", cwd: "/dev/b"), now: t0)
    #expect(panel.frame == frameAfterFirstIngest)
}
