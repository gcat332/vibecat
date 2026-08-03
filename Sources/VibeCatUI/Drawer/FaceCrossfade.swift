import SwiftUI

/// §9.1's face crossfade: **`190ms`, fade up 5pt with a 3pt blur.**
///
/// Declared by the prototype as `--t-face: 190ms` and specified by §9.1, and
/// never implemented until Plan 4.5 — recorded as unassigned in Plan 3's
/// follow-ups, then again in Plan 4.5's diff as the last item of §9.1 still
/// missing.
///
/// The rule it exists to obey is the one §9.1 states outright: *"Faces never
/// slide in from outside; they fade in **inside** a shape that is already the
/// right size."* So this is a transition on a face's own content, never on the
/// drawer's frame — `DrawerView` still sizes itself from `question.face.height`,
/// and the drawer's height spring (§9.1's `0.42/0.78`) remains the only thing
/// that moves the shape. A transition that translated the frame would be exactly
/// the slide-in this forbids.
///
/// Five points is a *fade up*, so the incoming face starts below its resting
/// place and rises into it; the outgoing one leaves the same way. The blur is
/// what stops 5pt of travel reading as a jump at this duration.
struct FaceCrossfade: ViewModifier {
    /// §9.1's own number, and the prototype's `--t-face`. Named so the
    /// transition and the animation driving it cannot disagree — an
    /// `.easeInOut(duration:)` at one value with a modifier written for another
    /// is a silent mismatch no render would reveal.
    static let duration: Double = 0.190
    /// §9.1: "fade up 5pt".
    static let rise: CGFloat = 5
    /// §9.1: "with a 3pt blur".
    static let blurRadius: CGFloat = 3

    /// 0 at the extremes of the transition, 1 at rest.
    let presence: Double

    func body(content: Content) -> some View {
        content
            .opacity(presence)
            .offset(y: Self.rise * (1 - presence))
            .blur(radius: Self.blurRadius * (1 - presence))
    }
}

extension AnyTransition {
    /// §9.1's face crossfade. Symmetric on purpose: a face leaving and a face
    /// arriving are the same 190ms figure in reverse, which is what a
    /// *crossfade* means — an asymmetric pair would read as two separate events.
    static var faceCrossfade: AnyTransition {
        .modifier(active: FaceCrossfade(presence: 0),
                  identity: FaceCrossfade(presence: 1))
    }
}
