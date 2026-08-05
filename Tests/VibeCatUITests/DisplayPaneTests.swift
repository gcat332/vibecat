import Testing
import Foundation
import SwiftUI
import VibeCatCore
@testable import VibeCatUI

/// The same shape as `makeNotificationsPaneModel` (`NotificationsPaneTests.swift`)
/// and for the identical reason: every test in this file and every test in
/// `SettingsSidebarTests`/`NotificationsPaneTests` that has to build a whole
/// `SettingsPaneView`/`SettingsShell`/`SettingsWindowModel` now needs a
/// `DisplayPaneModel` too, since Plan 6.6 Task 6 retired the owner note for
/// `"display"` in favour of the real page. One helper here rather than each call
/// site building its own `InMemoryPreferenceStore` is what keeps a store change
/// from having to land in four files.
@MainActor
func makeDisplayPaneModel(_ preferences: Preferences = Preferences()) -> DisplayPaneModel {
    DisplayPaneModel(store: InMemoryPreferenceStore(preferences))
}

/// A fixed instant for `SessionCardPreview`'s own `now:` parameter — private to
/// this file, the same way `SessionRowTests.swift`'s own `t0` is private to
/// that one. Two renders of the preview have to agree on `now` to be
/// comparable pixel-for-pixel; see `SessionCardPreview.previewSession`'s own
/// doc comment for why the elapsed-time field would otherwise drift between
/// the two renders a test takes.
private let t0 = Date(timeIntervalSince1970: 1_000_000)

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

// MARK: - Task 6: the live preview and the assembled page

/// **`lastUserMessage` really is left `nil`.** `SessionCardPreview`'s own doc
/// comment records why: no adapter anywhere populates this field on a real
/// session, and a preview that faked one would show `Show Your Last Message`
/// doing something no real session ever does. This is the data-level half of
/// that claim; `theShowLastMessageSwitchStillDrawsNothingOnThePreview` below is
/// the rendered half.
@Test @MainActor func thePreviewsFixtureLeavesLastUserMessageUnpopulated() {
    let preview = SessionCardPreview(options: .all)
    #expect(preview.previewSessionForTesting.lastUserMessage == nil,
            "the preview fakes a last-user-message the row would never see on real data")
}

/// **This is what proves the preview reuses `SessionRow` rather than merely
/// resembling it.** A fake that drew its own three lines from scratch could
/// pass every other test in this file while showing nothing the switches
/// actually gate — this asserts the *rendered* pixels move when an option
/// does, the same shape `SessionBlocksTests.eachBlockOptionGatesOnlyItsOwnBlock`
/// uses one layer down.
@MainActor @Test func thePreviewsTasksBlockIsGatedByTheTasksOption() throws {
    let shown = try rasterise(SessionCardPreview(options: .all, now: t0).frame(width: 420))
    let hidden = try rasterise(
        SessionCardPreview(options: SessionRow.Options.all.subtracting(.tasks), now: t0)
            .frame(width: 420))
    #expect(hidden.opaquePixelCount < shown.opaquePixelCount,
            "turning `.tasks` off drew the same preview — the option never reaches the row")
}

/// The honest half of the same claim: `Show Your Last Message`'s own switch
/// changes nothing on this preview, because nothing populates the field it
/// gates — matching what a real session does (or rather, does not do).
@MainActor @Test func theShowLastMessageSwitchStillDrawsNothingOnThePreview() throws {
    let with = try rasterise(SessionCardPreview(options: .all, now: t0).frame(width: 420))
    let without = try rasterise(
        SessionCardPreview(options: SessionRow.Options.all.subtracting(.lastMessage), now: t0)
            .frame(width: 420))
    #expect(with.opaquePixelCount == without.opaquePixelCount,
            "the preview's fixture must carry no lastUserMessage, or this switch would visibly do something the real card cannot")
}

