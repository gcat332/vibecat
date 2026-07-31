import Foundation
import Testing
@testable import VibeCatCore

@Test func kindCoversEveryWireValue() {
    #expect(Set(Kind.allCases.map(\.rawValue)) ==
            ["idle", "running", "done", "permission", "question", "failed"])
}

@Test func eventDefaultsAreSafe() {
    let e = VibeEvent(id: "a", cli: "claude-code", kind: .running,
                      session: "s1", cwd: "/tmp/api")
    #expect(e.v == 1)
    #expect(e.multi == false)
    #expect(e.wantsReply == false)
    #expect(e.choices == nil)
    #expect(e.origin == Origin())
}

@Test func taskItemUsesShortWireKeys() throws {
    let json = #"{"t":"Audit auth flow","s":"doing"}"#
    let item = try JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
    #expect(item.title == "Audit auth flow")
    #expect(item.status == .doing)
}

@Test func agentItemUsesShortWireKeys() throws {
    let json = #"{"n":"Explore","t":"8s","m":"Sonnet 4.6 · High","sub":"Grep: handleRequest"}"#
    let a = try JSONDecoder().decode(AgentItem.self, from: Data(json.utf8))
    #expect(a.name == "Explore")
    #expect(a.elapsed == "8s")
    #expect(a.model == "Sonnet 4.6 · High")
    #expect(a.activity == "Grep: handleRequest")
    #expect(a.finished == false)
}

@Test func decodingSuppliesDefaultsForAbsentKeys() throws {
    // Only the required keys; everything defaulted must come from init(from:).
    let json = #"{"id":"a","cli":"claude-code","kind":"running","session":"s1","cwd":"/tmp"}"#
    let e = try JSONDecoder().decode(VibeEvent.self, from: Data(json.utf8))
    #expect(e.v == 1)
    #expect(e.multi == false)
    #expect(e.wantsReply == false)
    #expect(e.origin == Origin())
    #expect(e.choices == nil)
    #expect(e.tasks == nil)
}

@Test func encodingEmitsTheShortWireKeys() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let task = try String(decoding: encoder.encode(TaskItem(title: "Audit", status: .doing)),
                          as: UTF8.self)
    #expect(task == #"{"s":"doing","t":"Audit"}"#)

    let agent = try String(decoding: encoder.encode(
        AgentItem(name: "Explore", elapsed: "8s", model: "Sonnet 4.6", activity: "Grep")),
                           as: UTF8.self)
    #expect(agent == #"{"done":false,"m":"Sonnet 4.6","n":"Explore","sub":"Grep","t":"8s"}"#)
}
