import SwiftUI
import VibeCatCore

/// The drawer's frame: the island's own ground colour, sized to whichever
/// face is showing, with the same rounded-bottom silhouette the collapsed
/// body has.
///
/// Plan 5's second face. `question` is now optional — nil is what routes to
/// `SessionListFace` — but the ordering rule stays the model's, not this
/// view's: `IslandModel.face`/`.sessions` already decide *what* to show
/// before this file ever runs, so `face` below only restates that same "a
/// question always wins" rule to pick which branch to draw, never a second
/// place that could disagree with it.
struct DrawerView: View {
    let question: QuestionModel?
    /// §11's list, in `SessionStore.mostUrgentFirst`'s order — only read when
    /// `question` is nil. Defaulted to `[]` so every existing call site (all
    /// of which pass a real `question` and never touch this) keeps compiling
    /// unchanged.
    var sessions: [Session] = []
    /// Forwarded straight to `SessionListFace`. Plan 6.6's Task 4 re-thread —
    /// see that view's own doc comment. Defaulted to `.all` for the same
    /// reason `sessions` is: every existing call site keeps compiling and
    /// rendering exactly as it always has.
    var options: SessionRow.Options = .all
    let accent: RGBA
    let width: CGFloat
    /// The bottom corner radius, `IslandGeometry.openBottomRadius` (20) in
    /// production — `island-motion.html:162`/`:164` give every expanded state
    /// `border-radius: 0 0 20px 20px`. Plan 6.3 Task 5.
    ///
    /// Defaulted rather than required, and the default is the *open* value rather
    /// than `IslandGeometry.bottomRadius`, because a `DrawerView` exists only while
    /// a drawer is open: there is no tier at which this view is the collapsed 15,
    /// so a caller that says nothing should get 20 and not the value it would have
    /// to override. `IslandView` passes `model.tier.bottomRadius` anyway, so
    /// production reads the one property that decides the radius rather than this
    /// default.
    var bottomRadius: CGFloat = IslandGeometry.openBottomRadius
    /// Fires with the `Reply` a tap inside `QuestionFace` produced. Threaded
    /// straight through to it — `DrawerView` itself makes no answering
    /// decision, `QuestionModel` already does (see its own doc comment).
    /// Defaulted so every existing test/preview call site (none of which
    /// cares whether a tap answers anything) keeps compiling unchanged.
    var onAnswer: (Reply) -> Void = { _ in }

    /// Forwarded straight to `PanelBar`'s own `muted` — never held as a
    /// `@State` of its own. `island-motion.html:1060`'s coupling
    /// ("the panel's mute button and the app's sound toggle are the same
    /// setting") is exactly what a local copy here would silently violate.
    /// Defaulted so every existing call site (none of which cares) keeps
    /// compiling unchanged.
    var muted: Bool = false
    /// Forwarded straight to `PanelBar`'s own `onToggleMute`. Defaulted for
    /// the same reason as `onAnswer` above.
    var onToggleMute: () -> Void = {}
    /// Forwarded straight to `PanelBar`'s own `onOpenSettings`. Still a
    /// no-op in production until Plan 6.4 Task 5 builds the settings
    /// window; defaulted for the same reason as `onAnswer` above.
    var onOpenSettings: () -> Void = {}

    /// A pending question always wins — `IslandModel.face`'s own rule,
    /// restated here because this file has to decide *which branch to draw*,
    /// not just report which one is showing.
    private var face: DrawerFace { question?.face ?? .sessionList }

    /// §6.4: the footer (mute + settings) is Plan 6's, not this plan's — a
    /// button that opens nothing is worse than no button (see this plan's
    /// own "Deliberately out of scope" table). Reserved here, unclaimed, so
    /// Plan 6 slots straight into it without forcing a relayout of
    /// everything above. Do not delete this as unused space: nothing draws
    /// here because nothing is *meant to* yet, not because it was forgotten.
    ///
    /// Plan 6.4, Task 3: claimed now, by `PanelBar`, built directly in
    /// `body` below. The value itself is unchanged; only its visibility
    /// widened from `private` so `PanelBarTests
    /// .theReservedFooterIsNoLongerEmpty` can crop a real render to exactly
    /// this many points from the bottom rather than a copy of the literal
    /// `44`.
    ///
    /// An earlier draft of this file routed `body` and a `footerProbeForTesting`
    /// helper through one shared static, on the theory that a single
    /// implementation can't let the two drift apart. That reasoning holds for
    /// "does the footer draw the right *content*", but not for the mutation
    /// this plan actually calls out — reverting `body`'s own call back to
    /// `Color.clear` — because a static the *test* calls directly is, by
    /// construction, never affected by what `body` does or doesn't call.
    /// Measured: that version of `theReservedFooterIsNoLongerEmpty` **stayed
    /// green** under exactly that mutation. Reported rather than quietly kept,
    /// per this plan's own rule about a mutation that stays green — the fix is
    /// below: render the real `DrawerView` and inspect its actual bottom
    /// strip, which cannot help but go through `body`.
    ///
    /// Plan 6.4, Task 4: `muted`/`onToggleMute`/`onOpenSettings` above are now
    /// forwarded rather than hardcoded — `IslandView` threads them down from
    /// `IslandModel`, which `NotchController` keeps in step with
    /// `Preferences.soundEnabled`. `onOpenSettings` stays a no-op in
    /// production (Task 5's job), wired through anyway so Task 5 has nothing
    /// left to touch in this file.
    static let footerHeight: CGFloat = 44

