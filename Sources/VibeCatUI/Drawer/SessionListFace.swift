import SwiftUI
import VibeCatCore

/// §11's list. Face-level only: the ordering is `SessionStore.mostUrgentFirst`'s
/// and the row is `SessionRow`'s, so this file owns nothing but the scroll and
/// the dividers.
/// F10 of Plan 5's final whole-branch review removed two parameters from here,
/// and the two removals are not the same kind of thing:
///
/// - `now:` was **genuinely dead** — threaded down to `SessionRow` and never
///   read by anything, because no line of §11 is a duration.
/// - `options:` was read and forwarded, but **nothing anywhere ever passed it**,
///   test or production, so no render ever exercised a value other than `.all`.
///   `SessionRow.Options` itself stays: it is §11's "every line is individually
///   switchable in Settings" switch point, and `sessionRowForwardsItsOptionsTo
///   SessionBlocks` pins its forwarding by mutation one level down. Plan 6 has
///   to re-thread one parameter through here when it wires Settings up; that is
///   a deliberate one-line cost, recorded in plans/README.md, rather than a
///   parameter kept alive on the strength of a caller that does not exist.
struct SessionListFace: View {
    let sessions: [Session]

    /// A running row's state field is an elapsed time, not a word (the mockup's
    /// `SESSIONS` gives one `state:'2m 14s'`), so the list needs a clock.
    ///
    /// **A real branch, not a paused timeline** — the same shape, and the same
    /// measurement, as `IslandView.body`: a paused-but-present `TimelineView`
    /// still costs ~6% of a core, and removing it costs 0.0%. With nothing
    /// running there is no duration on screen to advance, so there is nothing
    /// for a timeline to do and it is not created. This also satisfies the
    /// condition the removal of `SessionRow.now` was recorded under: "a `now`
    /// that never advances is worse than no `now` at all."
    ///
    /// Not gated on `MotionPreference`: a clock ticking is information, not
    /// motion, and §7's reduce-motion rule is about movement.
    private var needsClock: Bool { sessions.contains { $0.state == .running } }

    /// One second. `RevealContent.elapsed` only resolves finer than a minute
    /// below the first minute, so this is as fast as any visible digit changes.
    private static let clockInterval: Double = 1

    var body: some View {
        if needsClock {
            TimelineView(.animation(minimumInterval: Self.clockInterval, paused: false)) { ctx in
                list(now: ctx.date)
            }
        } else {
            list(now: Date())
        }
    }

    private func list(now: Date) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sessions) { session in
                    SessionRow(session: session, now: now)
                    if session.id != sessions.last?.id {
                        Rectangle()
                            .fill(Color.white.opacity(hairlineOpacity))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, QuestionFace.leadingPadding)
        }
        // §6.3: "420pt, rows scroll" — a fixed height with the content scrolling
        // inside it, never a height that follows the content. Growing would push
        // §6.4's reserved footer off the bottom.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollIndicators(.never)
    }
}
