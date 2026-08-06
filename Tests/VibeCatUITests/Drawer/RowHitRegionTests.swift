import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

/// Plan 9 Task 6: the header jumps, everything else in the row does not — and
/// answering, dismissing or reading a task line must never *also* jump, because
/// a question now renders inside the same row the jump gesture lives on.
///
/// **Why these go through testing hooks rather than a rendered tap.** This
/// project has no ViewInspector and no way to deliver a synthetic `NSEvent`
/// through a headless `ImageRenderer` render — `QuestionFaceTests.swift`'s own
/// doc comment already establishes this for `QuestionFace`, and the same limit
/// applies here. So `SessionRow.headerTapForTesting()`/`.dismissTapForTesting()`/
/// `.answerTapForTesting(questionID:choiceID:)` each call exactly what their real
/// gesture calls — `headerTapped()`/`dismissTapped(_:)`/`questionBlock(for:)`,
/// the same private methods `body` itself uses — rather than a hand-rebuilt
/// stand-in that could quietly drift from the real wiring.
private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func session(_ state: Kind = .permission) -> Session {
    let e = VibeEvent(id: "e", cli: "claude-code", kind: state, session: "s", cwd: "/Users/dev/api")
    return Session(event: e, now: t0)
}

/// `body: "pnpm install"`, deliberately **not** destructive — unlike
/// `SessionRowTests`' own `rowQuestion`, which never needs an actual reply out
/// of a tap and so never notices that its `rm -rf build/` body makes §10.3 ask
/// twice. `answeringInsideTheBlockDoesNotJump` below needs one tap to *finish*
/// answering, the same reason `QuestionFaceTests.threeChoices(destructive:
/// false)` picks a benign command.
@MainActor private func rowQuestion(_ id: String = "q1", handedBack: Bool = false) -> IslandModel.RowQuestion {
    IslandModel.RowQuestion(
        model: QuestionModel(event: VibeEvent(
            id: id, cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
            title: "Allow this command?", body: "pnpm install",
            choices: [Choice(id: "allow", label: "Allow once"), Choice(id: "deny", label: "Deny")],
            wantsReply: true)),
        isHandedBack: handedBack)
}

// MARK: - The three-test set the brief demands together

/// The owner's rule, as an assertion. Tapping inside the question block must not
/// call `onJump` — and a naive implementation that puts `.onTapGesture` on the
/// whole row rather than scoping it to `headline` alone risks exactly that,
/// since a question block is a sibling of the header under that same row.
///
/// Mutation-verified: see this file's own report for the mutant tried against
/// `questionBlock(for:)` and the fact that it goes red.
@MainActor @Test func answeringInsideTheBlockDoesNotJump() {
    var jumped = false
    var answered: Reply?
    let question = rowQuestion()
    let row = SessionRow(session: session(), now: t0, questions: [question],
                         onAnswer: { answered = $0 }, onJump: { jumped = true })

    row.answerTapForTesting(questionID: question.id, choiceID: "allow")

    #expect(answered?.choice == "allow",
            "setup: the testing hook did not answer the question at all, so the rest of this test proves nothing")
    #expect(jumped == false, "answering a parked question also jumped to the terminal")
}

/// And the header still jumps, so the first test is not passing because nothing
/// jumps at all.
@MainActor @Test func theHeaderStillJumps() {
    var jumped = false
    let row = SessionRow(session: session(), now: t0, onJump: { jumped = true })

    row.headerTapForTesting()

    #expect(jumped == true, "tapping the header did not call onJump")
}

/// Ruling B's control lives in the same header that jumps, so a tap that
/// propagated would jump *and* give up on the question in one click — the worst
/// possible pair of outcomes to combine, since one of them is irreversible for
/// that question. `.highPriorityGesture` on the Dismiss control is what this
/// test stands behind; see `SessionRow.dismissControl(for:)`'s own doc comment.
@MainActor @Test func dismissingFromTheHeaderDoesNotJump() {
    var jumped = false
    var dismissed: String?
    let question = rowQuestion()
    let row = SessionRow(session: session(), now: t0, questions: [question],
                         onJump: { jumped = true }, onDismiss: { dismissed = $0 })

    row.dismissTapForTesting()

    #expect(dismissed == question.id, "Dismiss did not fire onDismiss with the question's own id")
    #expect(jumped == false, "dismissing a question also jumped to its terminal")
}

// MARK: - Which question Dismiss actually names

/// A handed-back question's hook is already gone — there is nothing left for
/// `Dismiss` to release — so the brief's own gating condition
/// (`questions.contains { !$0.isHandedBack }`) has to reach the tap itself, not
/// just the control's visibility. Without it, `Dismiss` would silently fire for
/// a question nobody can still answer.
@MainActor @Test func dismissDoesNothingWithNoAnswerableQuestion() {
    var dismissed: String?
    let row = SessionRow(session: session(), now: t0,
                         questions: [rowQuestion(handedBack: true)],
                         onDismiss: { dismissed = $0 })

    row.dismissTapForTesting()

    #expect(dismissed == nil,
            "Dismiss fired for a handed-back question, which has no hook left to release")
}

/// A row can carry more than one parked question (parallel tool calls each fire
/// their own hook — `AppModel.questions`'s own doc comment). The header holds
/// exactly one `Dismiss` control, so it has to name a *specific* one rather than
/// whichever `first` happens to be handed-back.
@MainActor @Test func dismissNamesTheFirstAnswerableQuestionAmongSeveral() {
    var dismissed: String?
    let handedBack = rowQuestion("q1", handedBack: true)
    let answerable = rowQuestion("q2", handedBack: false)
    let row = SessionRow(session: session(), now: t0,
                         questions: [handedBack, answerable],
                         onDismiss: { dismissed = $0 })

    row.dismissTapForTesting()

    #expect(dismissed == "q2",
            "Dismiss named \(dismissed ?? "nil") rather than \"q2\", the one answerable question among two parked ones")
}

// MARK: - The control's own visibility

/// §10.2: the control carries the meaning. `Dismiss` must actually appear when
/// there is something to give up on, and not otherwise — not merely *do the
/// right thing* if somehow tapped, which the closure-level tests above already
/// cover but which says nothing about whether the control is reachable at all.
///
/// **Scoped to the header's own band (`y < 24`), not the whole row.** The block
/// below `.rtop` also changes shape with `isHandedBack` (choices vs. one line —
/// see `theHandedBackFlagSurvivesBeingThreadedToTheRow` in `SessionRowTests`),
/// so comparing whole-row ink between an answerable and a handed-back fixture
/// would be satisfied by that alone and prove nothing about `Dismiss`
/// specifically. `headline` itself never reads `isHandedBack` — only
/// `firstAnswerableQuestionID` does — so within this band the *only* thing that
/// can differ between the two fixtures is whether `Dismiss` drew.
@MainActor @Test func dismissDrawsInTheHeaderOnlyWhenAQuestionIsAnswerable() throws {
    func headerInk(handedBack: Bool) throws -> Int {
        let raster = try rasterise(SessionRow(session: session(), now: t0,
                                              questions: [rowQuestion(handedBack: handedBack)])
            .frame(width: 388))
        var n = 0
        for y in 0..<min(24, raster.height) {
            for x in 0..<raster.width where !raster[x, y].isTransparent { n += 1 }
        }
        return n
    }

    let answerable = try headerInk(handedBack: false)
    let handedBack = try headerInk(handedBack: true)
    #expect(answerable > handedBack,
            "the header drew the same ink (\(answerable) against \(handedBack)) whether the question was answerable or already handed back — Dismiss is not gated on isHandedBack, or was never wired into the header at all")
}
