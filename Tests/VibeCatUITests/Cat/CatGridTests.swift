import Testing
@testable import VibeCatUI

private let eyeTones: Set<Tone> = [.eyeWhite, .sparkle, .pupil]

@Test func theBaseGridIsEighteenByFourteen() {
    #expect(CatGrid.base.count == CatGrid.height)
    for row in CatGrid.base { #expect(row.count == CatGrid.width) }
}

@Test func tabbyIsTheBaseGridUnchanged() {
    #expect(CatGrid(coat: .tabby).cells == CatGrid.base)
}

/// Design §7.3: markings, never hue. Every tone a coat paints must already be
/// in the ramp — no coat may introduce a colour the base grid does not use.
@Test func noCoatIntroducesAToneTheBaseGridDoesNotUse() {
    let baseTones = Set(CatGrid.base.flatMap { $0 }.compactMap { $0 })
    for coat in Coat.allCases {
        let tones = Set(CatGrid(coat: coat).cells.flatMap { $0 }.compactMap { $0 })
        #expect(tones.isSubset(of: baseTones), "\(coat) introduced a new tone")
    }
}

/// The eyes always win. A coat may not repaint an eye cell.
@Test func noCoatTouchesTheEyes() {
    let base = CatGrid.base
    for coat in Coat.allCases {
        let cells = CatGrid(coat: coat).cells
        for row in 0..<CatGrid.height {
            for col in 0..<CatGrid.width where eyeTones.contains(base[row][col] ?? .body) {
                #expect(cells[row][col] == base[row][col],
                        "\(coat) repainted an eye cell at \(col),\(row)")
            }
        }
    }
}

/// A coat that changes nothing is not a coat.
@Test func everyNonDefaultCoatActuallyDiffersFromTabby() {
    let tabby = CatGrid(coat: .tabby).cells
    for coat in Coat.allCases where coat != .tabby {
        #expect(CatGrid(coat: coat).cells != tabby, "\(coat) is identical to tabby")
    }
}

// Brief's Step 1 wrote this as `#expect(!cells.flatMap { $0 }.contains(.shadow))`.
// On this toolchain (Swift 6.3.2, swift-testing 1902) that exact shape — a `!`
// applied directly to a `.contains(_:)` call whose argument is implicit-member
// syntax over `[Tone?]` — makes the macro's expectation evaluator report a
// failure even though the underlying boolean is `true` (confirmed by printing
// it directly: `contains` genuinely returns `false`). Rewriting the negation as
// `== false` sidesteps the same macro path and evaluates correctly; a
// standalone reproduction with a small unrelated optional-enum array did not
// reproduce this, so it is not a general `!arr.contains(.case)` bug, just this
// exact expression shape against `Tone?`. See task-2-report.md for the isolation.
@Test func plainRemovesEveryShadowMarking() {
    let cells = CatGrid(coat: .plain).cells
    #expect(cells.flatMap { $0 }.contains(.shadow) == false)
}

@Test func everyCoatKeepsTheSilhouette() {
    let base = CatGrid.base
    for coat in Coat.allCases {
        let cells = CatGrid(coat: coat).cells
        for row in 0..<CatGrid.height {
            for col in 0..<CatGrid.width {
                #expect((cells[row][col] == nil) == (base[row][col] == nil),
                        "\(coat) changed the silhouette at \(col),\(row)")
            }
        }
    }
}

@Test func theSubscriptIsColumnThenRowAndToleratesOutOfBounds() {
    let g = CatGrid(coat: .tabby)
    #expect(g[0, 0] == nil)          // top-left corner is transparent
    #expect(g[2, 0] == .outline)     // first ear cell
    #expect(g[-1, 0] == nil)
    #expect(g[99, 99] == nil)
}
