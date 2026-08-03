import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

/// §11: "The agent's own checklist, with a done/doing/open summary."
@Test func theTaskSummaryCountsEachStatusSeparately() {
    let tasks = [TaskItem(title: "a", status: .done),
                 TaskItem(title: "b", status: .doing),
                 TaskItem(title: "c", status: .open),
                 TaskItem(title: "d", status: .open)]
    #expect(SessionBlocks.taskSummary(tasks) == "1 done, 1 in progress, 2 open")
}

/// A summary that only ever reports totals would pass a weaker test. Zero of a
/// status must not be printed as "0 done" — that is noise on the majority of
/// real sessions.
@Test func theTaskSummaryOmitsStatusesWithNothingInThem() {
    #expect(SessionBlocks.taskSummary([TaskItem(title: "a", status: .open)]) == "1 open")
    #expect(SessionBlocks.taskSummary([]) == "")
}

/// §11, and this is the rule that matters most: "When Subagents are hidden the
/// block does not vanish — it collapses to `Agents · 2 running`, because
/// approvals and questions from a child agent still need to surface."
@MainActor @Test func hidingSubagentsCollapsesTheBlockRatherThanRemovingIt() throws {
    var e = VibeEvent(id: "e", cli: "claude-code", kind: .running, session: "s", cwd: "/tmp/api")
    e.agents = [AgentItem(name: "Explore (Search API endpoints)", elapsed: "8s", model: "Sonnet 4.6"),
                AgentItem(name: "Explore (Read config files)", elapsed: "Done", model: "Sonnet 4.6",
                          finished: true)]
    let s = Session(event: e, now: Date(timeIntervalSince1970: 1_000_000))
    let accent = Color(IslandState.running.accent)

    let shown = try rasterise(SessionBlocks(session: s, options: .all, accent: accent)
        .frame(width: 388))
    let collapsed = try rasterise(SessionBlocks(session: s, options: [.tasks, .agents], accent: accent)
        .frame(width: 388))

    #expect(collapsed.opaquePixelCount > 0,
            "hiding subagents erased the Agents block — §11 says it collapses to a count, because a child agent's question still has to surface")
    #expect(collapsed.opaquePixelCount < shown.opaquePixelCount,
            "hiding subagents changed nothing (\(collapsed.opaquePixelCount) against \(shown.opaquePixelCount)) — the option is ignored")
    #expect(collapsed.height < shown.height,
            "the collapsed block is the same height as the expanded one, so it is not collapsed")
}

/// CARRIED FINDING from Task 5's review: `turningALineOffRemovesItsInk` in
/// `SessionRowTests` flips `Options.all` against `[]` — every bit at once —
/// so it cannot tell "the `.tasks`/`.agents` gate is correct" apart from "the
/// guard checks the wrong bit entirely", since at the time only `.activity`
/// produced any ink and `.tasks`/`.agents` would have behaved identically
/// either way. Now that this task gives `.tasks` and `.agents` their own ink,
/// a per-bit test is possible for the first time: flip one bit at a time on a
/// session that has both tasks and agents, and require each bit's render to
/// differ from `[]` and from the other bit's render. This is what would catch
/// a copy-paste mistake like `options.contains(.tasks)` guarding the Agents
/// block (or vice versa) — a mistake `turningALineOffRemovesItsInk` cannot see
/// because it never isolates a single bit.
@MainActor @Test func eachBlockOptionGatesOnlyItsOwnBlock() throws {
    var e = VibeEvent(id: "e", cli: "claude-code", kind: .running, session: "s", cwd: "/tmp/api")
    e.tasks = [TaskItem(title: "Audit authentication flow", status: .doing),
               TaskItem(title: "Add regression coverage", status: .open)]
    e.agents = [AgentItem(name: "Explore (Search API endpoints)", elapsed: "8s", model: "Sonnet 4.6")]
    let s = Session(event: e, now: Date(timeIntervalSince1970: 1_000_000))
    let accent = Color(IslandState.running.accent)

    // A fixed height, not just a fixed width: `options: []` renders nothing,
    // and a `VStack` with no children resolves to zero size — `rasterise`
    // throws rather than measure a nonexistent image. Pinning the frame keeps
    // all three draws comparable on the same canvas.
    func draw(_ options: SessionRow.Options) throws -> Raster {
        try rasterise(SessionBlocks(session: s, options: options, accent: accent)
            .frame(width: 388, height: 80, alignment: .topLeading))
    }

    let none = try draw([])
    let tasksOnly = try draw(.tasks)
    let agentsOnly = try draw(.agents)

    #expect(tasksOnly.opaquePixelCount > none.opaquePixelCount,
            "`.tasks` alone drew nothing beyond an empty option set — the Tasks block is not gated by `.tasks`")
    #expect(agentsOnly.opaquePixelCount > none.opaquePixelCount,
            "`.agents` alone drew nothing beyond an empty option set — the Agents block is not gated by `.agents`")
    #expect(tasksOnly.opaquePixelCount != agentsOnly.opaquePixelCount,
            "`.tasks` alone and `.agents` alone drew the same ink — a mistake such as both bits guarding the same block would still pass a test that only ever flips them together")
}
