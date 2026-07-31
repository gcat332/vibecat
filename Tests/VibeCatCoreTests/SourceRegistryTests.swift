import Testing
@testable import VibeCatCore

private struct StubAdapter: SourceAdapter {
    let id = "stub"
    let displayName = "Stub"
    let jumpStrategy = JumpStrategy.activateApp(bundleID: "com.example.stub")
    let reports: Set<Kind> = [.running, .done]
    func parse(_ raw: [String: Any], origin: Origin) throws -> VibeEvent? { nil }
}

@Test func registryFindsAnAdapterById() {
    let r = SourceRegistry(adapters: [StubAdapter()])
    #expect(r.adapter(for: "stub")?.displayName == "Stub")
}

@Test func registryReturnsNilForAnUnknownId() {
    let r = SourceRegistry(adapters: [StubAdapter()])
    #expect(r.adapter(for: "nope") == nil)
}

@Test func registryListsItsIds() {
    let r = SourceRegistry(adapters: [StubAdapter()])
    #expect(r.ids == ["stub"])
}

@Test func jumpStrategyComparesByAssociatedValue() {
    #expect(JumpStrategy.activateApp(bundleID: "a") != .activateApp(bundleID: "b"))
    #expect(JumpStrategy.terminalSession == .terminalSession)
}

@Test func laterAdaptersWinOnADuplicateId() {
    struct Other: SourceAdapter {
        let id = "stub"                       // deliberately collides
        let displayName = "Other"
        let jumpStrategy = JumpStrategy.vscode
        let reports: Set<Kind> = [.failed]
        func parse(_ raw: [String: Any], origin: Origin) throws -> VibeEvent? { nil }
    }
    let r = SourceRegistry(adapters: [StubAdapter(), Other()])
    #expect(r.ids == ["stub"])                // one entry, not a crash
    #expect(r.adapter(for: "stub")?.displayName == "Other")
}

@Test func adapterErrorComparesByCaseAndValue() {
    #expect(AdapterError.missingField("session_id") == .missingField("session_id"))
    #expect(AdapterError.missingField("a") != .missingField("b"))
    #expect(AdapterError.missingField("a") != .unknownEvent("a"))
}
