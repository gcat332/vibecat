import Foundation
import Testing
@testable import VibeCatCore

/// `HookSnippet.command` produces a string that itself gets *executed* by a
/// shell (the CLI's own hook runner, or — since the tested shape wraps
/// itself in an explicit `/bin/sh -c` — the shell this test spawns to stand
/// in for that runner). So the tests that matter here do not read the string;
/// they **run** it, through a stand-in "hook binary" that records exactly
/// what it was invoked with, and check the recording — a test that only
/// inspected the string for a substring could pass with the escaping
/// silently broken, as long as the broken output happened to still contain
/// the right words somewhere.
///
/// A hostile id here is never a real destructive payload (no literal
/// `rm -rf`): if the escaping under test were actually broken, the test
/// process itself would be the one running whatever expanded. Each hostile
/// case instead plants a *sentinel* — `touch <marker>` inside `$()` or
/// backticks — and asserts the marker file was never created, which proves
/// no expansion happened without ever risking real damage if it had.
private func runShellSnippet(_ command: String, extraEnv: [String: String] = [:])
    throws -> (stdout: String, status: Int32)
{
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    var environment = ProcessInfo.processInfo.environment
    for (k, v) in extraEnv { environment[k] = v }
    process.environment = environment

    let outPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = Pipe()
    try process.run()
    let out = outPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (String(decoding: out, as: UTF8.self), process.terminationStatus)
}

