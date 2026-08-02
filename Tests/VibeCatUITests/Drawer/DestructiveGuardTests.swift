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
