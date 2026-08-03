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
    let accent: RGBA
    let width: CGFloat
    /// Fires with the `Reply` a tap inside `QuestionFace` produced. Threaded
    /// straight through to it — `DrawerView` itself makes no answering
    /// decision, `QuestionModel` already does (see its own doc comment).
    /// Defaulted so every existing test/preview call site (none of which
    /// cares whether a tap answers anything) keeps compiling unchanged.
    var onAnswer: (Reply) -> Void = { _ in }

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
    private static let footerHeight: CGFloat = 44

    private var accentColor: Color { Color(accent) }

    var body: some View {
        IslandShape()
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
                            SessionListFace(sessions: sessions)
                                .transition(.faceCrossfade)
                        }
                    }
                    .animation(.easeInOut(duration: FaceCrossfade.duration), value: question == nil)
                    // The reservation itself: an explicitly empty, fixed-
                    // height spacer rather than plain absence, so its height
                    // is checkable and its presence is a decision a later
                    // reader can see rather than infer.
                    Color.clear.frame(height: Self.footerHeight)
                }
            }
            // Re-clips the overlay's content to the same silhouette as the
            // fill beneath it — `IslandBody` does the same, for the same
            // reason: without it, a row's own rounded-rect background could
            // paint square into a corner the shape has already rounded off.
            .clipShape(IslandShape())
            // `IslandShape` always draws a flat top and rounded bottom
            // corners regardless of the rect it is given (see its own doc
            // comment) — reusing it here, rather than a second shape with
            // its own copy of `IslandGeometry.bottomRadius`, is what makes
            // these corners "IslandShape-consistent" by construction instead
            // of by two literals that could drift apart.
            .frame(width: width, height: face.height)
    }
}
