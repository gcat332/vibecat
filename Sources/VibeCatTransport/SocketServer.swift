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
    /// A hook writes its event immediately after connecting, so a peer still
    /// silent after this long is misbehaving. Without it, such a peer parks a
    /// thread for the lifetime of the app.
    public let readDeadline: TimeInterval
    private var listenFD: Int32 = -1
    private let lock = NSLock()
    private var running = false

    public init(path: String, readDeadline: TimeInterval = 5.0) {
        self.path = path
        self.readDeadline = Swift.max(0.05, readDeadline)
    }

    public func start(handler: @escaping @Sendable (VibeEvent) -> Reply?) throws {
        try prepareDirectory()
        unlink(path)                                  // clear any stale socket file

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.socketFailed(errno) }

        var addr = try UnixAddress.make(path)
        // bind() applies the process umask, so the file would briefly exist as
        // 0755 before the chmod below. Narrow the umask across the bind instead
        // of racing to fix it afterwards.
        let previousMask = umask(0o177)
        let bindResult = UnixAddress.withSockaddr(&addr) { bind(fd, $0, $1) }
        umask(previousMask)
        guard bindResult == 0 else {
            let e = errno; close(fd); throw SocketError.bindFailed(e)
        }
        guard listen(fd, 16) == 0 else {
            let e = errno; close(fd); throw SocketError.listenFailed(e)
        }
        chmod(path, 0o600)                            // owner only

        lock.lock(); listenFD = fd; running = true; lock.unlock()

        let deadline = readDeadline
        Thread.detachNewThread { [weak self] in
            self?.acceptLoop(fd: fd, deadline: deadline, handler: handler)
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
        // 0700: the socket's containing directory is a second line of defence
        // behind the socket's own mode.
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }

    private func acceptLoop(fd: Int32, deadline: TimeInterval,
                            handler: @escaping @Sendable (VibeEvent) -> Reply?) {
        while isRunning {
            let conn = accept(fd, nil, nil)
            if conn < 0 {
                if isRunning && errno == EINTR { continue }
                return
            }
            Thread.detachNewThread { Self.serve(conn: conn, deadline: deadline, handler: handler) }
        }
    }

    private static func serve(conn: Int32, deadline: TimeInterval,
                              handler: @Sendable (VibeEvent) -> Reply?) {
        defer { close(conn) }
        #if canImport(Darwin)
        var nosigpipe: Int32 = 1
        setsockopt(conn, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe,
                   socklen_t(MemoryLayout<Int32>.size))
        #else
        // Linux has no SO_NOSIGPIPE; the equivalent is MSG_NOSIGNAL on each
        // send(). Not adopted yet — Linux support is compile-only today.
        #endif
        guard let line = readLine(conn, deadline: deadline),
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

    private static func readLine(_ fd: Int32, deadline: TimeInterval) -> Data? {
        // Bound each syscall AND the whole loop: SO_RCVTIMEO alone lets a peer
        // that trickles bytes run indefinitely.
        var tv = timeval(tv_sec: Int(deadline),
                         tv_usec: Int32((deadline - floor(deadline)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let expiry = Date().addingTimeInterval(deadline)

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            if Date() >= expiry { return nil }
            let n = read(fd, &chunk, chunk.count)
            if n > 0 {
                buffer.append(contentsOf: chunk[0..<n])
                if let idx = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    return Data(buffer[buffer.startIndex..<idx])
                }
                continue
            }
            if n < 0 && errno == EINTR { continue }
            return nil
        }
    }
}
