import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum SocketError: Error, Equatable {
    case pathTooLong
    case socketFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case connectFailed(Int32)
    case timedOut
}

public enum UnixAddress {
    public static func make(_ path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        // Need room for the trailing NUL.
        guard bytes.count < capacity else { throw SocketError.pathTooLong }

        withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                for (i, byte) in bytes.enumerated() {
                    dst[i] = CChar(bitPattern: byte)
                }
                dst[bytes.count] = 0
            }
        }
        return addr
    }

    /// `connect` and `bind` want a `sockaddr *`; this does the rebind in one place.
    ///
    /// Reports the full struct size as the length rather than computing
    /// `offsetof(sun_path) + strlen(path)`. Verified correct on Darwin for
    /// ordinary filesystem paths: `sockaddr_un()` zero-fills, and BSD reads
    /// `sun_path` as a NUL-terminated string, so the trailing zeros are ignored.
    /// It would be WRONG for a Linux abstract-namespace socket, whose path
    /// begins with NUL and needs an exact length — `make` never produces one
    /// today, so nothing depends on that case yet.
    public static func withSockaddr<R>(_ addr: inout sockaddr_un,
                                       _ body: (UnsafePointer<sockaddr>, socklen_t) -> R) -> R {
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, len) }
        }
    }
}
