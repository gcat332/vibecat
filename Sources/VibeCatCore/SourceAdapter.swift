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

    /// Returns nil when the raw payload is a well-formed event this adapter
    /// deliberately ignores.
    func parse(_ raw: [String: Any], origin: Origin) throws -> VibeEvent?
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
