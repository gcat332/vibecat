import AppKit
import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

// MARK: - What was actually broken, and what this file is the test for
//
// After Plan 7's Tasks 1–5 the mechanism was complete and connected to nothing:
//
// - `SourceRegistry(adapters:)` appeared **once** in `Sources/`, inside
//   `CustomSource.swift`'s `loadingCustomSources`, called only from
//   `VibeCatHook/main.swift` — the *hook* process.
// - `VibeEvent` contained the string `icon` **zero times**, so the hook could not
//   tell the app.
// - `Session.icon` was declared and assigned from **nowhere**, and its own doc
//   comment said so.
//
// So no real custom-source definition could reach a real drawn row, and the whole
// plan's claim rested on parts that each passed their own tests. That is this
// project's third "built but never populated", after `Session.lastUserMessage`
// and Plan 6.4's three write-only preferences.
//
// Task 6 closed it on the **app** side — `AppModel` builds a registry through the
// same `SourceRegistry.loadingCustomSources(builtIns:from:)` the hook uses and
// resolves `cli` → `icon` in `applyAndNotify` — rather than by adding an icon
// field to the wire, because the icon is a display concern and the wire speaks
// only the shared `kind` vocabulary. See `AppModel.sources`' doc comment.
//
// **These tests run the whole app-side path**: a definition in a store, an
// `AppModel` built from that store, a real `ingest`, and a **rendered**
// `SessionRow` at the end of it. Every intermediate assertion here would also be
// satisfied by a `Session` a test set `.icon` on by hand — which is exactly what
// `SessionRowTests` already does and exactly what could not catch this defect —
// so the pixel count is the one that binds.

/// A solid square PNG built at runtime in a scratch directory. **Never a
/// committed file and never one of the owner's real icons**: §3's Global
/// Constraints make bundling a vendor logo a licence problem. Square and solid
/// for the reason `SourceIconTests.makeTempIcon` gives — no internal edge to
/// antialias, so a pixel count is exact.
@MainActor
private func makeTempIcon(_ colour: NSColor, side: Int = 64) throws -> String {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("vibecat-customsource-icon-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent("icon.png").path
    let rep = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    colour.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: side, height: side)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try #require(rep.representation(using: .png, properties: [:]))
        .write(to: URL(fileURLWithPath: path))
    return path
}

/// The same fixture colour `SourceIconTests` and `SessionRowTests` use, and for
/// the same reason: no `CLIMark` path, no ink tier and no state accent produces
/// it, so "this colour is on screen" can only mean the icon's own pixels drew.
/// `iconMagentaIsNotAnyStateAccent` in `SourceIconTests` is what checks that
/// property rather than assuming it.
private let iconMagenta = RGBA(r: 1, g: 0, b: 1)

/// A source that no code in `Adapters/` knows about — the plan's whole claim is
/// "a CLI nobody wrote code for", so the id is deliberately not one of
/// `CLIMark(cli:)`'s three known substrings either. It falls back to `.generic`,
/// which means the geometric mark drawn in the no-icon control below is the
/// *generic* one, and nothing in this file can accidentally be measuring a
/// hardcoded Claude/Codex/Gemini branch.
private let unknownCLI = "acme-agent"

@MainActor
private func definition(icon: String?) -> CustomSourceDefinition {
    CustomSourceDefinition(config: GenericAdapterConfig(
        id: unknownCLI, displayName: "Acme Agent", icon: icon,
        jumpStrategy: .terminalSession, reports: Set(Kind.allCases),
        eventNameKey: "event", sessionKey: "sid", cwdKey: "dir",
        events: ["working": EventRule(kind: .running)]))
}

/// A socket path that is never listened on and never connected to. `ingest` is
/// called directly here — the socket is `AppModel`'s *input*, not something this
/// path touches — and `start()` is deliberately never called, so no listener,
/// no accept thread and no teardown ordering to get wrong.
private func unusedSocketPath() -> String {
    "/tmp/vibecat-customsource-icon-\(UUID().uuidString).sock"
}

@MainActor
private func event(cli: String) -> VibeEvent {
    var e = VibeEvent(id: "e1", cli: cli, kind: .running, session: "s1",
                      cwd: "/Users/dev/api")
    e.title = "Asking to run"
    e.body = "rm -rf build/"
    return e
}

@MainActor
private func row(_ s: Session) throws -> Raster {
    try rasterise(SessionRow(session: s, now: Date(timeIntervalSince1970: 1_000_000),
                             options: .all, highlight: [])
        .frame(width: 388))
}

