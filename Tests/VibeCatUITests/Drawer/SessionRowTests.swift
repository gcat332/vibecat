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
        let raster = try rasterise(SessionRow(session: session(kind),
                                              now: Date(timeIntervalSince1970: 1_000_030))
            .frame(width: 388))
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
    let now = Date(timeIntervalSince1970: 1_000_030)
    let all = try rasterise(SessionRow(session: s, now: now, options: .all).frame(width: 388))
    let bare = try rasterise(SessionRow(session: s, now: now, options: [])
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
    let now = Date(timeIntervalSince1970: 1_000_030)

    let all = try rasterise(SessionRow(session: s, now: now, options: .all).frame(width: 388))
    let subagentsHidden = try rasterise(
        SessionRow(session: s, now: now, options: [.activity, .lastMessage, .tasks, .agents])
            .frame(width: 388))

    #expect(subagentsHidden.height < all.height,
            "hiding .subagents through SessionRow rendered the same height as .all — if the call site hardcodes `options: .all` instead of forwarding what it received, this passes no matter what the row was asked to show")
}
