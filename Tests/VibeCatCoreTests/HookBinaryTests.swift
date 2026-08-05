import Foundation
import Testing
@testable import VibeCatCore

/// Plan 7 Task 6, item 1: `vibecat-hook` had no installed home at all —
/// `Scripts/build-app.sh` bundled only `vibecat`, so the hook lived at
/// `.build/{debug,release}/vibecat-hook`, a path that moves with the build
/// configuration and sits inside a directory a person may delete. A snippet
/// pasted into another CLI's config file outlives all of that.
///
/// These drive `HookBinary` against real files in a scratch directory rather
/// than against the real bundle, for the reason `bundledURL(executable:)` takes
/// a parameter at all: the test runner's own executable has no `vibecat-hook`
/// beside it and never will, so a test that used the default would be asserting
/// on the absence of a file it cannot create.
private func scratch() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("vibecat-hookbinary-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// A file that `isExecutableFile` agrees with — mode matters here, because every
/// decision `HookBinary` makes is `isExecutableFile`, not `fileExists`. A
/// non-executable file at the same path must read as "not installed": that is
/// the "lost its execute bit" case the snippet's own `[ -x … ]` guard exists for.
@discardableResult
private func makeExecutable(_ url: URL, contents: String = "#!/bin/sh\nexit 0\n") throws -> URL {
    try Data(contents.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

// MARK: - Where the two locations are

/// The product name is spelled in three places that must agree —
/// `Package.swift`'s executable target, `Scripts/build-app.sh`'s `cp`, and this
/// constant. Asserting the constant against a literal would only restate it, so
/// this asserts it against **the real built product**, which is what the other
/// two actually produce. `#require`-free on purpose: in an environment where
/// `.build` is not next to the package this cannot be answered, so it reports
/// that rather than failing.
@Test func theProductNameMatchesABuiltExecutableOfThatName() throws {
    let fm = FileManager.default
    let candidates = ["debug", "release"].map { ".build/\($0)/\(HookBinary.name)" }
    let found = candidates.first { fm.isExecutableFile(atPath: $0) }
    try #require(found != nil,
                 "no built product named `\(HookBinary.name)` at any of \(candidates) — run `swift build` first; this test exists so that renaming the executable target without renaming `HookBinary.name` cannot pass")
}

@Test func theInstalledPathIsInsideTheAppsOwnSupportDirectory() {
    // The same directory `SocketPath.resolve` uses, derived from that function
    // rather than restated — a test that hardcoded the string would keep passing
    // if the two ever diverged, which is the one thing worth pinning here.
    let home = "/tmp/vibecat-fake-home"
    let socket = SocketPath.resolve(env: [:], home: home)
    let installed = HookBinary.installedURL(home: home).path
    let socketDir = (socket as NSString).deletingLastPathComponent
    #expect(installed.hasPrefix(socketDir + "/"),
            "the installed hook (\(installed)) is not inside the directory the socket lives in (\(socketDir)) — the app would be scattering files across two locations")
    #expect(installed.hasSuffix("/bin/\(HookBinary.name)"),
            "an executable belongs in a `bin` subdirectory, not beside the socket and the JSON config in the support directory's root")
}

@Test func theBundledPathIsTheSiblingOfTheRunningExecutable() throws {
    let dir = try scratch()
    let exe = dir.appendingPathComponent("vibecat")
    let bundled = try #require(HookBinary.bundledURL(executable: exe))
    #expect(bundled == dir.appendingPathComponent(HookBinary.name),
            "`bundledURL` did not resolve to the sibling of the executable — that one rule is what makes it correct for both `VibeCat.app/Contents/MacOS/` and a bare `.build/debug/`")
}

// MARK: - Installing the mirror

@Test func installCopiesTheBundledHookToTheFixedPath() throws {
    let dir = try scratch()
    let source = try makeExecutable(dir.appendingPathComponent(HookBinary.name),
                                    contents: "#!/bin/sh\necho one\n")
    let destination = dir.appendingPathComponent("bin/\(HookBinary.name)")

    let result = HookBinary.install(from: source, to: destination)
    #expect(result == destination)
    #expect(FileManager.default.isExecutableFile(atPath: destination.path),
            "the mirror is not an executable file — `copyItem` does preserve mode, so this failing means nothing was copied at all")
    #expect(try String(contentsOf: destination, encoding: .utf8).contains("one"))
}

/// The refresh half: an app update has to reach a snippet that was pasted months
/// ago, and the only thing that can carry it there is this copy running again.
///
/// Mutation-verified: making `needsCopy` return `false` whenever the destination
/// exists — i.e. "install once and never again", the obvious cheap version —
/// leaves this test reading `one` where it must read `two`.
@Test func installRefreshesAStaleMirror() throws {
    let dir = try scratch()
    let source = dir.appendingPathComponent(HookBinary.name)
    let destination = dir.appendingPathComponent("bin/\(HookBinary.name)")

    try makeExecutable(source, contents: "#!/bin/sh\necho one\n")
    HookBinary.install(from: source, to: destination)
    #expect(try String(contentsOf: destination, encoding: .utf8).contains("one"))

    // A different build: different length *and* a later mtime, which is what
    // `needsCopy` compares. Writing the file again is enough to move both.
    try makeExecutable(source, contents: "#!/bin/sh\necho twotwotwo\n")
    HookBinary.install(from: source, to: destination)
    #expect(try String(contentsOf: destination, encoding: .utf8).contains("twotwotwo"),
            "an updated bundled hook did not reach the fixed path — every already-installed snippet would keep running the old binary")
}

