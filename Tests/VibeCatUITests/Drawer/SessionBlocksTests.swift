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

/// **All three counts, always** — the mockup's `tasksHTML` (line 824) is
/// unconditional: `${done} done, ${doing} in progress, ${len-done-doing} open`.
///
/// This test replaces `theTaskSummaryOmitsStatusesWithNothingInThem`, which
/// pinned the opposite behaviour and was written to a plan's own guess rather
/// than to the reference. Three counts in a fixed order are read positionally
/// down a column of rows; a summary whose fields come and go has to be re-read
/// as a sentence every time — and "0 done" on a session that has been running
/// for ten minutes is information, not noise.
@Test func theTaskSummaryPrintsEveryCountIncludingZeroes() {
    #expect(SessionBlocks.taskSummary([TaskItem(title: "a", status: .open)])
            == "0 done, 0 in progress, 1 open")
    #expect(SessionBlocks.taskSummary([]) == "0 done, 0 in progress, 0 open")
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

    let shown = try rasterise(SessionBlocks(session: s, options: .all)
        .frame(width: 388))
    let collapsed = try rasterise(SessionBlocks(session: s, options: [.tasks, .agents])
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

    // A fixed height, not just a fixed width: `options: []` renders nothing,
    // and a `VStack` with no children resolves to zero size — `rasterise`
    // throws rather than measure a nonexistent image. Pinning the frame keeps
    // all three draws comparable on the same canvas.
    func draw(_ options: SessionRow.Options) throws -> Raster {
        try rasterise(SessionBlocks(session: s, options: options)
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

/// The mockup gates a subagent's own activity line on the *session's* activity
/// switch — `agentsHTML` line 837, `card.activity && a.sub`. Ours drew it
/// unconditionally, which made `.activity` a half-switch: a row could be asked
/// to drop every "what is happening right now" line and would keep the
/// children's.
///
/// The session itself carries **no** activity here, so line 2's own left half is
/// absent either way and the sub-line is the only thing the switch can move.
///
/// Mutation-verified: removing `options.contains(.activity)` from
/// `SessionBlocks.agentLine` makes both renders the same height and this fails.
/// Measured — before: 30pt against 45pt, passes. After: 45pt both ways, fails.
@MainActor @Test func activityOffAlsoHidesASubagentsOwnActivityLine() throws {
    var e = VibeEvent(id: "e", cli: "claude-code", kind: .running, session: "s", cwd: "/tmp/api")
    e.agents = [AgentItem(name: "Explore (Search API endpoints)", elapsed: "8s",
                          model: "Sonnet 4.6", activity: "Grep: handleRequest")]
    let s = Session(event: e, now: Date(timeIntervalSince1970: 1_000_000))

    func draw(_ options: SessionRow.Options) throws -> Raster {
        try rasterise(SessionBlocks(session: s, options: options)
            .frame(width: 388))
    }

    let withActivity = try draw([.agents, .subagents, .activity])
    let without = try draw([.agents, .subagents])
    #expect(without.height < withActivity.height,
            "hiding `.activity` left the subagent's `└ Grep: handleRequest` line in place (\(without.height)pt against \(withActivity.height)pt) — the switch reaches the session's own line 2 and stops there")
}

// MARK: - `.rblock` is a panel

@MainActor private func blocks(_ options: SessionRow.Options = .all,
                              onGround: Bool = false,
                              scale: CGFloat = 1) throws -> Raster {
    var e = VibeEvent(id: "e", cli: "claude-code", kind: .permission, session: "s",
                      cwd: "/tmp/api")
    e.tasks = [TaskItem(title: "Audit authentication flow", status: .doing),
               TaskItem(title: "Add regression coverage", status: .open),
               TaskItem(title: "Map session state", status: .done)]
    e.agents = [AgentItem(name: "Explore (Search API endpoints)", elapsed: "8s",
                          model: "Sonnet 4.6", activity: "Grep: handleRequest"),
                AgentItem(name: "Explore (Read config files)", elapsed: "Done",
                          model: "Sonnet 4.6", finished: true)]
    let s = Session(event: e, now: Date(timeIntervalSince1970: 1_000_000))
    let view = SessionBlocks(session: s, options: options).frame(width: 320)
    return try onGround ? rasterise(view.background(Color(islandGroundColour)), scale: scale)
                        : rasterise(view, scale: scale)
}

/// `.rblock{background:rgba(255,255,255,.035);border-radius:7px;padding:7px 9px}` —
/// a **panel**. This drew `┌ Tasks` and `● item` and called that a block.
///
/// The two things a panel does that box-drawing characters cannot, asserted
/// separately because they are separate defects:
///
/// 1. **It has a background.** Measured over the island's own ground, since 3.5%
///    white composited against nothing is invisible to a colour threshold — which
///    is also true of the eye, and is why the assertion is made the way a viewer
///    sees it.
/// 2. **Its items are indented by the panel, not by a glyph.** The previous wave
///    measured the consequence off the rendered list: task and agent lines started
///    about 5pt *left of their own header*, because `┌ ` and `● ` are different
///    widths and each line carried its own indent inside a string. One padding on
///    one container cannot produce that, so the claim is simply that no content
///    reaches the panel's 9pt inset.
///
/// Mutation-verified: deleting the `.background` takes the fill count from 46471
/// to **0** and fails the first; deleting `.padding(.horizontal, 9)` puts the
/// leftmost inked column at **0** and fails the second.
@MainActor @Test func aBlockIsAPanelAndItsItemsSitInsideThePanelsPadding() throws {
    // `rgba(255,255,255,.035)` over `--void`, which is what a viewer sees.
    let fill = RGBA(hex: "#0E1014")!
    #expect(try blocks(onGround: true).pixelCount(near: fill) > 1000,
            "the blocks drew no 3.5%-white field over the ground — `.rblock` has no background, so a session's internals float in the row with nothing containing them")

    let leftmost = try blocks().leftmostInkedColumn()
    #expect(leftmost == 9,
            "the leftmost content in the blocks is at x=\(leftmost.map(String.init) ?? "nothing") — the mockup's `padding:7px 9px` puts every line, header and item alike, at 9. A line further left is a line indenting itself with a glyph instead.")
}

