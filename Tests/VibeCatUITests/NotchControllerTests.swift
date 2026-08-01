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
@MainActor @Test func presentingWiresTheModelsOnChangeAndDismissingClearsIt() {
    let (c, model) = controller { mbp14 }
    #expect(model.onChange == nil)

    c.refreshGeometry()   // present() needs geometry to have somewhere to go
    c.present()
    #expect(model.onChange != nil)

    c.dismiss()
    #expect(model.onChange == nil)
}
