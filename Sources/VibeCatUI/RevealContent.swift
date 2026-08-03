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
    /// How many units of the duration to print.
    ///
    /// Two granularities on **one** formatter, deliberately not two formatters:
    /// the collapsed bar's reveal and §11's row would then be free to disagree
    /// about what "two minutes" looks like, which is the failure mode the reveal's
    /// formatter was shared to prevent.
    enum Precision: Sendable {
        /// One unit — `2m`. The reveal has 150pt for a project name *and* a
        /// duration, and a second unit there costs the name characters it needs
        /// more.
        case coarse
        /// Two units — `2m 14s`, the mockup's own `state:'2m 14s'` and
        /// `state:'0m 38s'`. §11's row has the width for it, and it is the
        /// difference between a triage list that shows a run *moving* and one
        /// where the number sits still for a minute at a time.
        case fine
    }

    nonisolated static func elapsed(_ interval: TimeInterval,
                                    precision: Precision = .coarse) -> String {
        let s = Int(max(0, interval))
        switch precision {
        case .coarse:
            if s < 60 { return "\(s)s" }
            if s < 3600 { return "\(s / 60)m" }
            if s < 86_400 { return "\(s / 3600)h" }
            return "\(s / 86_400)d"
        case .fine:
            // Under a minute stays `0m 38s` rather than falling back to `38s` —
            // the mockup's third session is exactly that case, and a state field
            // that changes shape as it crosses a minute cannot be read down a
            // column.
            if s < 3600 { return "\(s / 60)m \(s % 60)s" }
            if s < 86_400 { return "\(s / 3600)h \((s % 3600) / 60)m" }
            return "\(s / 86_400)d \((s % 86_400) / 3600)h"
        }
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
