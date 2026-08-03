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

// MARK: - §9.1's face crossfade

/// §9.1: "Face crossfade `190ms`, fade up 5pt with a 3pt blur", and the
/// prototype's `--t-face: 190ms`. Specified since the design doc and
/// unimplemented until Plan 4.5 — recorded unassigned twice before that.
///
/// A transition is at identity in any static render, so this asserts the modifier
/// mid-flight against its identity.
///
/// **`presence: 0.5`, not `0`, and the reason is a measured `ImageRenderer`
/// quirk worth knowing before writing any test against opacity.** Measured
/// directly: `.opacity(0)` under `ImageRenderer` is *ignored* — a label at
/// opacity 0 rendered the same 372 opaque pixels as one at full opacity, while
/// `.offset` and `.blur` both applied normally. And `opaquePixelCount` cannot see
/// opacity at all in between, because a half-alpha pixel still has `a > 0` (0.5
/// measured 367 against 372). So an "is it invisible" assertion at the extreme
/// would have been vacuous twice over. Mid-flight is also the state that actually
/// matters — it is what a person sees.
@MainActor @Test func theFaceCrossfadeFadesUpAndBlursRatherThanSliding() throws {
    let label = Text("Allow once").font(.system(size: 12.5)).foregroundStyle(Color.white)
        .frame(width: 120, height: 40)

    // Nested one level rather than rasterised bare: the effects need something to
    // composite against, which is also how they are used — a face inside the
    // drawer's own VStack.
    func render(_ presence: Double) throws -> Raster {
        try rasterise(ZStack { label.modifier(FaceCrossfade(presence: presence)) }
            .frame(width: 130, height: 50))
    }
    let atRest = try render(1)
    let midFlight = try render(0.5)

    #expect(atRest.width == midFlight.width && atRest.height == midFlight.height,
            "the crossfade changed the face's *size* — §9.1 says a face fades in inside a shape that is already the right size, so this must never alter layout")
    #expect(atRest.differingPixelCount(from: midFlight) > 200,
            "only \(atRest.differingPixelCount(from: midFlight)) pixels differ between rest and mid-crossfade — the rise and blur are not reaching the render")
    // The blur is the leg with a signature no other effect has: it spreads ink
    // into pixels that were empty at rest, so mid-flight must draw *more*
    // non-transparent pixels than the sharp version, not fewer.
    #expect(midFlight.opaquePixelCount > atRest.opaquePixelCount,
            "mid-crossfade drew \(midFlight.opaquePixelCount) pixels against \(atRest.opaquePixelCount) sharp — a 3pt blur must spread ink outward, so this leg is missing")
}

/// The numbers are §9.1's, so they are pinned rather than left to drift with a
/// later tuning pass. `duration` in particular is read twice — once by the
/// transition and once by the `.animation` driving it — and a mismatch between
/// those two would be silent in every render.
@MainActor @Test func theFaceCrossfadeCarriesTheDesignsOwnNumbers() {
    #expect(FaceCrossfade.duration == 0.190, "§9.1 and --t-face both say 190ms")
    #expect(FaceCrossfade.rise == 5, "§9.1 says fade up 5pt")
    #expect(FaceCrossfade.blurRadius == 3, "§9.1 says with a 3pt blur")
}

// MARK: - Confirmation banner copy

/// A whole-branch review minor: the banner's copy used to be one fixed
/// string naming "the highlighted choice," which is wrong for multi select —
/// there, a row tap only ever toggles (§10.2) and Send is the control that
/// actually confirms (`sendTapped()`, pinned by the test above). Checked
/// directly against the pure function rather than by rendering: a rendered
/// pixel comparison could show the banner's *position* changing without ever
/// confirming which words it actually says.
/// `@MainActor` like every other test in this file: `QuestionFace` conforms to
/// `View`, so even a pure static helper on it is main-actor isolated, and
/// calling it from a nonisolated test was this branch's one compiler warning.
@MainActor @Test func theConfirmationBannerNamesTheControlThatActuallyConfirms() {
    let single = QuestionFace.confirmationBannerText(isMulti: false)
    let multi = QuestionFace.confirmationBannerText(isMulti: true)

    #expect(single.contains("highlighted choice"))
    #expect(multi.contains("Send"))
    #expect(multi.contains("highlighted choice") == false,
            "multi select's banner still names the row tap, which never confirms a multi-select answer")
    #expect(single != multi, "single and multi select must not share identical confirmation copy")
}
