import Testing
@testable import VibeCatUI

@Test func eachIslandStateMapsToItsBadge() {
    #expect(Badge(state: .dormant) == .zzz)
    #expect(Badge(state: .running) == .squares)
    #expect(Badge(state: .waiting) == .bang)
    #expect(Badge(state: .idle) == .star)
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
@Test func onlyTheActiveBadgesAnimateContinuously() {
    #expect(Badge.squares.motion.isContinuous)
    #expect(Badge.bang.motion.isContinuous)
    #expect(Badge.zzz.motion.isContinuous)
    #expect(Badge.cross.motion.isContinuous == false)
    #expect(Badge.star.motion.isContinuous == false)
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
    #expect(Badge.star.motion.cycle == 2.2)
}
