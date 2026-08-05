import Foundation

/// One vendor event name's mapping onto the shared `Kind` vocabulary, plus the
/// handful of extra fields `ClaudeCodeAdapter` reads for that event.
///
/// Deliberately flat. `ClaudeCodeAdapter.command(from:)` walks *into*
/// `tool_input` with a preferred-key list and a sorted-keys fallback, and its
/// "always" choice label embeds the tool name into a sentence
/// (`"Allow every \(tool_name) call this session"`). Both are a nested key
/// path plus a transform — exactly what the plan warns is "the road to a DSL"
/// — and neither is expressed here. See `GenericAdapterTests` for the
/// equivalence test that found this: everything else round-trips, this does
/// not, and the honest fix is a smaller generic adapter, not a wider one.
public struct EventRule: Sendable, Equatable {
    public var kind: Kind
    public var wantsReply: Bool
    /// A top-level key in the raw payload to read the title from. Flat only —
    /// no dotted path, no nested traversal.
    public var titleKey: String?
    /// A top-level key in the raw payload to read the body from. Flat only,
    /// same reason. Covers `Notification`'s `message`; does not cover
    /// `PreToolUse`'s `tool_input.command` (see the type's doc comment).
    public var bodyKey: String?
    /// Declared once, statically. Cannot express `PreToolUse`'s dynamic
    /// "Allow every <tool> call this session" label — that label is built from
    /// the payload, and a static list has nothing to build it from.
    public var choices: [Choice]?

    public init(kind: Kind, wantsReply: Bool = false, titleKey: String? = nil,
                bodyKey: String? = nil, choices: [Choice]? = nil) {
        self.kind = kind
        self.wantsReply = wantsReply
        self.titleKey = titleKey
        self.bodyKey = bodyKey
        self.choices = choices
    }
}

/// Everything `GenericAdapter` needs, as values — id, display name, icon path,
/// jump strategy, reported kinds, which JSON keys carry the event name /
/// session / working directory, and the per-event-name mapping onto `Kind`.
///
/// Deliberately native Swift types (`Kind`, `JumpStrategy`), not a
/// JSON-decoded shape: a `Kind` here is one of the enum's six cases by
/// construction, so "a `kind` outside the vocabulary" cannot occur — the type
/// system is the fail-open guarantee, at this layer. Loading one of these from
/// a person's config *file* is Task 3's concern, where a string that does not
/// match a `Kind` case is a decode failure to handle there, not here.
public struct GenericAdapterConfig: Sendable {
    public var id: String
    public var displayName: String
    public var icon: String?
    public var jumpStrategy: JumpStrategy
    public var reports: Set<Kind>

    /// The JSON key holding the vendor's event name, e.g. `"hook_event_name"`.
    public var eventNameKey: String
    /// The JSON key holding the session identifier, e.g. `"session_id"`.
    public var sessionKey: String
    /// The JSON key holding the working directory, e.g. `"cwd"`.
    public var cwdKey: String
    /// Optional top-level keys read unconditionally, on every event, exactly
    /// as `ClaudeCodeAdapter` reads `model` / `reasoning_effort` regardless of
    /// which hook fired.
    public var modelKey: String?
    public var effortKey: String?

    /// Vendor event name → what it means. A name absent from this dictionary
    /// is a well-formed event this source deliberately does not surface —
    /// see `GenericAdapter.parse` for why that is `nil`, not a thrown error.
    public var events: [String: EventRule]

    public init(id: String, displayName: String, icon: String? = nil,
                jumpStrategy: JumpStrategy, reports: Set<Kind>,
                eventNameKey: String, sessionKey: String, cwdKey: String,
                modelKey: String? = nil, effortKey: String? = nil,
                events: [String: EventRule]) {
        self.id = id
        self.displayName = displayName
        self.icon = icon
        self.jumpStrategy = jumpStrategy
        self.reports = reports
        self.eventNameKey = eventNameKey
        self.sessionKey = sessionKey
        self.cwdKey = cwdKey
        self.modelKey = modelKey
        self.effortKey = effortKey
        self.events = events
    }
}

/// A `SourceAdapter` whose behaviour is entirely `GenericAdapterConfig` —
/// no vendor's name is known above this line. §3: *"a source is configuration,
/// not code."*
///
/// `parse`'s three required-field guards, in this order (name, session, cwd,
/// *then* look up the event), deliberately mirror `ClaudeCodeAdapter`'s own
/// order — a payload missing `session_id` still throws even for an event name
/// this config does not declare, because that is what the preset it is meant
/// to replace does, and the equivalence test in `GenericAdapterTests` checks it.
public struct GenericAdapter: SourceAdapter {
    public let config: GenericAdapterConfig

    public init(config: GenericAdapterConfig) {
        self.config = config
    }

    public var id: String { config.id }
    public var displayName: String { config.displayName }
    public var icon: String? { config.icon }
    public var jumpStrategy: JumpStrategy { config.jumpStrategy }
    public var reports: Set<Kind> { config.reports }

    public func parse(_ raw: [String: Any], origin: Origin) throws -> VibeEvent? {
        guard let name = raw[config.eventNameKey] as? String else {
            throw AdapterError.missingField(config.eventNameKey)
        }
        guard let session = raw[config.sessionKey] as? String else {
            throw AdapterError.missingField(config.sessionKey)
        }
        guard let cwd = raw[config.cwdKey] as? String else {
            throw AdapterError.missingField(config.cwdKey)
        }

        // An event name this config never declared is almost certainly a
        // well-formed event this source deliberately does not surface — the
        // same shape as ClaudeCodeAdapter's `default: return nil`. Mapping it
        // to a default Kind instead would invent state the CLI never
        // reported, so this is `nil`, never `AdapterError.unknownEvent`.
        guard let rule = config.events[name] else { return nil }

        return VibeEvent(
            id: UUID().uuidString,
            cli: config.id,
            kind: rule.kind,
            session: session,
            cwd: cwd,
            model: config.modelKey.flatMap { raw[$0] as? String },
            effort: config.effortKey.flatMap { raw[$0] as? String },
            title: rule.titleKey.flatMap { raw[$0] as? String },
            body: rule.bodyKey.flatMap { raw[$0] as? String },
            choices: rule.choices,
            wantsReply: rule.wantsReply,
            origin: origin)
    }
}
