import SwiftUI
import VibeCatCore

/// §14's Display pane. Plan 6.6.
///
/// **Only the controls whose behaviour exists.** The page offers 21 and roughly
/// eight switch nothing anywhere in this repo — Clean/Detailed island tiers,
/// `Meter`/`Dot` instead of the cat, the four panel-size sliders, the two
/// notch-tuning offsets, the multi-display picker, editable state colours,
/// Content Font Size, Completion Card Height — with the reveal's `Always`/`Never`
/// having only their `On hover` case built. Those are Plan 6.8's.
///
/// The rule comes from Plan 6.5, which met it with the `Soft`/`System`/`Blip`
/// sound packs: **a menu item that silently does nothing is worse than a shorter
/// menu.** Plan 6.1 restated it after leaving `.agentIcon` selectable and blank.
struct DisplayPane: View {
    let model: DisplayPaneModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RightFlankSection(model: model)
            CatSection(model: model)
            SessionCardSection(model: model)
            MotionSection(model: model)
        }
    }
}

/// `settings.html:409-417`'s `Right of the notch` group — §6.2's collapsed
/// content picker, wired to `Preferences.rightFlank`. Plan 6.6's Task 5.
///
/// **One row of two, and the other is left out on purpose.** `Reveal names
/// and timings` (`:412-413`) offers `On hover | Always | Never`, and only `On
/// hover` has ever been built anywhere in this repo — `Always`/`Never` are two
/// whole alternative hover-reveal behaviours, not a label this control could
/// pick between. Per the shorter-menu rule (Plan 6.5's `Soft`/`System`/`Blip`,
/// restated by Plan 6.1 after `.agentIcon` shipped selectable-and-blank): a
/// menu item that silently does nothing is worse than a shorter menu, so the
/// row is missing entirely rather than drawn with two dead thirds.
struct RightFlankSection: View {
    let model: DisplayPaneModel

    var body: some View {
        SettingsSectionHeading("Right of the notch", isNew: true)
        SettingsGroup {
            SettingsRow("Collapsed, show",
                detail: "A brand mark tells you what you already know. A count tells you "
                    + "how many sessions are open, and its colour tells you what they are doing.") {
                SettingsSegmented(model.rightFlankBinding) { $0.label }
            }
        }
    }
}

/// `settings.html:419-427`'s `The cat` group — §7.3's coat picker and the
/// read-only state-colour reference. Plan 6.6's Task 5.
///
/// **Two rows of three, and the first is left out on purpose.** `Left of the
/// notch` (`:420-422`) offers `Cat | Meter | Dot`, and only `Cat` has ever
/// existed — `Meter` and `Dot` are two whole alternative left-flank renderers
/// (this plan's own "Out of scope" section: Plan 6.8's), so shipping this row
/// would offer two choices that draw nothing different from what is already
/// on screen. The same shorter-menu rule `RightFlankSection` names for the row
/// beside it.
struct CatSection: View {
    let model: DisplayPaneModel

    var body: some View {
        SettingsSectionHeading("The cat", isNew: true)
        SettingsGroup {
            SettingsRow("Coat") {
                CoatPickerRow(coat: model.coatBinding)
            }
            SettingsRow("State colours",
                detail: "Colour only ever means state. Which agent is speaking is carried by its icon.") {
                StateSwatchesRow()
            }
        }
    }
}

/// `settings.html:423`'s `#skins` — five JS-rendered swatches
/// (`settings.html:588-590`), each a small cat wearing one coat with its own
/// name beneath it, the selected one outlined.
///
/// Reuses `CatCanvas` rather than re-implementing the sprite: a preview that
/// drew its own copy of the grid could drift from what the island actually
/// paints, and the whole point of showing five cats here is that they are the
/// same cat this picker changes.
struct CoatPickerRow: View {
    @Binding var coat: Coat

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Coat.allCases, id: \.self) { option in
                CoatSwatch(coat: option, isSelected: option == coat) {
                    coat = option
                }
            }
        }
    }
}