/// Writes an executable `/bin/sh` script at a fresh temp path that, when run,
/// writes its own `argv[1]` (the source id `HookSnippet.command` passes) and
/// `$VIBECAT_SOCKET` to two files a test can read back — the ground truth
/// for "did the id and the socket path arrive exactly as given," rather than
/// inferring it from what the generated string merely *looks* like.
private func makeFakeHook(_ n: String) throws -> (binary: URL, argFile: URL, envFile: URL) {
    let dir = FileManager.default.temporaryDirectory
    let binary = dir.appendingPathComponent("vibecat-hooksnippet-fake-\(n)-\(getpid())")
    let argFile = dir.appendingPathComponent("vibecat-hooksnippet-arg-\(n)-\(getpid())")
    let envFile = dir.appendingPathComponent("vibecat-hooksnippet-env-\(n)-\(getpid())")
    let script = """
    #!/bin/sh
    printf '%s' "$1" > '\(argFile.path)'
    printf '%s' "$VIBECAT_SOCKET" > '\(envFile.path)'
    exit 0
    """
    try script.write(to: binary, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    return (binary, argFile, envFile)
}

private func cleanup(_ urls: URL...) {
    for url in urls { try? FileManager.default.removeItem(at: url) }
}

// MARK: - the snippet names the binary and the socket path

@Test func theSnippetNamesTheBinaryAndTheSocketPath() {
    let command = HookSnippet.command(binaryPath: "/usr/local/bin/vibecat-hook",
                                       cli: "claude-code",
                                       socketPath: "/tmp/vibecat.sock")
    #expect(command.contains("/usr/local/bin/vibecat-hook"))
    #expect(command.contains("/tmp/vibecat.sock"))
    #expect(command.contains("claude-code"))
    #expect(command.hasPrefix("/bin/sh -c "))
}

@Test func theWholeCommandLineActuallyRunsAndInvokesTheRealBinaryWithTheRealId() throws {
    let (binary, argFile, envFile) = try makeFakeHook("happy")
    defer { cleanup(binary, argFile, envFile) }

    let command = HookSnippet.command(binaryPath: binary.path, cli: "claude-code",
                                       socketPath: "/tmp/vibecat-happy.sock")
    let result = try runShellSnippet(command)

    #expect(result.status == 0)
    #expect(try String(contentsOf: argFile, encoding: .utf8) == "claude-code")
    #expect(try String(contentsOf: envFile, encoding: .utf8) == "/tmp/vibecat-happy.sock")
}

// MARK: - a missing binary fails open (§2.3 at the shell layer)

@Test func aBinaryThatDoesNotExistStillExitsZero() throws {
    let command = HookSnippet.command(binaryPath: "/tmp/vibecat-hooksnippet-nonexistent-\(getpid())",
                                       cli: "claude-code", socketPath: "/tmp/vibecat.sock")
    let result = try runShellSnippet(command)
    #expect(result.status == 0)
}

// MARK: - hostile source ids: each must arrive byte-for-byte, unexpanded

@Test func aSourceIdWithASpaceArrivesIntact() throws {
    try assertIdSurvives("my cli", label: "space")
}

@Test func aSourceIdWithASingleQuoteArrivesIntact() throws {
    try assertIdSurvives("it's mine", label: "singlequote")
}

@Test func aSourceIdWithADoubleQuoteArrivesIntact() throws {
    try assertIdSurvives(#"say "hi" cli"#, label: "doublequote")
}

@Test func aSourceIdWithANewlineArrivesIntact() throws {
    try assertIdSurvives("line one\nline two", label: "newline")
}

@Test func aSourceIdWithNonASCIIArrivesIntact() throws {
    try assertIdSurvives("café🐱名前", label: "nonascii")
}

/// `$()` command substitution is the dangerous case: if `quoted(_:)` ever let
/// a `'` through unescaped (or dropped the quoting entirely), this id would
/// not just fail to match — the substituted command would actually run. So
/// this asserts two things: the id round-trips exactly, **and** the sentinel
/// file the embedded command would have created does not exist.
@Test func aSourceIdWithDollarParenDoesNotExpand() throws {
    let sentinel = FileManager.default.temporaryDirectory
        .appendingPathComponent("vibecat-hooksnippet-pwned-dollar-\(getpid())")
    defer { try? FileManager.default.removeItem(at: sentinel) }
    let hostile = "$(touch \(sentinel.path))"

    try assertIdSurvives(hostile, label: "dollarparen")
    #expect(!FileManager.default.fileExists(atPath: sentinel.path))
}

/// Same hazard, backtick spelling — `$()` and `` ` `` are the two command
/// substitution syntaxes POSIX `sh` recognises, and a quoting bug could plug
/// one without the other.
@Test func aSourceIdWithBacktickCommandSubstitutionDoesNotExpand() throws {
    let sentinel = FileManager.default.temporaryDirectory
        .appendingPathComponent("vibecat-hooksnippet-pwned-backtick-\(getpid())")
    defer { try? FileManager.default.removeItem(at: sentinel) }
    let hostile = "`touch \(sentinel.path)`"

    try assertIdSurvives(hostile, label: "backtick")
    #expect(!FileManager.default.fileExists(atPath: sentinel.path))
}

/// Every hazard named in the plan, in one id, plus a leading `-` (which could
/// otherwise be read as a flag) — the combination a real hand-edited config
/// is more likely to produce than any single case alone.
@Test func aSourceIdCombiningEveryHazardArrivesIntact() throws {
    let sentinel = FileManager.default.temporaryDirectory
        .appendingPathComponent("vibecat-hooksnippet-pwned-combo-\(getpid())")
    defer { try? FileManager.default.removeItem(at: sentinel) }
    let hostile = "-weird `touch \(sentinel.path)` $(touch \(sentinel.path)) \"it's\" a\nb"

    try assertIdSurvives(hostile, label: "combo")
    #expect(!FileManager.default.fileExists(atPath: sentinel.path))
}

/// A hostile binary path and socket path get the same treatment as a hostile
/// id: both are user input too (a hand-typed install location, a `VIBECAT_
/// SOCKET` override), and `HookSnippet.command` runs every piece through the
/// same `quoted(_:)`.
@Test func aBinaryPathWithASpaceAndQuoteStillRunsTheRealBinary() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("vibecat hook's dir \(getpid())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let binary = dir.appendingPathComponent("vibecat-hook")
    let argFile = dir.appendingPathComponent("arg")
    let envFile = dir.appendingPathComponent("env")
    let script = """
    #!/bin/sh
    printf '%s' "$1" > '\(argFile.path.replacingOccurrences(of: "'", with: "'\\''"))'
    printf '%s' "$VIBECAT_SOCKET" > '\(envFile.path.replacingOccurrences(of: "'", with: "'\\''"))'
    exit 0
    """
    try script.write(to: binary, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

    let command = HookSnippet.command(binaryPath: binary.path, cli: "claude-code",
                                       socketPath: "/tmp/vibecat.sock")
    let result = try runShellSnippet(command)

    #expect(result.status == 0)
    #expect(try String(contentsOf: argFile, encoding: .utf8) == "claude-code")
}

private func assertIdSurvives(_ id: String, label: String) throws {
    let (binary, argFile, envFile) = try makeFakeHook(label)
    defer { cleanup(binary, argFile, envFile) }

    let command = HookSnippet.command(binaryPath: binary.path, cli: id,
                                       socketPath: "/tmp/vibecat.sock")
    let result = try runShellSnippet(command)

    #expect(result.status == 0)
    #expect(try String(contentsOf: argFile, encoding: .utf8) == id)
}

// MARK: - `quoted(_:)` in isolation

@Test func quotedWrapsPlainTextInSingleQuotes() {
    #expect(HookSnippet.quoted("plain") == "'plain'")
}

@Test func quotedEscapesEveryEmbeddedSingleQuote() {
    #expect(HookSnippet.quoted("it's") == "'it'\\''s'")
    #expect(HookSnippet.quoted("''") == "''\\'''\\'''")
}
