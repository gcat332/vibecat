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
        // `--force` as a substring (deliberately unbounded, so `--force-with-
        // lease` and `--force-if-includes` still count), or the short spelling
        // `-f` — the same flag, not a different one, and the more common
        // spelling in practice — including bundled with `git push`'s other
        // pure-boolean short flags (`-u -n -v -q -d -4 -6`; confirmed against
        // real git in a scratch repo that e.g. `-uf`/`-fu` are accepted and
        // report "(forced update)" — see theBundledShortFlagsAlsoAskTwice).
        // `-o` (`--push-option`) is the one flag from git's own short-flag
        // list left out of the bundle alphabet: it takes a value, and
        // including it lets a cluster degrade into "any word starting with f
        // made of these letters" — `-foo` and `-flag` both read as f+o+o /
        // f+l+a+g under that reading, and neither is a real force flag.
        // Dropping just `-o` closes that without losing any real boolean
        // combination — verified against the engine, not assumed (see
        // theBundledClusterRequiresAnActualForceFlagNotJustFlagShapedLetters).
        // A cluster must stand as its own token (`\s` before, `\b` after),
        // exactly like the standalone spelling, so it inherits the same
        // exclusions: a branch/remote literally named `f`, a hyphenated name
        // like `my-feature-branch` (see theShortFlagDoesNotBecomeAFalsePositiveMagnet).
        #"\bgit\s+push\b(?=.*(?:--force|\s-[fFuUnNvVqQdD46]*[fF][fFuUnNvVqQdD46]*\b))"#,
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
