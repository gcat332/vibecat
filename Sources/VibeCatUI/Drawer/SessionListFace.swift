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

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sessions) { session in
                    SessionRow(session: session)
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
