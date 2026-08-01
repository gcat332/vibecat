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

/// Distinctness is pairwise, not just "differs from tabby" — two non-default
/// coats could still collide with each other. Worth checking directly rather
/// than by hand, especially now that the fur-only guard narrows what each
/// coat is allowed to repaint.
@Test func everyCoatDiffersFromEveryOtherCoat() {
    let all = Coat.allCases
    for i in all.indices {
        for j in all.indices where j > i {
            #expect(CatGrid(coat: all[i]).cells != CatGrid(coat: all[j]).cells,
                    "\(all[i]) is identical to \(all[j])")
        }
    }
}

// On this toolchain (swift-testing 1902), `#expect` mis-evaluates a bare `!`
// wrapped directly around `.contains(_:)` when the receiver is `[Tone?]` —
// verified independent of closures (reproduces even with no closure anywhere
// in the test). Use `== false`, not `!...contains(...)`, in this file.
@Test func plainRemovesEveryShadowMarking() {
    let flat = CatGrid(coat: .plain).cells.flatMap { $0 }
    #expect(flat.contains(.shadow) == false)
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
