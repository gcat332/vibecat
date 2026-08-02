import Foundation
import Observation
import VibeCatCore

/// What the drawer is showing and what has been chosen so far.
///
/// Deliberately free of SwiftUI: every rule §10 states — one tap answers a
/// single select, Send is dead at zero, `Other…` shrinks the drawer — is
/// decided here, where it can be tested without a render.
@Observable
@MainActor
public final class QuestionModel {
    public let event: VibeEvent
    public private(set) var selected: Set<String> = []
    public private(set) var isWritingOther = false
    public var otherText = ""
    public private(set) var isConfirming = false

    public init(event: VibeEvent) { self.event = event }

    /// True once a *permissive* answer has been picked for a body §10.3 names.
    /// Refusing a destructive command carries no danger, so a `deny` pick
    /// never trips this — only `allow`/`always` do.
    ///
    /// The same reasoning covers `Other…`: `beginOther()` clears `selected`,
    /// and this reads only `selected`, so a free-text reply can never trip it
    /// either. That is a decision, not an oversight — writing something else
    /// in place of the proposed command *is* a refusal of it, the same shape
    /// as picking `deny`, not an authorisation that merely took a different
    /// form. Pinned by `aFreeTextReplyToADestructiveBodyNeedsNoConfirmation`.
    public var needsConfirmation: Bool {
        guard DestructiveGuard.matches(event.body) else { return false }
        guard !isConfirming else { return false }
        return selected.contains(where: DestructiveGuard.isPermissive)
    }

    public func confirm() { isConfirming = true }

    public var rows: [Choice] { event.choices ?? [] }
    public var isMulti: Bool { event.multi }

    public var face: DrawerFace {
        if isWritingOther { return .questionWithReply }
        return isMulti ? .questionMulti : .question
    }

    /// Single select: the click *is* the answer (§10.1), so this both records
    /// the pick and makes `reply()` non-nil.
    public func pick(_ id: String) {
        guard !isMulti else { return }
        selected = [id]
    }

    public func toggle(_ id: String) {
        guard isMulti else { return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    public func beginOther() {
        isWritingOther = true
        selected = []
    }

    /// Only ever consulted for multi select — a single select has no Send.
    public var canSend: Bool { isMulti && !selected.isEmpty }

    public var tally: Int { selected.count }

    public func reply() -> Reply? {
        // One gate, above all three branches — §10.3's guard has to bind the
        // answer itself, not just the drawer's own UI state, or an agent
        // reading only the returned Reply would never see it withheld.
        guard !needsConfirmation else { return nil }
        if isWritingOther {
            let text = otherText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return Reply(id: event.id, text: text)
        }
        if isMulti {
            guard !selected.isEmpty else { return nil }
            return Reply(id: event.id, choices: selected.sorted())
        }
        guard let one = selected.first else { return nil }
        return Reply(id: event.id, choice: one)
    }
}
