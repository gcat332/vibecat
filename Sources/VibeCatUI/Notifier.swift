import AppKit
import CoreServices
import Foundation
import UserNotifications
import VibeCatCore

/// The two System Settings panes the `Elsewhere` group's buttons open, as
/// values rather than as URL strings at the call site.
///
/// Lives beside `Notifier` rather than with the rows that use it: like every
/// other member of this file it is a fact about the OS, and a test can pin the
/// strings without a view in sight.
///
/// **Both URLs were opened and observed on this machine (macOS 26.5.2, build
/// 25F84, 2026-08-04) rather than trusted from memory**: `NSWorkspace.shared.open` returned `true`, System Settings became
/// frontmost (`com.apple.systempreferences`), and its window title read
/// **"Notifications"** and **"Automation"** respectively — read back from
/// `CGWindowListCopyWindowInfo`'s `kCGWindowName`, not inferred. The pre-Ventura
/// spellings (`com.apple.preference.notifications`,
/// `com.apple.preference.security?Privacy_Automation`) were probed in the same
/// run and still resolve to the same two panes; the modern identifiers are used
/// here because they are the ones this OS documents.
public enum SystemSettingsPane: Sendable, Equatable, CaseIterable {
    case notifications, automation

    public var url: URL {
        switch self {
        case .notifications:
            URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        case .automation:
            URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
                + "?Privacy_Automation")!
        }
    }
}

/// §14's `Elsewhere` group, behind the two rows that report it and the one row
/// that switches it on: a system notification for the moments the island itself
/// cannot deliver, plus the live read of the two permissions §15 names.
///
/// **Touching `UNUserNotificationCenter.current()` in a process with no bundle
/// identifier kills it — measured, not feared.** A bundle-less process
/// (`swift run vibecat`, a `swift` script, this suite's own test runner) raises
/// `NSInternalInconsistencyException`, *"bundleProxyForCurrentProcess is nil"*,
/// from inside `+[UNUserNotificationCenter currentNotificationCenter]`, and an
/// uncaught Objective-C exception is `SIGABRT`: probed here on 2026-08-04, the
/// process died with exit `134` at the `current()` call itself — **before** any
/// `requestAuthorization`, so guarding only the request would not have saved it.
/// That is the same failure shape Plan 6.2 shipped for
/// `INFocusStatusCenter.requestAuthorization` and it was invisible to 509 green
/// tests for a whole plan, because **no test runs `main.swift`**.
///
/// So every path in this type that reaches `UNUserNotificationCenter` goes
/// through `hasApplicationBundle` first, and `NotifierTests` *calls* the guarded
/// methods rather than asserting about them — if the guard is deleted, the test
/// run aborts instead of failing, which is the only kind of assertion that can
/// speak for a process that is no longer running.
///
/// **Notifications need no usage-description key, and that is a finding rather
/// than an omission.** Plan 6.5's own Task 7 brief expected one in
/// `Scripts/build-app.sh`'s `Info.plist`, in the shape
/// `NSFocusStatusUsageDescription` takes. There is no such key for
/// `UserNotifications`: macOS gates it on the process having an *application
/// bundle* (a `CFBundleIdentifier`, which `Sources/VibeCatApp/Info.plist`
/// already carries and a bare binary cannot have), and the string in the
/// permission alert is the app's name, not a sentence we supply. The abort is
/// real; the key it would have needed is not. `Info.plist` records that
/// explicitly next to the Screen Recording note, which is the same shape of
/// "nothing goes here, and here is why" already established there.
///
/// **`automationPermission` never prompts** — written decision 2 of this plan.
/// Nothing in the app uses Automation until jump ships (Plan 6), so asking for
/// it would be demanding a capability the app does not exercise.
@MainActor @Observable public final class Notifier {
    /// The last read of `UNUserNotificationCenter`'s own authorization status.
    ///
    /// Stored rather than computed because the only API that answers it —
    /// `getNotificationSettings(completionHandler:)` — is asynchronous, and a
    /// row cannot draw a pill from a callback that has not landed yet.
    /// `notDetermined` until the first read completes, which is also the
    /// truthful answer for the interval in which nobody has asked.
    public private(set) var notificationPermission: PermissionState = .notDetermined

    /// The last read of Automation permission **for `automationTarget`**, taken
    /// with `askUserIfNeeded: false`.
    ///
    /// Stored, like the value above, for a different reason:
    /// `AEDeterminePermissionToAutomateTarget` is a synchronous round trip to
    /// another process, and a computed property read from a SwiftUI `body`
    /// would take it on every render of the page.
    public private(set) var automationPermission: PermissionState = .notDetermined

    public init() {
        readsSystem = true
        refresh()
    }

    /// Two fixed states and no system calls at all — for tests, and for the
    /// pixel fixtures that have to draw a `denied` pill on a machine where the
    /// real answer is something else.
    ///
    /// It exists for a second reason worth naming: `refresh()` reaches
    /// `AEDeterminePermissionToAutomateTarget`, which is a synchronous round
    /// trip to another process. Every render test that builds a page would
    /// otherwise make one, on a suite that runs in parallel — the shape of
    /// dependency this repo has already been burned by (`ps %cpu`, a locked
    /// screen, a window server) where a test's answer depends on the machine
    /// rather than on the code.
    init(notification: PermissionState, automation: PermissionState) {
        readsSystem = false
        notificationPermission = notification
        automationPermission = automation
    }