    private var accentColor: Color { Color(accent) }

    var body: some View {
        IslandShape(bottomRadius: bottomRadius)
            .fill(Color(islandGroundColour))
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    // Both faces sit above the same reservation below — the
                    // switch is scoped to the content alone, so neither
                    // branch can duplicate or consume §6.4's 44pt.
                    //
                    // §9.1's `--t-face: 190ms` crossfade, finally on the swap it
                    // was written for (F7 of the final whole-branch review).
                    // Plan 4.5 built `AnyTransition.faceCrossfade` and wired
                    // only its *duration* to `QuestionFace`'s rows ↔ reply-field
                    // sub-face swap, leaving the transition itself with no
                    // caller anywhere — while this, the drawer's first real face
                    // swap, hard-cut.
                    //
                    // §9.1's rule still governs: "faces never slide in from
                    // outside; they fade in **inside** a shape that is already
                    // the right size." So this is on the face's own content and
                    // never on the drawer's frame — `.frame(width:height:)`
                    // below still sizes from `face.height`, and `IslandView`'s
                    // own height spring keyed to `drawerHeight` remains the only
                    // thing that moves the shape. A transition that translated
                    // the frame would be exactly the slide-in §9.1 forbids.
                    //
                    // Keyed to `question == nil`, not to `face`: that is
                    // precisely "which branch of this switch", and nothing else.
                    // `face` also changes between `.question`,
                    // `.questionWithReply` and `.questionMulti`, which are
                    // *sub*-face changes inside `QuestionFace` that its own
                    // crossfade already animates — keying here on `face` would
                    // cross-fade the whole question face a second time whenever
                    // the reply field opened.
                    Group {
                        if let question {
                            QuestionFace(question: question, accent: accentColor, onAnswer: onAnswer)
                                .transition(.faceCrossfade)
                        } else {
                            SessionListFace(sessions: sessions, options: options)
                                .transition(.faceCrossfade)
                        }
                    }
                    // `IslandMotion.ease`, not `.easeInOut` — the same
                    // island-motion.html:173 `var(--ease)` `QuestionFace`'s own
                    // sub-face swap uses. §9.1's face crossfade is one figure;
                    // two curves for the two levels of it would not be.
                    .animation(IslandMotion.ease(duration: FaceCrossfade.duration),
                               value: question == nil)
                    // The reservation itself, now claimed by `PanelBar`.
                    // Task 4: `muted`/`onToggleMute`/`onOpenSettings` above are
                    // forwarded straight through rather than hardcoded — see
                    // this struct's own doc comments on those properties for
                    // why none of the three is a local copy. `onOpenSettings`
                    // still calls nothing in production (Task 5's job — a
                    // button that calls nothing yet is still correct chrome,
                    // the alternative being an empty 44pt gap). Built directly
                    // here, not through a shared static a test could call
                    // around `body` — see `footerHeight`'s own doc comment
                    // for why that indirection let a real mutation go
                    // uncaught.
                    PanelBar(muted: muted, onToggleMute: onToggleMute, onOpenSettings: onOpenSettings)
                        .frame(height: Self.footerHeight)
                }
            }
            // Re-clips the overlay's content to the same silhouette as the
            // fill beneath it — `IslandBody` does the same, for the same
            // reason: without it, a row's own rounded-rect background could
            // paint square into a corner the shape has already rounded off.
            .clipShape(IslandShape(bottomRadius: bottomRadius))
            // `IslandShape` always draws a flat top and rounded bottom
            // corners regardless of the rect it is given (see its own doc
            // comment) — reusing it here, rather than a second shape with
            // its own copy of `IslandGeometry.bottomRadius`, is what makes
            // these corners "IslandShape-consistent" by construction instead
            // of by two literals that could drift apart. Both this and the fill
            // above take `bottomRadius`, not the shape's default: the fill and its
            // own clip disagreeing would round the ground at one radius and the
            // content at another.
            .frame(width: width, height: face.height)
    }
}
