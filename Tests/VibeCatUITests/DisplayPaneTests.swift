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

// MARK: - The session card's eight switches

/// **One case per switch would be eight near-identical tests; one case with
/// eight independent models is the same coverage without the copy-paste this
/// task's own brief warns about** — the identical shape
/// `NotificationsPaneTests.eachAlertSwitchWritesItsOwnFieldAndNoNeighbours`
/// already uses for `AlertPolicy`'s four `Bool`s.
///
/// Each block flips *one* switch away from `SessionCardOptions()`'s all-true
/// default and asserts the **whole** struct against the expected value — so a
/// setter pointed at a neighbour's field fails here twice: once for the field
/// that should have changed and didn't, once for the field that shouldn't have
/// and did. A test that only ever set every switch to the same value (all
/// `false`, say) could not tell that apart — flipping *all eight* leaves every
/// field `false` regardless of which setter wrote to which key, which is
/// exactly the "nine booleans that are all false cannot detect a crossed key"
/// trap this plan's own self-review names for Task 1's persistence test.
///
/// Mutation-verified, one at a time: pointing each setter below at a
/// neighbour's `SessionCardOptions` field (`setShowProject` writing
/// `$0.cardOptions.worktree`, and so on) makes exactly two of the eight blocks
/// fail — the one whose own field stayed `true` and the one whose neighbour
/// silently moved. Confirmed for all eight; reverted after. See the task
/// report for the table.
@Test @MainActor func eachSessionCardSwitchWritesItsOwnFieldAndNoNeighbours() {
    let projectStore = InMemoryPreferenceStore()
    DisplayPaneModel(store: projectStore).setShowProject(false)
    #expect(projectStore.load().cardOptions == SessionCardOptions(project: false))

    let worktreeStore = InMemoryPreferenceStore()
    DisplayPaneModel(store: worktreeStore).setShowWorktree(false)
    #expect(worktreeStore.load().cardOptions == SessionCardOptions(worktree: false))

    let modelStore = InMemoryPreferenceStore()
    DisplayPaneModel(store: modelStore).setShowModel(false)
    #expect(modelStore.load().cardOptions == SessionCardOptions(model: false))

    let effortStore = InMemoryPreferenceStore()
    DisplayPaneModel(store: effortStore).setShowEffort(false)
    #expect(effortStore.load().cardOptions == SessionCardOptions(effort: false))

    let lastMessageStore = InMemoryPreferenceStore()
    DisplayPaneModel(store: lastMessageStore).setShowLastMessage(false)
    #expect(lastMessageStore.load().cardOptions == SessionCardOptions(lastMessage: false))

    let tasksStore = InMemoryPreferenceStore()
    DisplayPaneModel(store: tasksStore).setShowTasks(false)
    #expect(tasksStore.load().cardOptions == SessionCardOptions(tasks: false))

    let subagentsStore = InMemoryPreferenceStore()
    DisplayPaneModel(store: subagentsStore).setShowSubagents(false)
    #expect(subagentsStore.load().cardOptions == SessionCardOptions(subagents: false))

    let activityStore = InMemoryPreferenceStore()
    DisplayPaneModel(store: activityStore).setShowActivity(false)
    #expect(activityStore.load().cardOptions == SessionCardOptions(activity: false))
}

/// The clobber hazard, same shape as `theFollowSwitchPersistsIndependentlyOf
/// TheLevel` above: `save()` writes the whole `Preferences`, so each of these
/// eight writers has to `load()` fresh rather than hold a snapshot, or the
/// second switch flipped would silently revert the first.
@Test @MainActor func flippingOneSessionCardSwitchLeavesTheOthersAloneInTheStore() {
    let store = InMemoryPreferenceStore()
    let model = DisplayPaneModel(store: store)

    model.setShowWorktree(false)
    model.setShowTasks(false)
    model.setShowSubagents(false)

    #expect(store.load().cardOptions
            == SessionCardOptions(tasks: false, subagents: false, worktree: false),
            "flipping three switches in sequence did not leave exactly those three fields changed — an earlier write was clobbered")
}

/// The model opens on whatever was stored, not on `SessionCardOptions()`'s own
/// default — the same claim `theModelOpensOnWhateverWasStored` makes for the
/// Motion group, checked here for the session card's own state.
@Test @MainActor func theSessionCardModelOpensOnWhateverWasStored() {
    let store = InMemoryPreferenceStore(
        Preferences(cardOptions: SessionCardOptions(lastMessage: false, subagents: false)))
    let model = DisplayPaneModel(store: store)
    #expect(model.showLastMessageBinding.wrappedValue == false)
    #expect(model.showSubagentsBinding.wrappedValue == false)
    #expect(model.showProjectBinding.wrappedValue == true)
}