    /// Whether this instance is allowed to ask the system anything. `false`
    /// only for the fixed-state initialiser above.
    private let readsSystem: Bool

    /// Re-reads both permissions. Called from `init`, from the Notifications
    /// page when it appears, and after `requestAuthorizationIfNeeded` — a grant
    /// made in System Settings while this app is running changes nothing here
    /// until something asks again.
    public func refresh() {
        guard readsSystem else { return }
        refreshAutomationPermission()
        refreshNotificationPermission()
    }

    // MARK: - Notifications

    /// Asks for notification authorization, once, if the user has not decided.
    ///
    /// **`.alert` only, deliberately.** §12 owns sound in this app and renders
    /// its own five cues; adding `.sound` here would let macOS play a second,
    /// system one over the top of a cue the user chose, for the same event.
    /// `.badge` is meaningless in an `LSUIElement` app with no Dock icon.
    ///
    /// Called from `main.swift` next to `FocusStatusQuietHours
    /// .requestAuthorizationIfNeeded()`, which is where this app's other
    /// permissions are asked for.
    public func requestAuthorizationIfNeeded() {
        // See this type's doc comment: `current()` itself aborts a bundle-less
        // process, so the guard is here, ahead of every use of it.
        guard Self.hasApplicationBundle else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in
                // Neither the `Bool` nor the `Error?` is read: what the pill
                // shows comes from a fresh `getNotificationSettings`, which is
                // the system's answer rather than this call's. `Error` is not
                // `Sendable`, so hopping with it would need an escape hatch to
                // carry a value nothing uses.
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    /// Posts a notification now, or does nothing at all.
    ///
    /// **Fail open, §2.3.** Every reason this cannot deliver — no bundle, no
    /// grant, a user who declined — is a reason to do nothing, never to raise
    /// or block. Nothing in the event path waits on this call.
    public func post(title: String, body: String) {
        // Recorded before the guard so a test can prove the wiring reached
        // here in a process that must never touch the real centre — see
        // `postedForTesting`.
        posted.append(Post(title: title, body: body))
        if posted.count > Self.postHistoryLimit { posted.removeFirst() }
        guard Self.hasApplicationBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func refreshNotificationPermission() {
        guard Self.hasApplicationBundle else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            // `rawValue`, not the enum: this closure runs off the main actor and
            // an `Int` is the one thing that crosses back with no isolation
            // question to answer.
            let raw = settings.authorizationStatus.rawValue
            Task { @MainActor [weak self] in
                self?.notificationPermission = Notifier.permissionState(forNotificationStatus: raw)
            }
        }
    }

    /// `UNAuthorizationStatus` → the pill's three states.
    ///
    /// `.provisional` and `.ephemeral` count as granted: both mean macOS will
    /// deliver something without asking again, which is the only claim this
    /// pill makes. A raw value this SDK does not know is `notDetermined` rather
    /// than granted — the pill must never claim a permission nobody has
    /// established.
    nonisolated static func permissionState(forNotificationStatus raw: Int) -> PermissionState {
        switch UNAuthorizationStatus(rawValue: raw) {
        case .authorized, .provisional, .ephemeral: .granted
        case .denied: .denied
        default: .notDetermined
        }
    }

    // MARK: - Automation

    /// The app whose Automation state the `Elsewhere` row reports.
    ///
    /// **Automation is per-target, and that is the awkward fact behind this
    /// constant.** macOS grants "VibeCat may control X" one X at a time, so
    /// there is no single "Automation permission" to read — §13's jump targets
    /// whichever terminal an agent happens to be running in. `Terminal.app`
    /// stands in because it is the one terminal present on every macOS, and
    /// because it is the target §13's fallback path would use. When jump ships
    /// (Plan 6) this row will have to report per-target state, or the state of
    /// the target it is about to drive.
    nonisolated static let automationTarget = "com.apple.Terminal"

    private func refreshAutomationPermission() {
        automationPermission = Self.readAutomationPermission(target: Self.automationTarget)
    }

    /// Written decision 2: `askUserIfNeeded: false`, so this reads and never
    /// prompts.
    ///
    /// **Safe in a bundle-less process, measured rather than assumed** — the
    /// same probe that caught `UNUserNotificationCenter` aborting ran this
    /// against four bundle ids from a `swift` script with `bundleIdentifier ==
    /// nil` and it returned statuses without prompting or dying. It needs no
    /// guard of its own; sending a *real* Apple event later (jump) does need
    /// `NSAppleEventsUsageDescription`, which `Info.plist` has carried since
    /// Plan 6.4.
    nonisolated static func readAutomationPermission(target bundleID: String) -> PermissionState {
        var descriptor = AEAddressDesc()
        let bytes = Array(bundleID.utf8)
        let created = bytes.withUnsafeBufferPointer { buffer in
            AECreateDesc(typeApplicationBundleID, buffer.baseAddress, buffer.count, &descriptor)
        }
        guard created == noErr else { return .notDetermined }
        defer { AEDisposeDesc(&descriptor) }
        return permissionState(
            forAutomationStatus: AEDeterminePermissionToAutomateTarget(
                &descriptor, typeWildCard, typeWildCard, false))
    }

    /// `AEDeterminePermissionToAutomateTarget`'s status → the pill's three
    /// states.
    ///
    /// The two interesting mappings are both measured (2026-08-04, macOS 26.5):
    ///
    /// - `errAEEventWouldRequireUserConsent` (`-1744`) is exactly "not
    ///   determined" — the call would have prompted, and written decision 2
    ///   says it must not.
    /// - `procNotFound` (`-600`) is what a *not running* target answers, which
    ///   is the common case: with Terminal.app closed the read came back
    ///   `-600`, and with Finder running the same call read `0`. "The target
    ///   is not running" is not a grant and not a denial, so it lands in
    ///   `notDetermined` too — the state Task 3 built the neutral grey pill
    ///   for, and the reason this row genuinely needs it.
    nonisolated static func permissionState(forAutomationStatus status: OSStatus) -> PermissionState {
        switch status {
        case noErr: .granted
        case OSStatus(errAEEventNotPermitted): .denied
        default: .notDetermined
        }
    }

    // MARK: - Stalls, the one thing that posts today

    /// Task 5's detector, given the consumer it shipped without.
    ///
    /// **A stall gets a notification and no sound, and that is a rule rather
    /// than a shortcut.** §12 defines five cues and none of them is "stalled";
    /// Plan 6.2's written decision 3 forbids inventing a sound nothing
    /// specifies. So this is the whole alert.
    ///
    /// Lives here, in the library, rather than as three lines in `main.swift`,
    /// for the reason `SoundSettings(_:)`'s own doc comment records: no test
    /// runs `main.swift`, so wiring that has to be right belongs behind
    /// something a test can call. `stallsPostedByAModelReachTheNotifier` calls
    /// exactly this.
    public func postStall(_ key: SessionKey) {
        let message = Self.stallMessage(for: key)
        post(title: message.title, body: message.body)
    }

    /// The words a stall posts. `settings.html:334-335` is the specification —
    /// *"Nothing has happened in the session and no question is pending"* — and
    /// `StallDetector.threshold` is the number, read rather than restated so a
    /// changed threshold cannot leave this text lying.
    nonisolated static func stallMessage(for key: SessionKey) -> (title: String, body: String) {
        let minutes = Int((StallDetector.threshold / 60).rounded())
        return (title: "\(key.cli) has gone quiet",
                body: "No activity for \(minutes) minutes and no question pending "
                    + "— session \(key.session).")
    }

    /// Makes every stall this model reports arrive as a notification.
    ///
    /// `AppModel.onStall` is already gated by `AlertPolicy.allows(.stalled)`
    /// inside `prune`, so nothing here re-checks that switch — one place
    /// decides whether a trigger may alert, which is the same rule
    /// `CueSelector` follows for `onCue`.
    ///
    /// **`postsSystemNotification` is checked here, on every stall, rather
    /// than captured once.** The switch lives on the page the user is looking
    /// at while this closure is installed; reading it fresh from the store is
    /// what makes flipping it take effect without a relaunch, the same shape
    /// `AppModel` uses for `alerts`.
    public func postStalls(from model: AppModel, preferences: PreferenceStoring) {
        model.onStall = { [weak self] key in
            guard preferences.load().postsSystemNotification else { return }
            self?.postStall(key)
        }
    }

    // MARK: - Guard, and what a test can see

    /// Whether this process may touch `UNUserNotificationCenter` at all.
    ///
    /// `CFBundleIdentifier` is the exact thing whose absence makes
    /// `bundleProxyForCurrentProcess` nil — measured in both directions: a
    /// bundle-less `swift` script reported `bundleIdentifier: nil` and aborted
    /// at `current()`, and this suite's own runner reports `nil` too (with an
    /// empty `infoDictionary`), which is what makes `NotifierTests`' guarded
    /// calls safe. `Scripts/build-app.sh` copies an `Info.plist` that has it.
    nonisolated static var hasApplicationBundle: Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        return !id.isEmpty
    }

    struct Post: Equatable, Sendable {
        let title: String
        let body: String
    }

    /// Every `post(title:body:)` this instance was asked to make, whether or
    /// not a bundle existed to deliver it.
    ///
    /// The same shape of hook as `SoundSectionModel.lastPlayedCueForTesting`
    /// and for the same reason: nothing headless can observe Notification
    /// Center receive anything — the test process cannot even legally *ask* —
    /// so this records the one thing a wiring error would get wrong, which is
    /// whether the call arrived at all and with which words.
    /// Bounded, because this app runs for a whole login session and a stall
    /// every five minutes would otherwise grow this array for days.
    private var posted: [Post] = []
    var postedForTesting: [Post] { posted }
    static let postHistoryLimit = 20
}
