import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

private func session(_ state: Kind, project: String = "api") -> Session {
    var e = VibeEvent(id: "e", cli: "claude-code", kind: state, session: "s",
                      cwd: "/Users/dev/\(project)")
    e.worktree = "auth-hardening"
    e.model = "Opus 4.8"
    e.effort = "high"
    e.title = "Asking to run"
    e.body = "rm -rf build/"
    return Session(event: e, now: Date(timeIntervalSince1970: 1_000_000))
}

/// §11's line 1 carries "Project, worktree, state" — and the state is carried
/// by colour (§4.3), so the row must paint the accent of the state it is in and
/// not of any other.
@MainActor @Test func theRowWearsItsOwnStatesAccent() throws {
    for (kind, state) in [(Kind.permission, IslandState.waiting),
                          (.failed, .failed), (.running, .running)] {
        let raster = try rasterise(SessionRow(session: session(kind)).frame(width: 388))
        #expect(raster.pixelCount(near: state.accent) > 0,
                "\(kind): no \(state) accent in the row at all")
        for other in IslandState.allCases where other != state && other != .dormant {
            #expect(raster.pixelCount(near: other.accent) == 0,
                    "\(kind): the row also painted \(other)'s accent — colour must mean one state")
        }
    }
}

/// §11's own switch points. Turning a line off has to remove ink, not merely
/// stop reading a property — the failure this catches is an `Options` that is
/// threaded through and then ignored by the view.
@MainActor @Test func turningALineOffRemovesItsInk() throws {
    let s = session(.permission)
    let all = try rasterise(SessionRow(session: s, options: .all).frame(width: 388))
    let bare = try rasterise(SessionRow(session: s, options: [])
        .frame(width: 388))
    #expect(bare.opaquePixelCount < all.opaquePixelCount,
            "switching every optional line off drew the same ink (\(bare.opaquePixelCount) against \(all.opaquePixelCount)) — Options is threaded through and then ignored")
    #expect(bare.opaquePixelCount > 0,
            "switching the optional lines off erased the row entirely — line 1 is not optional in §11")
}

/// CARRIED FINDING (Task 6, review round 1): the reviewer temporarily hardcoded
/// `options: .all` at `SessionRow`'s `SessionBlocks(session:options:accent:)`
/// call site — dropping the forwarding of whatever `options` the row actually
/// received — and all 406 tests still passed. Neither this file's `session(_:)`
/// fixture (no tasks/agents, so `SessionBlocks` draws nothing regardless of
/// `options`) nor `SessionBlocksTests` (constructs `SessionBlocks` directly,
/// never going through `SessionRow`) could see the drop. This test goes
/// through `SessionRow` itself with a fixture that populates both, and fails
/// against exactly that mutation: with `options: .all` hardcoded, hiding
/// `.subagents` from the `SessionRow` call has no effect, so the two rasters
/// come out the same height instead of the collapsed one being shorter.
@MainActor @Test func sessionRowForwardsItsOptionsToSessionBlocks() throws {
    var e = VibeEvent(id: "e", cli: "claude-code", kind: .running, session: "s",
                      cwd: "/Users/dev/api")
    e.tasks = [TaskItem(title: "Audit authentication flow", status: .doing)]
    e.agents = [AgentItem(name: "Explore (Search API endpoints)", elapsed: "8s", model: "Sonnet 4.6"),
                AgentItem(name: "Explore (Read config files)", elapsed: "Done", model: "Sonnet 4.6",
                          finished: true)]
    let s = Session(event: e, now: Date(timeIntervalSince1970: 1_000_000))

    let all = try rasterise(SessionRow(session: s, options: .all).frame(width: 388))
    let subagentsHidden = try rasterise(
        SessionRow(session: s, options: [.activity, .lastMessage, .tasks, .agents])
            .frame(width: 388))

    #expect(subagentsHidden.height < all.height,
            "hiding .subagents through SessionRow rendered the same height as .all — if the call site hardcodes `options: .all` instead of forwarding what it received, this passes no matter what the row was asked to show")
}

/// §11's own first words: "**Three** lines per row." A row whose project name
/// wraps is four, and nothing here checked it.
///
/// Found by the visual fixture Plan 5's final review added
/// (`VIBECAT_LIST_SHOT`) — the first time anyone had looked at the assembled
/// list, because `ImageRenderer` renders a `ScrollView` blank and only
/// `NSHostingView` + `cacheDisplay` does not (see `rasteriseHosted`).
/// `Session.project` is `cwd`'s last path component, so its length is entirely
/// the user's, and a monorepo package directory reaches this length easily.
///
/// Compares rendered *height* against a short-named row rather than looking for
/// the wrap directly: a wrap is exactly what adds a line box, and height is the
/// property §11's "three lines" is a claim about. Everything else about the two
/// fixtures is held identical, so height is the only thing that can move.
///
/// Mutation-verified: removing `.lineLimit(1)` from `SessionRow.headline`'s
/// project `Text` renders the long-named row at 66pt against the short one's
/// 51pt — one extra line box — and this test fails with that message.
@MainActor @Test func aLongProjectNameDoesNotAddAFourthLineToTheRow() throws {
    func row(_ project: String) throws -> Raster {
        var e = VibeEvent(id: "e", cli: "claude-code", kind: .running, session: "s",
                          cwd: "/Users/dev/\(project)")
        e.title = "Asking to run"
        e.body = "rm -rf build/"
        let s = Session(event: e, now: Date(timeIntervalSince1970: 1_000_000))
        return try rasterise(SessionRow(session: s).frame(width: 388))
    }

    let short = try row("api")
    let long = try row("web-dashboard-with-a-really-quite-long-package-name")
    #expect(long.height == short.height,
            "a long project name rendered the row \(long.height)pt tall against \(short.height)pt for a short one — the name wrapped, so §11's three lines became four")
}
