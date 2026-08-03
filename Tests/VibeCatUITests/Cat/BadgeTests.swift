import Testing
@testable import VibeCatUI

@Test func eachIslandStateMapsToItsBadge() {
    #expect(Badge(state: .dormant) == .zzz)
    #expect(Badge(state: .running) == .squares)
    #expect(Badge(state: .waiting) == .bang)
    #expect(Badge(state: .idle) == .check)
    #expect(Badge(state: .failed) == .cross)
}

/// The fixed box is what stops the flank resizing and walking the cat sideways.
@Test func everyBadgeFillsTheSameFixedGrid() {
    for badge in Badge.allCases {
        for i in 0...10 {
            let cells = badge.cells(at: Double(i) / 10.0)
            #expect(cells.count == Badge.size, "\(badge) is not \(Badge.size) rows")
            for row in cells { #expect(row.count == Badge.size, "\(badge) row is not \(Badge.size)") }
        }
    }
}

@Test func everyBadgeDrawsSomething() {
    for badge in Badge.allCases {
        let lit = badge.cells(at: 0).flatMap { $0 }.filter { $0 }.count
        #expect(lit > 0, "\(badge) is blank at phase 0")
    }
}

/// A badge whose cells never change across the cycle is not animating.
@Test func continuousBadgesActuallyChangeAcrossTheCycle() {
    for badge in Badge.allCases where badge.motion.isContinuous {
        let frames = (0...9).map { badge.cells(at: Double($0) / 10.0) }
        #expect(Set(frames.map { "\($0)" }).count > 1, "\(badge) never changes")
    }
}

/// The spike's rule again: steady states get no timeline.
///
/// `.zzz` is deliberately in the still column here, not the continuous one:
/// dormant is the state a machine sits in all day, and a continuously
/// drifting badge cost 3.6–4.1% of a core for an animation (an I-beam and a
/// solid square, 3 frames, no fade) that did not read as one — see the
/// `motion` case comment on `Badge.zzz`. The sleeping cat's shut eyes
/// already carry "dormant".
@Test func onlyTheActiveBadgesAnimateContinuously() {
    #expect(Badge.squares.motion.isContinuous)
    #expect(Badge.bang.motion.isContinuous)
    #expect(Badge.zzz.motion.isContinuous == false)
    #expect(Badge.cross.motion.isContinuous == false)
    #expect(Badge.check.motion.isContinuous == false)
}

@Test func continuousBadgesRunInThePixelArtRange() {
    for badge in Badge.allCases where badge.motion.isContinuous {
        #expect(badge.motion.framesPerSecond >= 8)
        #expect(badge.motion.framesPerSecond <= 12)
    }
}

/// Four squares taking turns is the whole trick — exactly one is swollen at a
/// time, so it reads as rotation without anything rotating.
@Test func theRunningBadgeLightsOneQuadrantAtATime() {
    var seenLeaders: Set<String> = []
    for i in 0..<4 {
        let cells = Badge.squares.cells(at: Double(i) / 4.0 + 0.01)
        // Broken into named sub-expressions rather than one array literal: as
        // written inline, this toolchain (Swift 6.3.2) fails the whole
        // function with "unable to type-check this expression in reasonable
        // time" — a compile error, not a slow compile. Same four counts, same
        // order, just given to the type checker one at a time.
        let topLeft = cells[0...2].flatMap { $0[0...2] }.filter { $0 }.count
        let topRight = cells[0...2].flatMap { $0[4...6] }.filter { $0 }.count
        let bottomRight = cells[4...6].flatMap { $0[4...6] }.filter { $0 }.count
        let bottomLeft = cells[4...6].flatMap { $0[0...2] }.filter { $0 }.count
        let quadrants = [topLeft, topRight, bottomRight, bottomLeft]
        let leader = quadrants.firstIndex(of: quadrants.max()!)!
        #expect(quadrants.filter { $0 == quadrants.max()! }.count == 1,
                "phase \(i): more than one quadrant is largest")
        seenLeaders.insert("\(leader)")
    }
    #expect(seenLeaders.count == 4, "the swell does not visit all four quadrants")
}

@Test func theCycleLengthsMatchTheDesign() {
    #expect(Badge.check.motion.cycle == 2.2)
}

