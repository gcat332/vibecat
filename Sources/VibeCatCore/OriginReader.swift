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

    public static func read(env: [String: String]) -> Origin {
        let app = env["__CFBundleIdentifier"]
            ?? env["TERM_PROGRAM"].flatMap { bundleIDsByTermProgram[$0] }

        return Origin(app: app,
                      termSession: env["TERM_SESSION_ID"],
                      vscodePid: env["VSCODE_PID"])
    }
}
