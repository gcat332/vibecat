import SwiftUI
import VibeCatCore

/// §11's two optional blocks under a session's own three lines.
struct SessionBlocks: View {
    let session: Session
    let options: SessionRow.Options
    let accent: Color

    /// §11's "1 done, 1 in progress, 2 open" — **all three counts, always,
    /// zeros included.**
    ///
    /// This used to drop statuses with nothing in them, on the reasoning that
    /// "0 done, 0 in progress, 3 open" is noise. The mockup is unconditional
    /// (`tasksHTML`, line 824: `${done} done, ${doing} in progress,
    /// ${len-done-doing} open`) and it is right: three counts in a fixed order
    /// are a shape the eye learns once and then reads positionally down a
    /// column of rows, while a summary whose fields come and go has to be read
    /// as a sentence every time. The zeros also carry information a triage list
    /// wants — "0 done" on a session that has been running for ten minutes is
    /// the point.
    ///
    /// `nonisolated` because `SessionBlocks: View` otherwise infers this whole
    /// type — static members included — onto `@MainActor`, and this is a pure
    /// function the brief's own tests call from a non-`@MainActor` `@Test`.
    nonisolated static func taskSummary(_ tasks: [TaskItem]) -> String {
        let counts = [("done", TaskItem.Status.done),
                      ("in progress", .doing),
                      ("open", .open)]
        return counts
            .map { (label, status) in "\(tasks.count { $0.status == status }) \(label)" }
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
                    // NOTE (mockup-fidelity pass, deliberately left alone): the
                    // mockup prints `${s.agents.length} running` — the *total*,
                    // labelled "running", which is simply wrong once one of them
                    // has finished. `running` below counts the unfinished ones.
                    // See `.superpowers/sdd/mockup-fidelity-report.md`.
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
            // `card.activity && a.sub` (mockup, `agentsHTML` line 837): the
            // subagent's own activity line is gated by the same switch as the
            // session's, and was rendering unconditionally here. A row is meant
            // to be able to drop *every* "what is happening right now" line at
            // once; leaving the children's behind made the switch a half-switch.
            if options.contains(.activity), let activity = agent.activity {
                Text("  └ \(activity)").font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(hazeColour)).lineLimit(1)
            }
        }
    }
}
