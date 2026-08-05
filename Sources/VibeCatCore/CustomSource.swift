import Foundation

/// §3: *"Settings can add a custom source: name, icon file, jump target, and a
/// generated hook snippet."* This is that source, persisted — a wrapper
/// around `GenericAdapterConfig` rather than a second declaration of its
/// fields, so there is exactly one place `GenericAdapter` reads settings
/// from and exactly one place this file has to keep in step with Task 2.
///
/// **Why a file, not `Preferences`.** `Preferences` is a flat struct of
/// scalars read and written one field at a time; a custom source is a *list*
/// of records, each with its own nested `events` mapping, and forcing that
/// into `Preferences` would mean hand-rolling array persistence inside a type
/// built for `Bool`/`Double`/`String`. **Why a JSON file, not `UserDefaults`
/// as encoded data.** Both can hold arbitrary `Codable` data, but §3's own
/// point is that a source is *configuration* — "the differences between CLIs
/// live in `parse` and `jumpStrategy`" — and configuration a person can open
/// in a text editor and hand-edit is the feature, not a hazard to design
/// around. A `UserDefaults` blob is base64 behind `defaults write`; a JSON
/// file at a known path is something the Settings UI (Plan 6.7) can point a
/// "reveal in Finder" button at and something this plan's own tests can seed
/// with garbage bytes to prove the fail-open path.
public struct CustomSourceDefinition: Sendable {
    public var config: GenericAdapterConfig
    public init(config: GenericAdapterConfig) { self.config = config }

    /// The adapter this definition becomes. Always succeeds — every value
    /// inside `config` was already validated (or defaulted) by `decode(_:)`
    /// before a `CustomSourceDefinition` could exist at all.
    public func adapter() -> GenericAdapter { GenericAdapter(config: config) }
}

extension CustomSourceDefinition {
    /// Decodes one JSON object into a definition, or `nil` if it cannot be
    /// trusted to build a working `GenericAdapterConfig` — §2.3 applied to a
    /// hand-written file. Called per-array-element by `JSONFileCustomSourceStore
    /// .load()` rather than as one `Decodable` array, deliberately: a single
    /// malformed entry must drop only itself, not every source after it in the
    /// same file.
    ///
    /// `id`, `displayName`, `eventNameKey`, `sessionKey` and `cwdKey` are the
    /// only fields whose absence drops the whole definition — everything else
    /// degrades to a safe default instead, the same asymmetry
    /// `UserDefaultsPreferenceStore.load()` already draws between "this cannot
    /// mean anything" and "this can fall back":
    /// - an unrecognised `kind` inside `reports` is dropped from the set, not
    ///   fatal to the definition (`reports` is exposed for Settings to narrow,
    ///   never consulted by `parse` itself);
    /// - an absent or unrecognised `jumpStrategy` becomes `.none` — jump has no
    ///   code yet (this plan's own "out of scope" list), so there is nothing
    ///   this default could break;
    /// - an icon path is stored exactly as written, missing file or not:
    ///   validating it is `VibeCatUI.SourceIcon`'s job, done at *draw* time
    ///   (Task 1), and doing it again here would mean this file must be
    ///   re-decoded every time a file on disk moves;
    /// - inside `events`, an entry with an unrecognised `kind` is dropped from
    ///   the array (`compactMap`), not fatal to the source's other events —
    ///   mirroring `GenericAdapterConfig`'s own doc comment that the *type*
    ///   system is the fail-open guarantee once a `Kind` exists at all, one
    ///   layer further out where the string hasn't become one yet.
    static func decode(_ json: [String: Any]) -> CustomSourceDefinition? {
        guard let id = json["id"] as? String, !id.isEmpty,
              let displayName = json["displayName"] as? String,
              let eventNameKey = json["eventNameKey"] as? String,
              let sessionKey = json["sessionKey"] as? String,
              let cwdKey = json["cwdKey"] as? String
        else { return nil }

        let icon = json["icon"] as? String
        let modelKey = json["modelKey"] as? String
        let effortKey = json["effortKey"] as? String

        let reportsRaw = json["reports"] as? [String] ?? []
        let reports = reportsRaw.isEmpty
            ? Set(Kind.allCases)
            : Set(reportsRaw.compactMap { Kind(rawValue: $0) })

        let jumpStrategy = decodeJumpStrategy(json["jumpStrategy"])
        let events = decodeEvents(json["events"])

        let config = GenericAdapterConfig(
            id: id, displayName: displayName, icon: icon,
            jumpStrategy: jumpStrategy, reports: reports,
            eventNameKey: eventNameKey, sessionKey: sessionKey, cwdKey: cwdKey,
            modelKey: modelKey, effortKey: effortKey, events: events)
        return CustomSourceDefinition(config: config)
    }

