import SwiftUI

/// The drawer's frame: the island's own ground colour, sized to whichever
/// face `question` is showing, with the same rounded-bottom silhouette the
/// collapsed body has. Face-agnostic on purpose — Plan 5 adds a session-list
/// face beside `QuestionFace`, and this file should not need to change for
/// it to slot in.
struct DrawerView: View {
    let question: QuestionModel
    let accent: RGBA
    let width: CGFloat

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
                    QuestionFace(question: question, accent: accentColor)
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
            .frame(width: width, height: question.face.height)
    }
}
