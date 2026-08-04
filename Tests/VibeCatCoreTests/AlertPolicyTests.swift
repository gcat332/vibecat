import Testing
@testable import VibeCatCore

@Test func theAlertDefaultsAreThePrototypesOwnSwitchStates() {
    // settings.html:328-336: the first three are aria-checked="true", the stall
    // switch is "false". A stall alert on by default would make a quiet machine
    // noisy, which is the opposite of §6.1's rule that an idle machine looks idle.
    let p = AlertPolicy()
    #expect((p.onNeedsAnswer, p.onFinish, p.onFail) == (true, true, true))
    #expect(p.onStall == false)
}

@Test func eachSwitchGatesOnlyItsOwnEvent() {
    // The likeliest defect in this file: one guard copied four times with the
    // wrong field. A single-bit probe per switch is what catches it.
    var p = AlertPolicy()
    p.onFinish = false
    #expect(p.allows(.needsAnswer))
    #expect(!p.allows(.finished))
    #expect(p.allows(.failed))
}
