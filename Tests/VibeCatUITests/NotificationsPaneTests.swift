import Testing
import Foundation
import SwiftUI
import VibeCatCore
@testable import VibeCatUI

/// Task 7's own three surfaces: the `Alert me when an agent` switches, the
/// `Elsewhere` group, and the assembled page that replaced 6.4's owner note.
///
/// **What every wiring test in here is really guarding.** This plan's own
/// self-review named the failure that would leave the whole page decorative —
/// a control that writes nothing, or writes the wrong field — and recorded that
/// Plan 6.4 shipped that shape three times through six task reviews. So each
/// switch is asserted against the *store*, and each assertion also checks that
/// the neighbouring fields did **not** move: all four `AlertPolicy` fields are
/// `Bool`, so a copy-paste slip between them does not even change a type.
///
/// **`Notifier(notification:automation:)`, never `Notifier()`, in every render
/// fixture.** The real initialiser reads Automation permission through
/// `AEDeterminePermissionToAutomateTarget`, a synchronous round trip to another
/// process; a golden test whose pixels depend on this machine's TCC database is
/// not a golden test.
@MainActor
func makeNotificationsPaneModel(
    _ preferences: Preferences = Preferences(),
    notification: PermissionState = .granted,
    automation: PermissionState = .granted
) -> (model: NotificationsPaneModel, store: InMemoryPreferenceStore, opened: PaneSpy) {
    let store = InMemoryPreferenceStore(preferences)
    let spy = PaneSpy()
    let model = NotificationsPaneModel(
        store: store,
        sound: SoundSectionModel(store: store, syncSettings: { _ in }, playCue: { _ in }),
        notifier: Notifier(notification: notification, automation: automation),
        openPane: { spy.panes.append($0) })
    return (model, store, spy)
}

/// A reference type for the same reason `StallWiringTests.StallRecorder` is one:
/// a captured `var` mutated inside an escaping closure and read outside it trips
/// Swift 6's "mutated after capture" diagnostic.
@MainActor final class PaneSpy {
    var panes: [SystemSettingsPane] = []
}

@Suite("Notifications page")
struct NotificationsPaneTests {

    // MARK: - the four alert switches

    @Test @MainActor func eachAlertSwitchWritesItsOwnFieldAndNoNeighbours() {
        // One case per switch would be four near-identical tests; one case with
        // four independent models is the same coverage without the copy-paste
        // this file's own header warns about. Each block flips *one* switch away
        // from its default and asserts the whole `AlertPolicy` against the
        // expected value — so a setter pointed at a neighbour fails here twice,
        // once for the field that did not change and once for the one that did.
        let needsAnswer = makeNotificationsPaneModel()
        needsAnswer.model.setOnNeedsAnswer(false)
        #expect(needsAnswer.store.load().alerts
                == AlertPolicy(onNeedsAnswer: false, onFinish: true, onFail: true, onStall: false))

