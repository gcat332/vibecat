import Foundation
import Testing
@testable import VibeCatCore

private let origin = Origin(app: "com.googlecode.iterm2", termSession: "w0t1p0")

private func raw(_ json: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
}

private func tempJSONPath(_ n: String) -> URL {
    URL(fileURLWithPath: "/tmp/vibecat-customsource-\(n)-\(getpid()).json")
}

// MARK: - decode / a definition round-trips

private let minimalConfig = GenericAdapterConfig(
    id: "acme", displayName: "Acme CLI", icon: "/tmp/does-not-exist-acme.png",
    jumpStrategy: .vscode, reports: [.running, .done],
    eventNameKey: "event", sessionKey: "sid", cwdKey: "dir",
    modelKey: "model", effortKey: "effort",
    events: ["start": EventRule(kind: .running),
             "ask": EventRule(kind: .permission, wantsReply: true, bodyKey: "msg",
                              choices: [Choice(id: "yes", label: "Yes")])])

@Test func aDefinitionRoundTripsThroughEncodeAndDecode() throws {
    let written = CustomSourceDefinition(config: minimalConfig)
    let decoded = try #require(CustomSourceDefinition.decode(written.encoded()))

    #expect(decoded.config.id == "acme")
    #expect(decoded.config.displayName == "Acme CLI")
    #expect(decoded.config.icon == "/tmp/does-not-exist-acme.png")
    #expect(decoded.config.jumpStrategy == .vscode)
    #expect(decoded.config.reports == [.running, .done])
    #expect(decoded.config.eventNameKey == "event")
    #expect(decoded.config.sessionKey == "sid")
    #expect(decoded.config.cwdKey == "dir")
    #expect(decoded.config.modelKey == "model")
    #expect(decoded.config.effortKey == "effort")
    #expect(decoded.config.events["start"]?.kind == .running)
    #expect(decoded.config.events["ask"]?.kind == .permission)
    #expect(decoded.config.events["ask"]?.wantsReply == true)
    #expect(decoded.config.events["ask"]?.bodyKey == "msg")
    #expect(decoded.config.events["ask"]?.choices?.map(\.id) == ["yes"])
}

@Test func aDefinitionRoundTripsThroughARealJSONFile() throws {
    let url = tempJSONPath("roundtrip")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = JSONFileCustomSourceStore(url: url)

    store.save([CustomSourceDefinition(config: minimalConfig)])
    let loaded = store.load()

    #expect(loaded.count == 1)
    #expect(loaded.first?.config.id == "acme")
    #expect(loaded.first?.config.events["start"]?.kind == .running)
}

// MARK: - a custom source appears in the registry and parses an event