private struct CoatSwatch: View {
    let coat: Coat
    let isSelected: Bool
    let action: () -> Void

    /// The preview's own cell size — large enough that a `tabby` bar and a
    /// `plain` cheek read as different swatches at a glance, the same reason
    /// `CatGridTests.everyPairOfCoatsIsTellableApart` exists at the grid level.
    private static let cellSize: CGFloat = 2

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                // `settings.html:588`'s own preview colour
                // (`catSVG('#EDEFF4', 1, COATS[k])`) — **not** an `IslandState`
                // accent. This row previews *markings*, not mood, and tinting it
                // by state would be exactly the contamination §4.3 exists to
                // rule out: "a coat changes markings, never hue."
                CatCanvas(cat: ResolvedCat(coat: coat, mood: .happy, phase: 0),
                          palette: CatPalette(accent: CoatSwatchMetrics.previewColour),
                          cellSize: Self.cellSize,
                          motion: MotionPreference(chosen: .off, systemWantsReduced: false))
                    .frame(width: CGFloat(CatGrid.width) * Self.cellSize,
                           height: CGFloat(CatGrid.height) * Self.cellSize)
                Text(coat.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(SettingsPalette.haze))
            }
            // `settings.html:589`'s own inline override for exactly this button
            // (`style="padding:7px 8px;min-width:0;gap:5px"`), not `.mode`'s base
            // `padding:11px` (`:155`).
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            // `.mode{background:#1F1F22;...border-radius:9px}` (`:155`) — the
            // same `#1F1F22` `.seg`'s own container uses
            // (`SettingsSegmentedMetrics.container`), reused rather than
            // re-declared, and **not** `--card2`: a first pass drew this in
            // `--card2` (`#323236`), which is a different token for a different
            // control (`.sel`/`.btn`) and would have painted every swatch a shade
            // lighter than the prototype's own picker.
            .background(Color(SettingsSegmentedMetrics.container))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay {
                // `.mode{border:2px solid transparent}`, `:157`
                // `.mode[aria-pressed="true"]{border-color:var(--blue)}` — a
                // `2px` blue border, not a background fill.
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected ? Color(SettingsPalette.systemBlue) : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

private enum CoatSwatchMetrics {
    static let previewColour = RGBA(hex: "#EDEFF4")!
}

extension Coat {
    /// `settings.html:596`'s `COATNAMES`.
    var displayName: String {
        switch self {
        case .tabby:   "Tabby"
        case .plain:   "Plain"
        case .tuxedo:  "Tuxedo"
        case .siamese: "Siamese"
        case .patched: "Patched"
        }
    }
}

/// `settings.html:426`'s `#swatches` — four static squares
/// (`settings.html:593-595`), unpickable.
///
/// **Deliberately read-only.** §4.3 is the constraint the row's own sub-label
/// quotes: the four hues *mean* the four states, so a picker here would be
/// offering to change what state colour *means*, not merely what it looks
/// like — a new preference and a new invariant question ("does `waiting`
/// still mean amber once it can be repainted?") this plan defers rather than
/// invents an answer for. Showing the hues is honest; matching them to a
/// picker is not.
///
/// **The one legitimate reach for `IslandState.accent` in this file.** The
/// Global Constraint bars `Sources/VibeCatUI/Settings/` from the island's
/// state colour because a settings switch is blue because it is on, never
/// because some agent is blocked — but this row previews island state on
/// purpose, the same exception `SettingsPill`'s `.granted`/`.denied` colours
/// already use, and `theStateHuesInSettingsAreTheIslandsExactlyBecauseThey
/// PreviewIt` (`SettingsPaletteTests.swift`) is what keeps this from drifting.
struct StateSwatchesRow: View {
    /// `.dormant` excluded — `settings.html`'s own `STATES` names four, not
    /// five: "no sessions at all" is not a state a person picks a colour to
    /// recognise.
    private static let states: [IslandState] = [.idle, .running, .waiting, .failed]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Self.states, id: \.self) { state in
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(state.accent))
                    .frame(width: 22, height: 22)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    }
            }
        }
    }
}

