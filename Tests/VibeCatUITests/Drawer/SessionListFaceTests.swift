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

// MARK: - Plan 6.3 Task 6: the fold

/// The brightest ink in raster row `y`, as a distance from the island's own
/// ground colour. 0 means "nothing but ground here"; a glyph reads in the tens.
///
/// A distance from ground rather than a colour count, because that is the
/// quantity a fade changes: masking a row of `--bone` text over `--void`
/// interpolates it *toward the ground*, so full-strength text and faded text are
/// the same colour family at different distances. A `pixelCount(near:)` on either
/// endpoint would answer neither question.
private func inkDistance(_ r: Raster, row y: Int, from x0: Int, to x1: Int) -> Int {
    let g = Raster.Pixel(islandGroundColour)
    var worst = 0
    for x in max(0, x0)..<min(r.width, x1) {
        let p = r[x, y]
        guard p.a > 0 else { continue }
        worst = max(worst, max(abs(Int(p.r) - Int(g.r)),
                               max(abs(Int(p.g) - Int(g.g)), abs(Int(p.b) - Int(g.b)))))
    }
    return worst
}

/// **The fold dissolves instead of shearing, and the cue costs nothing when there
/// is nothing to cue.** `SessionListFace.foldFade`'s own doc comment carries the
/// reasoning — including why row-granular snapping cannot remove this shear;
/// this is the measurement.
///
/// Rendered through `rasteriseHosted`, the only route that draws a `ScrollView` at
/// all (`Raster.swift` has the repro: `ImageRenderer` paints its content fully
/// transparent). That is also why this is the first test in this file to look at
/// the list's *pixels* rather than at its reported height.
///
/// Two claims, and the second is what makes the first mean anything:
///
/// 1. **At 12 sessions** — 625pt of content in 376pt — the last 2pt before the
///    fold carries no ink at anything like full strength, while 40pt higher the
///    same list does. Deleting the `.mask` leaves row 8's first text line cut at
///    full opacity, which is the reported defect, and fails this.
/// 2. **At 1 session** — 53pt of content, no overflow — that session's own last
///    line is *not* attenuated and the band above the fold holds no ink at all.
///    This is the half that fails if the mask moves inside the `ScrollView` (it
///    would travel with the content and fade the one row there is) or above the
///    `.frame` (it would be handed the content's height, not the viewport's).
@MainActor @Test func theFoldDissolvesInsteadOfShearingAndOnlyWhereThereIsInk() throws {
    let width = DrawerFace.sessionList.width
    let height = DrawerFace.sessionList.height
    let fade = SessionListFace.foldFade

    @MainActor func render(_ n: Int) throws -> Raster {
        try rasteriseHosted(DrawerView(question: nil, sessions: sessionsOf(n),
                                       accent: IslandState.waiting.accent, width: width),
                            size: CGSize(width: width, height: height))
    }

    let many = try render(12)
    // `rasteriseHosted` renders at the host window's own backingScaleFactor, which
    // varies by machine — so every offset below is scaled rather than assumed.
    let scale = CGFloat(many.height) / height
    // The fold is the bottom of the scrolling region: the face less §6.4's footer
    // reservation, read back through `DrawerView.footerHeight` rather than a copy.
    let fold = Int((height - DrawerView.footerHeight) * scale)
    let columns = (Int(16 * scale), Int((width - 16) * scale))

    let atFold = (1...max(1, Int(2 * scale))).map {
        inkDistance(many, row: fold - $0, from: columns.0, to: columns.1)
    }.max() ?? 0
    let midList = (0..<max(1, Int(4 * scale))).map {
        inkDistance(many, row: fold - Int(40 * scale) - $0, from: columns.0, to: columns.1)
    }.max() ?? 0
    #expect(midList > 40,
            "40pt above the fold the list's own ink measures only \(midList) levels from ground — nothing rendered there, so the comparison below is vacuous")
    #expect(atFold < midList / 4,
            "the 2pt before the fold measures \(atFold) levels from ground against \(midList) mid-list — the fold is cutting glyphs at very nearly full strength, which is the shear this fade exists to remove")

    // One session: 53pt of content in 376pt of viewport (measured by
    // `MotionFidelityProbe.listContentHeights`).
    let one = try render(1)
    // **The content's own bottom, found rather than assumed.** Which row the last
    // glyph of a one-session row lands on is a font-metrics question this test has
    // no business encoding, and getting it wrong is how a fade assertion goes
    // vacuous. So: the lowest row holding any ink at all, then the 3pt ending
    // there. A 24pt ramp cannot exceed 12.5% of full strength over its last 3pt
    // (≈29 levels of the ~229 between `--bone` and `--void`), so a threshold of 60
    // separates "unattenuated glyph" from "tail of a ramp" with room either side.
    var lastInked = -1
    for y in stride(from: min(one.height, fold) - 1, through: 0, by: -1)
    where inkDistance(one, row: y, from: columns.0, to: columns.1) >= 8 {
        lastInked = y
        break
    }
    #expect(lastInked >= 0, "the one-session render has no ink at all above the fold")
    let oneInk = (0..<max(1, Int(3 * scale))).map {
        inkDistance(one, row: max(0, lastInked - $0), from: columns.0, to: columns.1)
    }.max() ?? 0
    #expect(oneInk > 60,
            "the single session's own last 3pt of ink measures \(oneInk) levels from ground — the fade has reached content nowhere near the fold, which is what happens if the mask travels with the scrolled content instead of sitting at the viewport's own bottom")
    let bandInk = (1...max(1, Int(fade * scale))).map {
        inkDistance(one, row: fold - $0, from: columns.0, to: columns.1)
    }.max() ?? 0
    #expect(bandInk == 0,
            "with one session the \(fade)pt above the fold measures \(bandInk) levels from ground — something is drawn in the band, so 'the cue is invisible when nothing overflows' is not what this render shows")
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

