import Testing
import VibeCatCore
@testable import VibeCatUI

/// Three plain choices — the same shape every other test file in this suite
/// uses for "selection mechanics, not §10.3" (see `QuestionModelTests`'s own
/// warning about this). Deliberately not a destructive body, so `allow`/
/// `always` never need confirmation here.
private func threeChoices(multi: Bool) -> VibeEvent {
    VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
              title: "Bash command", body: "pnpm install",
              choices: [Choice(id: "allow", label: "Allow once"),
                        Choice(id: "always", label: "Always allow"),
                        Choice(id: "deny", label: "Deny")],
              multi: multi, wantsReply: true)
}

/// A destructive body with a permissive first row — §10.3's second ask is
/// exactly what `aNumberKeyStillCannotSkipTheSecondAsk` below has to prove a
/// single keystroke cannot walk around.
private func destructiveEvent() -> VibeEvent {
    VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
              title: "Bash command", body: "rm -rf build/",
              choices: [Choice(id: "allow", label: "Allow once"),
                        Choice(id: "deny", label: "Deny")],
              wantsReply: true)
}

// MARK: - KeyRouting.pick

@MainActor @Test func numberKeysPickTheMatchingRow() {
    let m = QuestionModel(event: threeChoices(multi: false))
    #expect(KeyRouting.pick(character: "2", in: m) == "always")
    #expect(KeyRouting.pick(character: "9", in: m) == nil, "there is no ninth row")
    #expect(KeyRouting.pick(character: "0", in: m) == nil, "rows are 1-indexed, as the badges are")
}

/// The boundary in both directions, with a small fixture (3 rows) rather than
/// leaning on "9" alone — a mutant that widened the upper bound to a fixed
/// `(1...9)` window regardless of `rows.count` (i.e. read `character.
/// wholeNumberValue` but forgot to re-check against `rows.indices`) would
/// still fail `numberKeysPickTheMatchingRow`'s own "9" case, but "4" one past
/// the *actual* last row is a tighter check that a literal `9`-only test
/// would not by itself demand. Confirmed by mutation below.
@MainActor @Test func theBoundaryIsExactlyRowsCountNotAFixedNine() {
    let m = QuestionModel(event: threeChoices(multi: false))
    #expect(KeyRouting.pick(character: "1", in: m) == "allow", "the first digit must pick the first row")
    #expect(KeyRouting.pick(character: "3", in: m) == "deny", "the last real row must still be reachable")
    #expect(KeyRouting.pick(character: "4", in: m) == nil,
            "one past the last real row already misses — this must not require reaching all the way to 9")
}

@MainActor @Test func nonDigitCharactersNeverPickARow() {
    let m = QuestionModel(event: threeChoices(multi: false))
    for character: Character in ["a", "!", " ", "\n", "\u{1b}"] {
        #expect(KeyRouting.pick(character: character, in: m) == nil,
                "'\(character)' is not a digit and must not pick a row")
    }
}

/// A free-text (`Other…`) or otherwise choice-less event is reachable state
/// (`QuestionModel.rows` is `event.choices ?? []`) — every digit must miss,
/// not crash on an empty array.
@MainActor @Test func emptyRowsMeansEveryDigitMisses() {
    let event = VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                          wantsReply: true)
    let m = QuestionModel(event: event)
    #expect(m.rows.isEmpty, "setup: this event must carry no choices at all")
    for digit in "123456789" {
        #expect(KeyRouting.pick(character: digit, in: m) == nil)
    }
}

/// `Other…` is `QuestionFace.rows`' own synthetic row, added at render time —
/// never part of `QuestionModel.rows`, which is exactly `event.choices`. So
/// it must be unreachable by construction, not merely because a question
/// happens to run out of real rows first: this fixture fills every one of
/// the nine keys with a real choice, and `__other__` is still never among the
/// results.
@MainActor @Test func otherIsNeverReachableByAnyNumberKey() {
    let nineChoices = (1...9).map { Choice(id: "choice-\($0)", label: "Choice \($0)") }
    let event = VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                          choices: nineChoices, wantsReply: true)
    let m = QuestionModel(event: event)

    for digit in "123456789" {
        let picked = KeyRouting.pick(character: digit, in: m)
        #expect(picked != "__other__")
        #expect(picked == "choice-\(digit)",
                "digit '\(digit)' should still pick its own real row, not merely fail to reach Other")
    }
}

/// `Character.wholeNumberValue` also recognises numerals worth ten or more —
/// Roman numeral "Ⅹ" is 10 (confirmed directly below, not assumed) — which
/// `rows.indices.contains(index)` alone would not reject for a question with
/// that many rows: index 9 is a perfectly valid array index once ten rows
/// exist. The explicit `(1...9)` bound is what actually stops a numeral like
/// this from ever being treated as a row index at all, rather than the
/// array-bounds check happening to reject it only for as long as no question
/// ever has that many rows.
@MainActor @Test func aNumeralWorthTenOrMoreNeverPicksARowEvenIfOneExistsAtThatIndex() {
    let tenChoices = (0..<10).map { Choice(id: "choice-\($0)", label: "Choice \($0)") }
    let event = VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                          choices: tenChoices, wantsReply: true)
    let m = QuestionModel(event: event)
    #expect(Character("Ⅹ").wholeNumberValue == 10, "setup: this must be a real numeral worth ten")
    #expect(KeyRouting.pick(character: "Ⅹ", in: m) == nil,
            "a numeral worth ten must not silently pick row 9 just because one exists there")
}

/// A destructive answer must not be reachable by one keystroke — §10.3's
/// second ask is a real gate, verified firing on hardware (see
/// task-9-report.md), and a keyboard path around it would be a hole.
///
/// The literal version of this test that only calls `KeyRouting.pick` and
/// then reads `m.reply()` is vacuous: `pick` is a pure lookup that never
/// touches `m` at all, so `m.reply()` is `nil` regardless of whether any
/// destructive gate exists, purely because nothing was ever selected.
/// Confirmed by deleting `QuestionModel.needsConfirmation`'s body (`return
/// false` unconditionally) and re-running — the literal version stays green
/// while this one correctly fails. This version does what a real `keyDown`
/// handler is required to do with the id `pick` returns — call
/// `question.pick(id)`, the same method `QuestionFace.tapped(_:)` calls for
/// a mouse tap's first press — so it actually exercises the gate rather than
/// a tautology.
@MainActor @Test func aNumberKeyStillCannotSkipTheSecondAsk() throws {
    let m = QuestionModel(event: destructiveEvent())
    let id = try #require(KeyRouting.pick(character: "1", in: m))
    #expect(id == "allow", "setup: row 1 must be the permissive choice this test needs")

    m.pick(id)

    #expect(m.needsConfirmation,
            "picking a permissive choice on a destructive body must still need a second ask")
    #expect(m.reply() == nil, "a single keystroke produced a reply for a destructive command")
}

// MARK: - KeyRouting.isEscape

@Test func isEscapeRecognisesOnlyTheEscapeCharacter() {
    #expect(KeyRouting.isEscape("\u{1b}"))
    #expect(KeyRouting.isEscape("1") == false)
    #expect(KeyRouting.isEscape("") == false)
    #expect(KeyRouting.isEscape(nil) == false)
}
