import Testing
@testable import VibeCatCore

@Test func defaultsToApplicationSupport() {
    let p = SocketPath.resolve(env: [:], home: "/Users/me")
    #expect(p == "/Users/me/Library/Application Support/VibeCat/vibecat.sock")
}

@Test func environmentOverrideWins() {
    let p = SocketPath.resolve(env: ["VIBECAT_SOCKET": "/tmp/x.sock"], home: "/Users/me")
    #expect(p == "/tmp/x.sock")
}

@Test func anEmptyOverrideIsIgnored() {
    let p = SocketPath.resolve(env: ["VIBECAT_SOCKET": ""], home: "/Users/me")
    #expect(p == "/Users/me/Library/Application Support/VibeCat/vibecat.sock")
}
