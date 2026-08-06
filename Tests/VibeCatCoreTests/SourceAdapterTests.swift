import Testing
import Foundation
@testable import VibeCatCore

/// A conformer that never mentions `icon` at all — the case `SourceAdapter`'s
/// default implementation exists for, and the one every adapter written before
/// this task already is.
private struct BareAdapter: SourceAdapter {
    let id = "bare"
    let displayName = "Bare"
    let jumpStrategy = JumpStrategy.terminalSession
    let reports: Set<Kind> = [.running]
    func parse(_ raw: [String: Any], origin: Origin) throws -> VibeEvent? { nil }
}

/// A conformer that does set one, proving the protocol requirement is real —
/// not merely a default nobody can override.
private struct IconedAdapter: SourceAdapter {
    let id = "iconed"
    let displayName = "Iconed"
    let jumpStrategy = JumpStrategy.terminalSession
    let reports: Set<Kind> = [.running]
    let icon: String? = "/Users/someone/icons/mine.png"
    func parse(_ raw: [String: Any], origin: Origin) throws -> VibeEvent? { nil }
}

/// The load-bearing property of the default: forgetting to set `icon` and
/// setting it to `nil` explicitly must be the same outcome, because "no icon"
/// is §2.3's fail-open answer for a source that never had one.
///
/// Mutation-verified: deleting the `public extension SourceAdapter` default
/// implementation from `SourceAdapter.swift` makes `BareAdapter` fail to
/// conform to the protocol at all — a compile error, not a test failure, which
/// is the strongest form this particular guarantee can take.
@Test func aConformerThatNeverMentionsIconGetsNilByDefault() {
    #expect(BareAdapter().icon == nil)
}

@Test func aConformerThatSetsIconGetsExactlyWhatItSet() {
    #expect(IconedAdapter().icon == "/Users/someone/icons/mine.png")
}

/// **Retired 2026-08-06, and it did its job on the way out.**
///
/// This used to be `theClaudeCodePresetShipsNoIconPath`, asserting
/// `ClaudeCodeAdapter().icon == nil` and citing §3's rule that no vendor logo may be
/// committed. The owner then reversed that rule — knowingly, having been told what §3
/// said and that MIT grants copyright permissions and cannot grant trademark rights —
/// and this test failed immediately, which is exactly what a test guarding a policy
/// should do when the policy changes. It is replaced rather than deleted so the
/// reversal reads as a decision instead of as a lapse.
///
/// What replaces it is the half that is still true and still worth guarding: an
/// adapter for a source nothing ships a mark for must resolve to `nil`, so
/// `SourceIcon` falls back to `CLIMark`'s neutral geometry. **That is the property
/// that makes bundling cheap to undo** — delete the icons directory and the app
/// degrades to the geometry rather than breaking.
///
/// `ClaudeCodeAdapter`'s own path is asserted by
/// `theClaudeCodeAdapterCarriesItsOwnMarkRatherThanTheDefaultNil` below.
@Test func anAdapterForASourceWithNoBundledMarkStillResolvesToNil() {
    struct Unmarked: SourceAdapter {
        let id = "gemini"
        let displayName = "Gemini"
        let jumpStrategy = JumpStrategy.none
        let reports: Set<Kind> = [.running]
        var icon: String? { BundledIcon.forSourceID(id)?.path }
        func parse(_ raw: [String: Any], origin: Origin) throws -> VibeEvent? { nil }
    }
    #expect(Unmarked().icon == nil,
            "an unmarked source picked up someone else's logo, which would be a false claim about which agent is speaking (§4.3)")
}

// MARK: - the bundled icons
//
// These exist because the owner asked for the marks to be bundled after being told
// what §3 said and that MIT cannot grant trademark rights. The decision is theirs and
// is recorded in `BundledIcon`'s doc comment and a dated §3 correction; these tests
// only hold the mechanism honest.

@Test func everyBundledIconResolvesToAFileThatExists() throws {
    // `Bundle.module` needs the generated resource bundle beside the binary or in the
    // app's Resources. Under `swift test` it is beside the test binary, so a nil here
    // means the resource declaration is wrong rather than that the environment is
    // unusual — which is the failure worth catching, since `nil` is a *supported*
    // answer at runtime and would otherwise hide a broken `.copy`.
    for icon in BundledIcon.allCases {
        let path = try #require(icon.path, "\(icon.rawValue) did not resolve — check Package.swift's resources")
        #expect(FileManager.default.fileExists(atPath: path))
    }
}

@Test func theClaudeCodeAdapterCarriesItsOwnMarkRatherThanTheDefaultNil() throws {
    // The wiring, not the asset: `icon` has a default of `nil` on the protocol, so an
    // adapter that forgot to set one compiles and silently falls back to the geometric
    // mark. This is the assertion that notices.
    let path = try #require(ClaudeCodeAdapter().icon)
    #expect(path.hasSuffix("claude_logo.png"), "got \(path)")
}

@Test func anIdNothingShipsAMarkForResolvesToNilRatherThanToSomeoneElsesLogo() {
    // The mapping is a lookup on id, and a wrong `default:` branch would hand every
    // unknown CLI Claude's mark — which would be worse than the neutral geometry it
    // is supposed to fall back to, because it would be a false claim about which
    // agent is speaking (§4.3: shape says who).
    #expect(BundledIcon.forSourceID("gemini") == nil)
    #expect(BundledIcon.forSourceID("") == nil)
    #expect(BundledIcon.forSourceID("claude-code") == .claudeCode)
    #expect(BundledIcon.forSourceID("codex") == .codex)
}
