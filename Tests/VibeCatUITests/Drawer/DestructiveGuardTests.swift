import Testing
import VibeCatCore
@testable import VibeCatUI

@Test func theThreeNamedPatternsAskTwice() {
    #expect(DestructiveGuard.matches("rm -rf build/"))
    #expect(DestructiveGuard.matches("git push --force origin main"))
    #expect(DestructiveGuard.matches("DROP TABLE users;"))
}

/// Case and spacing are the attacker here, and the attacker is a person typing
/// naturally. `-rf`, `-fr`, `-r -f` and `--force` all mean the same thing.
@Test func theMatchSurvivesOrdinaryVariation() {
    #expect(DestructiveGuard.matches("RM -RF /tmp/x"))
    #expect(DestructiveGuard.matches("rm  -fr  node_modules"))
    #expect(DestructiveGuard.matches("git push  --force-with-lease"))
    #expect(DestructiveGuard.matches("drop   table  if exists t"))
}

/// A guard that fires on everything is a guard nobody reads.
@Test func ordinaryCommandsDoNotAskTwice() {
    for safe in ["ls -la", "rm build/one.o", "git push origin main",
                 "swift test", "SELECT * FROM users", "npm run drop-shadow-demo"] {
        #expect(DestructiveGuard.matches(safe) == false, "\(safe) was flagged as destructive")
    }
}

@Test func aQuestionWithNoBodyIsNotDestructive() {
    #expect(DestructiveGuard.matches(nil) == false)
    #expect(DestructiveGuard.matches("") == false)
}

/// The guard has to gate the *reply*, not just light up the UI.
@MainActor @Test func aDestructiveAnswerIsNotAnAnswerUntilConfirmed() {
    let e = VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                      title: "Bash command", body: "rm -rf build/",
                      choices: [Choice(id: "allow", label: "Allow once")],
                      wantsReply: true)
    let m = QuestionModel(event: e)
    m.pick("allow")
    #expect(m.needsConfirmation)
    #expect(m.reply() == nil, "a destructive answer was returned before it was confirmed")
    m.confirm()
    #expect(m.reply()?.choice == "allow")
}

/// Denying something destructive is not itself destructive.
@MainActor @Test func refusingADestructiveCommandNeedsNoConfirmation() {
    let e = VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                      body: "rm -rf build/",
                      choices: [Choice(id: "deny", label: "Deny")], wantsReply: true)
    let m = QuestionModel(event: e)
    m.pick("deny")
    #expect(m.reply()?.choice == "deny")
}

/// Neither lookahead may fire on a word that merely *contains* the letter r
/// or f somewhere in it — only an actual `-r`/`-f`-style flag counts. None of
/// these has a recursive-and-force flag combination; some (`-r folder`) have
/// only one real flag at all. Confirmed by mutating the trailing quantifier
/// from `-{1,2}` back to the brief's original `-{0,2}`: every case here
/// started matching, while `ordinaryCommandsDoNotAskTwice` and every other
/// brief-given test stayed green — that test's own fixture never happens to
/// contain both letters, so it could not have caught this on its own.
@Test func aLetterInsideAnOrdinaryArgumentIsNotAFlag() {
    for safe in ["rm for.txt", "rm refactor.py", "rm -r folder",
                 "rm transfer.log", "rm forecast.csv"] {
        #expect(DestructiveGuard.matches(safe) == false, "\(safe) was flagged as destructive")
    }
}

/// `isPermissive` names both `allow` and `always` — `HookRunner` treats them
/// identically as an authorisation to proceed. Every test above that picks a
/// permissive choice on a destructive body uses `allow`; confirmed by
/// narrowing `isPermissive` to `choiceID == "allow"` and re-running: this is
/// the only test in the file that goes red.
@MainActor @Test func aPermissiveAlwaysChoiceAlsoNeedsConfirmation() {
    let e = VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                      body: "rm -rf build/",
                      choices: [Choice(id: "always", label: "Allow every call this session")],
                      wantsReply: true)
    let m = QuestionModel(event: e)
    m.pick("always")
    #expect(m.needsConfirmation)
    #expect(m.reply() == nil, "an 'always' answer bypassed confirmation")
    m.confirm()
    #expect(m.reply()?.choice == "always")
}

/// `-f` is `--force` spelled shorter, and the more common spelling in
/// practice — §10.3 names a behaviour, not a literal string to grep for.
@Test func theShortFlagSpellingAlsoAsksTwice() {
    #expect(DestructiveGuard.matches("git push -f origin main"))
    #expect(DestructiveGuard.matches("git push origin -f"))
    #expect(DestructiveGuard.matches("git push -f"))
}