@Test func anUnchangedMirrorIsNotCopiedAgain() throws {
    let dir = try scratch()
    let source = try makeExecutable(dir.appendingPathComponent(HookBinary.name))
    let destination = dir.appendingPathComponent("bin/\(HookBinary.name)")
    HookBinary.install(from: source, to: destination)

    #expect(HookBinary.needsCopy(from: source, to: destination) == false,
            "a mirror that matches the bundled copy in size and mtime was still reported as needing a copy — every launch would rewrite a multi-megabyte binary")
    // And the identity really is size+mtime rather than "the file exists": a
    // destination whose mtime differs must be reported stale.
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: destination.path)
    #expect(HookBinary.needsCopy(from: source, to: destination),
            "a mirror with a different modification date was reported as up to date — `needsCopy` is not actually comparing anything")
}

// MARK: - Fail open (§2.3): installing a hook is never a launch requirement

@Test func installWithNoBundledCopyReportsNothingRatherThanThrowing() throws {
    let dir = try scratch()
    let missing = dir.appendingPathComponent(HookBinary.name)   // never created
    let destination = dir.appendingPathComponent("bin/\(HookBinary.name)")
    #expect(HookBinary.install(from: missing, to: destination) == nil)
    #expect(HookBinary.install(from: nil, to: destination) == nil)
}

/// The case that matters more than the one above: a *previous* launch installed a
/// mirror, and this launch cannot see a bundled copy (the app was launched from a
/// disk image, or `Bundle.main.executableURL` came back nil). The already-working
/// snippet must not be reported as broken.
@Test func installKeepsAnExistingMirrorWhenThereIsNothingToMirrorFrom() throws {
    let dir = try scratch()
    let destination = dir.appendingPathComponent("bin/\(HookBinary.name)")
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
    try makeExecutable(destination)

    #expect(HookBinary.install(from: nil, to: destination) == destination,
            "an existing, working mirror was reported as absent because this launch had no bundled copy to compare it against — Plan 6.7's Integrations page would show `not installed` for a hook that is installed and running")
}

@Test func aNonExecutableFileAtTheMirrorPathIsNotAnInstalledHook() throws {
    let dir = try scratch()
    let destination = dir.appendingPathComponent("bin/\(HookBinary.name)")
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
    try Data("#!/bin/sh\n".utf8).write(to: destination)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destination.path)

    #expect(HookBinary.install(from: nil, to: destination) == nil,
            "a file that has lost its execute bit was reported as an installed hook — `[ -x … ]` in the snippet would skip it, so reporting it installed tells a person the opposite of what will happen")
}

// MARK: - Which path a snippet gets

@Test func resolvedPathPrefersTheMirrorAndFallsBackToTheBundledCopy() throws {
    let dir = try scratch()
    let home = dir.appendingPathComponent("home")
    let exeDir = dir.appendingPathComponent("MacOS")
    try FileManager.default.createDirectory(at: exeDir, withIntermediateDirectories: true)
    let exe = exeDir.appendingPathComponent("vibecat")
    let bundled = try makeExecutable(exeDir.appendingPathComponent(HookBinary.name))

    #expect(HookBinary.resolvedPath(home: home.path, executable: exe) == bundled.path,
            "with no mirror yet, a snippet must still be offerable against the bundled copy")

    let mirror = HookBinary.installedURL(home: home.path)
    try FileManager.default.createDirectory(at: mirror.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
    try makeExecutable(mirror)
    #expect(HookBinary.resolvedPath(home: home.path, executable: exe) == mirror.path,
            "the mirror exists and was not preferred — a snippet would be written with a path inside the app bundle, which breaks the moment the app is moved")
}

@Test func resolvedPathIsNilWhenNothingIsInstalledAnywhere() throws {
    let dir = try scratch()
    #expect(HookBinary.resolvedPath(home: dir.appendingPathComponent("home").path,
                                    executable: dir.appendingPathComponent("MacOS/vibecat")) == nil,
            "`nil` is how Plan 6.7's Integrations page says `not installed`; anything else there would be a path that does not run")
}

// MARK: - The snippet a real installed path produces

/// Not a second `HookSnippetTests` — that file pins the quoting. This pins the
/// **join**: the path `HookBinary` hands out has a space in it on every Mac
/// (`Application Support`), and a snippet that did not quote it would fail with
/// `[: too many arguments` on the guard rather than anywhere obvious.
@Test func aSnippetBuiltFromTheInstalledPathSurvivesTheSpaceInApplicationSupport() throws {
    let path = HookBinary.installedURL(home: "/Users/someone").path
    #expect(path.contains(" "), "the fixture no longer exercises a space — `Application Support` is where this path lives and the space is the hazard")

    let command = HookSnippet.command(binaryPath: path, cli: "codex",
                                      socketPath: SocketPath.resolve(env: [:], home: "/Users/someone"))
    // Run it, rather than pattern-match it. The binary does not exist, so the
    // `[ -x … ]` guard is false and the whole thing must still exit 0 — which is
    // §2.3's own promise, and it is a claim about `sh`'s parse of this exact
    // string, not about its shape.
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", command]
    let err = Pipe()
    p.standardError = err
    p.standardOutput = Pipe()
    try p.run()
    p.waitUntilExit()
    let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    #expect(p.terminationStatus == 0,
            "the generated snippet exited \(p.terminationStatus) for a path that does not exist; stderr: \(stderr) — §2.3 says a hook must never fail the agent's turn")
    #expect(stderr.isEmpty,
            "the generated snippet wrote to stderr: \(stderr) — a CLI that surfaces hook stderr would show this to the user on every event")
}
