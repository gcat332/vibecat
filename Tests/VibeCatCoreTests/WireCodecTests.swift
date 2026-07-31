import Foundation
import Testing
@testable import VibeCatCore

@Test func encodeAppendsExactlyOneNewline() throws {
    let e = VibeEvent(id: "a", cli: "claude-code", kind: .running, session: "s", cwd: "/tmp")
    let data = try WireCodec.encode(e)
    #expect(data.last == UInt8(ascii: "\n"))
    #expect(data.filter { $0 == UInt8(ascii: "\n") }.count == 1)
}

@Test func eventSurvivesARoundTrip() throws {
    let e = VibeEvent(
        id: "uuid", cli: "claude-code", kind: .permission,
        session: "abc123", cwd: "/Users/me/dev/api",
        worktree: "auth-hardening", model: "Opus 4.8", effort: "high",
        title: "Bash command", body: "rm -rf build/",
        choices: [Choice(id: "allow", label: "Allow once"),
                  Choice(id: "deny", label: "Deny")],
        multi: false, wantsReply: true,
        tasks: [TaskItem(title: "Audit auth flow", status: .doing)],
        agents: [AgentItem(name: "Explore", elapsed: "8s", model: "Sonnet 4.6 · High",
                           activity: "Grep: handleRequest")],
        origin: Origin(app: "com.googlecode.iterm2", termSession: "w0t1p0:UUID"))

    let back = try WireCodec.decode(VibeEvent.self, from: WireCodec.encode(e))
    #expect(back == e)
}

@Test func replySurvivesARoundTrip() throws {
    let r = Reply(id: "uuid", choices: ["a", "b"])
    let back = try WireCodec.decode(Reply.self, from: WireCodec.encode(r))
    #expect(back == r)
}

@Test func splitLinesReturnsCompleteLinesAndKeepsTheRemainder() {
    var buf = Data(#"{"a":1}"#.utf8) + Data("\n".utf8)
             + Data(#"{"b":2}"#.utf8) + Data("\n".utf8)
             + Data(#"{"partial"#.utf8)
    let lines = WireCodec.splitLines(&buf)
    #expect(lines.count == 2)
    #expect(String(decoding: lines[0], as: UTF8.self) == #"{"a":1}"#)
    #expect(String(decoding: buf, as: UTF8.self) == #"{"partial"#)
}

@Test func splitLinesOnAnEmptyBufferReturnsNothing() {
    var buf = Data()
    #expect(WireCodec.splitLines(&buf).isEmpty)
}

@Test func splitLinesSkipsBlankLines() {
    var buf = Data("{\"a\":1}\n\n{\"b\":2}\n".utf8)
    let lines = WireCodec.splitLines(&buf)
    #expect(lines.count == 2)
    #expect(String(decoding: lines[0], as: UTF8.self) == "{\"a\":1}")
    #expect(String(decoding: lines[1], as: UTF8.self) == "{\"b\":2}")
    #expect(buf.isEmpty)
}

@Test func splitLinesHandlesASlicedBuffer() {
    // Data preserves a parent's indices when sliced, so anything assuming
    // startIndex == 0 breaks here.
    let parent = Data("XXXX{\"a\":1}\n{\"b\":2}\n".utf8)
    var buf = Data(parent.dropFirst(4))
    let lines = WireCodec.splitLines(&buf)
    #expect(lines.count == 2)
    #expect(String(decoding: lines[1], as: UTF8.self) == "{\"b\":2}")
}

@Test func encodeEmitsOneNewlineEvenWithANewlineInsideAStringValue() throws {
    let e = VibeEvent(id: "a", cli: "claude-code", kind: .failed,
                      session: "s", cwd: "/tmp", body: "line one\nline two")
    let data = try WireCodec.encode(e)
    // JSON escapes the embedded newline, so only the terminator is a raw 0x0A.
    #expect(data.filter { $0 == UInt8(ascii: "\n") }.count == 1)
    #expect(try WireCodec.decode(VibeEvent.self, from: data).body == "line one\nline two")
}
