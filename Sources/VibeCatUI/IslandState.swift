import Foundation      // String(format:)
import VibeCatCore

public struct RGBA: Sendable, Equatable {
    public let r: Double
    public let g: Double
    public let b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Strict on purpose: a colour that silently decodes wrong is a bug that
    /// only shows up as a slightly off island.
    public init?(hex: String) {
        guard hex.count == 7, hex.hasPrefix("#") else { return nil }
        let digits = hex.dropFirst()
        guard digits.allSatisfy(\.isHexDigit), let v = UInt32(digits, radix: 16)
        else { return nil }
        r = Double((v >> 16) & 0xFF) / 255
        g = Double((v >> 8) & 0xFF) / 255
        b = Double(v & 0xFF) / 255
    }

    public var hex: String {
        let c = { (x: Double) in Int((x * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}

/// What the island is reporting. Adds `dormant` to Core's four session states,
/// because "no sessions at all" is a property of the store, not of a session.
public enum IslandState: String, Sendable, CaseIterable {
    case dormant, idle, running, waiting, failed

    public init(store: SessionStore) {
        guard !store.sessions.isEmpty else { self = .dormant; return }
        switch store.aggregate {
        case .idle:    self = .idle
        case .running: self = .running
        case .waiting: self = .waiting
        case .failed:  self = .failed
        }
    }

    public var isDormant: Bool { self == .dormant }

    /// Colour means state and only state. Dormant shares idle's green: it is
    /// distinguished by the cat's mood, not by a fifth hue competing for
    /// meaning. Design §4.3.
    public var accent: RGBA {
        switch self {
        case .dormant, .idle: RGBA(hex: "#3FD99B")!
        case .running:        RGBA(hex: "#5B9DF9")!
        case .waiting:        RGBA(hex: "#FFA63C")!
        case .failed:         RGBA(hex: "#FF5C5C")!
        }
    }
}