@Test func aCustomSourceAppearsInTheRegistryAndParsesAnEvent() throws {
    let store = InMemoryCustomSourceStore([CustomSourceDefinition(config: minimalConfig)])
    let registry = SourceRegistry.loadingCustomSources(builtIns: [ClaudeCodeAdapter()], from: store)

    #expect(registry.ids.contains("acme"))
    #expect(registry.ids.contains("claude-code"))

    let adapter = try #require(registry.adapter(for: "acme"))
    let event = try #require(try adapter.parse(
        try raw(#"{"event":"start","sid":"s1","dir":"/d"}"#), origin: origin))
    #expect(event.kind == .running)
    #expect(event.cli == "acme")
}

// MARK: - the designed behaviour nothing currently proved: shadowing

/// A custom source with `id == "claude-code"` deliberately does **not**
/// declare `"Stop"`, which the built-in `ClaudeCodeAdapter` maps to `.done`.
/// So feeding a `Stop` payload through *whichever adapter the registry
/// actually resolves for that id* distinguishes the two: the built-in
/// produces an event, the shadow returns `nil` for an event it never
/// declared. Observing `nil` is therefore proof the shadow ran, not merely
/// that *something* is registered under that id.
@Test func aCustomSourceWithClaudeCodesIdShadowsTheBuiltInPreset() throws {
    let shadowConfig = GenericAdapterConfig(
        id: "claude-code", displayName: "Shadowed Claude Code",
        jumpStrategy: .none, reports: [.running],
        eventNameKey: "hook_event_name", sessionKey: "session_id", cwdKey: "cwd",
        events: ["PostToolUse": EventRule(kind: .running)])
    let store = InMemoryCustomSourceStore([CustomSourceDefinition(config: shadowConfig)])
    let registry = SourceRegistry.loadingCustomSources(builtIns: [ClaudeCodeAdapter()], from: store)

    // Not the built-in's own type — the later adapter in the list.
    #expect(registry.adapter(for: "claude-code")?.displayName == "Shadowed Claude Code")

    let stopPayload = try raw(#"{"hook_event_name":"Stop","session_id":"s1","cwd":"/dev/api"}"#)
    let result = try registry.adapter(for: "claude-code")?.parse(stopPayload, origin: origin)
    #expect(result == nil,
            "claude-code's built-in Stop→done mapping still ran — a later custom source with the same id must win, per SourceRegistry.init's own doc comment")

    // And the shadow really is wired for its own declared event, so this
    // isn't merely "the shadow parses nothing at all":
    let declaredPayload = try raw(#"{"hook_event_name":"PostToolUse","session_id":"s1","cwd":"/dev/api"}"#)
    let declaredResult = try registry.adapter(for: "claude-code")?.parse(declaredPayload, origin: origin)
    #expect(declaredResult?.kind == .running)
}

// MARK: - fail open: a corrupt file leaves the presets intact

@Test func aCorruptFileLeavesTheBuiltInPresetsIntact() {
    let url = tempJSONPath("corrupt")
    defer { try? FileManager.default.removeItem(at: url) }
    try? Data("this is not json { at all".utf8).write(to: url)

    let store = JSONFileCustomSourceStore(url: url)
    #expect(store.load().isEmpty, "a corrupt file must decode to no custom sources, never throw")

    let registry = SourceRegistry.loadingCustomSources(builtIns: [ClaudeCodeAdapter()], from: store)
    #expect(registry.ids == ["claude-code"])
    #expect(registry.adapter(for: "claude-code").map { $0 is ClaudeCodeAdapter } == true)
}

@Test func aMissingFileLeavesTheBuiltInPresetsIntact() {
    let store = JSONFileCustomSourceStore(url: tempJSONPath("never-written"))
    let registry = SourceRegistry.loadingCustomSources(builtIns: [ClaudeCodeAdapter()], from: store)
    #expect(registry.ids == ["claude-code"])
}

@Test func aTopLevelThatIsNotAnArrayOfObjectsProducesNoCustomSources() {
    let url = tempJSONPath("wrong-shape")
    defer { try? FileManager.default.removeItem(at: url) }
    try? Data(#"{"id":"acme"}"#.utf8).write(to: url)

    #expect(JSONFileCustomSourceStore(url: url).load().isEmpty)
}

// MARK: - every other shape of bad input

@Test func aDefinitionMissingARequiredFieldIsDroppedButOthersInTheSameArraySurvive() {
    let good = try! raw(#"""
      {"id":"good","displayName":"Good","eventNameKey":"e","sessionKey":"s","cwdKey":"c","events":[]}
      """#)
    let missingID = try! raw(#"""
      {"displayName":"No Id","eventNameKey":"e","sessionKey":"s","cwdKey":"c","events":[]}
      """#)

    #expect(CustomSourceDefinition.decode(missingID) == nil)
    let decodedGood = CustomSourceDefinition.decode(good)
    #expect(decodedGood?.config.id == "good")
}

@Test func anIconNamingAMissingFileStillRegisters() throws {
    let json = try raw(#"""
      {"id":"acme","displayName":"Acme","icon":"/does/not/exist.png",
       "eventNameKey":"e","sessionKey":"s","cwdKey":"c","events":[]}
      """#)
    let decoded = try #require(CustomSourceDefinition.decode(json))
    #expect(decoded.config.icon == "/does/not/exist.png")

    let store = InMemoryCustomSourceStore([decoded])
    let registry = SourceRegistry.loadingCustomSources(builtIns: [], from: store)
    #expect(registry.adapter(for: "acme")?.icon == "/does/not/exist.png")
}

@Test func anUnknownKindInsideEventsIsDroppedRatherThanCrashing() throws {
    let json = try raw(#"""
      {"id":"acme","displayName":"Acme","eventNameKey":"e","sessionKey":"s","cwdKey":"c",
       "events":[{"name":"good","kind":"running"},{"name":"bad","kind":"not-a-real-kind"}]}
      """#)
    let decoded = try #require(CustomSourceDefinition.decode(json))
    #expect(decoded.config.events["good"]?.kind == .running)
    #expect(decoded.config.events["bad"] == nil)
}

@Test func anUnrecognisedJumpStrategyFallsBackToNoneRatherThanDroppingTheDefinition() throws {
    let json = try raw(#"""
      {"id":"acme","displayName":"Acme","jumpStrategy":"not-a-real-strategy",
       "eventNameKey":"e","sessionKey":"s","cwdKey":"c","events":[]}
      """#)
    let decoded = try #require(CustomSourceDefinition.decode(json))
    #expect(decoded.config.jumpStrategy == .none)
}

@Test func anActivateAppJumpStrategyRoundTrips() throws {
    let config = GenericAdapterConfig(
        id: "acme", displayName: "Acme", jumpStrategy: .activateApp(bundleID: "com.acme.cli"),
        reports: [.running], eventNameKey: "e", sessionKey: "s", cwdKey: "c", events: [:])
    let decoded = try #require(CustomSourceDefinition.decode(CustomSourceDefinition(config: config).encoded()))
    #expect(decoded.config.jumpStrategy == .activateApp(bundleID: "com.acme.cli"))
}

// MARK: - the hazard Task 2 handed forward: a duplicate event name in a hand-edited file

@Test func aDuplicateEventNameInTheEventsArrayDoesNotTrapAndTheLaterEntryWins() throws {
    let json = try raw(#"""
      {"id":"acme","displayName":"Acme","eventNameKey":"e","sessionKey":"s","cwdKey":"c",
       "events":[{"name":"same","kind":"running"},{"name":"same","kind":"done"}]}
      """#)
    // The point of the test: this must not trap.
    let decoded = try #require(CustomSourceDefinition.decode(json))
    #expect(decoded.config.events.count == 1)
    #expect(decoded.config.events["same"]?.kind == .done,
            "a duplicate event name must resolve to the later entry, matching SourceRegistry's own duplicate-id rule")
}
