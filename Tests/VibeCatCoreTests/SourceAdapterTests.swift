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
/// **Amended again the same day**, when the owner asked for every source without a
/// mark of its own to share one rather than fall through to geometry. So the
/// assertion is now the opposite of what it briefly was: an unknown id resolves to a
/// real mark, and the property being guarded moved from "resolves to nil" to "resolves
/// to the *generic* mark and not to another CLI's identity".
///
/// `ClaudeCodeAdapter`'s own path is asserted by
/// `theClaudeCodeAdapterCarriesItsOwnMarkRatherThanTheDefaultNil` below.
@Test func anUnknownSourceGetsTheGenericMarkAndNotAnotherCLIsIdentity() throws {
    struct Unknown: SourceAdapter {
        let id = "some-cli-nobody-has-heard-of"
        let displayName = "Unknown"
        let jumpStrategy = JumpStrategy.none
        let reports: Set<Kind> = [.running]
        var icon: String? { BundledIcon.forSourceID(id).path }
        func parse(_ raw: [String: Any], origin: Origin) throws -> VibeEvent? { nil }
    }
    let path = try #require(Unknown().icon, "an unknown source got no mark at all")
    #expect(path.hasSuffix("iterm2.png"), "got \(path)")

    // The half that still matters most: it must not be a *named* CLI's mark. Handing
    // an unknown agent Claude's logo would be a false claim about which agent is
    // speaking, which is the identity half of §4.3.
    for named in [BundledIcon.claudeCode, .codex, .claude, .openai] {
        #expect(path != named.path, "an unknown source is wearing \(named.rawValue)")
    }
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

@Test func theMappingIsExactForKnownIdsAndGenericForEverythingElse() {
    // Every known id must reach its *own* mark: a `default:` branch that swallowed one
    // of these would silently rename an agent, and the id strings are the only thing
    // standing between a row and someone else's logo.
    #expect(BundledIcon.forSourceID("claude-code") == .claudeCode)
    #expect(BundledIcon.forSourceID("codex") == .codex)
    #expect(BundledIcon.forSourceID("claude") == .claude)
    #expect(BundledIcon.forSourceID("openai") == .openai)
    #expect(BundledIcon.forSourceID("chatgpt") == .openai)

    // Gemini ships a mark now — a PNG, after its SVG proved unrenderable through both
    // of macOS's paths. Everything genuinely unknown lands on the generic mark.
    #expect(BundledIcon.forSourceID("gemini") == .gemini)
    #expect(BundledIcon.forSourceID("") == .iterm2)
    #expect(BundledIcon.forSourceID("Claude-Code") == .iterm2, "the lookup is case-sensitive, which the ids are")
}
