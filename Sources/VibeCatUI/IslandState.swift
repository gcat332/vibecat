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
        // `allSatisfy(\.isHexDigit)` looks redundant with `UInt32(_:radix:)`
        // below — it is not. That initialiser accepts a leading sign, so
        // `UInt32("+5B9DF", radix: 16)` succeeds, and without this guard the
        // 7-character string "#+5B9DF" would parse as a valid colour. Keep it.
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

    /// One session's own state, for a row in §11's list. `init(store:)` answers a
    /// different question — what the *island* reports, which is the most urgent
    /// session plus `dormant` for "no sessions at all". A row is never dormant:
    /// a row exists, so a session exists.
    public init(_ state: SessionState) {
        switch state {
        case .idle:    self = .idle
        case .running: self = .running
        case .waiting: self = .waiting
        case .failed:  self = .failed
        }
    }

    public var isDormant: Bool { self == .dormant }

    /// §11's line 1 ends with the state in words as well as in colour — "Needs
    /// you ●". The words are not redundant with the dot: §4.3 reserves colour for
    /// state precisely so it can be read at a glance from the corner of an eye,
    /// and a list is the one place a person is already reading.
    public var label: String {
        switch self {
        case .dormant: "—"
        case .idle:    "Idle"
        case .running: "Running"
        case .waiting: "Needs you"
        case .failed:  "Failed"
        }
    }

    /// Colour means state and only state. Design §4.3's table covers only the
    /// four *session* states and never assigns dormant a colour — but the
    /// reference prototype (`docs/superpowers/prototypes/island-motion.html`,
    /// `--dim:#5A6273` on `.island[data-state="dormant"]`) does, and it is the
    /// authority this project has been iterating against throughout. Dormant
    /// is dim, not idle's green: a machine with no sessions at all must read
    /// as *off*, not as *a run just finished successfully* — the distinction
    /// this type exists to make in the first place. (An earlier version of
    /// this comment inferred dormant shared idle's green, reasoning it was
    /// distinguished by the cat's mood instead of a fifth hue; the prototype
    /// says otherwise, and it is the one with authority here.)
    public var accent: RGBA {
        switch self {
        case .dormant:  RGBA(hex: "#5A6273")!
        case .idle:     RGBA(hex: "#3FD99B")!
        case .running:  RGBA(hex: "#5B9DF9")!
        case .waiting:  RGBA(hex: "#FFA63C")!
        case .failed:   RGBA(hex: "#FF5C5C")!
        }
    }
}
