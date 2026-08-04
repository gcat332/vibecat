import Testing
import Foundation
import CoreServices
import VibeCatCore
@testable import VibeCatUI

// MARK: - touching UNUserNotificationCenter without an application bundle is fatal
//
// The same defect Plan 6.2 shipped for Focus status, in a different framework
// and with a different trigger. `INFocusStatusCenter` aborts on the *request*;
// `UNUserNotificationCenter` aborts on `current()` itself, which is earlier —
// so a guard placed only around `requestAuthorization` would not have helped.
//
// Measured, 2026-08-04, from a `swift` script with `Bundle.main.bundleIdentifier
// == nil`:
//
//     *** Terminating app due to uncaught exception
//     'NSInternalInconsistencyException', reason:
//     'bundleProxyForCurrentProcess is nil: mainBundle.bundleURL …'
//     … +[UNUserNotificationCenter currentNotificationCenter] …
//     EXIT=134
//
// The three tests below are the cheapest thing that would have caught it, and
// the first is unusual on purpose: it *calls* every guarded method. This test
// bundle has no bundle identifier (measured: `bundleIdentifier` nil, an empty
// `infoDictionary`, `bundleURL` pointing at the toolchain's `swift/pm`
// directory), so deleting a guard does not fail an assertion — it takes the
// whole run down with SIGABRT. `QuietHoursTests.swift` established the shape;
// its measured signature is the same here: a mutant exits 1 with no summary
// line, the guarded code exits 0.

@Test @MainActor func everyPathToNotificationCenterIsSkippedWithoutAnApplicationBundle() {
    // If any of these three loses its `hasApplicationBundle` guard, this line
    // aborts the entire test run rather than failing — which is exactly what it
    // is here to prevent. `Notifier()` alone is enough for `refresh()`; the
    // other two are named because each reaches `current()` by its own path.
    let notifier = Notifier()
    notifier.requestAuthorizationIfNeeded()
    notifier.post(title: "a stall", body: "in a process that may not say so")
    notifier.refresh()
}

@Test func aBuildWithoutAnApplicationBundleKnowsItCannotPost() {
    // Pins the premise the test above depends on. If the test runner ever gained
    // a bundle identifier, that test would stop proving anything and this one
    // says so — the same pairing `aBuildWithoutAUsageDescriptionKnowsItCannotAsk`
    // uses for Focus.
    #expect(Notifier.hasApplicationBundle == false,
            "the test runner has a bundle identifier — the guard test above is now vacuous")
}

@Test @MainActor func aPostIsRecordedEvenWhenItCannotBeDelivered() {
    // The premise `stallsReachTheNotifier` below depends on: `post` records
    // before it guards, so a wiring test in a bundle-less process can still see
    // that the call arrived. If the recording ever moved below the guard, every
    // wiring assertion in this file would pass against a `Notifier` that does
    // nothing at all.
    let notifier = Notifier()
    notifier.post(title: "t", body: "b")
    #expect(notifier.postedForTesting == [Notifier.Post(title: "t", body: "b")])
}

// MARK: - the two permission reads

@Test func automationStatusesMapToTheThreePillStatesAndNeverGuess() {
    // Measured statuses, not invented ones — see `permissionState(for
    // AutomationStatus:)`. The one that matters most is the last: a target that
    // is not running (`procNotFound`) must not read as *granted*, because a
    // green "Granted" pill is a claim about a security state nobody made.
    #expect(Notifier.permissionState(forAutomationStatus: noErr) == .granted)
    #expect(Notifier.permissionState(forAutomationStatus: OSStatus(errAEEventNotPermitted)) == .denied)
    #expect(Notifier.permissionState(
        forAutomationStatus: OSStatus(errAEEventWouldRequireUserConsent)) == .notDetermined)
    #expect(Notifier.permissionState(forAutomationStatus: OSStatus(procNotFound)) == .notDetermined)
}

@Test func notificationStatusesMapToTheThreePillStates() {
    // `UNAuthorizationStatus`: 0 notDetermined, 1 denied, 2 authorized,
    // 3 provisional, 4 ephemeral. Spelled as raw values because that is what
    // crosses back from `getNotificationSettings`' own non-main-actor callback.
    #expect(Notifier.permissionState(forNotificationStatus: 2) == .granted)
    #expect(Notifier.permissionState(forNotificationStatus: 3) == .granted)
    #expect(Notifier.permissionState(forNotificationStatus: 4) == .granted)
    #expect(Notifier.permissionState(forNotificationStatus: 1) == .denied)
    #expect(Notifier.permissionState(forNotificationStatus: 0) == .notDetermined)
    // A status this SDK does not know must not become a grant.
    #expect(Notifier.permissionState(forNotificationStatus: 99) == .notDetermined)
}

@Test func readingAutomationPermissionAnswersWithoutPromptingOrDying() {
    // Written decision 2, as the only assertion available: with
    // `askUserIfNeeded: false` this returns a status for a target that does not
    // exist rather than prompting (a prompt in `swift test` would hang the run,
    // which is a failure signal of its own) or aborting the way
    // `UNUserNotificationCenter` does. Measured in the same probe: four bundle
    // ids from a bundle-less process, all four answered, none prompted.
    #expect(Notifier.readAutomationPermission(target: "com.example.definitely-not-installed")
            == .notDetermined)
}

// MARK: - the consumer AppModel.onStall shipped without

