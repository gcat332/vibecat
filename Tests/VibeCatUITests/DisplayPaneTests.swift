import Testing
import Foundation
import SwiftUI
import VibeCatCore
@testable import VibeCatUI

// MARK: - the Motion group writes, and what it writes reaches the island

@Test @MainActor func choosingAMotionLevelPersistsItAndTellsTheIsland() {
    // Two halves, and the second is the one Plan 6.4 shipped broken three times:
    // `volume`, `quietDuringDoNotDisturb` and `selectedPage` were each persisted and
    // never read, through six task reviews. So this asserts the value lands in the
    // store *and* that the change is announced.
    let store = InMemoryPreferenceStore()
    var announced: [MotionLevel] = []
    let model = DisplayPaneModel(store: store) { announced.append($0.motion) }

    model.setMotion(.off)
    #expect(store.load().motion == .off, "the level never reached the store")
    #expect(announced == [.off], "nothing was told the island")
    #expect(model.motion == .off)
}

@Test @MainActor func theFollowSwitchPersistsIndependentlyOfTheLevel() {
    // The clobber hazard, made concrete: `save()` writes the whole struct, so a model
    // holding a snapshot would drop whichever field it did not know about. Writing one
    // field must leave the other alone.
    let store = InMemoryPreferenceStore()
    let model = DisplayPaneModel(store: store)

    model.setMotion(.reduced)
    model.setFollowsSystem(false)
    #expect(store.load().motion == .reduced, "the second write clobbered the first")
    #expect(store.load().followsSystemReduceMotion == false)

    model.setMotion(.full)
    #expect(store.load().followsSystemReduceMotion == false,
            "the third write clobbered the switch")
}

@Test @MainActor func theModelOpensOnWhateverWasStored() {
    // A picker that always opens on `.full` looks right on a fresh install and lies
    // on every launch after the first.
    let store = InMemoryPreferenceStore(
        Preferences(motion: .reduced, followsSystemReduceMotion: false))
    let model = DisplayPaneModel(store: store)
    #expect(model.motion == .reduced)
    #expect(model.followsSystemReduceMotion == false)
}

// MARK: - the level reaches an IslandModel
//
// **Deliberately not a render test.** `MotionBypassTests` already pins what each level
// draws — `withMotionOffTheIslandIsPosedTheSameWayEveryTime`,
// `withMotionOffTheRunningCatsEyesAreOpen`, `withMotionFullTheCatStillBlinks` and
// `withMotionReducedThePhaseStillAdvances`, all rasterised at real instants. A first
// draft of this file re-rendered a cat at two instants and would have duplicated that
// coverage while proving nothing new.
//
// What is new in Plan 6.6 is the *seam*: a level chosen in the pane becoming the level
// an `IslandModel` carries. That is what these assert, and it is the shape of failure
// this project actually ships — Plan 6.4 had three preferences persisted and never
// read, through six task reviews.

@Test @MainActor func aChosenLevelBecomesTheLevelAnIslandModelCarries() {
    let store = InMemoryPreferenceStore()
    var built: MotionPreference?
    let model = DisplayPaneModel(store: store) { prefs in
        built = MotionPreference(chosen: prefs.motion, systemWantsReduced: false,
                                 followsSystem: prefs.followsSystemReduceMotion)
    }

    model.setMotion(.off)
    #expect(built?.chosen == .off)
    #expect(built?.allowsMotion == false, "the island would still be allowed to move")

    model.setMotion(.full)
    #expect(built?.allowsMotion == true)
}

@Test @MainActor func theFollowSwitchChangesWhatTheIslandResolvesToUnderAReducingSystem() {
    // The switch's whole purpose, one layer out from `MotionPreference`'s own tests:
    // with the system asking for less, flipping this changes the *effective* level the
    // island would be handed.
    let store = InMemoryPreferenceStore()
    var built: MotionPreference?
    let model = DisplayPaneModel(store: store) { prefs in
        // systemWantsReduced: true — the case the switch exists for.
        built = MotionPreference(chosen: prefs.motion, systemWantsReduced: true,
                                 followsSystem: prefs.followsSystemReduceMotion)
    }

    model.setFollowsSystem(true)
    #expect(built?.effective == .reduced, "following is on, so the system must win")

    model.setFollowsSystem(false)
    #expect(built?.effective == .full, "following is off, so the user's choice must stand")
}
