import SwiftUI
import VibeCatCore

/// §5.2's "name and timings on hover", and §9.1's reveal content — promised
/// since the design doc and, until Plan 5, revealed as 150pt of empty ground.
struct RevealContent: View {
    let session: Session?
    let now: Date

    /// Measured from `updatedAt`, not `startedAt`: §1's premise is that "an
    /// agent that asked a question five minutes ago has been idle for five
    /// minutes", so time *in the current state* is the number that matters.
    /// Clamped at zero because the hook's clock and this process's are not the
    /// same clock.
    ///
    /// Explicitly `nonisolated`: `RevealContent`'s conformance to `View`
    /// infers `@MainActor` onto every member by default, including this one —
    /// see `IslandView.minimumInterval(for:)`'s own doc comment for the exact
    /// same reasoning. This is a pure calculation over `Sendable` value types
    /// with no actor-isolated state to touch, so it should be freely callable
    /// (and testable) from anywhere, `body` included.
    nonisolated static func elapsed(_ interval: TimeInterval) -> String {
        let s = Int(max(0, interval))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86_400 { return "\(s / 3600)h" }
        return "\(s / 86_400)d"
    }

    var body: some View {
        if let session {
            HStack(spacing: 6) {
                Text(session.project)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color(boneColour))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Self.elapsed(now.timeIntervalSince(session.updatedAt)))
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(Color(hazeColour))
            }
        }
    }
}
