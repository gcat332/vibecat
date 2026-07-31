import Foundation
import Testing
@testable import VibeCatTransport

private func tempSocketPath(_ name: String) -> String {
    "/tmp/vibecat-\(name)-\(getpid()).sock"
}

@Test func missingSocketFailsOpenRatherThanThrowing() {
    let client = SocketClient(path: tempSocketPath("absent"), deadline: 0.1)
    #expect(client.sendExpectingReply(Data("{}\n".utf8)) == nil)
}

@Test func sendWithoutAReplyIsSafeWhenNobodyIsListening() {
    let client = SocketClient(path: tempSocketPath("absent2"), deadline: 0.1)
    client.send(Data("{}\n".utf8))   // must not crash or hang
}

@Test func aServerThatNeverAnswersHitsTheDeadline() async throws {
    let path = tempSocketPath("silent")
    let server = try SilentServer(path: path)
    defer { server.stop() }

    let started = Date()
    let client = SocketClient(path: path, deadline: 0.2)
    let reply = client.sendExpectingReply(Data("{}\n".utf8))

    #expect(reply == nil)
    #expect(Date().timeIntervalSince(started) < 1.0)   // gave up promptly
}

/// Accepts a connection and then says nothing, to exercise the deadline.
private final class SilentServer: @unchecked Sendable {
    private let fd: Int32
    private let path: String
    private var running = true

    init(path: String) throws {
        self.path = path
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = try UnixAddress.make(path)
        _ = UnixAddress.withSockaddr(&addr) { bind(fd, $0, $1) }
        listen(fd, 4)
        Thread.detachNewThread { [fd] in
            while self.running {
                let c = accept(fd, nil, nil)
                if c >= 0 { Thread.sleep(forTimeInterval: 2); close(c) }
            }
        }
    }

    func stop() {
        running = false
        close(fd)
        unlink(path)
    }
}
