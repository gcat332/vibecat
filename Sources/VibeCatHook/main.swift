import Foundation
import VibeCatCore
import VibeCatTransport
import VibeCatHookKit

// usage: vibecat-hook <cli-id>
let cli = CommandLine.arguments.dropFirst().first ?? "claude-code"
let env = ProcessInfo.processInfo.environment

let deadline = env["VIBECAT_TIMEOUT_MS"].flatMap(Double.init).map { $0 / 1000 } ?? 0.3

// Plan 7 Task 3: built-in presets plus whatever §3's custom sources a person
// has defined in `~/Library/Application Support/VibeCat/custom-sources.json`
// — a later one wins on a duplicate id, so a custom source can deliberately
// shadow `claude-code`. All the reading, decoding and fail-open handling for
// a missing or corrupt file lives in `SourceRegistry.loadingCustomSources`
// and `JSONFileCustomSourceStore`, in `VibeCatCore` where a test can reach
// it — this line is the whole of what this untestable file does with it.
let runner = HookRunner(
    registry: SourceRegistry.loadingCustomSources(
        builtIns: [ClaudeCodeAdapter()],
        from: JSONFileCustomSourceStore()),
    client: SocketClient(path: SocketPath.default, deadline: deadline),
    env: env)

let input = FileHandle.standardInput.readDataToEndOfFile()

if let out = runner.run(cli: cli, stdin: input) {
    print(out)
}

// Always zero. A hook that fails must never fail the agent's turn.
exit(0)
