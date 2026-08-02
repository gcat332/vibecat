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
        // short flags (`-u -n -v -q -d -4 -6 -o`; confirmed against real git
        // in a scratch repo that e.g. `-uf`/`-fu` are accepted and report
        // "(forced update)" — see theBundledShortFlagsAlsoAskTwice).
        //
        // git parses a cluster left to right, and that *order* — not merely
        // which letters appear — decides whether force is reached. `-o`
        // (`--push-option`) is the only one of the nine that takes a value:
        // once parsing reaches it, everything left in the token is swallowed
        // as *its* argument, and nothing after that point is parsed as a
        // flag at all. Confirmed against real git in a scratch repo with
        // `receive.advertisePushOptions=true` and a genuinely diverged
        // history: `-foo` parses as `-f` (force) then `-o` taking the
        // literal value "o", and reports "(forced update)"; `-of` parses
        // `-o` *first*, which swallows the trailing "f" as its value, so
        // force is never reached at all (see
        // orderInsideTheClusterDecidesForceNotJustWhichLettersAppear). So the
        // rule: everything *before* the first `f` must be a pure boolean —
        // the alphabet below excludes `o` for exactly that reason — and
        // everything *after* it is irrelevant, because force is already
        // parsed by then, whether what follows is more booleans, an `-o`
        // swallowing the rest, or a character git doesn't recognise at all.
        // That last case is real too: `-flag` makes git error "unknown
        // switch 'l'" and exit before ever reaching the network, but `f` was
        // still the first character parsed, so this still matches it —
        // asking twice on a command that was always going to fail is a
        // cheap trade against missing a real `-foo` (see
        // anInvalidTrailingFlagAfterForceIsStillCaughtRatherThanMissed).
        //
        // A cluster must still stand as its own token (`\s` immediately
        // before the dash): `git push origin f` and `git push origin
        // my-feature-branch` have no leading dash on the argument at all, so
        // neither ever reaches this clause in the first place — see
        // theShortFlagDoesNotBecomeAFalsePositiveMagnet. And a cluster with
        // no `f` anywhere in it is never force regardless of order, because
        // there is nothing for any parse to reach — see
        // theBundledClusterRequiresAnActualForceFlagPresent.
        #"\bgit\s+push\b(?=.*(?:--force|\s-[fFuUnNvVqQdD46]*[fF]))"#,
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
