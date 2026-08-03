import SwiftUI
import VibeCatCore

/// §11's list. Face-level only: the ordering is `SessionStore.mostUrgentFirst`'s
/// and the row is `SessionRow`'s, so this file owns nothing but the scroll and
/// the dividers.
struct SessionListFace: View {
    let sessions: [Session]
    let now: Date
    var options: SessionRow.Options = .all

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sessions) { session in
                    SessionRow(session: session, now: now, options: options)
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