/// **Renders until the icon's own loader has actually loaded, bounded.**
///
/// `SourceIcon`'s read is deliberately capped at 50ms on a dedicated thread, and its
/// documented timeout branch draws `CLIMark`'s geometric fallback while the background
/// read keeps going and caches when it finishes (`SourceIcon.swift:198-220`). So a
/// *single* render immediately after writing a fresh PNG is a bet on winning that race
/// against a cold page cache — and one render is exactly what
/// `anIconFromACustomSourceReachesARenderedRow` used to make.
///
/// **This was a latent defect, not a new one.** On the tree before Plan 9's Task 7 that
/// test passed in the full suite and failed on its own; adding nine tests elsewhere
/// changed what ran before it and it began failing in the suite too. Widening the pixel
/// threshold would have hidden a race rather than removed one; asserting against the
/// second render honours the loader's actual contract, which is "the cache is warm once
/// the read lands", not "the first frame has the icon".
///
/// Bounded at 40 attempts (~2s), so a genuinely broken icon path still fails rather than
/// hanging — the failure this helper must not swallow.
@MainActor private func rowOnceIconIsLoaded(_ s: Session, expecting colour: RGBA) throws -> Raster {
    var last = try row(s)
    for _ in 0..<40 where last.pixelCount(near: colour) <= 20 {
        Thread.sleep(forTimeInterval: 0.05)
        last = try row(s)
    }
    return last
}

// MARK: - The whole loop, in one test

/// **The test this task exists for.** A definition on disk (here: in the store
/// that stands for it), an `AppModel` built from it, one real `ingest`, and a
/// rendered row that shows the icon's own colour.
///
/// Mutation-verified, three ways — all three of which left the entire rest of the
/// suite green, which is the point:
///
/// 1. Dropping `icon:` from `store.apply(event, now: now, icon: icon)` in
///    `AppModel.applyAndNotify` (both branches). `session.icon` becomes `nil` and
///    the magenta count goes from >20 to **0**.
/// 2. Building `AppModel.sources` as `SourceRegistry(adapters: [ClaudeCodeAdapter()])`
///    — i.e. ignoring the store, which is what "the app has a registry but not
///    the user's sources" would look like. Same failure.
/// 3. Passing the store but reading `adapter(for: event.session)` instead of
///    `event.cli` — a plausible slip. Same failure.
@MainActor @Test func anIconFromACustomSourceReachesARenderedRow() throws {
    let path = try makeTempIcon(.magenta)
    let store = InMemoryCustomSourceStore([definition(icon: path)])
    let model = AppModel(socketPath: unusedSocketPath(), sources: store)

    model.ingest(event(cli: unknownCLI))

    let session = try #require(model.store.sessions.first,
                              "ingest produced no session at all")
    #expect(session.icon == path,
            "`Session.icon` is \(session.icon ?? "<nil>") — the app resolved no icon for a cli its own registry has a definition for, which is the exact defect this task closed")

    let drawn = try rowOnceIconIsLoaded(session, expecting: iconMagenta)
    #expect(drawn.pixelCount(near: iconMagenta) > 20,
            "the rendered row drew \(drawn.pixelCount(near: iconMagenta)) pixels of the icon's own magenta — a real custom-source icon is not reaching the drawn row")
}

/// The control, and it is doing real work rather than being symmetry for its own
/// sake: it establishes that the magenta in the test above cannot come from
/// anything the row draws anyway. Same event, same render, same everything — one
/// input differs, and it is the store.
@MainActor @Test func withNoDefinitionTheSameEventDrawsTheGeometricMarkInstead() throws {
    let model = AppModel(socketPath: unusedSocketPath(), sources: InMemoryCustomSourceStore([]))
    model.ingest(event(cli: unknownCLI))

    let session = try #require(model.store.sessions.first)
    #expect(session.icon == nil,
            "an app with no custom-source definitions resolved an icon from somewhere — there is no other source of one")
    #expect(try row(session).pixelCount(near: iconMagenta) == 0,
            "a row with no icon still drew the fixture's magenta, so the count in the test above is not evidence the icon loaded")
}

/// A definition with no `icon` at all — the common case for every built-in
/// preset, since §3 forbids committing a vendor logo. It must resolve to `nil`
/// rather than to something, and it must not be an error: an adapter that exists
/// and has no icon is not a failure to look one up.
@MainActor @Test func aDefinitionWithoutAnIconResolvesToNothingRatherThanFailing() throws {
    let store = InMemoryCustomSourceStore([definition(icon: nil)])
    let model = AppModel(socketPath: unusedSocketPath(), sources: store)
    model.ingest(event(cli: unknownCLI))
    #expect(try #require(model.store.sessions.first).icon == nil)
}