/// `-f` must stand as its own token, or it becomes a false-positive magnet:
/// a branch/remote literally named `f`, a hyphenated name that merely
/// *contains* "-f" (its dash is preceded by a letter, not whitespace), and
/// unrelated short flags must all pass straight through. Verified against
/// the real regex engine with a standalone probe script before this landed,
/// not by inspection alone.
@Test func theShortFlagDoesNotBecomeAFalsePositiveMagnet() {
    for safe in ["git push origin feature", "git push origin my-feature-branch",
                 "git push origin f", "git push f main",
                 "git push -u origin main", "git push -v origin main",
                 "git push -n origin main"] {
        #expect(DestructiveGuard.matches(safe) == false, "\(safe) was flagged as destructive")
    }
}

/// Git genuinely accepts bundled short flags for `git push` — confirmed
/// against real git in a scratch repo with a local bare remote:
/// `git push -uf origin main --dry-run` is accepted and reports
/// "(forced update)". So `-uf`/`-fu` are not a strawman; they are real,
/// valid, destructive invocations that must ask twice exactly like `-f` on
/// its own.
@Test func theBundledShortFlagsAlsoAskTwice() {
    #expect(DestructiveGuard.matches("git push -uf origin main"))
    #expect(DestructiveGuard.matches("git push -fu origin main"))
    #expect(DestructiveGuard.matches("git push -nf origin main"))
}

/// A cluster with no `f` anywhere in it is never force, regardless of git's
/// own left-to-right parsing order — there is nothing for any parse to
/// reach. `-un` is set-upstream + dry-run; `-uv` is set-upstream + verbose;
/// neither touches force.
@Test func theBundledClusterRequiresAnActualForceFlagPresent() {
    for safe in ["git push -un origin main", "git push -uv origin main"] {
        #expect(DestructiveGuard.matches(safe) == false, "\(safe) was flagged as destructive")
    }
}

/// git's own left-to-right cluster parsing — not which letters merely
/// appear — decides this. Confirmed against real git in a scratch repo with
/// `receive.advertisePushOptions=true` and a genuinely diverged history:
/// `-foo` parses as `-f` (force) then `-o` swallowing the literal value
/// "o", and reports "(forced update)"; `-of` parses `-o` *first*, which
/// swallows the trailing "f" as its own value, so `-f` is never parsed at
/// all. An earlier version of this file asserted `-foo` must *not* match —
/// on nothing but assumption, the exact shape of bug this task started with.
@Test func orderInsideTheClusterDecidesForceNotJustWhichLettersAppear() {
    #expect(DestructiveGuard.matches("git push -foo origin main --dry-run"),
            "f before o still forces")
    #expect(DestructiveGuard.matches("git push -of origin main --dry-run") == false,
            "o swallows the trailing f as its own value; force is never reached")
}

/// `-flag` is never valid git — it errors "unknown switch 'l'", exit 129,
/// before ever reaching the network — but `f` is still the *first*
/// character parsed, so force is set before that error aborts everything.
/// Matching it anyway is a deliberate trade: a confirmation prompt on a
/// command that was always going to fail is cheap, cheaper than a pattern
/// contorted to exclude it that also risks missing a real `-foo`.
@Test func anInvalidTrailingFlagAfterForceIsStillCaughtRatherThanMissed() {
    #expect(DestructiveGuard.matches("git push -flag origin main"))
}

/// `beginOther()` clears `selected`, and `needsConfirmation` only ever reads
/// `selected` — so a free-text reply against a destructive body is never
/// gated. Pinned deliberately, per `needsConfirmation`'s doc comment: writing
/// something else in place of the proposed command *is* a refusal of it, the
/// same shape as picking `deny`, and refusals are already exempt (see
/// `refusingADestructiveCommandNeedsNoConfirmation`).
@MainActor @Test func aFreeTextReplyToADestructiveBodyNeedsNoConfirmation() {
    let e = VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
                      body: "rm -rf build/",
                      choices: [Choice(id: "allow", label: "Allow once")],
                      wantsReply: true)
    let m = QuestionModel(event: e)
    m.beginOther()
    m.otherText = "use pnpm instead"
    #expect(m.needsConfirmation == false)
    #expect(m.reply()?.text == "use pnpm instead")
}
