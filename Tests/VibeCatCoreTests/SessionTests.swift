import Foundation
import Testing
@testable import VibeCatCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func event(_ kind: Kind, cwd: String = "/Users/me/dev/api",
                   title: String? = nil, body: String? = nil) -> VibeEvent {
    VibeEvent(id: "e", cli: "claude-code", kind: kind,
              session: "s1", cwd: cwd, title: title, body: body)
}

@Test func projectIsTheLastPathComponentOfCwd() {
    let s = Session(event: event(.running), now: t0)
    #expect(s.project == "api")
}

@Test func identityIsCliPlusSessionId() {
    let s = Session(event: event(.running), now: t0)
    #expect(s.id == SessionKey(cli: "claude-code", session: "s1"))
}

@Test func mergeAdvancesStateAndTimestamp() {
    var s = Session(event: event(.running), now: t0)
    s.merge(event(.permission), now: t0.addingTimeInterval(30))
    #expect(s.state == .waiting)
    #expect(s.updatedAt == t0.addingTimeInterval(30))
    #expect(s.startedAt == t0)          // start time is never rewritten
}

@Test func activityCombinesTitleAndBody() {
    let s = Session(event: event(.permission, title: "Asking to run", body: "rm -rf build/"),
                    now: t0)
    #expect(s.activity == "Asking to run rm -rf build/")
}

@Test func mergeKeepsTasksWhenAnEventOmitsThem() {
    var e = event(.running)
    e.tasks = [TaskItem(title: "Audit auth flow", status: .doing)]
    var s = Session(event: e, now: t0)
    s.merge(event(.running), now: t0.addingTimeInterval(1))   // no tasks on this event
    #expect(s.tasks.count == 1)
}
