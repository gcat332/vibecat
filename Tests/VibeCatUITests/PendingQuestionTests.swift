import Foundation
import Testing
import VibeCatCore
@testable import VibeCatUI

private func question(id: String = "q1") -> VibeEvent {
    VibeEvent(id: id, cli: "claude-code", kind: .permission, session: "s1", cwd: "/tmp/proj",
              choices: [Choice(id: "allow", label: "Allow once"),
                        Choice(id: "deny", label: "Deny")],
              wantsReply: true)
}

@Test func anAnsweredQuestionHandsTheReplyBackToTheWaiter() async throws {
    let p = PendingQuestion(event: question(), deadline: 5)
    let waiter = Task.detached { p.await() }
    // Resolve from another thread, as the UI will.
    try await Task.sleep(for: .milliseconds(20))
    #expect(p.resolve(Reply(id: "q1", choice: "allow")))
    let reply = await waiter.value
    #expect(reply?.choice == "allow")
}

@Test func anUnansweredQuestionTimesOutAndFailsOpen() {
    let p = PendingQuestion(event: question(), deadline: 0.05)
    let start = Date()
    let reply = p.await()
    #expect(reply == nil, "a question nobody answered must return nil so the CLI prompts itself")
    #expect(Date().timeIntervalSince(start) < 1.0, "await outran its deadline")
}

/// The hook has already given up and the CLI has printed its own prompt. An
/// answer given in the island after that point would be answering a question
/// nobody is listening to — and could differ from what the person then types
/// into the terminal.
@Test func aLapsedQuestionStopsBeingAnswerable() {
    let p = PendingQuestion(event: question(), deadline: 0.05)
    _ = p.await()                                   // let it time out
    #expect(p.hasLapsed(at: Date()))
    #expect(p.resolve(Reply(id: "q1", choice: "allow")) == false,
            "resolve() succeeded on a question that had already lapsed")
}

@Test func aReplyForADifferentQuestionIsRefused() {
    let p = PendingQuestion(event: question(id: "q1"), deadline: 5)
    #expect(p.resolve(Reply(id: "someone-elses", choice: "allow")) == false)
}

/// Two resolves race only in theory — the UI is main-actor — but the waiter
/// must be signalled exactly once either way, or the second signal leaks.
@Test func onlyTheFirstResolveWins() async throws {
    let p = PendingQuestion(event: question(), deadline: 5)
    let waiter = Task.detached { p.await() }
    try await Task.sleep(for: .milliseconds(20))
    #expect(p.resolve(Reply(id: "q1", choice: "allow")))
    #expect(p.resolve(Reply(id: "q1", choice: "deny")) == false)
    #expect(await waiter.value?.choice == "allow")
}
