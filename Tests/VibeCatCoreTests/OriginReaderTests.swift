import Testing
@testable import VibeCatCore

@Test func itermIsIdentifiedByItsBundleId() {
    let o = OriginReader.read(env: [
        "__CFBundleIdentifier": "com.googlecode.iterm2",
        "TERM_SESSION_ID": "w0t1p0:ABC",
    ])
    #expect(o.app == "com.googlecode.iterm2")
    #expect(o.termSession == "w0t1p0:ABC")
    #expect(o.vscodePid == nil)
}

@Test func termProgramIsUsedWhenNoBundleIdIsPresent() {
    let o = OriginReader.read(env: ["TERM_PROGRAM": "Apple_Terminal"])
    #expect(o.app == "com.apple.Terminal")
}

@Test func ghosttyIsRecognised() {
    let o = OriginReader.read(env: ["TERM_PROGRAM": "ghostty"])
    #expect(o.app == "com.mitchellh.ghostty")
}

@Test func vscodeCarriesItsPid() {
    let o = OriginReader.read(env: ["TERM_PROGRAM": "vscode", "VSCODE_PID": "4242"])
    #expect(o.app == "com.microsoft.VSCode")
    #expect(o.vscodePid == "4242")
}

@Test func anUnknownTerminalYieldsAnEmptyOrigin() {
    #expect(OriginReader.read(env: [:]) == Origin())
}

@Test func aNonTerminalGuiAppIsNotMistakenForATerminal() {
    // Measured from a real shell spawned by a desktop app: __CFBundleIdentifier
    // was com.anthropic.claudefordesktop with TERM_PROGRAM unset. Recording that
    // would make the island jump to the wrong application.
    let o = OriginReader.read(env: ["__CFBundleIdentifier": "com.anthropic.claudefordesktop"])
    #expect(o.app == nil)
}

@Test func termProgramWinsOverAConflictingBundleId() {
    let o = OriginReader.read(env: [
        "TERM_PROGRAM": "ghostty",
        "__CFBundleIdentifier": "com.googlecode.iterm2",
    ])
    #expect(o.app == "com.mitchellh.ghostty")
}

@Test func aRecognisedTerminalBundleIdIsStillAcceptedWithoutTermProgram() {
    let o = OriginReader.read(env: ["__CFBundleIdentifier": "com.apple.Terminal"])
    #expect(o.app == "com.apple.Terminal")
}
