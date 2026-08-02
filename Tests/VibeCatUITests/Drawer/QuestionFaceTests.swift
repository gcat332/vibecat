import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

/// `QuestionFace.tapped(_:)`/`sendTapped()` are the decision logic behind
/// every tap in the drawer — pick vs. confirm for a row, when Send actually
/// finishes an answer. Called directly here, the same way
/// `NotchControllerTests` drives `click()`/`setQuestion(_:)` directly instead
/// of a real `NSEvent`: `swift test` has no window server, and this project
/// takes no view-inspection dependency that could synthesise a tap through
/// SwiftUI's own `.onTapGesture` recognition. What a *rendered* tap
/// ultimately calls is these same two methods, wired verbatim in
/// `QuestionFace.rows`/`.sendRow` — reading that wiring is a one-line check,
/// not something worth a second, indirect layer of testing.
private func threeChoices(multi: Bool, destructive: Bool = false) -> VibeEvent {
    VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
              title: "Bash command", body: destructive ? "rm -rf build/" : "pnpm install",
              choices: [Choice(id: "allow", label: "Allow once"),
                        Choice(id: "always", label: "Always allow"),
                        Choice(id: "deny", label: "Deny")],
              multi: multi, wantsReply: true)
}

@MainActor private final class ReplyBox {
    var value: Reply?
}

@MainActor private func face(_ question: QuestionModel, _ box: ReplyBox) -> QuestionFace {
    QuestionFace(question: question, accent: .white, onAnswer: { box.value = $0 })
}

// MARK: - Single select

/// §10.1: "the click IS the answer" — for an ordinary (non-destructive)
/// body, one tap both picks and finishes.
@MainActor @Test func tappingARowSendsImmediatelyWhenNothingNeedsConfirming() {
    let question = QuestionModel(event: threeChoices(multi: false))
    let box = ReplyBox()
    face(question, box).tapped("allow")

    #expect(question.selected == ["allow"])
    #expect(box.value?.choice == "allow",
            "the tap picked the row but the answer never reached onAnswer")
}

/// §10.3: destructive + permissive asks twice. The *first* tap on "allow"
/// picks it and must not send — `needsConfirmation` is what the confirmation
/// banner's own visibility already keys on (`QuestionFace.rows`), so this is
/// the same gate, checked at the call that would otherwise skip it.
@MainActor @Test func aPermissiveRowOnADestructiveBodyDoesNotSendOnTheFirstTap() {
    let question = QuestionModel(event: threeChoices(multi: false, destructive: true))
    let box = ReplyBox()
    face(question, box).tapped("allow")

    #expect(question.selected == ["allow"])
    #expect(question.needsConfirmation)
    #expect(box.value == nil, "a destructive pick sent on its first tap, skipping §10.3's second ask")
}

/// The *second* tap on the same, already-selected row is what the
/// confirmation banner's own text means by "tap the highlighted choice
/// again to confirm" — this is the tap that both confirms and finishes,
/// in one call, mirroring how the first tap both picks and finishes for a
/// non-destructive body.
@MainActor @Test func tappingTheSameRowAgainConfirmsAndSends() {
    let question = QuestionModel(event: threeChoices(multi: false, destructive: true))
    let box = ReplyBox()
    let f = face(question, box)
    f.tapped("allow")
    #expect(box.value == nil, "setup: the first tap must not have already sent")

    f.tapped("allow")

    #expect(question.isConfirming)
    #expect(box.value?.choice == "allow",
            "tapping the already-selected row again did not confirm and send")
}

/// Refusing a destructive command carries no danger (§10.3's own reasoning,
/// already pinned at the model level by `refusingADestructiveCommandNeedsNoConfirmation`
/// in `DestructiveGuardTests`) — the *tap* layer must not add a confirmation
/// step of its own on top of that.
@MainActor @Test func tappingDenyOnADestructiveBodySendsImmediately() {
    let question = QuestionModel(event: threeChoices(multi: false, destructive: true))
    let box = ReplyBox()
    face(question, box).tapped("deny")

    #expect(box.value?.choice == "deny",
            "denying a destructive command should never need a second tap")
}

/// Picking a *different* permissive choice while one is still mid-confirmation
/// must re-arm confirmation for the new pick, not silently inherit the old
/// one's already-selected id (which `tapped(_:)`'s own `selected.contains(id)`
/// check would otherwise never revisit for a fresh id).
@MainActor @Test func switchingToADifferentPermissiveRowRestartsConfirmation() {
    let question = QuestionModel(event: threeChoices(multi: false, destructive: true))
    let box = ReplyBox()
    let f = face(question, box)
    f.tapped("allow")
    #expect(question.needsConfirmation, "setup: the first pick must need confirmation")

    f.tapped("always")

    #expect(question.selected == ["always"])
    #expect(question.needsConfirmation,
            "switching to a different permissive choice did not re-arm confirmation")
    #expect(box.value == nil, "the switched-to pick sent without its own confirmation")
}

// MARK: - Multi select

/// §10.2: a row's own tap only ever toggles — it is never itself the answer,
/// unlike single select.
@MainActor @Test func tappingARowInMultiSelectOnlyToggles() {
    let question = QuestionModel(event: threeChoices(multi: true))
    let box = ReplyBox()
    face(question, box).tapped("allow")

    #expect(question.selected == ["allow"])
    #expect(box.value == nil, "a multi-select row tap sent an answer on its own")
}

@MainActor @Test func sendWithNothingSelectedDoesNothing() {
    let question = QuestionModel(event: threeChoices(multi: true))
    let box = ReplyBox()
    face(question, box).sendTapped()

    #expect(box.value == nil)
}

/// Send is multi select's own "the click IS the answer" moment (§10.2) —
/// unlike a row, which only toggles.
@MainActor @Test func sendFinishesTheAnswerWhenNothingNeedsConfirming() {
    let question = QuestionModel(event: threeChoices(multi: true))
    question.toggle("allow")
    question.toggle("always")
    let box = ReplyBox()
    face(question, box).sendTapped()

    #expect(box.value?.choices == ["allow", "always"])
}

/// §10.3 for multi select: Send is the one control that can finish the
/// answer, so it is also the one that has to carry the "asks twice" gate —
/// confirming and sending in the same tap, the same shape as a single-select
/// row's own second tap.
@MainActor @Test func sendConfirmsAndSendsInOneTapWhenConfirmationWasPending() {
    let question = QuestionModel(event: threeChoices(multi: true, destructive: true))
    question.toggle("allow")
    #expect(question.needsConfirmation, "setup: toggling a permissive choice must need confirmation")
    let box = ReplyBox()

    face(question, box).sendTapped()

    #expect(question.isConfirming)
    #expect(box.value?.choices == ["allow"],
            "Send did not confirm and send in one tap once confirmation was already pending")
}
