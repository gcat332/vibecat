import Foundation

/// Design §10.1: "A number badge marks each row and the matching number key
/// picks it." `ChoiceRow`'s badge shows `index + 1` (see that type's own doc
/// comment on `index`), so this is the inverse: digit `1` names `rows[0]`,
/// digit `2` names `rows[1]`, and so on.
///
/// A pure function of `QuestionModel.rows`, not a `NotchPanel.keyDown`
/// override's own inline arithmetic — so the mapping is checkable without
/// ever creating a window (see KeyRoutingTests, and NotchController's own
/// escape-only wiring, which needs the same "testable without a window"
/// split for the same reason).
///
/// This alone never answers a question. Nothing here calls
/// `QuestionModel.pick`/`.reply()` — it only reports which row's `id` a digit
/// names, the same way a person reads a badge without that reading being an
/// answer. Whatever eventually drives this off a real keystroke (Task 9's
/// own still-open hardware question — see `KeyDownProbe`) has to route the
/// returned id back through those same methods, exactly the way
/// `QuestionFace.tapped(_:)` already does for a mouse tap: pick, then check
/// `reply()`, never fabricate a `Reply` directly from a raw id. Skipping that
/// would let a keyboard path walk straight around §10.3's second ask, which
/// is the one thing this whole task exists to not do.
public enum KeyRouting {
    /// `nil` for anything that is not a digit `1`–`9`, or a digit past the
    /// end of `question.rows` — including `"0"`, which the badges never show
    /// (`ChoiceRow` numbers from `index + 1`, so the lowest visible badge is
    /// `1`, never `0`), and `Other…`, which is not part of `question.rows` at
    /// all no matter how many real choices exist. `Other…` is a view-only row
    /// `QuestionFace.rows` synthesises at render time (`Choice(id:
    /// "__other__", ...)`) specifically so it has no numeral — see that
    /// type's own doc comment — so there is no digit this function could ever
    /// map to it; the exclusion is structural, not a range check that happens
    /// to leave it out.
    @MainActor public static func pick(character: Character, in question: QuestionModel) -> String? {
        guard let digit = character.wholeNumberValue, (1...9).contains(digit) else { return nil }
        let index = digit - 1
        guard question.rows.indices.contains(index) else { return nil }
        return question.rows[index].id
    }

    /// Whether a keyDown's own character is Escape (U+001B). A plain string
    /// comparison against `NSEvent.charactersIgnoringModifiers`, not the
    /// `NSEvent` itself, so this is checkable with a bare string and needs no
    /// real event delivered through a window server — the same reasoning as
    /// `pick(character:in:)` taking a `Character` rather than an `NSEvent`.
    /// Unlike a digit, Escape is a control character no keyboard layout remaps
    /// to something else, so there is no per-layout ambiguity to reason about
    /// here the way there could be for a digit typed on a non-US layout.
    public static func isEscape(_ charactersIgnoringModifiers: String?) -> Bool {
        charactersIgnoringModifiers == "\u{1b}"
    }
}
