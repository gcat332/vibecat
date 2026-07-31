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