/// `settings.html:444-490`'s `Session card` group — §11's nine switch points
/// (`SessionRow.Options`), Plan 6.6's Task 4.
///
/// **Eight rows, not nine**, despite this task's own brief saying "nine"
/// twice. The prototype offers exactly eight — `Show Project Name` through
/// `Show Agent Activity Detail` — and `SessionRow.Options.agents` (the
/// whole-block hide, as opposed to `.subagents`' collapse-to-count) has no row
/// here at all; only `Show Subagents` exists, and its detail text below is the
/// prototype's own words for `.subagents`'s collapse behaviour, not for
/// `.agents`. Built to the markup rather than to the brief's count, per the
/// Global Constraint that the prototype is the authority on appearance —
/// `cardOptions.agents` stays at its Task 1 default (`true`) with no writer
/// anywhere on this page, which is honest rather than an oversight: there is
/// no prototype text this page could attach a ninth switch to.
///
/// **`Show Your Last Message`'s detail line says, in the row itself, that
/// nothing populates the field it gates.** `Session.lastUserMessage` renders
/// (`SessionRow.lastMessageLine`) and no adapter anywhere sets it to anything
/// but `nil` — see `Session.init`. A switch that cannot be seen doing
/// anything on real data is exactly what this plan's own scope section warns
/// against shipping silently, so the row says so rather than only this
/// comment doing.
struct SessionCardSection: View {
    let model: DisplayPaneModel

    var body: some View {
        SettingsSectionHeading("Session card")
        SettingsGroup {
            SettingsRow("Show Project Name") {
                SettingsSwitch(isOn: model.showProjectBinding)
            }
            SettingsRow("Show Worktree") {
                SettingsSwitch(isOn: model.showWorktreeBinding)
            }
            SettingsRow("Show AI Model") {
                SettingsSwitch(isOn: model.showModelBinding)
            }
            SettingsRow("Show Reasoning Effort") {
                SettingsSwitch(isOn: model.showEffortBinding)
            }
            SettingsRow("Show Your Last Message",
                detail: "A reminder of what you asked for, under the current activity. "
                    + "Nothing populates this field yet, so the row stays empty either way.",
                isNew: true) {
                SettingsSwitch(isOn: model.showLastMessageBinding)
            }
            SettingsRow("Show Tasks",
                detail: "Show the task checklist in each session card.") {
                SettingsSwitch(isOn: model.showTasksBinding)
            }
            SettingsRow("Show Subagents",
                detail: "Show child agent details. When hidden, a running count "
                    + "replaces them; approvals and questions stay visible.") {
                SettingsSwitch(isOn: model.showSubagentsBinding)
            }
            SettingsRow("Show Agent Activity Detail") {
                SettingsSwitch(isOn: model.showActivityBinding)
            }
            // `settings.html:490+`'s `.cardpreview` — the live preview, Task 6.
            // `SessionRow.Options(model.cardOptions)` is the same conversion
            // `IslandModel.cardOptions` is built from at launch (see that
            // extension's own doc comment), so this preview and the drawer read
            // the switches through the identical mapping.
            SessionCardPreview(options: SessionRow.Options(model.cardOptions))
        }
    }
}

/// `settings.html:498-508`'s `Motion` group — a three-way level and a switch.
///
/// **This is the user-facing end of a measured 30× difference that until now
/// nothing could select.** Plan 6.1 fixed three motion bypasses (`IslandBody
/// .phase`, `BadgeCanvas`, `CatCanvas`) and made `motion:` a required, undefaulted
/// parameter on both canvases so a fourth could not appear silently; Plan 6.3 gated
/// hover's three clocks. Measured with `getrusage` from a real bundle: the dormant
/// island reads **10.23% and 12.60% of a core at `full`, and 0.38% at `off`** on a
/// quiet machine — landing on the standalone hover monitor's own 0.35%.
struct MotionSection: View {
    let model: DisplayPaneModel

