import SwiftUI
import VibeCatCore

/// Title, the command body, and whichever content matches `question.face`:
/// the row list, or — once `Other…` is picked — the reply field. The
/// drawer's only face today; Plan 5 adds a session list beside it, which is
/// why all of this content-specific knowledge lives here rather than in
/// `DrawerView`, which stays face-agnostic.
///
/// Purely a function of `question`'s current state, the same as
/// `ChoiceRow` — see that file's own doc comment for why nothing here wires
/// a tap to `pick`/`toggle`/`confirm` yet.
struct QuestionFace: View {
    let question: QuestionModel
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if question.isWritingOther {
                replyField
            } else {
                rows
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var header: some View {
        if let title = question.event.title {
            Text(title)
                .font(RightFlankFont.swiftUI)
                .foregroundStyle(Color.white)
        }
        if let body = question.event.body {
            // It is a command, so it reads as one (monospaced).
            Text(body)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(question.rows.enumerated()), id: \.element.id) { index, choice in
                ChoiceRow(choice: choice, index: index, isMulti: question.isMulti,
                          isSelected: question.selected.contains(choice.id),
                          isRecommended: isRecommended(index), accent: accent)
            }
            if !question.isMulti {
                // §10.1: "`Other…` is the last row." A synthetic `Choice` so
                // it shares `ChoiceRow`'s row chrome (padding, wrapping
                // label) rather than a second, driftable copy of it. Never
                // recommended, never ticked — picking it is a distinct model
                // action (`beginOther()`), not a member of `selected` — and
                // `isOther: true` gives it a control that is neither a
                // numeral nor a checkbox; see `ChoiceRow.isOther`'s own doc
                // comment for why (§10.2's rule, read the other way round,
                // resolves the §10.1/§10.2 contradiction a numbered `Other…`
                // would otherwise be). `index` is unread with `isOther`.
                ChoiceRow(choice: Choice(id: "__other__", label: "Other…"),
                          index: 0, isMulti: false,
                          isSelected: false, isRecommended: false, accent: accent,
                          isOther: true)
            }
            if question.needsConfirmation {
                confirmBanner
            }
            if question.isMulti {
                sendRow
            }
        }
    }

    /// Nothing in `VibeEvent`/`Choice` marks a choice "recommended" — the
    /// field doesn't exist anywhere on this branch. The convention rendered
    /// here is positional: row 0 is whichever choice an adapter lists
    /// first, which every fixture in this codebase already treats as the
    /// suggested one (`allow` ahead of `deny`). Single select only — §10.1
    /// is written under "Single select," and a checklist has no one answer
    /// to lead with, so multi-select never tints a row.
    private func isRecommended(_ index: Int) -> Bool {
        !question.isMulti && index == 0
    }

    @ViewBuilder private var confirmBanner: some View {
        // §10.3: a second ask, not a second colour — this stays the state's
        // own accent rather than a new "danger" hue (§4.3: colour means
        // state, and only state).
        Text("This can't be undone — tap the highlighted choice again to confirm.")
            .font(.system(size: 11))
            .foregroundStyle(accent)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sendRow: some View {
        HStack {
            Text("\(question.tally) selected")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.55))
            Spacer()
            // §10.2: "Send is disabled at zero" — and disabled has to look
            // disabled, not merely refuse a tap nobody is wiring yet: a
            // muted capsule and dimmed label versus a filled, black-on-
            // accent one. This is a call-to-action button, not one of the
            // rows §10.1's "tinted, not filled" rule is about, so a solid
            // fill here when it *can* be pressed is the correct treatment,
            // not a violation of it.
            Text("Send")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(question.canSend ? Color.black : Color.white.opacity(0.35))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(question.canSend ? accent : Color.white.opacity(0.08)))
        }
    }

    private var replyField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reply")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
            // A real `TextField` was tried here first and rendered as a
            // solid accent bar with a system "prohibited" glyph and no
            // visible text at all under `ImageRenderer` — confirmed by
            // rendering this exact face in the contact sheet before this
            // fix, caught by Step 5's own instruction to actually look at
            // the PNG rather than trust 8 passing tests that never happen
            // to exercise this face. A plain `Text` of the current value is
            // what actually rasterises: keyboard input into this field is
            // Task 8/9's wiring (the panel first has to become key), so
            // nothing is lost by not drawing a control that cannot yet be
            // typed into anyway.
            Text(question.otherText.isEmpty ? "Type your answer…" : question.otherText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(question.otherText.isEmpty ? Color.white.opacity(0.4) : Color.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.6), lineWidth: 1))
        }
    }
}