// MARK: - The seams either side of the resolution

/// Built-in presets keep working, and — the part worth pinning — the *shadowing*
/// rule the registry was built for reaches the app too. A custom source with the
/// same id as `claude-code` gives `claude-code` sessions its icon.
///
/// This is the app-side counterpart of
/// `aCustomSourceLoadedFromAStoreShadowsClaudeCodeThroughARealHookRunner`, which
/// proves the same rule on the hook side. Two processes, one factory: if only one
/// of them honoured "later wins", a session's row and its parsed events would
/// disagree about which definition is in force.
@MainActor @Test func aCustomSourceShadowingABuiltInGivesItsIconToThatBuiltInsSessions() throws {
    let path = try makeTempIcon(.magenta)
    let shadow = CustomSourceDefinition(config: GenericAdapterConfig(
        id: "claude-code", displayName: "Shadowed", icon: path,
        jumpStrategy: .none, reports: [.running],
        eventNameKey: "hook_event_name", sessionKey: "session_id", cwdKey: "cwd",
        events: ["Stop": EventRule(kind: .done)]))
    let model = AppModel(socketPath: unusedSocketPath(),
                         sources: InMemoryCustomSourceStore([shadow]))

    model.ingest(event(cli: "claude-code"))
    #expect(try #require(model.store.sessions.first).icon == path,
            "a custom source with the built-in's own id did not shadow it on the app side — `SourceRegistry`'s later-wins rule is honoured by the hook and not by the app, so the row and the parser would disagree")
}

/// A second event for the same session must not lose the icon. `merge` leaves
/// omitted fields alone, and the icon is not on the event at all, so this is
/// checking that the resolution happens on *every* apply rather than only on
/// creation.
///
/// Mutation-verified: removing `if let icon { sessions[i].icon = icon }` from
/// `SessionStore.apply`'s merge branch leaves this green, because the create
/// branch already set it and nothing clears it. **Reported rather than adjusted**
/// — see the task report. The line is kept for the case no reachable assertion
/// covers (a session created before its definition was loaded), and this test
/// pins the property that actually matters: an icon survives a merge.
@MainActor @Test func asecondEventForTheSameSessionKeepsTheIcon() throws {
    let path = try makeTempIcon(.magenta)
    let model = AppModel(socketPath: unusedSocketPath(),
                         sources: InMemoryCustomSourceStore([definition(icon: path)]))
    model.ingest(event(cli: unknownCLI))
    var second = event(cli: unknownCLI)
    second.kind = .done
    model.ingest(second)

    let session = try #require(model.store.sessions.first)
    #expect(model.store.sessions.count == 1, "the second event created a second session")
    #expect(session.state == .idle || session.state == .running,
            "the fixture must actually have merged a state change: got \(session.state)")
    #expect(session.icon == path, "the icon was lost on merge")
}

/// The resolution runs on `SocketServer`'s per-connection thread in production —
/// `ingest` is `nonisolated` and `applyAndNotify`'s non-main branch is the real
/// path. A dictionary lookup cannot block, but the *placement* can be wrong: the
/// icon is resolved before the branch, so both branches see the same value. This
/// drives the off-main branch, which no other test in this file does.
@Test func theIconIsResolvedOnTheOffMainIngestPathToo() async throws {
    let path = try await makeTempIcon(.magenta)
    let model = await AppModel(socketPath: unusedSocketPath(),
                               sources: InMemoryCustomSourceStore([definition(icon: path)]))
    let e = await event(cli: unknownCLI)

    // Not `Task { }`: that would inherit the main actor from this test's own
    // isolation and take the `Thread.isMainThread` branch, which is the branch
    // every other test here already covers.
    await withCheckedContinuation { continuation in
        Task.detached {
            model.ingest(e)
            continuation.resume()
        }
    }
    // `applyAndNotify`'s off-main branch hops to the main actor to apply, so the
    // store is not written by the time `ingest` returns. Poll rather than sleep a
    // fixed interval — a fixed sleep is what makes a test like this a full-suite
    // flake.
    var session: Session?
    for _ in 0..<200 {
        session = await MainActor.run { model.store.sessions.first }
        if session != nil { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    let resolved = try #require(session)
    #expect(resolved.icon == path,
            "an event ingested off the main thread produced a session with no icon — the resolution is only on the main-thread branch of `applyAndNotify`")
}
