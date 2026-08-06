import SwiftUI
import VibeCatCore

/// A question drawn under its own session's row, as one of the mockup's nested
/// blocks — Plan 9's whole point.
///
/// ## Why this exists where it does
///
/// `island-motion.html:832`, inside `agentsHTML`: *"hidden subagents collapse to a
/// count — approvals and questions would stay."* A question belonging inside a
/// session's `.rblock`s was the prototype's own intent and was never rendered. This
/// completes it rather than inventing against it, and reuses `RBlock`/`RBlockHeader`
/// so the container's metrics have one home.
///
/// **The visual grammar is not in the prototype and the three tiers are copied from
/// the two blocks that are.** `Tasks` and `Agents` each read as *category label +
/// one-line summary*, then item lines; this reads as `Permission` + the question's
/// own sentence, then the command, then the choices. Nothing here is derived from a
/// CSS rule for a question block, because there is none — so this is new design, and
/// saying so is more useful than implying a reference exists.
///
/// ## The two states (Plan 9 ruling C)
///
/// | State | Draws |
/// |---|---|
/// | answerable | the command, then the choices one per row |
/// | handed back | the command, then one line naming the terminal |
///
/// The hand-back happens when the hook's deadline runs out. Measured (Plan 9's own
/// protocol measurements): while a hook blocks, the CLI shows nothing of its own, so
/// the deadline is the *only* mechanism by which the terminal ever gets a prompt.
/// Once it has one, there is nothing here left to answer — hence no choices — and
/// nothing to give up on, hence no control at all.
///
/// **The command is in both states, and that is the one line here that touches
/// safety.** `.truncationMode(.middle)`, for the reason `QuestionFace` records at
/// length: before it had that, `…/build/cache/tmp` and `…/build/cache/src` rendered
/// at exactly 0 differing pixels, so a person authorising `rm -rf` could not see what
/// it was aimed at. It matters *more* in the handed-back state, which is what someone
/// reads immediately before walking to a terminal to approve something, with nothing
/// else on screen to check the target against.
///
/// ## Measured, and left as it is pending the owner's eye
///
/// A three-choice block is **161pt** tall at the row's real width; one choice is
/// 89pt, and the handed-back state is 70pt. `DrawerFace.sessionList` is 420pt in
/// total, so **two waiting sessions fill the drawer on their own** and a third
/// scrolls.
///
/// The cause is that `ChoiceRow` was built for the 288pt `.question` face and brings
/// that face's type size and row height into an 11pt nested block — the header is
/// 10.5pt, the command 11pt, and then the choices jump to `ChoiceRow`'s own scale, so
/// they dominate the block visually.
///
/// **Not "fixed" here, deliberately.** A compact variant of `ChoiceRow` would touch
/// the view `QuestionFace` depends on, and the larger type is arguably right: the
/// choices are the actionable part and the thing being decided should not be the
/// smallest text on screen. The numbers are recorded so the decision is the owner's
/// with the cost in front of them, rather than mine by omission.
///
/// **No `Dismiss` here.** Plan 9 ruling B puts it on the session row's header
/// (`.rtop`, `island-motion.html:351`), which is `SessionRow`'s, so the closure is
/// threaded from there. This view draws the question and never releases a hook.
struct QuestionBlock: View {
    let question: QuestionModel
    /// The row's state accent — §4.3: the mark, the badge and a recommended choice
    /// all share `--accent`, and a parked question does not get a hue of its own.
    let accent: Color
    /// Non-`nil` puts this block in its handed-back state, naming the terminal the
    /// question went to. `nil` while `isHandedBack` is what an unknown origin app
    /// produces, so the two are one optional rather than a `Bool` plus a `String?`
    /// that could disagree — see `handedBackTo`'s use below.
    var isHandedBack: Bool = false
    var handedBackTo: String?
    /// Fires with a choice's id. Defaulted so a rendering-only test or preview keeps
    /// compiling; `SessionRow` passes a real one.
    var onPick: (String) -> Void = { _ in }

    /// The category label, matching `Tasks`/`Agents`' grammar rather than restating
    /// the row's own `Needs you`.
    private var categoryLabel: String {
        question.event.kind == .permission ? "Permission" : "Question"
    }

    var body: some View {
        RBlock {
            RBlockHeader(title: categoryLabel, detail: question.event.title ?? "")
            if let body = question.event.body {
                // Monospaced because it is a command, at `.tk`'s own 11pt so it sits
                // in the same ink rhythm as a task line.
                //
                // `.lineLimit(1)` then `.truncationMode(.middle)`: the first decides
                // how much of a long command is shown, the second decides *which
                // part*, and only the second is a safety property. SwiftUI's default
                // is `.tail`, which elides the end — and the end of a command is its
                // target.
                Text(body)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(hazeColour))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.bottom, 2)
            }
            if isHandedBack {
                handedBackLine
            } else {
                choices
            }
        }
    }

    /// `Waiting for you in iTerm2 ↗` — and `↗` because the useful action from here is
    /// jumping, which the row's header already does.
    ///
    /// The name is never interpolated as an empty string: an unknown origin app reads
    /// `the terminal`, which is still true and still tells a person where to look. A
    /// line reading "Waiting for you in " would be a rendering bug that no colour or
    /// height assertion would catch, so `anUnknownTerminalStillProducesALine` compares
    /// the two renders instead.
    private var handedBackLine: some View {
        HStack(spacing: 5) {
            Text("Waiting for you in \(handedBackTo ?? "the terminal")")
                .font(.system(size: 11))
                .foregroundStyle(Color(hazeColour))
                .lineLimit(1)
            Text("↗")
                .font(.system(size: 9))
                .foregroundStyle(Color(dimColour))
        }
        .padding(.vertical, 1.5)
    }

    /// One per row, top to bottom, because real permission labels are sentences.
    ///
    /// `isMulti` is the question's, never hardcoded: §10.2's rule is that the control
    /// carries the meaning — a number badge means the click *is* the answer, a
    /// checkbox means it is not — so a block that always drew badges would let a
    /// multi-select question be committed by one reflex click. `ChoiceRow` already
    /// implements both and switches on this flag; this only has to pass it through,
    /// and `aMultiSelectQuestionDrawsCheckboxesRatherThanBadges` is what notices if it
    /// stops.
    ///
    /// **`isRecommended` is deliberately always `false` here.** `QuestionFace` tints
    /// the first row of a single-select question, and this block does not: at 11pt
    /// inside a `.rblock` inside a row inside a list, a tinted row would be the fourth
    /// use of `--accent` within about 40 points of vertical space — the mark, the state
    /// label, the pip, and then this. §10.1's rule is that the recommendation is
    /// *tinted, not filled* because a wide block of colour shouts; the same reasoning
    /// says a fourth accent in a dense list shouts too. Recorded rather than left as
    /// an omission someone would read as a bug.
    private var choices: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(question.rows.enumerated()), id: \.offset) { index, choice in
                ChoiceRow(choice: choice,
                          index: index,
                          isMulti: question.isMulti,
                          isSelected: question.selected.contains(choice.id),
                          isRecommended: false,
                          accent: accent,
                          onTap: { onPick(choice.id) })
            }
        }
    }
}

extension QuestionBlock {
    /// The handed-back state, spelled so a call site reads as one thing rather than as
    /// two flags that could contradict each other.
    init(question: QuestionModel, accent: Color, handedBackTo terminal: String?) {
        self.init(question: question, accent: accent,
                  isHandedBack: true, handedBackTo: terminal)
    }
}
