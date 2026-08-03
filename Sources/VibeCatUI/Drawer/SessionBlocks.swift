import SwiftUI
import VibeCatCore

/// §11's two optional blocks under a session's own three lines.
struct SessionBlocks: View {
    let session: Session
    let options: SessionRow.Options
    let accent: Color

    /// §11's "1 done, 1 in progress, 2 open". Statuses with nothing in them are
    /// omitted rather than printed as a zero — most real sessions have only one
    /// or two of the three, and "0 done, 0 in progress, 3 open" is noise.
    ///
    /// `nonisolated` because `SessionBlocks: View` otherwise infers this whole
    /// type — static members included — onto `@MainActor`, and this is a pure
    /// function the brief's own tests call from a non-`@MainActor` `@Test`.
    nonisolated static func taskSummary(_ tasks: [TaskItem]) -> String {
        let counts = [("done", TaskItem.Status.done),
                      ("in progress", .doing),
                      ("open", .open)]
        return counts
            .map { (label, status) in (label, tasks.count { $0.status == status }) }
            .filter { $0.1 > 0 }
            .map { "\($0.1) \($0.0)" }
            .joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if options.contains(.tasks), !session.tasks.isEmpty {
                blockHeader("Tasks", detail: Self.taskSummary(session.tasks))
                ForEach(Array(session.tasks.enumerated()), id: \.offset) { _, task in
                    taskLine(task)
                }
            }
            if options.contains(.agents), !session.agents.isEmpty {
                if options.contains(.subagents) {
                    blockHeader("Agents", detail: "\(session.agents.count)")
                    ForEach(Array(session.agents.enumerated()), id: \.offset) { _, agent in
                        agentLine(agent)
                    }
                } else {
                    // §11: collapsed, never absent.
                    let running = session.agents.count { !$0.finished }
                    blockHeader("Agents", detail: "\(running) running")
                }
            }
        }
    }

    private func blockHeader(_ title: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Text("┌ \(title)").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hazeColour))
            Text(detail).font(.system(size: 11)).foregroundStyle(Color(hazeColour))
        }
    }

    private func taskLine(_ task: TaskItem) -> some View {
        HStack(spacing: 6) {
            Text(marker(task.status)).font(.system(size: 11)).foregroundStyle(
                task.status == .doing ? accent : Color(hazeColour))
            Text(task.title)
                .font(.system(size: 11.5))
                .foregroundStyle(task.status == .done ? Color(hazeColour) : Color(boneColour))
                .strikethrough(task.status == .done)
                .lineLimit(1)
        }
    }

    /// `doing` takes the accent and the filled marker: §11's diagram shows `●`
    /// for in-progress against `☐`/`☑`, and the accent is already this session's
    /// state colour, so no new hue enters (§4.3).
    private func marker(_ status: TaskItem.Status) -> String {
        switch status {
        case .doing: "●"
        case .open:  "☐"
        case .done:  "☑"
        }
    }

    private func agentLine(_ agent: AgentItem) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text("● \(agent.name)").font(.system(size: 11.5))
                    .foregroundStyle(Color(boneColour)).lineLimit(1)
                Spacer(minLength: 8)
                Text("\(agent.elapsed) · \(agent.model)").font(.system(size: 11))
                    .foregroundStyle(Color(hazeColour)).lineLimit(1)
            }
            if let activity = agent.activity {
                Text("  └ \(activity)").font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(hazeColour)).lineLimit(1)
            }
        }
    }
}
