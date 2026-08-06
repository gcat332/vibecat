import Foundation

/// The source icons that ship with the app, resolved to a path `SourceIcon` can load.
///
/// ## This reverses §3, on the owner's instruction, and the spec says so
///
/// §3 originally read: *"VibeCat ships neutral geometric marks and lets a source point
/// at its own icon file. Bundling third-party logos is a trademark question we do not
/// need to answer to ship."* Plan 7 built exactly that — a path on the adapter, loaded
/// at runtime, with `CLIMark`'s neutral geometry as the fallback.
///
/// **The owner then asked for the marks to be bundled**, having been told what §3 says
/// and that the repository is public under MIT, which grants copyright permissions and
/// **cannot grant trademark rights**. That is their call to make and it is recorded
/// here and in a dated §3 correction rather than left for someone to infer from a
/// directory listing.
///
/// **What that means in practice, stated plainly because a future reader will need
/// it:** these files are third-party marks distributed in a public repository. The MIT
/// licence in the repository root does not cover them, redistributing them is not
/// something MIT permits on the trademark holders' behalf, and a rights holder asking
/// for one to be removed is a normal outcome rather than a surprise.
///
/// **The mechanism §3 designed still exists and is still the primary path.** An
/// adapter's `icon` is a path, a custom source names its own file, and nothing here
/// is required for VibeCat to work — `CLIMark` still draws when a path resolves to
/// nothing. Bundling adds a default; it did not replace the design.
public enum BundledIcon: String, Sendable, CaseIterable {
    /// Claude Code the CLI — the glyph-only mark, brand-coloured, transparent corners.
    case claudeCode = "claude_logo"
    /// Codex the CLI — likewise glyph-only.
    case codex = "codex_logo"
    /// Claude the desktop app: a filled circle. A §13 jump target, not a CLI.
    case claude
    /// ChatGPT / OpenAI: a filled circle. Also a jump target.
    case openai
    /// iTerm2 and VS Code — §13 jump targets, unused until jump ships.
    case iterm2
    case vscode

    /// The absolute path, or `nil` when the resource bundle is not beside the
    /// executable.
    ///
    /// **`nil` is a supported answer, not a failure.** `Bundle.module` needs the
    /// generated resource bundle next to the running binary, which is true for
    /// `swift run` and for a bundle `Scripts/build-app.sh` assembled — and false for
    /// anything else. `SourceIcon` already falls back to `CLIMark` for a path that
    /// resolves to nothing, and Plan 7's Task 1 proved that for four separate shapes
    /// of bad input, so a missing bundle degrades to the neutral mark rather than to
    /// an empty row.
    public var path: String? {
        Bundle.module.url(forResource: "Icons/\(rawValue)", withExtension: "png")?.path
    }

    /// The icon a source id should use, or `nil` for an id nothing ships a mark for.
    ///
    /// Deliberately a lookup on **id**, not a new adapter field: §3's rule is that a
    /// source is configuration and *"nothing above this line learns their names"*, so
    /// the mapping lives here, beside the assets, rather than as a branch anywhere in
    /// the core. A custom source that wants its own icon names a path and never
    /// reaches this.
    public static func forSourceID(_ id: String) -> BundledIcon? {
        switch id {
        case "claude-code": .claudeCode
        case "codex": .codex
        default: nil
        }
    }
}
