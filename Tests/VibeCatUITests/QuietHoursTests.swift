import Testing
import Foundation
@testable import VibeCatUI

// MARK: - asking for Focus status without a usage description is fatal
//
// Plan 6.2 added `requestAuthorizationIfNeeded()` to `main.swift` and broke
// `VIBECAT_SOCKET=… swift run vibecat`, the dev workflow `CLAUDE.md` documents.
// macOS does not deny the request or return an error — it `abort()`s the process:
// "This app has crashed because it attempted to access privacy-sensitive data
// without a usage description." A bare binary has no `Info.plist`, so there was
// nowhere for the key to be.
//
// It shipped because **no test runs `main.swift`** — an `executableTarget` with a
// `main.swift` cannot be `@testable import`ed, which is why this project keeps its
// executables as empty shells in the first place. 509 tests were green across five
// full runs while the documented way to launch the app died on sight.
//
// These two tests are the cheapest thing that would have caught it. The first is
// unusual and deliberate: it *calls* the guarded method. The test bundle has no
// `NSFocusStatusUsageDescription`, so if the guard is ever removed this does not
// fail an assertion — it takes the entire suite down with SIGABRT. That is a
// stronger signal than any `#expect`, and it is the only kind of assertion that
// can speak for a process that is no longer running.

@Test @MainActor func askingForFocusStatusIsSkippedWhenNoUsageDescriptionExists() {
    // The test bundle carries no NSFocusStatusUsageDescription. If the guard in
    // `requestAuthorizationIfNeeded` is deleted, this line aborts the whole test
    // run rather than failing — which is exactly what it is here to prevent.
    FocusStatusQuietHours().requestAuthorizationIfNeeded()
}

@Test func aBuildWithoutAUsageDescriptionKnowsItCannotAsk() {
    // Pins the premise the test above depends on. If the test bundle ever gained
    // the key, the test above would stop proving anything and this one says so.
    #expect(FocusStatusQuietHours.hasUsageDescription == false,
            "the test bundle has an NSFocusStatusUsageDescription — the guard test above is now vacuous")
}

@Test @MainActor func anUnauthorisedMachineIsNeverConsideredQuiet() {
    // §12 respects Do Not Disturb, but a user who enabled sound and never
    // answered — or declined — a permission prompt must still hear their agents.
    // Silently swallowing every cue is the worse failure, and this is the value
    // that decides it.
    #expect(FocusStatusQuietHours().isQuiet == false)
}

@Test func neverQuietIsNeverQuiet() {
    // The seam's other implementation, used by every sound test. If this ever
    // returned true the whole sound suite would go silent and pass.
    #expect(NeverQuiet().isQuiet == false)
}