    /// `events` is stored on disk as an **array** of named entries, not a JSON
    /// object — `[{"name": "...", "kind": "...", ...}, ...]` — precisely so a
    /// hand-edited file that repeats the same name twice cannot trap: two
    /// array entries with the same `name` decode without incident, and the
    /// dictionary they become is built with `Dictionary(_:uniquingKeysWith:)`,
    /// **not a dictionary literal** (`Dictionary(uniqueKeysWithValues:)` /
    /// `[:]` construction traps on a duplicate key). This is the exact hazard
    /// `SourceRegistry.init` already carries a comment for — a duplicate id
    /// there resolves in favour of the later adapter — applied one layer down
    /// to a duplicate event name inside a single source. Later wins here too,
    /// for the same reason: consistency, not a considered new rule.
    private static func decodeEvents(_ raw: Any?) -> [String: EventRule] {
        guard let entries = raw as? [[String: Any]] else { return [:] }
        let pairs: [(String, EventRule)] = entries.compactMap { entry in
            guard let name = entry["name"] as? String,
                  let kindRaw = entry["kind"] as? String,
                  let kind = Kind(rawValue: kindRaw)
            else { return nil }
            let wantsReply = entry["wantsReply"] as? Bool ?? false
            let titleKey = entry["titleKey"] as? String
            let bodyKey = entry["bodyKey"] as? String
            let choices: [Choice]? = (entry["choices"] as? [[String: Any]])?.compactMap { c in
                guard let cid = c["id"] as? String, let label = c["label"] as? String else { return nil }
                return Choice(id: cid, label: label)
            }
            return (name, EventRule(kind: kind, wantsReply: wantsReply,
                                    titleKey: titleKey, bodyKey: bodyKey, choices: choices))
        }
        return Dictionary(pairs, uniquingKeysWith: { _, later in later })
    }

    /// A string for the three cases with no payload, an object for the one
    /// that has one (`{"activateApp": "bundle.id"}`) — anything else,
    /// including a recognised string spelled wrong, becomes `.none` rather
    /// than dropping the whole definition. See `decode(_:)`'s own comment for
    /// why that asymmetry is deliberate here.
    private static func decodeJumpStrategy(_ raw: Any?) -> JumpStrategy {
        switch raw {
        case let s as String:
            switch s {
            case "terminalSession": return .terminalSession
            case "vscode": return .vscode
            default: return .none
            }
        case let dict as [String: Any]:
            if let bundleID = dict["activateApp"] as? String { return .activateApp(bundleID: bundleID) }
            return .none
        default:
            return .none
        }
    }

    /// The inverse of `decode(_:)` — a plain JSON-serialisable value, used by
    /// `JSONFileCustomSourceStore.save(_:)`. Round-trips everything `decode`
    /// can produce; does not need to round-trip everything `decode` can
    /// *accept*, since a hand-edited file may contain shapes this app never
    /// writes itself (that asymmetry is the whole reason `decode` exists).
    func encoded() -> [String: Any] {
        var json: [String: Any] = [
            "id": config.id,
            "displayName": config.displayName,
            "eventNameKey": config.eventNameKey,
            "sessionKey": config.sessionKey,
            "cwdKey": config.cwdKey,
            "reports": config.reports.map(\.rawValue).sorted(),
            "jumpStrategy": Self.encodeJumpStrategy(config.jumpStrategy),
            "events": config.events.map { name, rule in Self.encodeEvent(name: name, rule: rule) },
        ]
        if let icon = config.icon { json["icon"] = icon }
        if let modelKey = config.modelKey { json["modelKey"] = modelKey }
        if let effortKey = config.effortKey { json["effortKey"] = effortKey }
        return json
    }

