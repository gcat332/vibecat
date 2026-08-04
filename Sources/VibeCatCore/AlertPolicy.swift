import Foundation

/// Which of the island's agent events earn an alert — §14's four switches
/// (`settings.html:328-336`), as data.
///
/// **Lives in Core, not next to `Cue`.** The obvious signature is
/// `allows(_ cue: Cue) -> Bool`, but `Cue` is declared in `VibeCatUI/Sound`
/// alongside the oscillator tables, and `AlertPolicy` has to be visible from
/// Core so both `CueSelector` (UI) and the notifier (also UI, Task 7) can read
/// the same stored policy without Core ever importing UI — that dependency
/// direction is one-way and this repo has never inverted it.
///
/// `allows(_:)` therefore takes `Trigger`, a small Core-level enum, rather than
/// `Cue` or `VibeEvent.Kind` directly: neither existing vocabulary lines up.
/// `Kind` has `.permission` and `.question` as two separate cases where this
/// page has one switch (`Needs an answer`) governing both, and `Cue` is UI-only.
/// `Trigger` also carries `.stalled` for Task 5's detector, which nothing in
/// this file reaches yet but which the same four-switch shape already covers.
public struct AlertPolicy: Sendable, Equatable {
    /// The moments the four switches gate.
    public enum Trigger: Sendable, Equatable, CaseIterable {
        case needsAnswer, finished, failed, stalled
    }

    /// `settings.html:328-330`: `aria-checked="true"`.
    public var onNeedsAnswer: Bool
    /// `settings.html:331-333`: `aria-checked="true"`.
    public var onFinish: Bool
    /// `settings.html:333`: `aria-checked="true"`.
    public var onFail: Bool
    /// `settings.html:334-336`: `aria-checked="false"` — the one switch off by
    /// default, because a stall alert that fired on a fresh install would make
    /// an otherwise-quiet machine noisy, the opposite of §6.1's idle rule.
    public var onStall: Bool

    public init(onNeedsAnswer: Bool = true, onFinish: Bool = true,
                onFail: Bool = true, onStall: Bool = false) {
        self.onNeedsAnswer = onNeedsAnswer
        self.onFinish = onFinish
        self.onFail = onFail
        self.onStall = onStall
    }

    /// Whether this trigger is allowed to sound. Written decision 4: gating a
    /// trigger here must never be read as gating the island's own reported
    /// state — `Trigger` has no notion of §4.2's worst-state-wins and cannot
    /// express it; only what happens after it is already known.
    public func allows(_ trigger: Trigger) -> Bool {
        switch trigger {
        case .needsAnswer: onNeedsAnswer
        case .finished: onFinish
        case .failed: onFail
        case .stalled: onStall
        }
    }
}

/// A per-cue override on the Sound page (`settings.html:339-357`), one of
/// `.standard` (the cue's own default note table), `.meow`, or `.none`.
///
/// Written decision 1: `Blip` is not offered because nothing in this repo
/// defines what it sounds like — this enum has three cases, not four, on
/// purpose. Adding a case later is additive.
public enum CueChoice: String, Sendable, CaseIterable {
    case standard, meow, none
}
