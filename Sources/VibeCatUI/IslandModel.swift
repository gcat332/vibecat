import Foundation
import Observation
import VibeCatCore

/// Everything the island view reads, in one observable place.
///
/// This exists because the previous render path assigned a freshly built
/// SwiftUI tree to `NSHostingView.rootView` on every change. That survives a
/// handful of renders per second and nothing more; at sprite rates it is the
/// dominant cost. The hosting view's root is now assigned once and reads this.
@MainActor @Observable public final class IslandModel {
    public var state: IslandState = .dormant
    public var sessionCount: Int = 0
    public var hovering: Bool = false
    /// §6.2's choosable right flank: "session count (default), agent icon, or
    /// nothing." Mirrors `Preferences.rightFlank`'s default so a model built
    /// with no preference wired in yet (every existing call site) renders
    /// exactly as it always has.
    ///
    /// Since Plan 6.1's Task 6 the **launch** value comes off disk:
    /// `NotchController.init` assigns `preferences.load().rightFlank` here, so a
    /// hand-edited plist (or Plan 6.6's Display picker, when it exists) changes
    /// what the island draws on the next launch. There is still no UI —
    /// `LaunchWiringTests` is what keeps that read from quietly disappearing.
    public var rightFlank: RightFlank = .sessionCount
    public var geometry: IslandGeometry
    public var aura = AuraTrigger()
    public var coat: Coat
    public var motion: MotionPreference

    /// What is actually behind the island, when it can be measured. Nil means
    /// "not measured", not "dark" — the view falls back to the system
    /// appearance rather than to a default that looks like a reading.
    ///
    /// Only the aura uses it. See `BackdropSampler`: on a real machine, with
    /// the menu bar auto-hidden over a dark wallpaper, the system reported
    /// Light while the captured strip came back at luminance 48.
    public var backdrop: Backdrop?

    /// The question the drawer is showing, if any. `nil` is the only "closed"
    /// state this model has — `IslandView` reads this one property to decide
    /// both whether to draw a drawer at all and how tall it is, rather than a
    /// separate open/closed flag that could disagree with it.
    public var question: QuestionModel?

    /// The session the hover reveal names. §4.2's most urgent one, assigned by
    /// `NotchController.render()` alongside `state` — the island reports the most
    /// urgent session, so the reveal names that same one rather than a second
    /// notion of "current".
    public var revealed: Session?

    /// The sessions §11's list shows, in §11's order. Assigned by
    /// `NotchController.render()` from `store.mostUrgentFirst` — one ordering,
    /// shared with `revealed`'s own "most urgent" (`SessionStore
    /// .mostUrgentSession`), so the list and the hover reveal never disagree
    /// about which session matters.
    public var sessions: [Session] = []

    /// Whether a click has actually opened the drawer. Deliberately separate
    /// from `question`: a question arriving must not open the drawer by
    /// itself (design §6.1's "Click" tier is a distinct gesture from a
    /// question merely existing) — it changes the cat and waits. This is
    /// what that "waits" is — `false` until `NotchController.click()` sets it,
    /// and reset to `false` whenever `question` clears (answered, dismissed,
    /// or lapsed) so a *later* question does not inherit a stale "open" from
    /// one that already closed.
    public var drawerOpen: Bool = false

    /// Fires when the island itself — the collapsed silhouette, not the
    /// drawer — is clicked. Wired by `NotchController.present()` to call
    /// `click()`. `@ObservationIgnored`: this is wiring, the same reasoning
    /// as `AppModel.onChange`'s own doc comment — nothing should re-render
    /// because this closure was reassigned.
    @ObservationIgnored
    public var onIslandClick: (@MainActor () -> Void)?

    /// Fires when the drawer produces an answer: a single-select pick (once
    /// confirmed, if §10.3 asked twice) or a multi-select Send. Wired by
    /// `NotchController.present()` to call `appModel.answer(_:)`. Read by
    /// `IslandView`, threaded down to `DrawerView`/`QuestionFace` as a plain
    /// closure parameter rather than passing `IslandModel` itself into the
    /// drawer's own view tree — `DrawerView` stays face-agnostic and
    /// `QuestionModel`-only, the same reasoning its own doc comment gives.
    @ObservationIgnored
    public var onAnswer: (@MainActor (Reply) -> Void)?