private let stallT0 = Date(timeIntervalSince1970: 1_000_000)

private func stallEvent(_ session: String) -> VibeEvent {
    VibeEvent(id: "e-\(session)", cli: "claude-code", kind: .running,
              session: session, cwd: "/dev/\(session)")
}

@Test @MainActor func stallsReachTheNotifierWithTheSessionThatWentQuiet() {
    // Task 5 shipped `AppModel.onStall` with nothing listening, and named that
    // explicitly in its own doc comment. This is the assertion that it is
    // listening now — and it goes through `postStalls(from:preferences:)`, the
    // library seam `main.swift` calls, rather than through a closure this test
    // installs itself. A test that wired `onStall` by hand would pass against
    // an app where nothing ever did.
    let store = InMemoryPreferenceStore(Preferences(alerts: AlertPolicy(onStall: true),
                                                   postsSystemNotification: true))
    let model = AppModel(socketPath: "/tmp/vibecat-notifier-\(UUID().uuidString).sock",
                         preferences: store)
    let notifier = Notifier(notification: .granted, automation: .granted)
    notifier.postStalls(from: model, preferences: store)

    _ = model.ingest(stallEvent("abc123"), now: stallT0)
    model.prune(now: stallT0.addingTimeInterval(StallDetector.threshold))

    #expect(notifier.postedForTesting.count == 1)
    // Names the session, so two stalled agents are told apart — and the CLI, so
    // the title says who without the body having to.
    #expect(notifier.postedForTesting.first?.body.contains("abc123") == true)
    #expect(notifier.postedForTesting.first?.title.contains("claude-code") == true)
}

@Test @MainActor func aStallPostsNothingWhileTheSystemNotificationSwitchIsOff() {
    // `Also post a system notification` ships off (`settings.html:368`), and it
    // is the switch that decides whether this channel is used at all. Same
    // model, same stall, one field different — so this cannot pass for any
    // reason other than the switch being read.
    let store = InMemoryPreferenceStore(Preferences(alerts: AlertPolicy(onStall: true),
                                                   postsSystemNotification: false))
    let model = AppModel(socketPath: "/tmp/vibecat-notifier-\(UUID().uuidString).sock",
                         preferences: store)
    let notifier = Notifier(notification: .granted, automation: .granted)
    notifier.postStalls(from: model, preferences: store)

    _ = model.ingest(stallEvent("abc123"), now: stallT0)
    model.prune(now: stallT0.addingTimeInterval(StallDetector.threshold))

    #expect(notifier.postedForTesting.isEmpty)
}

@Test @MainActor func flippingTheSwitchAfterWiringTakesEffectOnTheNextStall() {
    // The reason `postStalls` reads the store inside the closure instead of
    // capturing `postsSystemNotification` once: the switch lives on a page the
    // user is looking at *after* this wiring ran. A captured snapshot passes
    // both tests above and fails this one.
    let store = InMemoryPreferenceStore(Preferences(alerts: AlertPolicy(onStall: true),
                                                   postsSystemNotification: false))
    let model = AppModel(socketPath: "/tmp/vibecat-notifier-\(UUID().uuidString).sock",
                         preferences: store)
    let notifier = Notifier(notification: .granted, automation: .granted)
    notifier.postStalls(from: model, preferences: store)

    _ = model.ingest(stallEvent("first"), now: stallT0)
    model.prune(now: stallT0.addingTimeInterval(StallDetector.threshold))
    #expect(notifier.postedForTesting.isEmpty)

    var prefs = store.load()
    prefs.postsSystemNotification = true
    store.save(prefs)

    _ = model.ingest(stallEvent("second"), now: stallT0.addingTimeInterval(StallDetector.threshold))
    model.prune(now: stallT0.addingTimeInterval(2 * StallDetector.threshold))
    #expect(notifier.postedForTesting.count == 1)
    #expect(notifier.postedForTesting.first?.body.contains("second") == true)
}

@Test func theStallMessageReadsItsThresholdRatherThanRestatingIt() {
    // §12 has no cue for a stall, so these words are the entire alert — and the
    // number in them has to be the detector's own. A hardcoded "5 minutes"
    // would go on lying if `StallDetector.threshold` ever moved; deriving it
    // means this assertion moves with it.
    let message = Notifier.stallMessage(for: SessionKey(cli: "codex", session: "s1"))
    let minutes = Int((StallDetector.threshold / 60).rounded())
    #expect(message.body.contains("\(minutes) minutes"))
    #expect(message.title.contains("codex"))
    #expect(message.body.contains("s1"))
}

// MARK: - the two System Settings URLs

@Test func eachPermissionRowPointsAtItsOwnSystemSettingsPane() {
    // Both URLs were opened on this machine and the resulting window title read
    // back from `CGWindowListCopyWindowInfo` — "Notifications" and "Automation"
    // respectively (macOS 26.5.2, 2026-08-04; see `SystemSettingsPane`'s doc
    // comment). This pins the two strings that observation validated, and that
    // they are not the same string: a copy-paste slip would send the Automation
    // row to the Notifications pane, which no render can show.
    #expect(SystemSettingsPane.notifications.url.absoluteString
            == "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    #expect(SystemSettingsPane.automation.url.absoluteString
            == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
            + "?Privacy_Automation")
    #expect(SystemSettingsPane.notifications.url != SystemSettingsPane.automation.url)
}
