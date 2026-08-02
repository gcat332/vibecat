import SwiftUI
import VibeCatCore

/// Title, the command body, and whichever content matches `question.face`:
/// the row list, or — once `Other…` is picked — the reply field. The
/// drawer's only face today; Plan 5 adds a session list beside it, which is
/// why all of this content-specific knowledge lives here rather than in
/// `DrawerView`, which stays face-agnostic.
///
/// A function of `question`'s current state, the same as `ChoiceRow` — but
/// unlike that file, this one *does* decide what a tap means (`tapped(_:)`/
/// `sendTapped()` below), because §10's rules about *when* a tap finishes
/// answering (single select sends immediately unless §10.3 asks twice;
/// multi select never auto-sends) are about the question as a whole, not
/// about any one row in isolation.
struct QuestionFace: View {
    let question: QuestionModel
    let accent: Color
    /// Fires with the `Reply` a tap actually produced — never called for a
    /// tap that only picks, toggles, or opens the reply field without
    /// finishing the answer. Defaulted so every existing test/preview call
    /// site keeps compiling unchanged; `DrawerView` passes a real one.
    var onAnswer: (Reply) -> Void = { _ in }

    /// Distance from the drawer's own left edge to where a row's own
    /// content — and so its accent border, when it has one — actually
    /// starts. Named rather than left as a bare `16` so a test can derive
    /// the drawer's expected left edge from this exact value instead of a
    /// second copy of the literal that could silently drift from it: see
    /// `islandViewComposesTheDrawerFlushBelowAndAlignedWithTheCollapsedBody`,
    /// which needs this to tell a correctly-aligned drawer apart from one
    /// whose leading offset quietly went to zero — a blanket pixel
    /// tolerance wide enough to absorb this padding as slop turned out to
    /// be wide enough to also absorb that bug.
    static let leadingPadding: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if question.isWritingOther {
                replyField
            } else {
                rows
            }
        }
        .padding(.horizontal, Self.leadingPadding)
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
            //
            // `.lineLimit(1)`: final whole-branch review, finding 2. Without
            // any limit, `.fixedSize(vertical: true)` below lets this grow to
            // as many lines as the text needs, with no ceiling — an unusually
            // long command (a long path, a long argument list) pushed the
            // rows, the confirmation banner, and eventually the reserved
            // footer down with it; measured before this fix, a 90-odd
            // character body reached row 287 of a 288pt-tall drawer, slicing
            // the banner mid-line rather than merely crowding it.
            //
            // Measured 2 lines too, before settling on 1: at this drawer's
            // real production width (§6.3's `.question` face, three choices
            // plus the §10.3 confirmation banner — the worst realistic case,
            // not a padded one), a 2-line cap still overflowed the reserved
            // footer by 8pt. There simply is not room for a second line of
            // command text alongside three rows and a banner inside a fixed
            // 288pt drawer, so 1 line is not an arbitrary choice — it is the
            // number that measured clear. `.fixedSize` still applies within
            // that cap, so an ordinary short, one-line command (the common
            // case — `rm -rf build/`, Task 8's own hardware verification) is
            // completely unaffected; only a command long enough to need a
            // second line loses the tail of it to an ellipsis.
            Text(body)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.65))
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(question.rows.enumerated()), id: \.element.id) { index, choice in
                ChoiceRow(choice: choice, index: index, isMulti: question.isMulti,
                          isSelected: question.selected.contains(choice.id),
                          isRecommended: isRecommended(index), accent: accent,
                          onTap: { tapped(choice.id) })
            }
            // §10.1 says "`Other…` is the last row" — deliberately not
            // rendered here. Final whole-branch review (2026-08-02): the row
            // was already inert going in (see the fix-round-1 comment this
            // replaces — typing into the field it opens needs the panel to
            // hold key status, Task 9's own unresolved hardware question) and
            // could not be backed out of once tapped, which reads as broken
            // rather than as not-yet-built once every *other* row in the same
            // list responds visibly. Cutting it also gives back the height
            // this file's own 44pt footer reservation (`DrawerView
            // .footerHeight`) needs: the confirmation banner below invaded
            // and then clipped that footer with the row still costing its
            // own space (see `theDrawerStaysClearOfTheFooterAfterPicking
            // ADestructiveAnswerAtProductionWidth` in DrawerGoldenTests.swift).
            // A deliberate deviation from §10.1, recorded as the reviewer's
            // decision rather than a bug it merely missed — Plan 6 (real
            // keyboard input) is where `ChoiceRow.isOther`/`beginOther()`
            // still exist for restoring it. Do not re-add this blind.
            if question.needsConfirmation {
                confirmBanner
            }
            if question.isMulti {
                sendRow
            }
        }
    }

    /// A row was tapped. Multi select only ever toggles (§10.2: the row is
    /// never itself the answer). Single select is where §10.1's "the click
    /// is the answer" and §10.3's "asks twice" meet: tapping an
    /// already-selected row that still needs confirmation is the *second*
    /// tap the confirmation banner asks for — it confirms rather than
    /// re-picking the same id — and either branch then attempts to send,
    /// which is a no-op via `reply()`'s own guard whenever confirmation is
    /// still outstanding (a fresh pick on a destructive+permissive choice).
    ///
    /// `internal`, not `private`: this is the entry point
    /// `QuestionFaceTests` calls directly to verify tap semantics without a
    /// real gesture — see that file's own doc comment on why a synthesised
    /// `NSEvent` cannot reach a SwiftUI `.onTapGesture` in this test suite.
    func tapped(_ id: String) {
        if question.isMulti {
            question.toggle(id)
            return
        }
        if question.selected.contains(id) && question.needsConfirmation {
            question.confirm()
        } else {
            question.pick(id)
        }
        if let reply = question.reply() {
            onAnswer(reply)
        }
    }

    /// Send was tapped. Multi select's own "click IS the answer" moment —
    /// checkboxes only toggle, so this is the one gesture that can actually
    /// finish a multi-select answer. `canSend`'s own guard already keeps a
    /// disabled-looking Send inert; `reply()`'s guard keeps a tap while
    /// confirmation is still outstanding from finishing anything, the same
    /// as `tapped(_:)` above. `internal` for the same reason `tapped(_:)` is.
    func sendTapped() {
        // Confirmed redundant with reply()'s own `!selected.isEmpty` guard
        // for multi select (deleting this line alone changes no test's
        // outcome) — kept anyway so a reader sees "disabled Send does
        // nothing" here directly, without tracing into reply()'s internals.
        guard question.canSend else { return }
        if question.needsConfirmation {
            question.confirm()
        }
        if let reply = question.reply() {
            onAnswer(reply)
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

    /// The confirmation banner's own copy, factored out from the view so a
    /// test can pin the exact wording without rendering — `internal`, not
    /// `private`, the same reasoning `tapped(_:)`/`sendTapped()` give.
    ///
    /// A whole-branch review minor: this used to be one fixed string naming
    /// "the highlighted choice," which is only true for single select
    /// (§10.1: the row tap itself confirms). Multi select's own confirming
    /// control is Send (§10.2: a row only ever toggles, never answers on its
    /// own — see `sendTapped()`), so a multi-select person reading the
    /// single-select wording would be told to tap a control that will not
    /// confirm anything they tap.
    static func confirmationBannerText(isMulti: Bool) -> String {
        isMulti ? "This can't be undone — tap Send again to confirm."
                : "This can't be undone — tap the highlighted choice again to confirm."
    }

    @ViewBuilder private var confirmBanner: some View {
        // §10.3: a second ask, not a second colour — this stays the state's
        // own accent rather than a new "danger" hue (§4.3: colour means
        // state, and only state).
        Text(Self.confirmationBannerText(isMulti: question.isMulti))
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
            // disabled, which stays true regardless of the tap gesture below:
            // `sendTapped()` re-checks `canSend` itself, so an unconditional
            // gesture on a visually-disabled Send is still inert, the same
            // as a real disabled control would be. This is a call-to-action
            // button, not one of the rows §10.1's "tinted, not filled" rule
            // is about, so a solid fill here when it *can* be pressed is the
            // correct treatment, not a violation of it.
            Text("Send")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(question.canSend ? Color.black : Color.white.opacity(0.35))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(question.canSend ? accent : Color.white.opacity(0.08)))
                .contentShape(Capsule())
                .onTapGesture { sendTapped() }
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
