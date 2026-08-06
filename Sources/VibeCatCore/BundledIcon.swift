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
    /// Gemini the CLI.
    ///
    /// **A PNG, because the SVG could not be rendered.** `gemini-color.svg` produced
    /// 475 opaque pixels out of 65536 through CoreSVG *regardless of what the file
    /// contained* — measured against three progressively simplified rewrites, all
    /// byte-identical — and QuickLook returned a white page with the glyph in a
    /// corner. Its root used `width="1em"` and its glyph was three stacked copies of
    /// one path, two referencing React-generated gradient ids (`_R_0_`). The owner
    /// supplied a 640x640 PNG instead; it is downscaled to 256 like the rest.
    case gemini
    /// Claude the desktop app: a filled circle. A §13 jump target, not a CLI.
    case claude
    /// ChatGPT / OpenAI: a filled circle. Also a jump target.
    case openai
    /// iTerm2 and VS Code — §13 jump targets.
    ///
    /// **`iterm2` doubles as the mark for any source nothing else ships one for**, on
    /// the owner's instruction. Its palette is why that works rather than jars:
    /// measured, the file fills with `#0078D4` and `#f2f2f2` — Microsoft blue on
    /// off-white, not iTerm2's black terminal — so it reads as a generic *code* mark
    /// and not as a claim that some other CLI is iTerm2. **The file is very likely
    /// mislabelled**, and that mislabelling is what makes it a serviceable default.
    case iterm2
    case vscode

    /// How much of its slot this mark should occupy, measured rather than guessed.
    ///
    /// `iconWeight` renders every mark in the row's real 16pt slot and reports what it
    /// paints. With the scale applied: `vscode` and `codex_logo` both fill 85.9%,
    /// `gemini` 90.6%, `iterm2` 93.8%, and the two filled circles 100% — a 1.16×
    /// spread that is the assets' own, not something this value tries to flatten.
    ///
    /// **`vscode` is scaled because the owner looked at it and said so.** Its chevron
    /// reaches corner to corner diagonally, so it reads heavier than a circle of the
    /// same box; 0.86 puts it level with `codex_logo`, the other diagonal glyph.
    ///
    /// **The first version of this comment claimed a 1.02× spread and that nothing
    /// needed scaling. That was a broken measurement**, not a finding: the probe
    /// thresholded on `Pixel.isTransparent` (`a == 0`), so it counted antialiased
    /// edge pixels and reported every mark at 98–100% — the canvas, not the glyph.
    /// Left recorded because the wrong number was the more convincing one.
    public var opticalScale: Double {
        switch self {
        case .vscode: 0.86
        default: 1
        }
    }

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
    /// Never `nil` while any mark ships: an id nothing has a mark for gets `iterm2`,
    /// which is a generic code mark rather than another CLI's identity — see that
    /// case's own note.
    ///
    /// **This trades one §4.3 property for another, and the trade is deliberate.**
    /// Shape says which agent is speaking, so one mark shared by every unknown source
    /// says less than `CLIMark`'s four geometries did — `CLIMark(cli:)` at least maps
    /// several known names to distinct shapes. What it buys is that an unknown source
    /// is *visibly a source* at a glance instead of falling through to a shape that
    /// looked like a mark for nothing in particular. The owner asked for it, and the
    /// property it gives up is named here rather than lost.
    ///
    /// `CLIMark` is still the fallback below this: if the resource bundle is missing,
    /// `path` returns `nil` and `SourceIcon` draws geometry, which is what shipped
    /// before any of this existed.
    public static func forSourceID(_ id: String) -> BundledIcon {
        switch id {
        case "claude-code": .claudeCode
        case "codex": .codex
        case "gemini": .gemini
        case "claude": .claude
        case "chatgpt", "openai": .openai
        case "vscode", "code": .vscode
        default: .iterm2
        }
    }
}