/// `SettingsWindowModel.pageBinding`'s recorded defect, checked here for the
/// session card group: a `Binding` built from `@Bindable`'s straight-to-storage
/// form updates the view and persists nothing. The eight setters above could
/// all be correct while every switch on this row wrote to a dead end.
@Test @MainActor func aSessionCardWriteGoesThroughTheBindingAndNotOnlyTheSetter() {
    let store = InMemoryPreferenceStore()
    let model = DisplayPaneModel(store: store)

    model.showActivityBinding.wrappedValue = false
    model.showProjectBinding.wrappedValue = false

    #expect(store.load().cardOptions == SessionCardOptions(activity: false, project: false))
}

// MARK: - Task 5: the right flank and the coat

@Test @MainActor func choosingARightFlankPersistsIt() {
    let store = InMemoryPreferenceStore()
    let model = DisplayPaneModel(store: store)

    model.setRightFlank(.agentIcon)
    #expect(store.load().rightFlank == .agentIcon, "the choice never reached the store")
    #expect(model.rightFlank == .agentIcon)
}

@Test @MainActor func choosingACoatPersistsIt() {
    let store = InMemoryPreferenceStore()
    let model = DisplayPaneModel(store: store)

    model.setCoat(.siamese)
    #expect(store.load().coat == .siamese, "the choice never reached the store")
    #expect(model.coat == .siamese)
}

/// The clobber hazard again, this time across all four of this task's and
/// Task 3's writers in sequence — `save()` writes the whole `Preferences`, so
/// a model holding a snapshot rather than `load()`-mutate-`save()`-ing fresh
/// would drop whichever fields it did not just write.
@Test @MainActor func rightFlankAndCoatWritesDoNotClobberEachOtherOrTheMotionGroup() {
    let store = InMemoryPreferenceStore()
    let model = DisplayPaneModel(store: store)

    model.setMotion(.reduced)
    model.setRightFlank(.nothing)
    model.setCoat(.tuxedo)

    let saved = store.load()
    #expect(saved.motion == .reduced, "the coat/rightFlank writes clobbered the motion group")
    #expect(saved.rightFlank == .nothing, "a later write clobbered the right flank")
    #expect(saved.coat == .tuxedo, "the third write did not land")
}

/// Same claim `theModelOpensOnWhateverWasStored` makes for the Motion group,
/// checked here for the right flank and the coat.
@Test @MainActor func theRightFlankAndCoatModelsOpenOnWhateverWasStored() {
    let store = InMemoryPreferenceStore(
        Preferences(rightFlank: .agentIcon, coat: .patched))
    let model = DisplayPaneModel(store: store)
    #expect(model.rightFlank == .agentIcon)
    #expect(model.coat == .patched)
}

/// `SettingsWindowModel.pageBinding`'s recorded defect, checked here the same
/// way `aSessionCardWriteGoesThroughTheBindingAndNotOnlyTheSetter` checks it
/// for the session card: a `Binding` built from `@Bindable`'s straight-to-
/// storage form updates the view and persists nothing.
@Test @MainActor func aRightFlankOrCoatWriteGoesThroughTheBindingAndNotOnlyTheSetter() {
    let store = InMemoryPreferenceStore()
    let model = DisplayPaneModel(store: store)

    model.rightFlankBinding.wrappedValue = .nothing
    model.coatBinding.wrappedValue = .plain

    #expect(store.load().rightFlank == .nothing)
    #expect(store.load().coat == .plain)
}

/// `RightFlank.label`'s three cases against `settings.html:411`'s own three
/// button texts — pinned directly since `SettingsSegmentedTests` already
/// covers `SettingsSegmented` generically and has no reason to know this
/// particular enum's words.
@Test func rightFlankLabelsMatchThePrototype() {
    #expect(RightFlank.sessionCount.label == "Count")
    #expect(RightFlank.agentIcon.label == "Agent icon")
    #expect(RightFlank.nothing.label == "Nothing")
}

/// `Coat.displayName`'s five cases against `settings.html:596`'s own
/// `COATNAMES`.
@Test func coatDisplayNamesMatchThePrototype() {
    #expect(Coat.tabby.displayName == "Tabby")
    #expect(Coat.plain.displayName == "Plain")
    #expect(Coat.tuxedo.displayName == "Tuxedo")
    #expect(Coat.siamese.displayName == "Siamese")
    #expect(Coat.patched.displayName == "Patched")
}