        let finish = makeNotificationsPaneModel()
        finish.model.setOnFinish(false)
        #expect(finish.store.load().alerts
                == AlertPolicy(onNeedsAnswer: true, onFinish: false, onFail: true, onStall: false))

        let fail = makeNotificationsPaneModel()
        fail.model.setOnFail(false)
        #expect(fail.store.load().alerts
                == AlertPolicy(onNeedsAnswer: true, onFinish: true, onFail: false, onStall: false))

        let stall = makeNotificationsPaneModel()
        stall.model.setOnStall(true)
        #expect(stall.store.load().alerts
                == AlertPolicy(onNeedsAnswer: true, onFinish: true, onFail: true, onStall: true))
    }

    @Test @MainActor func theSystemNotificationSwitchWritesItsOwnFieldOnly() {
        let (model, store, _) = makeNotificationsPaneModel()
        model.setPostsSystemNotification(true)
        let prefs = store.load()
        #expect(prefs.postsSystemNotification == true)
        // The rest of the struct is untouched: `save(_:)` writes the whole
        // `Preferences`, so a writer that built a fresh one instead of mutating
        // a fresh `load()` would silently reset every other field on this page.
        #expect(prefs.alerts == AlertPolicy() && prefs.pack == Preferences().pack
                && prefs.volume == Preferences().volume)
    }

    @Test @MainActor func aBindingReadsTheStoredValueRatherThanAFreshDefault() {
        // The defect Task 4 already had to fix once in `AppModel`: a switch that
        // renders `AlertPolicy()` instead of what is on disk looks right on a
        // fresh install and silently lies for everyone else.
        let stored = Preferences(alerts: AlertPolicy(onNeedsAnswer: false, onFinish: false,
                                                     onFail: false, onStall: true),
                                 postsSystemNotification: true)
        let (model, _, _) = makeNotificationsPaneModel(stored)
        #expect(model.onNeedsAnswerBinding.wrappedValue == false)
        #expect(model.onFinishBinding.wrappedValue == false)
        #expect(model.onFailBinding.wrappedValue == false)
        #expect(model.onStallBinding.wrappedValue == true)
        #expect(model.postsSystemNotificationBinding.wrappedValue == true)
    }

    @Test @MainActor func aWriteGoesThroughTheBindingAndNotOnlyTheSetter() {
        // `SettingsWindowModel.pageBinding`'s recorded defect, checked here for
        // all five: a `Binding` built from `@Bindable`'s straight-to-storage form
        // updates the view and persists nothing. The setters above could all be
        // right while every switch on the page wrote to a dead end.
        let (model, store, _) = makeNotificationsPaneModel()
        model.onStallBinding.wrappedValue = true
        model.postsSystemNotificationBinding.wrappedValue = true
        model.onFailBinding.wrappedValue = false
        #expect(store.load().alerts.onStall == true)
        #expect(store.load().alerts.onFail == false)
        #expect(store.load().postsSystemNotification == true)
    }

    @Test @MainActor func aFlippedSwitchSilencesTheVeryNextEvent() {
        // **The end-to-end assertion this whole page exists for.** One store,
        // shared by the page's model and `AppModel` exactly as `main.swift`
        // shares it: a switch flipped here must change what the event pipeline
        // does on the next event, with nothing else to wire and no relaunch.
        // Fails against a page whose writes never reach the store, against an
        // `AppModel` that snapshots `alerts` once, and against a `CueSelector`
        // that ignores its policy.
        let store = InMemoryPreferenceStore()
        let appModel = AppModel(socketPath: "/tmp/vibecat-pane-\(UUID().uuidString).sock",
                                preferences: store)
        let recorder = CueRecorder()
        appModel.onCue = { recorder.cues.append($0) }
        let page = NotificationsPaneModel(
            store: store,
            sound: SoundSectionModel(store: store, syncSettings: { _ in }, playCue: { _ in }),
            notifier: Notifier(notification: .granted, automation: .granted),
            openPane: { _ in })

        appModel.ingest(finishEvent(session: "a"))
        #expect(recorder.cues == [.done], "the done cue must fire while `Finishes` is on")

        page.setOnFinish(false)
        appModel.ingest(finishEvent(session: "b"))
        #expect(recorder.cues == [.done], "flipping `Finishes` off did not reach the pipeline")
    }

    // MARK: - the two permission buttons

    @Test @MainActor func eachSystemSettingsButtonAsksForItsOwnPane() {
        // The seam, not the row: nothing headless can prove *which* button a
        // closure is attached to (this project has no ViewInspector and takes
        // none — `PanelBarTests` records the same limit), so what is asserted is
        // that the model forwards each pane distinctly and records it. The URLs
        // themselves are pinned in `NotifierTests`, against a real observation
        // of which pane each one opened.
        let (model, _, opened) = makeNotificationsPaneModel()
        model.openSystemSettings(.notifications)
        model.openSystemSettings(.automation)
        #expect(opened.panes == [.notifications, .automation])
        #expect(model.lastOpenedPaneForTesting == .automation)
    }

    // MARK: - what the page actually draws

    @Test @MainActor func theStoredPolicyDecidesWhichSwitchesAreOn() throws {
        // **Two renders differing in exactly one input** — the stored
        // `AlertPolicy` — with the direction pinned rather than merely "differs".
        // With the prototype's defaults three switches are on and one is off
        // (`settings.html:328-336`), so the blue track area must be about three
        // times the grey one; inverted, about a third.
        //
        // Counted over the group's own render, which contains nothing else that
        // is `--blue` or `#48484E`: the switch is the only control in this group.
        // `300`, not the pane's own `656`: the label's own `min-width:190px` plus
        // the `14pt` gap, the `38pt` switch and `2×14pt` padding come to 270, so a
        // row lays out unchanged and the switch is identical, for under a quarter
        // of the pixels. Cheap matters here —
        // this file's own load broke three parked-question tests in
        // `AppModelTests` once already; see `theNotificationsPaneDraws
        // ControlsWhereTheOwnerNoteUsedToBe` for that measurement.
        let defaults = try rasterise(AlertsSection(model: makeNotificationsPaneModel().model)
            .frame(width: 300))
        let inverted = try rasterise(AlertsSection(
            model: makeNotificationsPaneModel(Preferences(
                alerts: AlertPolicy(onNeedsAnswer: false, onFinish: false,
                                    onFail: false, onStall: true))).model)
            .frame(width: 300))

        let onDefaults = Double(defaults.pixelCount(near: SettingsPalette.systemBlue, tolerance: 6))
        let offDefaults = Double(defaults.pixelCount(near: SettingsPalette.switchOff, tolerance: 6))
        let onInverted = Double(inverted.pixelCount(near: SettingsPalette.systemBlue, tolerance: 6))
        let offInverted = Double(inverted.pixelCount(near: SettingsPalette.switchOff, tolerance: 6))

        // **The same colour, across the two renders** — not blue against grey
        // within one. Measured why: an on-track and an off-track do not cover
        // equal area (268 blue pixels per on switch, but 633 grey for one off
        // switch against 1323 for three, because the knob's shadow falls
        // differently over each). Blue *is* exactly proportional — 804 for three
        // on, 268 for one — so the ratio between the two renders is the derived
        // 3, and the grey comparison is asserted only by direction.
        #expect(onInverted > 0 && offDefaults > 0,
                "a render drew no switch at all: blue=\(onInverted) grey=\(offDefaults)")
        #expect(abs(onDefaults / onInverted - 3) < 0.3,
                "three switches on by default against one when inverted: \(onDefaults) vs \(onInverted)")
        #expect(offInverted > 1.5 * offDefaults,
                "three switches off when inverted against one by default: \(offInverted) vs \(offDefaults)")
    }

    @Test @MainActor func eachPermissionRowDrawsItsOwnStateAndInItsOwnRow() throws {
        // **A crossed pill is the failure that matters here** — the Automation
        // row showing the notification permission's state, or both rows reading
        // one field — and "both colours appear" cannot see it. So this reads
        // *where* each colour landed: `Elsewhere`'s rows run switch, notification,
        // automation (`settings.html:365-376`), so the automation pill is always
        // the lower of the two.
        let granted = RGBA(hex: "#3FD99B")!
        let denied = RGBA(hex: "#FFA63C")!

        let notificationDenied = try rasterise(ElsewhereSection(
            model: makeNotificationsPaneModel(notification: .denied, automation: .granted).model)
            .frame(width: 300))
        let automationDenied = try rasterise(ElsewhereSection(
            model: makeNotificationsPaneModel(notification: .granted, automation: .denied).model)
            .frame(width: 300))

        let deniedHigh = try Self.meanY(of: denied, in: notificationDenied)
        let grantedLow = try Self.meanY(of: granted, in: notificationDenied)
        #expect(deniedHigh < grantedLow,
                "with only Notifications denied, the amber pill must be the upper one")

        let grantedHigh = try Self.meanY(of: granted, in: automationDenied)
        let deniedLow = try Self.meanY(of: denied, in: automationDenied)
        #expect(deniedLow > grantedHigh,
                "with only Automation denied, the amber pill must be the lower one")
    }

    @Test @MainActor func theNotificationsPaneDrawsControlsWhereTheOwnerNoteUsedToBe() throws {
        // **The one assertion that the *pane* contains the page**, rather than
        // that the page renders well on its own. Deleting
        // `NotificationsPane(model:)` from `SettingsPaneView` passes every other
        // test in this file: the sections still render, the owner note is still
        // `nil`, and `rasterise` sees a `ScrollView`'s content as transparent
        // either way. Only a render that actually lays the scroller out can tell.
        //
        // So this is the one test here that goes through `rasteriseHosted`
        // (`NSHostingView` in an offscreen borderless window — documented safe,
        // unlike a titled one).
        //
        // **One render at 400×240, and the size and the count are both load
        // decisions with a measurement behind them.** Two captures at 704×620
        // cost 1.6s of main-actor time, and that alone broke the parked-question
        // tests in `AppModelTests` — `answerDeadline: 5`, a 50ms hop, and a main
        // actor busy for seconds means the question lapses on its own deadline
        // while `m.pending` still reads non-nil, which is exactly the failure
        // seen: `ingest.value` nil, three tests red, 4 runs in 5. Bisected by
        // disabling this one test: without it, 4 full runs showed only
        // `PipelineTests`' documented flake and the suite came back from 8.3s to
        // 7.3s. Trimming to a single 400×240 capture is this task fixing its own
        // load rather than another test's budget, the same call Task 6 made.
        //
        // Plan 6.4 measured `cacheDisplay` as untrustworthy for absolute flat
        // *window* colours, so both readings below are checked against what this
        // very path measures for a control pane rather than assumed: a note-only
        // pane (Display) at this size reads `card` at 28% of the raster and 528
        // blue pixels, against 49% and 4260 here. The thresholds sit between the
        // two, and the blue one is also derivable — three on-switches at this
        // backing scale are ~1072 device pixels each.
        let hosted = try rasteriseHosted(
            SettingsPaneView(page: SettingsPage.page(for: SettingsPageKey.notifications)!,
                             notifications: makeNotificationsPaneModel().model,
                             display: makeDisplayPaneModel()),
            size: CGSize(width: 400, height: 240))
        let area = Double(hosted.width * hosted.height)
        let cardFraction = Double(hosted.pixelCount(near: SettingsPalette.card, tolerance: 6)) / area
        #expect(cardFraction > 0.35,
                "the pane is not covered in rows of card: \(cardFraction) of the raster")
        #expect(hosted.pixelCount(near: SettingsPalette.systemBlue, tolerance: 20) > 2000,
                "no switches reached the pane: only \(hosted.pixelCount(near: SettingsPalette.systemBlue, tolerance: 20)) blue pixels")
    }

    @Test @MainActor func theHeadingSurvivesAPageTallerThanItsPane() throws {
        // **The bug the assembled page shipped with for one build, kept as a
        // test.** The three groups are 771pt tall; the content area is 552.
        // Without the `ScrollView` in `SettingsPaneView`, a `VStack` overflowing
        // its proposal centres the overflow — and the `.ptitle` was pushed clean
        // off the top of the render: the page's own chip colour appeared at *no*
        // pixel of a 704×620 raster, and three chip assertions in
        // `SettingsSidebarTests` went red at once.
        //
        // Asserted where the prototype puts the chip (`.content{padding:20px
        // 24px}` → 24,20) rather than "somewhere", because "the chip is drawn"
        // was true of the broken build too — just 200pt higher than the frame.
        // 300pt rather than the window's 620: the page is 771pt tall, so it
        // overflows either frame — which is the condition under test — and this
        // costs a quarter of the pixels.
        let pane = try rasterise(
            SettingsPaneView(page: SettingsPage.page(for: SettingsPageKey.notifications)!,
                             notifications: makeNotificationsPaneModel().model,
                             display: makeDisplayPaneModel())
                .frame(width: 704, height: 200))
        let chip = SettingsPage.page(for: SettingsPageKey.notifications)!.chip
        var found = 0
        for y in 20..<44 {
            for x in 24..<48 where Self.near(pane[x, y], chip, tolerance: 3) { found += 1 }
        }
        #expect(found > 300, "the pane heading's chip is not at (24,20): \(found) px")
    }

    @Test @MainActor func theWholePageCarriesAllThreeOfTheProtypesGroups() throws {
        // The three `h2` headings are the page's own table of contents, and a
        // missing group is the one assembly error that looks fine in isolation —
        // each section's own test would still pass. Counted as *bands of card*:
        // three groups separated by `margin-bottom:18px` of window ground means
        // the card colour must appear in at least three separate runs of rows.
        let raster = try rasterise(NotificationsPane(model: makeNotificationsPaneModel().model)
            .frame(width: 656)
            .background(Color(SettingsPalette.background)))
        // **Counted as gaps, not as runs, and that distinction is measured.** A
        // run-based count read 18 bands, not 3: every row boundary inside a card
        // is a full-width `1px` hairline, which is not the card colour, so each
        // one closed a band. What separates two *groups* is `margin-bottom:18px`
        // of window ground plus the next `h2` — tens of rows with no card at all
        // — so a gap of at least eight card-free scanlines is the thing that can
        // only be a group boundary.
        // Sampled every eighth column, not every pixel: a card row is full width
        // (656pt of it), so 82 samples answer "is this scanline card" exactly as
        // well as 656 do, for an eighth of the work. The same load discipline as
        // the narrower renders above.
        let stride = 8
        let columns = Array(Swift.stride(from: 0, to: raster.width, by: stride))
        var cardRows: [Bool] = []
        for y in 0..<raster.height {
            let cardPixels = columns.count { x in
                Self.near(raster[x, y], SettingsPalette.card, tolerance: 3)
            }
            cardRows.append(cardPixels > columns.count / 2)
        }
        var bands = 0
        // Starts at the threshold, not at `Int.max`: incrementing `Int.max`
        // overflows and Swift traps on it, which is a crashed test run rather
        // than a failed assertion — met once while writing this.
        var gap = 8   // "before the first card" already counts as a gap
        for isCard in cardRows {
            if isCard {
                if gap >= 8 { bands += 1 }
                gap = 0
            } else {
                gap += 1
            }
        }
        #expect(bands == 3, "expected three groups of rows, saw \(bands) bands of card")
    }

    // MARK: - helpers

    /// The mean y of every pixel within tolerance of `colour`. Throws rather
    /// than returning a sentinel when the colour is absent: "the pill is
    /// missing" must fail loudly, not compare as `0` and pass.
    static func meanY(of colour: RGBA, in raster: Raster) throws -> Double {
        var total = 0.0
        var n = 0.0
        // Every other pixel in both axes: a pill's dot and text are tens of
        // pixels across, so a stride of two cannot miss one, and this file's
        // load is measured (see `theNotificationsPaneDrawsControls…`).
        for y in Swift.stride(from: 0, to: raster.height, by: 2) {
            for x in Swift.stride(from: 0, to: raster.width, by: 2)
            where near(raster[x, y], colour, tolerance: 8) {
                total += Double(y)
                n += 1
            }
        }
        try #require(n > 0, "no pixel near \(colour) was drawn at all")
        return total / n
    }

    static func near(_ p: Raster.Pixel, _ colour: RGBA, tolerance: Int) -> Bool {
        let target = Raster.Pixel(colour)
        return p.a > 0
            && abs(Int(p.r) - Int(target.r)) <= tolerance
            && abs(Int(p.g) - Int(target.g)) <= tolerance
            && abs(Int(p.b) - Int(target.b)) <= tolerance
    }
}

@MainActor final class CueRecorder {
    var cues: [Cue] = []
}

private func finishEvent(session: String) -> VibeEvent {
    VibeEvent(id: "e-\(session)", cli: "claude-code", kind: .done,
              session: session, cwd: "/tmp/\(session)")
}
