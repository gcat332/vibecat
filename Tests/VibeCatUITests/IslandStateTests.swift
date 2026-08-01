import Foundation
import Testing
import VibeCatCore
@testable import VibeCatUI

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func event(_ kind: Kind, session: String) -> VibeEvent {
    VibeEvent(id: "e-\(session)", cli: "claude-code", kind: kind,
              session: session, cwd: "/dev/\(session)")
}

/// The distinction Core cannot make: an empty store aggregates to .idle,
/// but "nothing has ever run" is not "a run just finished".
@Test func anEmptyStoreIsDormantNotIdle() {
    #expect(SessionStore().aggregate == .idle)
    #expect(IslandState(store: SessionStore()) == .dormant)
}

@Test func aStoreWithOnlyFinishedSessionsIsIdle() {
    var store = SessionStore()
    store.apply(event(.done, session: "a"), now: t0)
    #expect(IslandState(store: store) == .idle)
}

@Test func theWorstStateWins() {
    var store = SessionStore()
    store.apply(event(.running, session: "a"), now: t0)
    store.apply(event(.failed, session: "b"), now: t0)
    store.apply(event(.permission, session: "c"), now: t0)
    #expect(IslandState(store: store) == .waiting)
}

@Test func accentsAreTheSpecColours() {
    #expect(IslandState.idle.accent.hex == "#3FD99B")
    #expect(IslandState.running.accent.hex == "#5B9DF9")
    #expect(IslandState.waiting.accent.hex == "#FFA63C")
    #expect(IslandState.failed.accent.hex == "#FF5C5C")
}

/// Dormant is a mood, not a fifth colour — an idle machine reads as idle.
@Test func dormantBorrowsTheIdleAccent() {
    #expect(IslandState.dormant.accent == IslandState.idle.accent)
    #expect(IslandState.dormant.isDormant)
}

@Test func hexRoundTrips() throws {
    let c = try #require(RGBA(hex: "#5B9DF9"))
    #expect(c.hex == "#5B9DF9")
    #expect(abs(c.r - 0x5B / 255.0) < 0.0001)
}

@Test func aMalformedHexIsRejectedRatherThanGuessed() {
    #expect(RGBA(hex: "#GGGGGG") == nil)
    #expect(RGBA(hex: "#FFF") == nil)
    #expect(RGBA(hex: "5B9DF9") == nil)
}