/// **The whole list at its real size, with parked questions in it** — what no assertion
/// in this file can judge: whether a row carrying a question still *reads* beside rows
/// that do not.
///
/// `rasteriseHosted`, because `ImageRenderer` paints nothing for a `ScrollView` (see this
/// file's own note above), and at `DrawerFace.sessionList`'s real 560×420 so the fold
/// lands where it really lands.
///
///     VIBECAT_LIST_SHEET=/tmp/list.png Scripts/test.sh --filter listSheet
@Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAT_LIST_SHEET"] != nil))
@MainActor func listSheet() throws {
    let out = try #require(ProcessInfo.processInfo.environment["VIBECAT_LIST_SHEET"])
    let width = DrawerFace.sessionList.width
    let height = DrawerFace.sessionList.height

    var sessions = sessionsOf(4)
    // Two of the four are waiting on an answer, which is the case the layout had to be
    // rebalanced for — one used to fill the page on its own at 406pt.
    var questions: [SessionKey: [IslandModel.RowQuestion]] = [:]
    for i in [0, 2] {
        let e = VibeEvent(id: "q\(i)", cli: "claude-code", kind: .permission,
                          session: sessions[i].id.session, cwd: "/tmp/p\(i)",
                          title: "Allow this command?",
                          body: "rm -rf /Users/dev/projects/vibecat/.build/debug/ModuleCache/tmp",
                          choices: [Choice(id: "allow", label: "Allow once"),
                                    Choice(id: "always", label: "Allow every Bash call this session"),
                                    Choice(id: "deny", label: "Deny")],
                          wantsReply: true)
        questions[sessions[i].id] = [
            IslandModel.RowQuestion(model: QuestionModel(event: e),
                                    // The second one handed back, so both block states
                                    // appear side by side in one sheet.
                                    isHandedBack: i == 2, onDismiss: {})
        ]
    }
    let view = DrawerView(question: nil, sessions: sessions, rowQuestions: questions,
                          accent: IslandState.waiting.accent, width: width)
    _ = try rasteriseHosted(view, size: CGSize(width: width, height: height))
        .writePNG(to: out)
    print("\nlist -> \(out)  (rows 1 and 3 waiting; row 3's hook has already handed back)")
}