/// The blocks' own share of the prototype's three-rung ink ladder: `.tk`, `.ag`
/// and `.bh` are `--haze`, while `.bh em` (the summary), `.tk.done`, `.ag .m` and
/// `.sub` are `--dim`. All four `--dim` fields are things you refer back to rather
/// than read, which is the whole distinction the tier carries.
///
/// Split out from `SessionRowTests`' own tier test rather than folded into it,
/// because a row carrying blocks can satisfy either half on the strength of the
/// other: the first version of that test passed with every one of *these* fields
/// still correct and every one of the row's own collapsed.
///
/// `tolerance: 0` at `scale: 2`, for the reason spelled out at
/// `theRowSpendsAllFourOfItsInkTiers`: at this suite's usual tolerance of 6 the
/// antialiased edge of a `--haze` glyph passes through `--dim` often enough to
/// satisfy a floor on its own, and a tier is only really present when some pixel
/// sits *exactly* on it.
///
/// Mutation-verified: repointing this file's `dimColour` users at `hazeColour`
/// takes the dim count to **0** and fails.
@MainActor @Test func aBlockSpendsTheDimTierOnWhatItRefersBackTo() throws {
    let raster = try blocks(onGround: true, scale: 2)
    #expect(raster.pixelCount(near: dimColour, tolerance: 0) > 100,
            "the blocks drew \(raster.pixelCount(near: dimColour, tolerance: 0)) pixels of exactly `--dim` — the summary, the finished task, an agent's timing and its sub-line are all being drawn at the same weight as the items they annotate")
    #expect(raster.pixelCount(near: hazeColour, tolerance: 0) > 100,
            "the blocks drew \(raster.pixelCount(near: hazeColour, tolerance: 0)) pixels of exactly `--haze` — if the tier below has swallowed the tier above, the hierarchy is flattened in the other direction")
}

/// `.tk i` is a 9×9 shape and `.ag i` a 6px dot, each coloured by **its own**
/// state: `.tk.doing i{background:var(--running)}`, `.ag i.ok{background:var(--idle)}`.
/// We printed `●`, `☐`, `☑` and `●` — three optical sizes, three baselines, and an
/// agent bullet that rendered in `--bone` at more than twice the mockup's diameter.
///
/// The size is pinned **from both ends**, which is the only way to catch a glyph
/// without restating the number: a 6pt dot contains a solid 3×3 patch and cannot
/// contain a solid 6×6 one. An 11.5pt `●` contains both.
///
/// Mutation-verified: restoring `Text("● \(agent.name)")` in `boneColour` fails the
/// first two (no accent patch of either state survives) and the third (the glyph
/// makes a solid 6×6); tinting both dots `IslandState.running.accent` regardless of
/// `finished` fails the second.
@MainActor @Test func blockMarkersAreShapesSizedOnceAndTintedByTheirOwnState() throws {
    let agents = try blocks(.agents.union(.subagents))
    #expect(agents.containsSolidSquare(of: IslandState.running.accent, side: 3),
            "no `--running` patch in the Agents block — a running subagent's dot is not carrying its own state")
    #expect(agents.containsSolidSquare(of: IslandState.idle.accent, side: 3),
            "no `--idle` patch in the Agents block — a *finished* subagent is drawn exactly like a running one, which is the one thing `.ag i.ok` exists to prevent")
    #expect(!agents.containsSolidSquare(of: IslandState.running.accent, side: 6),
            "the Agents block holds a solid 6×6 patch of `--running` — the dot is bigger than the mockup's 6px, which is what a `●` glyph at this font size measures")

    // The task marker is the row's other shape, and `doing` is the filled one.
    #expect(try blocks(.tasks).containsSolidSquare(of: IslandState.running.accent, side: 5),
            "no filled `--running` marker in the Tasks block — a task in progress is drawn like one that is not")
}
