import Foundation

/// §3's sketch lists `hookInstall` on `SourceAdapter` — *"how to write the hook
/// into that CLI's config"*. This is that, under a name that fits what got
/// built rather than what was sketched: a **shell command line**, not a
/// protocol member, because the thing a person actually pastes is CLI-agnostic
/// — any CLI that can run a command as a hook can run this same invocation —
/// while the *wrapper* around it (Claude Code's is a `"hooks"` block in a JSON
/// settings file; another CLI might use a TOML file or a shell script) is
/// specific to that CLI's own config format and is not this type's job to know.
/// Adding a per-CLI wrapper here would be exactly the branch-in-the-core §3
/// forbids — "a source is configuration, not code."
///
/// **The real invocation, read from the source rather than assumed:**
/// - `Sources/VibeCatHook/main.swift` takes the source id as `argv[1]`
///   (`CommandLine.arguments.dropFirst().first`) and reads the event JSON from
///   **stdin** (`FileHandle.standardInput.readDataToEndOfFile()`) — so the
///   invocation is `<binary> <cli-id>` with the CLI piping its event to stdin,
///   not a flag or an env var carrying the payload.
/// - `Sources/VibeCatCore/SocketPath.swift` resolves the socket from
///   `VIBECAT_SOCKET` if set, else `~/Library/Application Support/VibeCat/
///   vibecat.sock` via `NSHomeDirectory()`. The hook's own `HOME` at the moment
///   the CLI invokes it is not guaranteed to match the GUI app's — a hook can
///   run under `sudo`, inside a container, or under a login shell with a
///   different environment than the one that granted permissions to the app —
///   so the snippet pins the socket explicitly with `VIBECAT_SOCKET=` rather
///   than trusting the two processes to re-derive the same default.
/// - **`vibecat-hook` has an installed home as of Plan 7 Task 6, and this
///   comment used to say it did not.** It is bundled at
///   `VibeCat.app/Contents/MacOS/vibecat-hook` and mirrored on launch to
///   `~/Library/Application Support/VibeCat/bin/vibecat-hook`; `HookBinary
///   .resolvedPath()` is what a caller should pass as `binaryPath`, and that
///   type's doc comment says why the mirror exists rather than the bundle path
///   being used directly. `binaryPath` stays a **required parameter** rather
///   than defaulting to it: this function is pure and testable precisely
///   because it never consults the file system, and Plan 6.7's Integrations
///   page needs to be able to show a snippet for a path a person chose.
/// - `~/.claude/settings.json` on this machine wires an unrelated hook bridge
///   the same way: `"command": "/bin/sh -c '[ -x \"$BIN\" ] && \"$BIN\" ...;
///   exit 0'"` — a guard that skips the binary if it is not there, followed by
///   an unconditional `exit 0`. This snippet follows that precedent for the
///   same reason: `vibecat-hook`'s own `main.swift` already calls `exit(0)`
///   unconditionally, but that only protects a *running* binary. If the binary
///   has not been built yet, moved, or lost its execute bit, the guard is what
///   stops "command not found" from becoming a nonzero exit that could deny a
///   tool call — §2.3 applied one layer outside the Swift process, where the
///   Swift process cannot protect itself.
///
/// **Shell targeted: POSIX `sh`, explicitly, via `/bin/sh -c`.** Not whatever
/// shell the CLI happens to invoke its own hook commands with. That was
/// originally a *guess*, resting only on the `~/.claude/settings.json`
/// precedent above, and Task 6 settled it against a second, independent CLI:
///
/// **Measured, 2026-08-06, against Codex CLI 0.145.0 — a real second CLI, not a
/// fixture.** A probe hook installed in Codex's own `hooks.json` recorded how it
/// was invoked, and reported:
///
/// ```
/// argv0=/bin/zsh          ZSH_VERSION=5.9      BASH_VERSION=unset
/// dash=569X               SHELL=/bin/zsh
/// selfcmd=/bin/zsh -c <the command string, verbatim>
/// ```
///
/// So Codex hands the whole `"command"` string to **`$SHELL -c`** — the *user's*
/// shell, whatever that is, here zsh 5.9 rather than `sh`. (Non-login and
/// non-interactive: no `l` and no `i` in `$-`. The binary's own string table
/// carries `SHELL` next to `-lc` in `hooks/src/engine/command_runner.rs`, which
/// read as a login shell; the empirical run says `-c`, and the run wins. Recorded
/// because reading a flag out of a string table is exactly the kind of inference
/// this note exists to replace.)
///
/// That settles what this wrapper is for, and it is a stronger reason than the
/// one originally given: the outer interpreter is **not a property of the CLI at
/// all**, it is `$SHELL`, so the same `"command"` string is read by a different
/// dialect on every machine. `zsh` and `bash` disagree on word splitting, on
/// `[`'s edge cases and on empty-variable expansion. Wrapping in an explicit
/// `/bin/sh -c` fixes the *inner* dialect to one this file can escape for
/// correctly, whatever the outer one turns out to be. On this machine `/bin/sh`
/// is a build of bash 3.2 in POSIX mode — the same interpreter
/// `Scripts/build-app.sh` was bitten by (an unbraced `$APP…` read as part of the
/// variable name) — and `quoted(_:)` below is written for that dialect
/// specifically.
///
/// The generated snippet was then installed for real and driven: see the Task 6
/// report. Codex ran it, `vibecat-hook` reached the island over the socket, and
/// the hook exited `0`.
///
/// **Two layers of quoting, and this type owns exactly one.** The string this
/// function returns must itself be valid POSIX `sh` — that is `quoted(_:)`'s
/// job, applied to every piece of user input (the binary path, the socket
/// path, the source id) and then once more to the whole guarded command, since
/// it is itself the single argument to `sh -c`. The **second** layer — this
/// whole string becoming the value of a JSON `"command"` key in a CLI's config
/// file — belongs to whatever writes that file, not here: `CustomSource.swift`
/// already writes its JSON through `JSONSerialization`, which escapes a Swift
/// `String` correctly, and hand-rolling a second escaper for the same purpose
/// would be a second parser for something Foundation already gets right.
/// Handing back a pre-JSON-escaped string would double-escape it there.
public enum HookSnippet {
    /// The full `/bin/sh -c '...'` command line to paste into a `"command"`
    /// field (or, for a CLI that is not Claude Code, whatever the equivalent
    /// slot in its own config format is).
    public static func command(binaryPath: String, cli: String, socketPath: String) -> String {
        let guarded = "[ -x \(quoted(binaryPath)) ] && "
            + "VIBECAT_SOCKET=\(quoted(socketPath)) \(quoted(binaryPath)) \(quoted(cli))"
            + "; exit 0"
        return "/bin/sh -c \(quoted(guarded))"
    }

    /// Single-quotes `s` for POSIX `sh`. Inside single quotes, `sh` treats
    /// `$`, `` ` ``, `"`, a literal newline and any non-ASCII byte as inert —
    /// none of them end the quoted string or introduce expansion. The **one**
    /// character that does is `'` itself, which cannot appear inside a
    /// single-quoted string at all; the standard escape is to close the quote,
    /// emit a single, separately-escaped literal quote (`\'`, itself outside
    /// any quoting, is always literal), and reopen: `'\''`. That is the entire
    /// substitution this function performs, and it is the entire defence —
    /// there is no second case to handle once every `'` is replaced this way.
    static func quoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
