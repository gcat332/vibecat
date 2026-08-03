import CoreGraphics
import Foundation
import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

/// Three plain choices, single- or multi-select depending on the caller — the
/// same fixture `DrawerGoldenTests`/`QuestionFaceTests` each keep their own
/// copy of, needed here only for `aPendingQuestionOutranksTheSessionList`'s
/// "a question exists" half.
private func threeChoices(multi: Bool) -> VibeEvent {
    VibeEvent(id: "q", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
              title: "Bash command", body: "pnpm install",
              choices: [Choice(id: "allow", label: "Allow once"),
                        Choice(id: "always", label: "Always allow"),
                        Choice(id: "deny", label: "Deny")],
              multi: multi, wantsReply: true)
}

/// A shared session fixture: `n` plain running sessions, cheap to vary in
/// count for both tests below.
@MainActor private func sessionsOf(_ n: Int) -> [Session] {
    (0..<n).map { i in
        Session(event: VibeEvent(id: "e\(i)", cli: "claude-code", kind: .running,
                                 session: "s\(i)", cwd: "/tmp/p\(i)"),
                now: Date(timeIntervalSince1970: 1_000_000))
    }
}

/// **Harness limitation, recorded so the next person does not rediscover it
/// the hard way (the same category as `QuestionFaceTests`' own `.opacity(0)`
/// note):** `ImageRenderer` paints *nothing* for a `ScrollView`'s content —
/// confirmed with a minimal repro, a bare `Text` inside a fixed frame paints
/// 760 opaque pixels; the identical `Text` wrapped in a `ScrollView` at the
/// same frame paints **0**. This is not specific to `SessionListFace` — it
/// reproduces with a one-line `ScrollView { Text(...) }`.
///
/// An earlier version of this file had one test,
/// `manySessionsScrollRatherThanGrowingTheDrawer`, that rasterised
/// `SessionListFace` inside a test-supplied `.frame(width:388, height:
/// DrawerFace.sessionList.height)` and compared the *rendered* height for 2
/// sessions against 20. It could not fail: both renders are byte-identical
/// blank canvases at the size the test's own outer frame forced, regardless
/// of whether the content overflows, whether it scrolls, or whether
/// `SessionListFace` is broken outright — confirmed by deleting its
/// `ScrollView` entirely (letting the row `VStack` grow unbounded) and
/// finding the old test still green. See the task report for the full
/// measurement.
///
/// What *does* survive `ImageRenderer`, measured directly: its **layout**
/// pass still sizes a `ScrollView`'s content correctly even though its
/// **paint** pass draws none of it. Given only a width (no height
/// constraint), `SessionListFace(sessions: sessionsOf(2), ...).frame(width:
/// 388)` measures 69pt tall; the identical rows assembled in a plain
/// `VStack` with no `ScrollView` around them at all measures 68pt (the 1pt
/// gap is `.frame(maxHeight: .infinity)`'s own rounding, not a real
/// discrepancy) — so the two tests below trust that reported *height*
/// without ever needing the blanked-out pixels.

/// §6.3's first half: "rows scroll" is only a meaningful claim if the rows
/// actually need more room than 420pt gives them — otherwise "scrolls" and
/// "never overflows anyway" render identically and this fixture would prove
/// nothing about scrolling either way. 20 sessions, unconstrained in height,
/// must measure taller than the fixed face — if they didn't, that would be
/// worth reporting on its own rather than silently making the second test
/// below vacuous.
@MainActor @Test func twentySessionsGenuinelyOverflowTheFixedFace() throws {
    let raster = try rasterise(SessionListFace(sessions: sessionsOf(20)).frame(width: 388))
    // `CGFloat(raster.height)`, never `Double(raster.height)`, on this side —
    // see the note above `theSessionListFaceHeightDoesNotGrowWithSessionCount`
    // on a second, independent toolchain trap this file's own writing ran
    // into: an explicit `Double(_:)` conversion compared against a `CGFloat`
    // via `#expect` reports a false failure on this toolchain even though
    // the plain `==` operator (and the printed operands) agree.
    #expect(CGFloat(raster.height) > DrawerFace.sessionList.height,
            "20 sessions measured only \(raster.height)pt unconstrained — at or under the fixed \(DrawerFace.sessionList.height)pt face, scrolling would have nothing to do")
}

/// §6.3's second half: "420pt" — the face's own frame does not follow its
/// content, however much of it there is. Deliberately renders `DrawerView`
/// with **no test-supplied `.frame`** at all (unlike the vacuous test this
/// replaces) — the only thing constraining the result is `DrawerView.body`'s
/// own `.frame(width:height:)`, keyed to `face.height`, so this can actually
/// fail: reverting that line to a `.fixedSize()` (or deleting it) would let
/// the render follow content the way `twentySessionsGenuinelyOverflowThe
/// FixedFace` above measures it wanting to — 699pt at 20 sessions, confirmed
/// by mutation (see the task report).
///
/// **A second, independent toolchain trap found while writing this test:**
/// `#expect(Double(raster.height) == DrawerFace.sessionList.height)` reports
/// a false failure on this toolchain (Swift 6.3.2 / swift-testing 1902) —
/// reproduced with a minimal, unrelated case (`#expect(Double(58) ==
/// IslandGeometry.leftFlank)` fails the same way), confirmed *not* a real
/// value mismatch (`asDouble == expected` printed `true`, and the two
/// operands' bit patterns were identical, immediately before the same
/// `#expect` call reported them unequal). `CGFloat(_:)` on the left instead
/// of `Double(_:)` avoids it reliably. If a future edit here reintroduces a
/// bare `Double(...)` against a `CGFloat`-typed value, that is this trap
/// again, not a real regression — verify with a plain `==` before trusting
/// the failure.
@MainActor @Test func theSessionListFaceHeightDoesNotGrowWithSessionCount() throws {
    let few = try rasterise(DrawerView(question: nil, sessions: sessionsOf(2),
                                       accent: IslandState.waiting.accent, width: 388))
    let many = try rasterise(DrawerView(question: nil, sessions: sessionsOf(20),
                                        accent: IslandState.waiting.accent, width: 388))
    #expect(CGFloat(few.height) == DrawerFace.sessionList.height,
            "2 sessions rendered \(few.height)pt, not the fixed \(DrawerFace.sessionList.height)pt face height")
    #expect(CGFloat(many.height) == DrawerFace.sessionList.height,
            "20 sessions rendered \(many.height)pt, not the fixed \(DrawerFace.sessionList.height)pt face height — the face grew with its content")
}

/// A question must never be buried under a list — §4.2's own reasoning: a
/// waiting agent is idling on you right now.
@MainActor @Test func aPendingQuestionOutranksTheSessionList() {
    let model = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    model.sessions = [Session(event: VibeEvent(id: "e", cli: "claude-code", kind: .running,
                                               session: "s", cwd: "/tmp/api"),
                              now: Date(timeIntervalSince1970: 1_000_000))]
    #expect(model.face == .sessionList, "with no question the drawer shows the list")

    model.question = QuestionModel(event: threeChoices(multi: false))
    #expect(model.face == .question,
            "a pending question was buried under the session list")
}