    var body: some View {
        SettingsSectionHeading("Motion", isNew: true)
        SettingsGroup {
            SettingsRow("Status animation",
                        detail: "The cat, the badges and the flare. Off leaves everything static but still coloured.") {
                SettingsSegmented(model.motionBinding) { $0.label }
            }
            // §14's row, and §9.3 already required it: "Settings offers Full /
            // Reduced / Off, and **by default** follows the system Reduce Motion
            // setting, which overrides the choice." The qualifier presupposes this
            // switch. See `MotionPreference.followsSystem` for why the plan's claim
            // that this contradicted §9.3 was a summary's error, not the spec's.
            SettingsRow("Follow the system Reduce Motion setting") {
                SettingsSwitch(isOn: model.followsSystemBinding)
            }
        }
    }
}

/// What the Display pane reads and writes.
///
/// Same shape as `NotificationsPaneModel`: it owns the values, and every write is a
/// `load()`-mutate-`save()` against the store rather than a held snapshot — because
/// `save()` writes the whole `Preferences` struct, so two surfaces each holding a
/// copy would clobber each other's fields. This page has more writers than any
/// other, which is why the rule is restated here.
@MainActor @Observable final class DisplayPaneModel {
    private(set) var motion: MotionLevel
    private(set) var followsSystemReduceMotion: Bool
    /// §11's nine session-card switches — `SessionCardSection`'s own doc
    /// comment records why only eight of the nine fields here have a row.
    private(set) var cardOptions: SessionCardOptions
    /// §6.2's collapsed content picker — `RightFlankSection`'s own row.
    private(set) var rightFlank: RightFlank
    /// §7.3's coat picker — `CatSection`'s own row.
    private(set) var coat: Coat

    private let store: PreferenceStoring
    /// Called after a write lands, so the island can pick the new value up without
    /// this type knowing what an island is. A closure rather than a `NotchController`
    /// for the same reason `SoundSectionModel` takes closures over the engine: Plan
    /// 6.5's Task 6 found that holding the concrete player pulled a real 858ms render
    /// onto a background queue that outlived a test.
    private let onChange: (Preferences) -> Void

    init(store: PreferenceStoring, onChange: @escaping (Preferences) -> Void = { _ in }) {
        self.store = store
        self.onChange = onChange
        let loaded = store.load()
        self.motion = loaded.motion
        self.followsSystemReduceMotion = loaded.followsSystemReduceMotion
        self.cardOptions = loaded.cardOptions
        self.rightFlank = loaded.rightFlank
        self.coat = loaded.coat
    }

    var motionBinding: Binding<MotionLevel> {
        Binding(get: { self.motion }, set: { self.setMotion($0) })
    }

    var followsSystemBinding: Binding<Bool> {
        Binding(get: { self.followsSystemReduceMotion }, set: { self.setFollowsSystem($0) })
    }

    func setMotion(_ level: MotionLevel) {
        motion = level
        persist { $0.motion = level }
    }

    func setFollowsSystem(_ follows: Bool) {
        followsSystemReduceMotion = follows
        persist { $0.followsSystemReduceMotion = follows }
    }

    var rightFlankBinding: Binding<RightFlank> {
        Binding(get: { self.rightFlank }, set: { self.setRightFlank($0) })
    }

    func setRightFlank(_ flank: RightFlank) {
        guard flank != rightFlank else { return }
        rightFlank = flank
        persist { $0.rightFlank = flank }
    }

    var coatBinding: Binding<Coat> {
        Binding(get: { self.coat }, set: { self.setCoat($0) })
    }

    func setCoat(_ coat: Coat) {
        guard coat != self.coat else { return }
        self.coat = coat
        persist { $0.coat = coat }
    }

