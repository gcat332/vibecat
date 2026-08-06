import SwiftUI
import VibeCatCore

/// §11's two optional blocks under a session's own three lines.
///
/// **Takes no `accent`.** It used to, for one marker, and the mockup's row CSS
/// spends no `--accent` inside `.rblock` at all: the block's ink is `--haze` and
/// `--dim`, and its two coloured markers are `--running` and `--idle` — the
/// *item's* own state, not the session's. See `TaskMarker`. A parameter that is
/// passed by a real caller and then read by nothing is the same dead weight as
/// one with no caller, which this repo has removed twice before.
struct SessionBlocks: View {
    let session: Session
    let options: SessionRow.Options

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
        // Two `.rblock`s, each with its own `margin-top:6px` — not one list with
        // two headers in it. `spacing: 0` because the margin belongs to the block
        // (`panel` applies it), so a stack spacing would add a second one.
        VStack(alignment: .leading, spacing: 0) {
            if options.contains(.tasks), !session.tasks.isEmpty {
                RBlock {
                    RBlockHeader(title: "Tasks", detail: Self.taskSummary(session.tasks))
                    ForEach(Array(session.tasks.enumerated()), id: \.offset) { _, task in
                        taskLine(task)
                    }
                }
            }
            if options.contains(.agents), !session.agents.isEmpty {
                if options.contains(.subagents) {
                    RBlock {
                        RBlockHeader(title: "Agents", detail: "\(session.agents.count)")
                        ForEach(Array(session.agents.enumerated()), id: \.offset) { _, agent in
                            agentLine(agent)
                        }
                    }
                } else {
                    // NOTE (mockup-fidelity pass, deliberately left alone): the
                    // mockup prints `${s.agents.length} running` — the *total*,
                    // labelled "running", which is simply wrong once one of them
                    // has finished. `running` below counts the unfinished ones.
                    // See `.superpowers/sdd/mockup-fidelity-report.md`.
                    // §11: collapsed, never absent.
                    let running = session.agents.count { !$0.finished }
                    // A panel too — `agentsHTML`'s collapsed branch emits the same
                    // `<div class="rblock">` with only its `.bh` inside it. The
                    // collapse loses the detail, not the container.
                    RBlock { RBlockHeader(title: "Agents", detail: "\(running) running") }
                }
            }
        }
    }

    // `.rblock` and `.bh` moved to `RBlock`/`RBlockHeader` when Plan 9 gave them a
    // third caller — a parked question renders as one of these under its own row.
    // The CSS and the reasoning travelled with them; see that file.

    private func taskLine(_ task: TaskItem) -> some View {
        HStack(spacing: 7) {
            TaskMarker(status: task.status)
            Text(task.title)
                .font(.system(size: 11))
                .foregroundStyle(Color(task.status == .done ? dimColour : hazeColour))
                .strikethrough(task.status == .done)
                .lineLimit(1)
        }
        .padding(.vertical, 1.5)
    }

    private func agentLine(_ agent: AgentItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                // `.ag i{width:6px;height:6px;border-radius:50%;background:var(--running)}`,
                // `.ag i.ok{background:var(--idle)}`.
                Circle()
                    .fill(Color(agent.finished ? IslandState.idle.accent
                                               : IslandState.running.accent))
                    .frame(width: 6, height: 6)
                Text(agent.name).font(.system(size: 11))
                    .foregroundStyle(Color(hazeColour)).lineLimit(1)
                Spacer(minLength: 8)
                // `.ag .m{font-size:9.5px;…monospace;color:var(--dim)}`.
                Text("\(agent.elapsed) · \(agent.model)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Color(dimColour)).lineLimit(1)
            }
            .padding(.vertical, 1.5)
            // `card.activity && a.sub` (mockup, `agentsHTML` line 837): the
            // subagent's own activity line is gated by the same switch as the
            // session's, and was rendering unconditionally here. A row is meant
            // to be able to drop *every* "what is happening right now" line at
            // once; leaving the children's behind made the switch a half-switch.
            if options.contains(.activity), let activity = agent.activity {
                // `.sub{font-size:10px;…monospace;color:var(--dim);padding:0 0 2px 13px}`
                // — the indent is padding, not two leading spaces in the string.
                Text("└ \(activity)").font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(dimColour)).lineLimit(1)
                    .padding(.leading, 13)
                    .padding(.bottom, 2)
            }
        }
    }
}

/// `.tk i` — a **9×9 shape**, where this row drew `●`, `☐` and `☑`.
///
/// Glyphs were wrong in three ways at once, all visible in the rendered list: the
/// three characters have three different optical sizes and three different
/// baselines, none of them is 9pt at an 11pt font size, and `●` in particular came
/// out as a disc more than twice the mockup's. A shape is one size by
/// construction.
///
/// The hue is the **task's** state, not the row's — `.tk.doing i` is
/// `var(--running)`, which stays blue inside an amber row. That is §4.3's rule
/// applied one level down rather than an exception to it: the row's three lines
/// say how the *session* is doing, and an item inside a block says how the *item*
/// is doing. A task in progress is running whatever has happened to the session
/// around it, and this is the only reason `SessionBlocks` no longer takes the
/// row's `accent` at all.
private struct TaskMarker: View {
    let status: TaskItem.Status

    /// `border:1.5px solid rgba(255,255,255,.22)`, which `.done` also fills with.
    private static let rule = Color.white.opacity(0.22)

    var body: some View {
        // `.tk.doing i{border-radius:50%}` — in progress is the one that is round.
        let shape = RoundedRectangle(cornerRadius: status == .doing ? 4.5 : 3)
        return shape
            .fill(fill)
            .overlay(shape.strokeBorder(status == .doing ? running : Self.rule, lineWidth: 1.5))
            .frame(width: 9, height: 9)
    }

    private var running: Color { Color(IslandState.running.accent) }

    private var fill: Color {
        switch status {
        case .doing: running
        case .open:  .clear
        case .done:  Self.rule
        }
    }
}
