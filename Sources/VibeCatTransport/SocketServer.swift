import Foundation
import VibeCatCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// One thread accepts, one thread per connection reads a single line and
/// answers it. Connections are short-lived — a hook sends one event and leaves.
public final class SocketServer: @unchecked Sendable {
    public let path: String
    private var listenFD: Int32 = -1
    private let lock = NSLock()
    private var running = false

    public init(path: String) {
        self.path = path
    }

    public func start(handler: @escaping @Sendable (VibeEvent) -> Reply?) throws {
        try prepareDirectory()
        unlink(path)                                  // clear any stale socket file

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.socketFailed(errno) }

        var addr = try UnixAddress.make(path)
        guard UnixAddress.withSockaddr(&addr, { bind(fd, $0, $1) }) == 0 else {
            let e = errno; close(fd); throw SocketError.bindFailed(e)
        }
        guard listen(fd, 16) == 0 else {
            let e = errno; close(fd); throw SocketError.listenFailed(e)
        }
        chmod(path, 0o600)                            // owner only

        lock.lock(); listenFD = fd; running = true; lock.unlock()

        Thread.detachNewThread { [weak self] in
            self?.acceptLoop(fd: fd, handler: handler)
        }
    }

    public func stop() {
        lock.lock()
        running = false
        let fd = listenFD
        listenFD = -1
        lock.unlock()
        if fd >= 0 { close(fd) }
        unlink(path)
    }

    private var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }; return running
    }

    private func prepareDirectory() throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir,
                                                withIntermediateDirectories: true)
    }

    private func acceptLoop(fd: Int32, handler: @escaping @Sendable (VibeEvent) -> Reply?) {
        while isRunning {
            let conn = accept(fd, nil, nil)
            if conn < 0 {
                if isRunning && errno == EINTR { continue }
                return
            }
            Thread.detachNewThread { Self.serve(conn: conn, handler: handler) }
        }
    }

    private static func serve(conn: Int32, handler: @Sendable (VibeEvent) -> Reply?) {
        defer { close(conn) }
        guard let line = readLine(conn),
              let event = try? WireCodec.decode(VibeEvent.self, from: line) else { return }

        guard let reply = handler(event), event.wantsReply,
              let out = try? WireCodec.encode(reply) else { return }

        _ = out.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            var sent = 0
            while sent < out.count {
                let n = write(conn, base.advanced(by: sent), out.count - sent)
                if n <= 0 { break }
                sent += n
            }
            return sent
        }
    }

    private static func readLine(_ fd: Int32) -> Data? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return buffer.isEmpty ? nil : buffer }
            buffer.append(contentsOf: chunk[0..<n])
            if let idx = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                return Data(buffer[buffer.startIndex..<idx])
            }
        }
    }
}
