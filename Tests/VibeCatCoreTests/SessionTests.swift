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

/// `Session.Activity` keeps §11's line 2 in the two halves the wire sends it in.
/// It used to join them with a space, which is what stopped the row emphasising
/// the command — the field a triage list is actually scanned for. Each half must
/// survive on its own, because an event may carry either alone.
@Test func activityKeepsTitleAndBodyApart() {
    let both = Session(event: event(.permission, title: "Asking to run", body: "rm -rf build/"),
                       now: t0)
    #expect(both.activity?.sentence == "Asking to run")
    #expect(both.activity?.command == "rm -rf build/")

    let titleOnly = Session(event: event(.running, title: "Thinking"), now: t0)
    #expect(titleOnly.activity?.sentence == "Thinking")
    #expect(titleOnly.activity?.command == nil)

    let bodyOnly = Session(event: event(.running, body: "swift build"), now: t0)
    #expect(bodyOnly.activity?.sentence == nil)
    #expect(bodyOnly.activity?.command == "swift build")

    // Neither half stays `nil` activity rather than an empty `Activity`, so
    // `SessionRow` can drop line 2's left side by asking one question.
    #expect(Session(event: event(.running), now: t0).activity == nil)
}

@Test func mergeKeepsTasksWhenAnEventOmitsThem() {
    var e = event(.running)
    e.tasks = [TaskItem(title: "Audit auth flow", status: .doing)]
    var s = Session(event: e, now: t0)
    s.merge(event(.running), now: t0.addingTimeInterval(1))   // no tasks on this event
    #expect(s.tasks.count == 1)
}

@Test func mergePreservesEveryFieldABareEventOmits() {
    // An event carries only what changed. A bare event must erase nothing.
    var rich = event(.running)
    rich.worktree = "auth-hardening"
    rich.model = "Opus 4.8"
    rich.effort = "high"
    rich.title = "Editing"
    rich.body = "src/auth.swift"
    rich.tasks = [TaskItem(title: "Audit auth flow", status: .doing)]
    rich.agents = [AgentItem(name: "Explore", elapsed: "8s", model: "Sonnet 4.6")]

    var s = Session(event: rich, now: t0)
    s.merge(event(.running), now: t0.addingTimeInterval(10))   // bare: no optional fields

    #expect(s.worktree == "auth-hardening")
    #expect(s.model == "Opus 4.8")
    #expect(s.effort == "high")
    #expect(s.activity == Session.Activity(sentence: "Editing", command: "src/auth.swift"))
    #expect(s.tasks.count == 1)
    #expect(s.agents.count == 1)
    #expect(s.startedAt == t0)
    #expect(s.updatedAt == t0.addingTimeInterval(10))
}
