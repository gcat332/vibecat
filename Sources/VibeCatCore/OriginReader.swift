import Foundation

/// Reads where the agent is running from the hook process's own environment.
/// No event is ever read from a GUI app — the GUI is only ever a jump target.
public enum OriginReader {
    static let bundleIDsByTermProgram: [String: String] = [
        "iTerm.app":       "com.googlecode.iterm2",
        "Apple_Terminal":  "com.apple.Terminal",
        "ghostty":         "com.mitchellh.ghostty",
        "WezTerm":         "com.github.wez.wezterm",
        "Alacritty":       "org.alacritty",
        "vscode":          "com.microsoft.VSCode",
        "Hyper":           "co.zeit.hyper",
    ]

    /// Only these are accepted from `__CFBundleIdentifier`. That variable holds
    /// whatever GUI app owns the process tree, which is often not a terminal at
    /// all — a shell spawned by a desktop app reports that app. Recording it
    /// blindly makes the island jump to the wrong application.
    static let knownTerminalBundleIDs: Set<String> =
        Set(bundleIDsByTermProgram.values)

    public static func read(env: [String: String]) -> Origin {
        // TERM_PROGRAM is set by the terminal emulator itself, so it is the
        // trustworthy signal. __CFBundleIdentifier is only a fallback, and only
        // when it names a terminal we recognise.
        let fromTermProgram = env["TERM_PROGRAM"].flatMap { bundleIDsByTermProgram[$0] }
        let fromBundleID = env["__CFBundleIdentifier"]
            .flatMap { knownTerminalBundleIDs.contains($0) ? $0 : nil }

        return Origin(app: fromTermProgram ?? fromBundleID,
                      termSession: env["TERM_SESSION_ID"],
                      vscodePid: env["VSCODE_PID"])
    }
}
