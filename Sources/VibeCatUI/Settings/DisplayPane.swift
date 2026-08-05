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
            MotionSection(model: model)
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