/// **The wiring test, one layer up from the two above.** Nothing here proves
/// `SessionCardPreview` works in isolation is worth anything unless `DisplayPane`
/// actually hands it `model.cardOptions` — a copy-paste slip that hardcoded
/// `.all` at the call site would leave every one of the eight switches silently
/// decorative on this page alone, the exact "persisted but never read" shape
/// this plan's own Global Constraints name three times over. `SessionRow
/// .Options(model.cardOptions)` is the same conversion `IslandModel.cardOptions`
/// uses at launch, so this is also a second, rendered check on that mapping.
@MainActor @Test func theAssembledPagePassesTheStoredCardOptionsToThePreview() throws {
    let allOn = DisplayPaneModel(store: InMemoryPreferenceStore())
    let tasksOff = DisplayPaneModel(store: InMemoryPreferenceStore(
        Preferences(cardOptions: SessionCardOptions(tasks: false))))

    let shown = try rasterise(DisplayPane(model: allOn).frame(width: 654))
    let hidden = try rasterise(DisplayPane(model: tasksOff).frame(width: 654))

    #expect(hidden.opaquePixelCount < shown.opaquePixelCount,
            "a stored `cardOptions.tasks == false` did not change the assembled page's own preview")
}

/// The four groups are a zero-spacing `VStack`, so the assembled page's own
/// height has to equal the sum of its four sections' heights exactly — not
/// merely "at least four card-coloured bands", which the black preview card
/// defeats: it is 200-odd points of *non*-`--card` colour sitting inside the
/// Session card group, tall enough that a band-counting technique (the one
/// `NotificationsPaneTests.theWholePageCarriesAllThreeOfTheProtypesGroups`
/// uses, where no section contains an opaque black box) reads the group's own
/// exposed bottom margin as a fifth band — measured directly: a first version
/// of this test used that technique and read 5 bands for 4 groups.
///
/// **Each section is wrapped in its own `VStack(alignment: .leading, spacing:
/// 0)` before being rasterised alone, and that wrapper is load-bearing, not
/// decoration.** `RightFlankSection.body` (and its three siblings) is a bare
/// multi-statement `some View` — a heading followed by a group, with no
/// container of its own — and `ImageRenderer` given that `TupleView` directly
/// as root content does not lay the two out the same way `DisplayPane`'s own
/// `VStack` does: measured, the four sections rasterised bare summed to
/// 1174pt against the assembled page's own 1142pt, a 32pt gap that closes
/// exactly once each is measured inside the same kind of container that
/// actually hosts it in production.
///
/// Summing four independent renders and comparing to one assembled render is
/// what actually catches a dropped or duplicated section: drop `MotionSection`
/// from `DisplayPane.body` and the assembled height shrinks while the sum of
/// the four independent renders does not move, so the two stop agreeing.
/// Duplicate one and the assembled height grows past the sum instead.
@MainActor @Test func theDisplayPageIsExactlyItsFourSectionsStackedInOrder() throws {
    let model = DisplayPaneModel(store: InMemoryPreferenceStore())
    let width: CGFloat = 654

    func stacked(@ViewBuilder _ content: () -> some View) throws -> Raster {
        try rasterise(VStack(alignment: .leading, spacing: 0, content: content)
            .frame(width: width))
    }

    let whole = try rasterise(DisplayPane(model: model).frame(width: width))
    let right = try stacked { RightFlankSection(model: model) }
    let cat = try stacked { CatSection(model: model) }
    let card = try stacked { SessionCardSection(model: model) }
    let motion = try stacked { MotionSection(model: model) }

    let summedHeight = right.height + cat.height + card.height + motion.height
    #expect(whole.height == summedHeight,
            "the assembled page is \(whole.height)pt tall; its own four sections sum to \(summedHeight)pt — a section was dropped, duplicated, or gained extra spacing between them")
}

@Test @MainActor func writeDisplayPanePNG() throws {
    guard let prefix = ProcessInfo.processInfo.environment["VIBECAT_DISPLAY_PNG"] else { return }
    let model = DisplayPaneModel(store: InMemoryPreferenceStore())
    let raster = try rasterise(
        DisplayPane(model: model)
            .frame(width: 654)
            .background(Color(SettingsPalette.background)),
        scale: 2)
    _ = raster.writePNG(to: "\(prefix).png")
}
