import Foundation

/// Design §10.3: `rm -rf`, `git push --force` and `drop table` ask twice.
///
/// Three patterns, not a general danger heuristic. A guard that fires on
/// everything is one nobody reads, so `rm build/one.o` and `git push origin
/// main` pass straight through — the tests name the ones that must.
public enum DestructiveGuard {
    private static let patterns = [
        // rm with a recursive AND a force flag, in either order, together or
        // apart: -rf, -fr, -r -f, --recursive --force. Each trailing segment
        // requires an actual dash (`-{1,2}`, not `-{0,2}`) — without it the
        // lookahead degrades to "some later word contains the letter r/f
        // anywhere", which flags ordinary filenames like `transfer.log` or
        // `refactor.py`, or even a plain recursive delete like `rm -r folder`
        // (whose argument merely starts with an 'f').
        #"\brm\b(?=(?:\s+-{1,2}\w+)*\s+-{1,2}\w*[rR])(?=(?:\s+-{1,2}\w+)*\s+-{1,2}\w*[fF])"#,
        #"\bgit\s+push\b(?=.*--force)"#,
        #"\bdrop\s+table\b"#,
    ]

    public static func matches(_ body: String?) -> Bool {
        guard let body, !body.isEmpty else { return false }
        return patterns.contains { pattern in
            body.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    /// The answers that actually carry the danger. Refusing a destructive
    /// command is not itself destructive, so it is not gated.
    public static func isPermissive(_ choiceID: String) -> Bool {
        choiceID == "allow" || choiceID == "always"
    }
}
