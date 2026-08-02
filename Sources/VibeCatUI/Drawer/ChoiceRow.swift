import SwiftUI
import VibeCatCore

/// One answer a person can pick. §10.2's entire single/multi distinction
/// lives in the leading control — a numbered badge for single select, a
/// checkbox for multi — never in the label, so a single- and a multi-select
/// row must not read the same at a glance.
///
/// Purely presentational: whether a tap here does anything is Task 8's
/// wiring ("click to open, and the round trip end to end"), not this file's.
/// Nothing in this plan tests a click landing on a row — only the model
/// methods a future click would call (`pick`/`toggle`, already green in
/// `QuestionModelTests`) and the pixels this file itself produces.
struct ChoiceRow: View {
    let choice: Choice
    /// 0-based row position. Used for the single-select badge's numeral
    /// (shown as `index + 1`) and, later, for the number key that picks it
    /// (§10.1, Task 9) — the same position, so the badge never shows a digit
    /// the keyboard would disagree with.
    let index: Int
    let isMulti: Bool
    let isSelected: Bool
    /// §10.1: "The recommended answer is tinted, not filled." `QuestionFace`
    /// decides which row this is; never true for more than one row at once.
    let isRecommended: Bool
    let accent: Color

    private static let controlSize: CGFloat = 20
    private static let cornerRadius: CGFloat = 8

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            control
            // Plain white, not the accent: this is legible body content, not
            // a state signal, and §4.3 ("colour means state, and only
            // state") is about not inventing a *second* hue to carry
            // meaning — it does not make ordinary text illegible by
            // reserving every colour for the accent. The accent stays for
            // the pieces that actually mean something: the badge, the
            // checkbox, the recommended tint.
            Text(choice.label)
                .font(.system(size: 13))
                .foregroundStyle(Color.white)
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
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
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
                .frame(width: Self.controlSize, height: Self.controlSize)
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
                .fill(isSelected ? accent : Color.white.opacity(0.05))
                .overlay(Circle().strokeBorder(accent, lineWidth: 1.5))
                .overlay(
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.black : accent)
                )
                .frame(width: Self.controlSize, height: Self.controlSize)
        }
    }
}
