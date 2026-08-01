import Testing
@testable import VibeCatUI

@Test func withoutASystemPreferenceTheChoiceStands() {
    for level in MotionLevel.allCases {
        #expect(MotionPreference(chosen: level, systemWantsReduced: false).effective == level)
    }
}

/// Design §9.3: the system setting overrides the choice.
@Test func theSystemSettingOverridesAChoiceOfMoreMotion() {
    #expect(MotionPreference(chosen: .full, systemWantsReduced: true).effective == .reduced)
    #expect(MotionPreference(chosen: .reduced, systemWantsReduced: true).effective == .reduced)
}

/// But it does not drag someone who asked for none back into motion.
@Test func theSystemSettingNeverIncreasesMotion() {
    #expect(MotionPreference(chosen: .off, systemWantsReduced: true).effective == .off)
}

@Test func fullLeavesAProfileAlone() {
    let p = MotionPreference(chosen: .full, systemWantsReduced: false)
    let trot = CatMood.trot.motion
    #expect(p.resolve(trot) == trot)
}

@Test func reducedHalvesTheRateButKeepsAnimating() {
    let p = MotionPreference(chosen: .reduced, systemWantsReduced: false)
    let resolved = p.resolve(CatMood.trot.motion)
    #expect(resolved.isContinuous)
    #expect(resolved.framesPerSecond == 8)     // 12 halved is 6, floored to 8
    #expect(resolved.cycle == CatMood.trot.motion.cycle)
}

/// Off is the 0.0% case — nothing may run.
@Test func offStopsEverything() {
    let p = MotionPreference(chosen: .off, systemWantsReduced: false)
    for mood in CatMood.allCases {
        #expect(p.resolve(mood.motion).isContinuous == false)
        #expect(p.resolve(mood.motion).framesPerSecond == 0)
    }
}

/// A profile that was already still stays still at every level.
@Test func aStillProfileIsNeverMadeToMove() {
    for level in MotionLevel.allCases {
        let p = MotionPreference(chosen: level, systemWantsReduced: false)
        #expect(p.resolve(.still).isContinuous == false)
        #expect(p.resolve(CatMood.sleep.motion).isContinuous == false)
    }
}
