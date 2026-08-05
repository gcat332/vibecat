import Foundation

public enum JumpStrategy: Sendable, Equatable {
    case terminalSession
    case activateApp(bundleID: String)
    case vscode
    case none
}

public enum AdapterError: Error, Equatable {
    case missingField(String)
    case unknownEvent(String)
}

/// A source is configuration, not code: the differences between CLIs live in
/// `parse` and `jumpStrategy`, and nothing above this line learns their names.
public protocol SourceAdapter: Sendable {
    var id: String { get }
    var displayName: String { get }
    var jumpStrategy: JumpStrategy { get }
    /// Which kinds this source is allowed to raise. Settings narrows this.
    var reports: Set<Kind> { get }

    /// §3's *"a swappable runtime asset"* — a **path**, resolved at draw time,
    /// never the pixels themselves. `VibeCatCore` has no `AppKit` dependency and
    /// none may be added here for a picture: loading, validating and falling
    /// back to the geometric mark all belong to `VibeCatUI.SourceIcon`, which is
    /// the only place in the module graph that touches `NSImage`. This property
    /// is nothing but the string that view needs.
    ///
    /// No path this project may ship points at a committed file — §3 and the
    /// plan's own Global Constraints are explicit that a vendor logo is a
    /// trademark question, not a licence one MIT can settle, so **no adapter in
    /// `Adapters/` sets this**. It exists for a *custom* source (Task 3), where
    /// the path is something a person typed into Settings, pointing at a file on
    /// their own disk.
    ///
    /// Defaulted to `nil` below rather than required, and that default is
    /// deliberately the same value a conformer gets by forgetting to override
    /// it — the two cases must be indistinguishable, because "no icon" is
    /// exactly the fail-open (§2.3) answer for a source that never had one.
    var icon: String? { get }

    /// Returns nil when the raw payload is a well-formed event this adapter
    /// deliberately ignores.
    func parse(_ raw: [String: Any], origin: Origin) throws -> VibeEvent?
}

public extension SourceAdapter {
    /// See `icon`'s own doc comment: the default is the safe answer, not merely
    /// a convenient one, which is why this project gives one at all — a
    /// conformer that never mentions `icon` gets exactly the geometric-mark
    /// fallback it would have gotten by setting it to `nil` explicitly.
    var icon: String? { nil }
}

public struct SourceRegistry: Sendable {
    private let byID: [String: any SourceAdapter]

    /// Later adapters win on a duplicate id, so a user's custom source can
    /// deliberately override a built-in preset. Never traps: a duplicate id
    /// is user input, and Settings can produce one.
    public init(adapters: [any SourceAdapter]) {
        byID = Dictionary(adapters.map { ($0.id, $0) },
                          uniquingKeysWith: { _, later in later })
    }

    public func adapter(for id: String) -> (any SourceAdapter)? { byID[id] }

    public var ids: [String] { byID.keys.sorted() }
}