    private static func encodeEvent(name: String, rule: EventRule) -> [String: Any] {
        var entry: [String: Any] = ["name": name, "kind": rule.kind.rawValue, "wantsReply": rule.wantsReply]
        if let titleKey = rule.titleKey { entry["titleKey"] = titleKey }
        if let bodyKey = rule.bodyKey { entry["bodyKey"] = bodyKey }
        if let choices = rule.choices {
            entry["choices"] = choices.map { ["id": $0.id, "label": $0.label] }
        }
        return entry
    }

    private static func encodeJumpStrategy(_ strategy: JumpStrategy) -> Any {
        switch strategy {
        case .terminalSession: "terminalSession"
        case .vscode:          "vscode"
        case .none:            "none"
        case .activateApp(let bundleID): ["activateApp": bundleID]
        }
    }
}

/// Same shape as `PreferenceStoring` — a store a test can substitute an
/// in-memory double for, so nothing that reads custom sources ever has to
/// touch a real file to be exercised.
public protocol CustomSourceStoring: Sendable {
    func load() -> [CustomSourceDefinition]
    func save(_ definitions: [CustomSourceDefinition])
}

/// A JSON file at `url`, defaulting to the same `Application Support`
/// directory `SocketPath` already uses for the socket itself.
///
/// **Fail open, the whole way down.** A missing file, an unreadable file, a
/// file that is not JSON at all, and a top level that is not an array of
/// objects all produce `[]` — the same answer as "no custom sources were ever
/// defined" — rather than throwing. Plan 6.2 shipped a launch path that
/// `abort()`ed on exactly this kind of input and 509 green tests never saw it,
/// because nothing ran `main.swift`; this type is what `main.swift` calls
/// instead, through `SourceRegistry.loadingCustomSources(builtIns:from:)`
/// below, so the same decode path this file's own tests exercise is the one a
/// real launch runs.
public struct JSONFileCustomSourceStore: CustomSourceStoring {
    public let url: URL

    public init(url: URL = JSONFileCustomSourceStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Application Support/VibeCat/custom-sources.json")
    }

    public func load() -> [CustomSourceDefinition] {
        guard let data = try? Data(contentsOf: url),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return array.compactMap(CustomSourceDefinition.decode)
    }

    public func save(_ definitions: [CustomSourceDefinition]) {
        let array = definitions.map { $0.encoded() }
        guard let data = try? JSONSerialization.data(withJSONObject: array,
                                                      options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// For tests, and for any surface that should not touch the user's real file
/// — same role as `InMemoryPreferenceStore`.
public struct InMemoryCustomSourceStore: CustomSourceStoring {
    private final class Box: @unchecked Sendable {
        var value: [CustomSourceDefinition]
        init(_ v: [CustomSourceDefinition]) { value = v }
    }
    private let box: Box
    public init(_ initial: [CustomSourceDefinition] = []) { box = Box(initial) }
    public func load() -> [CustomSourceDefinition] { box.value }
    public func save(_ definitions: [CustomSourceDefinition]) { box.value = definitions }
}

extension SourceRegistry {
    /// The production registry: built-in presets plus whatever custom sources
    /// `store` has, in that order. `SourceRegistry.init(adapters:)`'s own
    /// "later wins" rule then does the rest — a custom source with the same
    /// `id` as a built-in preset silently shadows it, which is designed
    /// behaviour (`SourceRegistry.init`'s own doc comment) that nothing proved
    /// end to end before `CustomSourceTests`.
    ///
    /// **This is the whole reason this function exists, rather than leaving
    /// `VibeCatHook/main.swift` build a `SourceRegistry(adapters:)` literal
    /// with an inline file read spliced in.** An `executableTarget` with a
    /// `main.swift` cannot be `@testable import`ed, so anything written
    /// directly in that file is untested by construction — Plan 6.2 shipped a
    /// launch-path `abort()` that way and 509 green tests could not see it.
    /// Putting the read, the decode and the fail-open handling here instead
    /// means `main.swift`'s own diff for this task is one call to a function
    /// this module's own tests already drive with a real `CustomSourceStoring`
    /// — see `CustomSourceTests` and the launch-wiring test in
    /// `VibeCatTransportTests` that carries this one hop further, through a
    /// real `HookRunner.run`.
    public static func loadingCustomSources(builtIns: [any SourceAdapter],
                                            from store: CustomSourceStoring) -> SourceRegistry {
        let custom = store.load().map { $0.adapter() }
        return SourceRegistry(adapters: builtIns + custom)
    }
}
