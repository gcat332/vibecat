import SwiftUI
import VibeCatCore

/// One answer a person can pick. §10.2's entire single/multi distinction
/// lives in the leading control — a numbered badge for single select, a
/// checkbox for multi — never in the label, so a single- and a multi-select
/// row must not read the same at a glance.
///
/// Presentational plus one plain callback: *what* a tap here means (pick,
/// toggle, or confirm) is `QuestionFace.tapped(_:)`'s decision, not this
/// file's — this only reports that a tap landed, for whichever choice this
/// row was built for.
struct ChoiceRow: View {
    let choice: Choice
    /// 0-based row position. Used for the single-select badge's numeral
    /// (shown as `index + 1`) and, later, for the number key that picks it
    /// (§10.1, Task 9) — the same position, so the badge never shows a digit
    /// the keyboard would disagree with. Ignored entirely when `isOther`.
    let index: Int
    let isMulti: Bool
    let isSelected: Bool
    /// §10.1: "The recommended answer is tinted, not filled." `QuestionFace`
    /// decides which row this is; never true for more than one row at once.
    let isRecommended: Bool
    let accent: Color

    /// **A nested block is not the 288pt face, and the same row cannot serve both.**
    /// `QuestionBlock` draws these inside an `.rblock` whose own ink is 10.5–11pt, and
    /// the face's scale carried in there made the *deepest* thing in a session row the
    /// biggest: measured against the prototype, a choice marker was 20×20 beside
    /// `.tk i`'s 9×9 (`island-motion.html:374`) and `.ag i`'s 6×6 (`:379`). It also cost
    /// height a scrolling list does not have — one waiting row measured **406pt** against
    /// the list's real **376pt** viewport, so a single session filled the page and
    /// everything else fell below the fold.
    ///
    /// `compact` is that second scale. Nothing else about the row changes: §10.2's rule
    /// that the control carries the meaning is about badge-versus-checkbox, not about
    /// size, so both shapes are still drawn — just smaller.
    ///
    /// Declared above `onTap` because the memberwise initialiser takes them in
    /// declaration order and every existing call site passes `onTap` last.
    var compact = false

    /// `Other…`: §10.1 lists it right after "a number badge marks each row,"
    /// but §10.2 is the rule that actually settles what it looks like —
    /// "a number badge means the click is the answer... a checkbox means it
    /// is not" — and clicking `Other…` does not answer, it opens the reply
    /// field. A numbered `Other…` would also promise a keystroke Task 9
    /// cannot honour: `KeyRouting.pick` is scoped to route `1`–`9` through
    /// `QuestionModel.rows`, which is `event.choices` and structurally
    /// excludes this synthetic row, so the badge would be a dead key by
    /// construction. Set for exactly one row, never with `isMulti`.
    var isOther: Bool = false
    /// Fires on a tap anywhere in the row. Defaulted so every existing
    /// test/preview call site (rendering only, no interaction) keeps
    /// compiling unchanged; `QuestionFace.rows` passes a real one per row.
    var onTap: () -> Void = {}

    private var controlSize: CGFloat { compact ? 13 : 20 }
    private var labelSize: CGFloat { compact ? 11 : 12.5 }
    private var verticalPadding: CGFloat { compact ? 2.5 : 8 }
    /// Zero inside a block, because `RBlock` already pads 9 and the prototype gives
    /// `.rblock`'s own items no horizontal padding at all (`.tk` `:373`, `.ag` `:378`).
    /// With both, the choices sat 10pt right of the header and command they belong to —
    /// the same misalignment `RBlock`'s doc comment records fixing in the other
    /// direction, reintroduced mirrored.
    private var horizontalPadding: CGFloat { compact ? 0 : 10 }
    private static let cornerRadius: CGFloat = 8

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            control
            // A neutral tone, not the accent: this is legible body content, not
            // a state signal, and §4.3 ("colour means state, and only
            // state") is about not inventing a *second* hue to carry
            // meaning — it does not make ordinary text illegible by
            // reserving every colour for the accent. The accent stays for
            // the pieces that actually mean something: the badge, the
            // checkbox, the recommended tint.
            //
            // Plan 4.5: `--bone` on the recommended row, `--haze` on the rest —
            // the prototype's `.choice` against `.choice.alt`, which is the one
            // place it distinguishes rows by text tone rather than by control.
            // 12.5px, not 13: `.label`/`.choice` is the prototype's most common
            // size, used nine times.
            Text(choice.label)
                .font(.system(size: labelSize))
                .foregroundStyle(Color(isRecommended ? boneColour : hazeColour))
                // A label like "Allow all pnpm commands in ~/dev/api for
                // this session" (§10.1) must wrap onto its own row instead
                // of being truncated. Without this, a `Text` inside a row
                // whose height is driven by its siblings reports its ideal
                // size as a single line and the rest is silently clipped;
                // `.fixedSize` says take the full wrapped height regardless
                // of what the row proposes.
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, verticalPadding)
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                // Tinted, never filled (§10.1): `.opacity` over the ground,
                // not a solid `.fill(accent)` — "a wide block of solid
                // colour shouts" is exactly what this must not become.
                .fill(isRecommended ? accent.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(isRecommended ? accent : Color.clear, lineWidth: 1)
        )
        // The whole row is tappable, not just its drawn content — an
        // explicit `.contentShape` because the label's `Spacer` and the
        // unfilled background (`Color.clear` on every non-recommended row)
        // would otherwise leave gaps a tap could fall through.
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    @ViewBuilder private var control: some View {
        if isMulti {
            // §10.2: "a checkbox instead of a number badge" — never a
            // numeral, so the control alone carries the distinction, not a
            // label anyone could get away with skimming past.
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? accent : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(accent, lineWidth: 1.5))
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.black)
                    }
                }
                .frame(width: controlSize, height: controlSize)
        } else if isOther {
            // Neither a numeral nor a checkbox, and deliberately not
            // accent-tinted either — colour means state (§4.3), and this
            // row is not one of the states an answer can carry. An ellipsis
            // reads as "something else," not "option N."
            Circle()
                .strokeBorder(Color(hazeColour), lineWidth: 1.5)
                .overlay(
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(hazeColour))
                )
                .frame(width: controlSize, height: controlSize)
        } else {
            // `isSelected` used to go unread on this branch entirely: a
            // single-select pick recorded correctly in the model but never
            // painted anywhere, unless the picked row also happened to be
            // the recommended one (row 0) — confirmed by rasterising before
            // and after `pick("deny")` on a three-row question and finding
            // the two renders *pixel-identical*, caught only by Step 5's
            // contact sheet, not by any of this file's read-back-the-model
            // tests. A single tap is the whole answer for this mode
            // (§10.1), so it has to be visible which one was tapped — a
            // filled badge for the pick, an outline for everything else,
            // the same filled/outline language the checkbox already uses.
            Circle()
                .fill(isSelected ? accent : Color.white.opacity(hairlineOpacity))
                .overlay(Circle().strokeBorder(accent, lineWidth: 1.5))
                .overlay(
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.black : accent)
                )
                .frame(width: controlSize, height: controlSize)
        }
    }
}
