import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The hook side of the socket. Deliberately blocking and deliberately
/// infallible: every error path returns nil so the calling CLI carries on.
public struct SocketClient: Sendable {
    public let path: String
    public let deadline: TimeInterval

    public init(path: String, deadline: TimeInterval = 0.3) {
        self.path = path
        self.deadline = deadline
    }

    public func send(_ line: Data) {
        guard let fd = connectSocket() else { return }
        defer { close(fd) }
        _ = writeAll(fd, line)
    }

    public func sendExpectingReply(_ line: Data) -> Data? {
        guard let fd = connectSocket() else { return nil }
        defer { close(fd) }
        guard writeAll(fd, line) else { return nil }
        return readLine(fd)
    }

    // MARK: - plumbing

    private func connectSocket() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        guard var addr = try? UnixAddress.make(path) else {
            close(fd)
            return nil
        }
        setTimeout(fd, SO_SNDTIMEO)
        setTimeout(fd, SO_RCVTIMEO)

        let rc = UnixAddress.withSockaddr(&addr) { connect(fd, $0, $1) }
        guard rc == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    private func setTimeout(_ fd: Int32, _ option: Int32) {
        var tv = timeval(tv_sec: Int(deadline),
                         tv_usec: Int32((deadline - floor(deadline)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, option, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        var sent = 0
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else { return false }
            while sent < data.count {
                let n = write(fd, base.advanced(by: sent), data.count - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }

    /// Reads until the first newline or the socket timeout, whichever comes first.
    private func readLine(_ fd: Int32) -> Data? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 1024)
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
