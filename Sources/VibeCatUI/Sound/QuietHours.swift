import Foundation
#if canImport(Intents)
import Intents
#endif

/// Whether the machine is asking for silence.
///
/// A protocol rather than a function because the mechanism is the uncertain
/// part: macOS 14 exposes Focus only through `INFocusStatusCenter`, which needs
/// its own authorization, and §15 does not list it among the app's three
/// permissions. Keeping it behind this seam means the answer to "how do we read
/// DND" can change without touching anything that decides what a cue sounds
/// like.
public protocol QuietHours: Sendable {
    var isQuiet: Bool { get }
}

/// For tests, and for any build that has not been granted Focus access.
public struct NeverQuiet: QuietHours {
    public init() {}
    public var isQuiet: Bool { false }
}

#if canImport(Intents)
/// §12's "Respects Do Not Disturb", via the only supported API on macOS 14.
///
/// **Reads `false` unless authorization was actually granted.** A user who
/// enabled sound and never answered — or declined — a permission prompt should
/// hear their agents; silently swallowing every cue because a fourth permission
/// went unanswered is the worse failure. §14's Notifications section already
/// carries a Permissions row, which is where the state belongs; Plan 6.4 wires
/// it.
///
/// **Half verified on hardware, 2026-08-03; the other half is labelled, not
/// assumed.** `INFocusStatusCenter` needs `NSFocusStatusUsageDescription` in the
/// bundle's `Info.plist`, and a bare `swift run` cannot test it — with no bundle
/// identifier TCC attributes the request to the launching terminal and the grant
/// dies as soon as the app is opened any other way. From a signed
/// `VibeCat.app`: `authorizationStatus` read `0` (`.notDetermined`) before
/// `requestAuthorization`, immediately after it returned, and three seconds
/// later; on a launch minutes later it read `3` (`.authorized`), so a prompt was
/// presented and allowed in between, though nothing observed it being drawn.
/// With authorization granted and Do Not Disturb off, `isQuiet` read `false`.
/// **The `true` path — `focusStatus.isFocused` during an actual Focus session —
/// is unverified**, because toggling system Focus was not available to the
/// process that ran the check. See §15's dated correction.
///
/// `@MainActor` on the class, `nonisolated` on the reads: `QuietHours` is
/// `Sendable` and its requirement is not actor-isolated, and an isolated
/// conformance cannot be erased into a `Sendable` existential — which is what
/// `SoundPlayer`'s `any QuietHours` is. The class stays `@MainActor` anyway
/// because that is what makes it `Sendable` without an unchecked escape hatch,
/// and because anything stateful added here later belongs on the main actor.
/// `INFocusStatusCenter` is not annotated for isolation by the SDK, and every
/// call below is a synchronous read of a system-owned singleton.
@MainActor public final class FocusStatusQuietHours: QuietHours {
    public init() {}

    public nonisolated var isQuiet: Bool {
        let centre = INFocusStatusCenter.default
        guard centre.authorizationStatus == .authorized else { return false }
        return centre.focusStatus.isFocused ?? false
    }

    /// Call once at launch. Does nothing if the user has already decided.
    ///
    /// **Called from `Sources/VibeCatApp/main.swift`**, next to
    /// `BackdropSampler.requestAccessIfAskedTo()`, which is where the app's other
    /// permission is asked for. Named here because the final-fix brief reported this
    /// method as having no caller and §12's "Respects Do Not Disturb" as therefore
    /// silently dead — it does have one, and `isQuiet`'s own doc comment records the
    /// hardware run where `authorizationStatus` went from `0` to `3` across it.
    /// Written down so the next reader does not have to grep to find that out.
    /// **Refuses to ask without an `NSFocusStatusUsageDescription`, because asking
    /// without one is fatal.** macOS does not fail this call, deny it, or return an
    /// error — it `abort()`s the process with *"This app has crashed because it
    /// attempted to access privacy-sensitive data without a usage description."*
    ///
    /// A bare binary has no `Info.plist` at all, so `VIBECAT_SOCKET=… swift run
    /// vibecat` — the dev workflow `CLAUDE.md` documents and the one used to drive
    /// this app with replayed hook payloads — died on launch with SIGABRT the moment
    /// Plan 6.2 added the call above. `swift test` cannot see it: no test runs
    /// `main.swift`. It was found by Plan 6.4's Task 4 trying to follow the
    /// documented instructions, and confirmed against unmodified `main`.
    ///
    /// The guard is not defensive padding — it is the same shape as this project's
    /// fail-open rule (§2.3). A missing key means Focus status is unavailable, and
    /// unavailable must degrade to "not quiet" (the documented behaviour when
    /// authorization is absent), never to a dead process.
    public nonisolated func requestAuthorizationIfNeeded() {
        guard Self.hasUsageDescription else { return }
        guard INFocusStatusCenter.default.authorizationStatus == .notDetermined else { return }
        INFocusStatusCenter.default.requestAuthorization { _ in }
    }

    /// Whether this build can legally ask for Focus status. `Scripts/build-app.sh`
    /// writes the key; a bare binary has no `Info.plist` to write it into.
    nonisolated static var hasUsageDescription: Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "NSFocusStatusUsageDescription") as? String
        else { return false }
        return !value.isEmpty
    }

    /// The raw `INFocusStatusAuthorizationStatus` value, for reporting what a
    /// build actually observed rather than what it was expected to.
    ///
    /// **Deliberately unreferenced, and kept.** The whole-branch review found it
    /// called from nowhere, which is true: it was added for the hardware probe whose
    /// results `isQuiet`'s doc comment records, and that probe has been run. It stays
    /// for two reasons. The correction block in §15 asserts specific raw values
    /// (`0` then `3`), and a claim about an observed number should remain
    /// re-observable — a `SwiftUI` label or a fresh probe can print it again without
    /// anyone re-deriving how to ask. And §14's Permissions row, which Plan 6.4
    /// owns, is the consumer this was shaped for: it has to show *which* state the
    /// grant is in, not merely whether `isQuiet` came back false.
    public nonisolated var authorizationStatusRawValue: Int {
        INFocusStatusCenter.default.authorizationStatus.rawValue
    }
}
#endif
