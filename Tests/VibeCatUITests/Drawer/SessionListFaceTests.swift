import CoreGraphics
import Foundation
import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

/// Three plain choices, single- or multi-select depending on the caller — the
/// same fixture `DrawerGoldenTests`/`QuestionFaceTests` each keep their own
/// copy of, needed here only for `aPendingQuestionOutranksTheSessionList`'s
/// "a question exists" half.
private func threeChoices(multi: Bool) -> VibeEvent {
    VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
              title: "Bash command", body: "pnpm install",
              choices: [Choice(id: "allow", label: "Allow once"),
                        Choice(id: "always", label: "Always allow"),
                        Choice(id: "deny", label: "Deny")],
              multi: multi, wantsReply: true)
}

/// §11's rows scroll inside §6.3's fixed 420pt. The failure this catches is a
/// list that grows the drawer instead of scrolling inside it — which would push
/// §6.4's reserved footer off the bottom.
@MainActor @Test func manySessionsScrollRatherThanGrowingTheDrawer() throws {
    func face(_ n: Int) throws -> Raster {
        let sessions = (0..<n).map { i in
            Session(event: VibeEvent(id: "e\(i)", cli: "claude-code", kind: .running,
                                     session: "s\(i)", cwd: "/tmp/p\(i)"),
                    now: Date(timeIntervalSince1970: 1_000_000))
        }
        return try rasterise(SessionListFace(sessions: sessions,
                                             now: Date(timeIntervalSince1970: 1_000_030))
            .frame(width: 388, height: DrawerFace.sessionList.height))
    }
    let two = try face(2).height
    let twenty = try face(20).height
    #expect(two == twenty,
            "twenty sessions rendered a different height than two — the list is growing the drawer instead of scrolling inside it")
}

/// A question must never be buried under a list — §4.2's own reasoning: a
/// waiting agent is idling on you right now.
@MainActor @Test func aPendingQuestionOutranksTheSessionList() {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.sessions = [Session(event: VibeEvent(id: "e", cli: "claude-code", kind: .running,
                                               session: "s", cwd: "/tmp/api"),
                              now: Date(timeIntervalSince1970: 1_000_000))]
    #expect(model.face == .sessionList, "with no question the drawer shows the list")

    model.question = QuestionModel(event: threeChoices(multi: false))
    #expect(model.face == .question,
            "a pending question was buried under the session list")
}
