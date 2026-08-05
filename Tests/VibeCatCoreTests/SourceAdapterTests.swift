import Testing
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

/// The preset this repo actually ships. §3's Global Constraints are explicit
/// that no vendor logo may be committed, so the one built-in adapter today
/// must resolve to the geometric mark rather than pointing at anything —
/// confirmed at the adapter level, not merely inferred from the fact that no
/// file exists in the repo to point at.
@Test func theClaudeCodePresetShipsNoIconPath() {
    #expect(ClaudeCodeAdapter().icon == nil)
}