    /// Whether the drawer's own footer should show the muted glyph. **The
    /// same setting as `Preferences.soundEnabled`** — `island-motion.html:1060`
    /// states the coupling explicitly: "the panel's mute button and the
    /// app's sound toggle are the same setting." `NotchController` is the
    /// only writer (see its own `toggleMute()`), kept in step with whichever
    /// `PreferenceStoring` main.swift handed it at construction — never a
    /// second, private copy `PanelBar` or `DrawerView` could disagree with.
    /// Plain (not `@ObservationIgnored`): unlike the closures below, this is
    /// content the drawer actually draws, so a change must invalidate the view.
    public var muted: Bool = false

    /// Fires when the drawer's own mute button (`PanelBar`'s `#pmute`) is
    /// tapped. Wired by `NotchController.present()` to `toggleMute()`, which
    /// persists the flip and reports the fresh `Preferences.soundEnabled`
    /// value onward so main.swift can keep the running `SoundPlayer` in
    /// step. `@ObservationIgnored` for the same reason as `onAnswer`: this is
    /// wiring, not content, and reassigning it should not itself invalidate
    /// anything.
    @ObservationIgnored
    public var onToggleMute: (@MainActor () -> Void)?

    /// Fires when the drawer's own gear button (`PanelBar`'s `#pgear`) is
    /// tapped. Left unwired by this plan's Task 4 — Task 5 builds the
    /// window this is meant to open.
    @ObservationIgnored
    public var onOpenSettings: (@MainActor () -> Void)?

    public init(geometry: IslandGeometry, coat: Coat = .tabby, motion: MotionPreference) {
        self.geometry = geometry
        self.coat = coat
        self.motion = motion
    }

    public var layout: CollapsedLayout {
        CollapsedLayout(right: rightContent, hovering: hovering)
    }

    /// Maps `rightFlank` (Task 1's stored preference, which cannot carry a
    /// live count) onto `CollapsedLayout.RightContent` (which needs one for
    /// `.sessionCount`) — the mapping `RightFlank`'s own doc comment says
    /// Task 5 owns.
    ///
    /// `.sessionCount` passes `sessionCount` through unconditionally, even at
    /// zero, rather than special-casing zero to `.nothing` the way the
    /// hardcoded ternary this replaces did. That special case was an accident
    /// of the hardcoding, not a decision worth preserving: `CollapsedLayout`
    /// already treats `.sessionCount(0)` as indistinguishable from `.nothing`
    /// on every axis that matters — `sessionCountText` is `nil` (guards `n >
    /// 0`), `rightFlankWidth` falls to the same corner-minimum floor, and
    /// `hasRightContent` is `false` — pinned by
    /// `CollapsedLayoutTests.aZeroCountCollapsesToNothing`. Re-deriving that
    /// here would just be a second, independent copy of a rule the type
    /// already owns correctly, and one that could drift from it.
    private var rightContent: CollapsedLayout.RightContent {
        switch rightFlank {
        case .sessionCount: .sessionCount(sessionCount)
        case .agentIcon: .agentIcon
        case .nothing: .nothing
        }
    }

    /// Which face the drawer shows. A pending question always wins: §4.2's own
    /// reasoning is that a waiting agent is idling on you *right now*, so a
    /// question must never be buried under a list.
    public var face: DrawerFace { question?.face ?? .sessionList }

    /// Design §6.1's three tiers, derived rather than stored redundantly:
    /// `.drawer` whenever a click actually opened one, sized to whichever face
    /// is currently showing; otherwise whatever the hover state already was.
    /// `.rest` and `.hover` compute identically for `frames`/`panelFrames`
    /// below (`IslandTier.extraHeight` is 0 for both) — the case only matters
    /// to callers that switch on it.
    ///
    /// Plan 5: this used to read `guard drawerOpen, let question else { ... }`,
    /// which made `.drawer` unreachable without a question — an open session
    /// list (no question at all) would silently stay at `.rest`, and the panel
    /// would never grow to show it. `face` already resolves to `.sessionList`
    /// with no question (see above), so reading it here instead of `question`
    /// covers both faces with the same guard, and changes nothing for a
    /// question still open: `face` is `question.face` in that case, exactly
    /// what this returned before.
    public var tier: IslandTier {
        guard drawerOpen else { return hovering ? .hover : .rest }
        return .drawer(face: face)
    }

