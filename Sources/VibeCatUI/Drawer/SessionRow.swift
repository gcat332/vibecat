import SwiftUI
import VibeCatCore

/// §11: three lines per row, most urgent information first.
///
/// ```
/// ✳  api  ⑂ auth-hardening                       Needs you ●
///    ▶ Asking to run rm -rf build/         iTerm2 · Opus 4.8 · high
///    │ clean the build and rebuild from scratch
/// ```
struct SessionRow: View {
    /// §11: "Every line is individually switchable in Settings." Settings is
    /// Plan 6; the switch points have to exist here or Plan 6 rewrites this
    /// view. Line 1 is deliberately not switchable — a row with no project and
    /// no state is not a row.
    struct Options: OptionSet, Sendable {
        let rawValue: Int
        static let activity = Options(rawValue: 1 << 0)
        static let lastMessage = Options(rawValue: 1 << 1)
        static let tasks = Options(rawValue: 1 << 2)
        static let agents = Options(rawValue: 1 << 3)
        /// §11: when Subagents are hidden the block collapses to a count rather
        /// than vanishing, "because approvals and questions from a child agent
        /// still need to surface".
        static let subagents = Options(rawValue: 1 << 4)
        static let all: Options = [.activity, .lastMessage, .tasks, .agents, .subagents]
    }

    let session: Session
    let now: Date
    var options: Options = .all

    private var accent: Color { Color(IslandState(session.state).accent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            headline
            if options.contains(.activity), let activity = session.activity {
                secondLine(activity)
            }
            if options.contains(.lastMessage), let asked = session.lastUserMessage {
                Text("│ \(asked)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(hazeColour))
                    .lineLimit(2)
            }
            // `SessionBlocks` is Task 6's deliverable and is wired in there, not
            // here: it consumes `SessionRow.Options`, which this task defines, so
            // calling it from this task would make the two circular and leave
            // Task 5 unable to compile on its own.
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headline: some View {
        HStack(spacing: 6) {
            Circle().fill(accent).frame(width: 6, height: 6)
            Text(session.project)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color(boneColour))
            if let worktree = session.worktree {
                Text("⑂ \(worktree)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(hazeColour))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(IslandState(session.state).label)
                .font(.system(size: 11))
                .foregroundStyle(accent)
        }
    }

    private func secondLine(_ activity: String) -> some View {
        HStack(spacing: 6) {
            Text("▶ \(activity)")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color(boneColour))
                .lineLimit(1)
                // The same reasoning as the drawer's command body: the end of a
                // command is its target, so never elide the end.
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text([session.origin.app.map(originName), session.model, session.effort]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 11))
                .foregroundStyle(Color(hazeColour))
                .lineLimit(1)
        }
    }
}

/// A small bundle-id map for the origins §11's line 2 names by example. An
/// unknown bundle id falls back to its last dot-component so a raw identifier
/// never reaches the row — `com.example.SomeEditor` reads as "SomeEditor",
/// not as the identifier itself.
private func originName(_ bundleID: String) -> String {
    switch bundleID {
    case "com.googlecode.iterm2": "iTerm2"
    case "com.apple.Terminal":    "Terminal"
    case "com.microsoft.VSCode":  "VS Code"
    default: bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }
}
