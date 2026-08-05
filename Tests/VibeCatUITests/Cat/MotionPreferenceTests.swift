import Testing
import VibeCatCore
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

// MARK: - §14's "Follow the system Reduce Motion setting"
//
// Plan 6.6's plan file called this switch a contradiction with §9.3 and asked for a
// dated spec correction. It is not, and §9.3 is unchanged. §9.3 reads: "Settings
// offers Full / Reduced / Off, and **by default** follows the system Reduce Motion
// setting, which overrides the choice." Those two words presuppose the switch, and
// §14 lists it. The contradiction came from `CLAUDE.md`'s summary, which kept the
// override's direction and dropped the qualifier — the same failure mode as the
// `9px` radius Plan 6.3 untangled.

@Test func followingIsOnByDefaultSoTheSystemStillOverrides() {
    // The half of §9.3 that was never in doubt, pinned so the new field cannot
    // quietly invert it.
    let p = MotionPreference(chosen: .full, systemWantsReduced: true)
    #expect(p.followsSystem, "the default must be to follow, per §9.3's 'by default'")
    #expect(p.effective == .reduced, "a system asking for less must still win")
}

@Test func turningFollowingOffLetsAUserKeepFullMotion() {
    // What the switch is *for*. With it off, the system's bit is ignored — which is
    // the one thing `effective` did unconditionally before and is why the switch
    // could not have been shipped as decoration.
    let following = MotionPreference(chosen: .full, systemWantsReduced: true, followsSystem: true)
    let not = MotionPreference(chosen: .full, systemWantsReduced: true, followsSystem: false)
    #expect(following.effective == .reduced)
    #expect(not.effective == .full, "the switch is off, so the system must not override")
}

@Test func theSwitchCannotDragAUserWhoChoseOffBackIntoMotion() {
    // §9.3's one-way rule, which the switch does not touch: it can only stop the
    // system from *reducing*, never promote a chosen level upward. Both settings of
    // the switch must leave `off` alone.
    for follows in [true, false] {
        let p = MotionPreference(chosen: .off, systemWantsReduced: true, followsSystem: follows)
        #expect(p.effective == .off, "followsSystem: \(follows) promoted `off`")
        #expect(!p.allowsMotion)
    }
}

@Test func theSwitchChangesNothingWhenTheSystemIsNotAskingForLess() {
    // Guards against a fix that made `followsSystem` a second motion level rather
    // than a gate on the override. With the system quiet, all four combinations must
    // agree with the user's own choice.
    for follows in [true, false] {
        for chosen in MotionLevel.allCases {
            let p = MotionPreference(chosen: chosen, systemWantsReduced: false,
                                     followsSystem: follows)
            #expect(p.effective == chosen,
                    "chosen \(chosen), follows \(follows) drifted to \(p.effective)")
        }
    }
}

@Test @MainActor func aRefreshKeepsTheUsersFollowingChoiceAndNotJustTheirLevel() {
    // The file's own doc comment warns that `current()` cannot serve as `refreshed()`
    // because its `chosen` defaults to `.full` and would promote a user who chose
    // `off`. `followsSystem` defaults to `true` and has exactly the same hazard one
    // field later — omitting it in `refreshed()` would silently switch following back
    // on the first time the system posted an accessibility change.
    let p = MotionPreference(chosen: .reduced, systemWantsReduced: false, followsSystem: false)
    let after = p.refreshed()
    #expect(after.followsSystem == false, "the refresh re-enabled following")
    #expect(after.chosen == .reduced, "the refresh moved the chosen level")
}