/// Design §4.3: colour means state, but only if shape carries it too. Idle and
/// failed once differed by hue alone — the same `+` figure, one rotated 45°,
/// green against red, the classic colour-vision failure pair.
///
/// `check`, `cross` and `bang` now share one outline **deliberately**: a filled
/// disc, because all three are verdicts rather than activities. That makes the
/// old "not rotations of each other" check meaningless — they are supposed to
/// look alike from a distance — and moves the entire burden of telling them
/// apart onto the glyph punched out of the disc. So each glyph carries a
/// structural signature that survives desaturation, and this pins all three.
///
/// Each assertion is load-bearing against a specific plausible mistake:
/// drawing the tick as a symmetric V (it would mirror onto itself, and read as
/// a V), punching `cross` off-centre, or letting `bang`'s stem drift out of its
/// column.
@Test func theThreeVerdictBadgesShareADiscAndDifferOnlyInTheirGlyph() {
    let disc = Badge.check.cells(at: 0)
    let cross = Badge.cross.cells(at: 0)
    let bang = Badge.bang.cells(at: 0)

    // One family: the outline — every cell but the four corners — is common.
    for (name, cells) in [("check", disc), ("cross", cross), ("bang", bang)] {
        // Three cells per corner, not one: removing only the corner itself
        // renders as a squircle, and that is what shipped before this was
        // pinned. Reverting to it must fail here.
        for (r, c) in [(0, 0), (0, 1), (1, 0),
                       (0, 6), (0, 5), (1, 6),
                       (6, 0), (6, 1), (5, 0),
                       (6, 6), (6, 5), (5, 6)] {
            #expect(cells[r][c] == false,
                    "\(name)'s disc fills (\(r),\(c)) — with the corner shoulders present it reads as a squircle, not a circle")
        }
        #expect(cells[0][3], "\(name) has no disc rim above its glyph")
        #expect(cells[3][0], "\(name) has no disc rim beside its glyph")
    }

    let mid = Badge.size / 2

    // check: the only one whose centre survives, and the only asymmetric one.
    #expect(disc[mid][mid], "check's centre is holed — that is cross's signature, not check's")
    #expect(disc != disc.map { $0.reversed().map { $0 } },
            "check is symmetric under a horizontal mirror — a symmetric tick is a V, and mirrors onto cross's family")

    // cross: holed centre, symmetric both ways.
    #expect(cross[mid][mid] == false, "cross's centre is not holed")
    #expect(cross == cross.map { $0.reversed().map { $0 } }, "cross is not horizontally symmetric")
    #expect(cross == cross.reversed().map { $0 }, "cross is not vertically symmetric")

    // bang: every hole in one column.
    let bangHoleColumns = Set(bang.indices.flatMap { r in
        bang[r].indices.filter { bang[r][$0] == false && !isOutsideDisc(r, $0) }
    })
    #expect(bangHoleColumns == [mid],
            "bang's holes span columns \(bangHoleColumns.sorted()) — a `!` is one column, and spreading it blurs it into cross")
}

/// Outside the disc entirely — an unlit cell here is background, not a punched
/// glyph, so `bang`'s column check must not count it.
private func isOutsideDisc(_ r: Int, _ c: Int) -> Bool {
    Badge.check.cells(at: 0)[r][c] == false && Badge.cross.cells(at: 0)[r][c] == false
}

/// Whether `cells` contains a fully-lit 2×2 block anywhere — the structural
/// difference between a figure with a filled body and one built entirely
/// from 1-cell-wide lines.
private func hasAFilledBlock(_ cells: [[Bool]]) -> Bool {
    for r in 0..<(cells.count - 1) {
        for c in 0..<(cells[r].count - 1) {
            if cells[r][c], cells[r][c + 1], cells[r + 1][c], cells[r + 1][c + 1] {
                return true
            }
        }
    }
    return false
}

/// A2's actual instruction, checked directly, not just approximated:
/// "a four- or five-pointed form with a body, not a `+`." A `+` and an `X`
/// are both built entirely from 1-cell-wide lines — no two lit cells ever
/// form a filled 2×2 square — so this is what "has a body" means
/// structurally, and it is what `starAndCrossAreNotJustRotationsOfEachOther`
/// above does *not* actually pin: reverting `star` to its old `+` shape
/// leaves star and cross with different counts and profiles regardless (9
/// vs 13 lit cells) — a 45°-rotated raster does not preserve pixel count on
/// a 7×7 grid — so that exact regression slips past both checks above.
/// Verified by temporarily reverting `star` to the old `+` during this
/// task's own work and confirming the count/profile test still passed; this
/// test is what actually would have caught it.
/// A z is its diagonal, and the diagonal is exactly what the old artwork had
/// no room for. The big z was three rows — `###`/`.#.`/`###` — whose middle
/// stroke can only sit in the centre column, which is also where a capital I
/// puts its stem: a 3×3 z and a 3×3 I are the same nine cells. The small z was
/// a solid 2×2 block with no glyph at all. Rendered, the badge read as an
/// I-beam beside a square (ContactSheet.swift is how that was finally seen).
///
/// Two structural properties separate a z from both of those:
///
///  - a single-cell stroke that *moves sideways as it descends*. An I's stem
///    never does; a z's diagonal is nothing but that.
///  - no filled block anywhere. That is precisely what the small z was.
///
/// Each is load-bearing against the exact art that shipped: the old grid has
/// only one row with a single lit cell, so no step exists, and its small z is
/// a filled 2×2.
@Test func theSleepBadgeIsZsRatherThanAnIBeamAndABlock() {
    let cells = Badge.zzz.cells(at: 0)
    let singleStrokeRows = cells.enumerated().compactMap { row, line -> (row: Int, col: Int)? in
        let lit = line.indices.filter { line[$0] }
        return lit.count == 1 ? (row, lit[0]) : nil
    }
    let descendingSteps = zip(singleStrokeRows, singleStrokeRows.dropFirst()).filter {
        $1.row == $0.row + 1 && $1.col != $0.col
    }
    #expect(descendingSteps.isEmpty == false,
            "zzz has no stroke that moves sideways as it descends — with a straight stem it is an I, not a z")
    #expect(hasAFilledBlock(cells) == false,
            "zzz contains a filled block — that is what the small z was before it had a glyph")
}

/// Every verdict badge has a body now, which is the point — a bounded disc
/// reads as a conclusion where a thin mark reads as activity. This replaces an
/// older test that asserted the opposite for `cross`, whose premise the disc
/// family retires. `zzz` keeps the no-filled-block rule (see above), so the
/// two families stay distinguishable by weight as well as by outline.
@Test func everyVerdictBadgeHasAFilledBodyAndTheAmbientOnesDoNot() {
    for badge in [Badge.check, .cross, .bang] {
        #expect(hasAFilledBlock(badge.cells(at: 0)),
                "\(badge) has no filled 2×2 anywhere — it is not reading as a disc")
    }
    #expect(hasAFilledBlock(Badge.zzz.cells(at: 0)) == false,
            "zzz has a filled body — it should read as a loose mark, not a verdict")
}
