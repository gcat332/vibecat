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