    /// The collapsed content's own frame — the cat, the badge, the count.
    /// Tier-aware for height so a rendered `IslandBody` can actually show an
    /// open drawer's extra space (see `IslandGoldenTests
    /// .nothingIsDrawnInsideTheCutoutWithTheDrawerOpen`), but this changes
    /// nothing for any caller while the drawer is closed: `.rest` and
    /// `.hover` both contribute zero extra height, exactly as the hardcoded
    /// `.rest` this replaces always did.
    public var frames: IslandFrames {
        geometry.frames(rightFlank: layout.rightFlankWidth, tier: tier)
    }

    /// The real panel's own bounds, at whatever tier is current.
    ///
    /// **Tier-aware in both dimensions since Plan 6.3 Task 1.** It was height-only
    /// while the drawer had no width of its own; now that it has one
    /// (`IslandGeometry.openWidth(face:)`, 560pt) a panel fixed at the collapsed
    /// ceiling would clip the drawer's right-hand 137pt. `rightFlank` is still the
    /// theoretical widest, which still fixes the panel across every *collapsed*
    /// state — that is what the spike's p95 finding was about, and it is
    /// unchanged. `NotchController.reflow()` is what actually resizes the live
    /// window to match this, once per tier change.
    public var panelFrames: IslandFrames { geometry.maxCollapsedFrames(tier: tier) }

    /// The drawer's own width — deliberately independent of `hovering`,
    /// unlike `frames.body.width`. Final whole-branch review, finding 5:
    /// `frames.body.width` carries the collapsed pill's own 150pt hover
    /// reveal (§9.1's `CollapsedLayout.hoverReveal`), which exists so the
    /// *pill* can show a session's name and elapsed time once hovered.
    /// Nothing in the drawer's own content (`QuestionFace`'s title, body, or
    /// rows) reads either of those, so widening the drawer for the same
    /// reason serves it no purpose — and doing so anyway meant every row
    /// reflowed instantly the moment the cursor drifted off `hover.frame`
    /// (measured before this fix: 423.1pt while hovering, 273.1pt while not,
    /// on the identical open question), while the collapsed silhouette above
    /// it eased the identical width change over 280ms
    /// (`IslandBody.hoverRevealWidth`'s own `IslandMotion.ease(duration: 0.28)`).
    ///
    /// Decision: the drawer's width does not depend on hover at all, rather
    /// than animating the snap with the island's own reveal timing — there is
    /// no content in the drawer that timing would ever need to reveal, so
    /// matching the *other* animation's duration would just be dressing up a
    /// change that should not happen in the first place.
    ///
    /// **Plan 6.3 Task 1: it no longer depends on the collapsed layout either.**
    /// That reading kept hover out, which was half the rule, and left the other
    /// half wrong: the width came from `CollapsedLayout(hovering: false)`, so the
    /// drawer was as wide as the *collapsed* island — 273.1pt on the `mbp14`
    /// fixture — and moved only when the session tally gained a digit. §11's rows
    /// saturate at 420pt, so line 2 truncated to `As…` at every session count. It
    /// now reads the face's own width through `IslandGeometry.openWidth(face:)`,
    /// the one place that number and its floor are written down, and the property
    /// stays what it was for: the place a non-view caller (a settings surface, a
    /// test) can ask "how wide is the drawer" without constructing a view first.
    ///
    /// Keyed to `face`, not to `tier`, so it answers for the face that *would*
    /// open as well as the one that has — `IslandView` reads it only inside its
    /// own `if case .drawer` gate, but the probes and tests that ask before a
    /// click get the same number rather than a collapsed one.
    public var drawerWidth: CGFloat { geometry.openWidth(face: face) }

    public var mood: CatMood { CatMood(state: state) }
    public var badge: Badge { Badge(state: state) }

    /// Whichever of the cat and the badge wants redrawing more often.
    public var activeProfile: MotionProfile {
        let cat = motion.resolve(mood.motion)
        let badge = motion.resolve(self.badge.motion)
        if cat.isContinuous && badge.isContinuous {
            return cat.framesPerSecond >= badge.framesPerSecond ? cat : badge
        }
        return cat.isContinuous ? cat : badge
    }

    /// True only when something genuinely needs per-frame redraws. Measured: a
    /// live timeline costs ~6% of a core even at 8 fps, and removing it costs
    /// 0.0% — so this is the only thing that makes an idle machine idle.
    public var needsTimeline: Bool {
        if motion.effective == .off { return false }
        if activeProfile.isContinuous { return true }
        return aura.isBlooming(at: Date())
    }
}
