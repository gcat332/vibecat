import Testing
import VibeCatCore
@testable import VibeCatUI

/// `body` deliberately stays clear of the three patterns Task 6's
/// `DestructiveGuard` names (`rm -rf`, `git push --force`, `drop table`):
/// this file's tests are about selection mechanics, not §10.3, and every
/// test here picks `allow`/`always` freely — a destructive-looking body
/// would silently make `reply()` wait on confirmation it never asks for,
/// which is exactly what happened when this fixture read `"rm -rf build/"`.
private func event(multi: Bool, choices: [String] = ["allow", "always", "deny"],
                    id: String = "q") -> VibeEvent {
    VibeEvent(id: id, cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
              title: "Bash command", body: "npm test",
              choices: choices.map { Choice(id: $0, label: $0.capitalized) },
              multi: multi, wantsReply: true)
}

/// §10.2: "distinguished by the control, not by a label."
@MainActor @Test func multiSelectIsDrivenByTheEventNotByGuesswork() {
    #expect(QuestionModel(event: event(multi: false)).isMulti == false)
    #expect(QuestionModel(event: event(multi: true)).isMulti)
}

@MainActor @Test func theFaceFollowsTheMode() {
    #expect(QuestionModel(event: event(multi: false)).face == .question)
    #expect(QuestionModel(event: event(multi: true)).face == .questionMulti)
}

/// §10.1: picking is the answer. One tap, one reply, no Send button.
@MainActor @Test func singleSelectRepliesTheMomentSomethingIsPicked() {
    let m = QuestionModel(event: event(multi: false))
    #expect(m.reply() == nil, "nothing is picked yet")
    m.pick("always")
    #expect(m.reply()?.choice == "always")
    #expect(m.reply()?.choices == nil, "a single-select reply must not carry a choices array")
    // The doc comment on `canSend` promises this ("a single select has no
    // Send") but nothing checked it: `canSend` dropping its `isMulti` guard
    // entirely still passed every other test in this file.
    #expect(m.canSend == false, "a single select must never offer Send")
}

/// §10.2: "Send is disabled at zero, so a half-made selection can never be
/// committed by reflex."
@MainActor @Test func multiSelectCannotBeSentEmpty() {
    let m = QuestionModel(event: event(multi: true))
    #expect(m.canSend == false)
    m.toggle("allow")
    #expect(m.canSend)
    m.toggle("allow")
    #expect(m.canSend == false, "unticking the last box left Send enabled")
}

@MainActor @Test func multiSelectRepliesWithEveryTickedChoice() {
    let m = QuestionModel(event: event(multi: true))
    m.toggle("allow"); m.toggle("deny")
    let reply = m.reply()
    #expect(reply?.choices?.sorted() == ["allow", "deny"])
    #expect(reply?.choice == nil, "a multi-select reply must not also carry a single choice")
}

/// §10.1: "`Other…` is the last row; clicking it collapses the list into a
/// text field and shrinks the drawer to match."
@MainActor @Test func choosingOtherShrinksTheDrawerAndRepliesWithText() {
    let m = QuestionModel(event: event(multi: false))
    m.beginOther()
    #expect(m.isWritingOther)
    #expect(m.face == .questionWithReply)
    #expect(m.face.height < DrawerFace.question.height)
    #expect(m.reply() == nil, "an empty field is not an answer")
    m.otherText = "  "
    #expect(m.reply() == nil, "whitespace is not an answer")
    m.otherText = "use pnpm instead"
    #expect(m.reply()?.text == "use pnpm instead")
}

/// The reply's id is the last checkpoint before a destructive command is
/// authorised; HookRunner refuses a mismatch, and it must never see one.
@MainActor @Test func everyReplyCarriesTheQuestionsOwnId() {
    let m = QuestionModel(event: event(multi: false))
    m.pick("deny")
    #expect(m.reply()?.id == "q")
}

/// Task 9's number keys map `"2"` to `rows[1]` by position (`KeyRouting.pick`),
/// so a row order that drifted from the event's own would answer the wrong
/// key. Nothing above ever reads `.rows` — confirmed by reversing it and
/// re-running the file: every test above still passed. The chosen order is
/// neither ascending nor descending by id, so either direction of an
/// accidental sort would show up here rather than by coincidence surviving
/// because the fixture already happened to be sorted.
@MainActor @Test func rowsPreserveTheEventsDeclaredOrder() {
    let m = QuestionModel(event: event(multi: false, choices: ["deny", "allow", "always"]))
    #expect(m.rows.map(\.id) == ["deny", "allow", "always"])
}

/// §10.2's running tally, unread by any test above — confirmed by changing
/// `tally` to `selected.count + 1` and re-running the file: still green.
@MainActor @Test func tallyCountsExactlyWhatIsTicked() {
    let m = QuestionModel(event: event(multi: true))
    #expect(m.tally == 0)
    m.toggle("allow")
    #expect(m.tally == 1)
    m.toggle("deny")
    #expect(m.tally == 2)
    m.toggle("allow")
    #expect(m.tally == 1)
}

/// Every test above builds its event through the shared `event(...)` helper,
/// which always passes `id: "q"` — so a `reply()` that hardcoded the literal
/// `"q"` instead of echoing `event.id` would still satisfy every one of
/// them (confirmed: it did). Worth closing precisely because the id is the
/// field `HookRunner`/`PendingQuestion` treat as authorisation — this checks
/// all three reply shapes against an id nothing else in the file uses.
@MainActor @Test func everyReplyKindCarriesItsOwnEventsIdRatherThanAConstant() {
    let single = QuestionModel(event: event(multi: false, id: "single-id"))
    single.pick("always")
    #expect(single.reply()?.id == "single-id")

    let multi = QuestionModel(event: event(multi: true, id: "multi-id"))
    multi.toggle("allow")
    #expect(multi.reply()?.id == "multi-id")

    let other = QuestionModel(event: event(multi: false, id: "other-id"))
    other.beginOther()
    other.otherText = "use pnpm instead"
    #expect(other.reply()?.id == "other-id")
}
