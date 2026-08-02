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
                 "git push -n origin main", "git push -foo origin main"] {
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

/// Two ways a bundle-aware pattern could over-match, both closed and pinned
/// here rather than left to the comment alone: a cluster made only of
/// *other* known flag letters, with no `f` anywhere in it (`-un` is
/// set-upstream + dry-run, not force), must not count; and `-o`
/// (`--push-option`, the one bundle letter that takes a value) is
/// deliberately excluded from the alphabet, because keeping it in would let
/// `-foo`/`-flag` parse as "f" plus letters that merely happen to also be
/// flag names — exactly the false-positive magnet
/// `theShortFlagDoesNotBecomeAFalsePositiveMagnet` already refuses for the
/// standalone spelling.
@Test func theBundledClusterRequiresAnActualForceFlagNotJustFlagShapedLetters() {
    for safe in ["git push -un origin main", "git push -uv origin main",
                 "git push -foo origin main", "git push -flag origin main"] {
        #expect(DestructiveGuard.matches(safe) == false, "\(safe) was flagged as destructive")
    }
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
