import Testing
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import VibeCatTransport

@Test func addressRoundTripsThePath() throws {
    var addr = try UnixAddress.make("/tmp/vibecat-test.sock")
    // Hoisted deliberately: reading addr.sun_path inside the closure would
    // overlap the exclusive access withUnsafePointer(to: &…) already holds,
    // which Swift 6 rejects. Same reason UnixAddress.make hoists it.
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    let read = withUnsafePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: capacity) {
            String(cString: $0)
        }
    }
    #expect(read == "/tmp/vibecat-test.sock")
    #expect(addr.sun_family == sa_family_t(AF_UNIX))
}

@Test func anOverlongPathIsRejectedRatherThanTruncated() {
    let tooLong = "/tmp/" + String(repeating: "x", count: 200) + ".sock"
    #expect(throws: SocketError.pathTooLong) {
        _ = try UnixAddress.make(tooLong)
    }
}