    // MARK: - The session card's eight switches
    //
    // One binding and one setter per field, never a parameterised helper —
    // the same choice `AlertsSection`'s and `SoundSection`'s own writers
    // record, and for the same reason: **eight near-identical bodies is this
    // task's own named defect class**, and a copy-paste slip between them
    // does not even change the type it assigns to, since every field here is
    // a `Bool`. Mutation-verified by hand, one at a time — point a setter at
    // a neighbour's field, confirm the matching `DisplayPaneTests` case goes
    // red, revert. The table is in this task's report.

    var showProjectBinding: Binding<Bool> {
        Binding(get: { self.cardOptions.project }, set: { self.setShowProject($0) })
    }
    var showWorktreeBinding: Binding<Bool> {
        Binding(get: { self.cardOptions.worktree }, set: { self.setShowWorktree($0) })
    }
    var showModelBinding: Binding<Bool> {
        Binding(get: { self.cardOptions.model }, set: { self.setShowModel($0) })
    }
    var showEffortBinding: Binding<Bool> {
        Binding(get: { self.cardOptions.effort }, set: { self.setShowEffort($0) })
    }
    var showLastMessageBinding: Binding<Bool> {
        Binding(get: { self.cardOptions.lastMessage }, set: { self.setShowLastMessage($0) })
    }
    var showTasksBinding: Binding<Bool> {
        Binding(get: { self.cardOptions.tasks }, set: { self.setShowTasks($0) })
    }
    var showSubagentsBinding: Binding<Bool> {
        Binding(get: { self.cardOptions.subagents }, set: { self.setShowSubagents($0) })
    }
    var showActivityBinding: Binding<Bool> {
        Binding(get: { self.cardOptions.activity }, set: { self.setShowActivity($0) })
    }

    func setShowProject(_ value: Bool) {
        guard value != cardOptions.project else { return }
        cardOptions.project = value
        persist { $0.cardOptions.project = value }
    }
    func setShowWorktree(_ value: Bool) {
        guard value != cardOptions.worktree else { return }
        cardOptions.worktree = value
        persist { $0.cardOptions.worktree = value }
    }
    func setShowModel(_ value: Bool) {
        guard value != cardOptions.model else { return }
        cardOptions.model = value
        persist { $0.cardOptions.model = value }
    }
    func setShowEffort(_ value: Bool) {
        guard value != cardOptions.effort else { return }
        cardOptions.effort = value
        persist { $0.cardOptions.effort = value }
    }
    func setShowLastMessage(_ value: Bool) {
        guard value != cardOptions.lastMessage else { return }
        cardOptions.lastMessage = value
        persist { $0.cardOptions.lastMessage = value }
    }
    func setShowTasks(_ value: Bool) {
        guard value != cardOptions.tasks else { return }
        cardOptions.tasks = value
        persist { $0.cardOptions.tasks = value }
    }
    func setShowSubagents(_ value: Bool) {
        guard value != cardOptions.subagents else { return }
        cardOptions.subagents = value
        persist { $0.cardOptions.subagents = value }
    }
    func setShowActivity(_ value: Bool) {
        guard value != cardOptions.activity else { return }
        cardOptions.activity = value
        persist { $0.cardOptions.activity = value }
    }

    private func persist(_ mutate: (inout Preferences) -> Void) {
        var prefs = store.load()
        mutate(&prefs)
        store.save(prefs)
        onChange(prefs)
    }
}

extension MotionLevel {
    /// The prototype's own labels, `settings.html:502-503`.
    var label: String {
        switch self {
        case .full: "Full"
        case .reduced: "Reduced"
        case .off: "Off"
        }
    }
}

extension RightFlank {
    /// The prototype's own labels, `settings.html:411`.
    var label: String {
        switch self {
        case .sessionCount: "Count"
        case .agentIcon:    "Agent icon"
        case .nothing:      "Nothing"
        }
    }
}
