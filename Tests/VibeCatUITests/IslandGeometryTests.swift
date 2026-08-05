import Testing
import CoreGraphics
@testable import VibeCatUI

private let mbp14 = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
    safeAreaTop: 32,
    auxLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
    auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))

private let externalDisplay = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
    visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415),
    safeAreaTop: 0, auxLeft: nil, auxRight: nil)

/// Design §5.3. This is the whole reason LW is a constant.
@Test func theLeftEdgeDoesNotMoveWhenTheRightFlankGrows() {
    let g = IslandGeometry(screen: mbp14)
    let widths: [CGFloat] = [0, 35, 51, 120, 400]
    let edges = widths.map { g.frames(rightFlank: $0, tier: .rest).body.minX }
    #expect(Set(edges).count == 1)
    // The `as CGFloat` anchors the literal arithmetic's type explicitly: on
    // this toolchain (swift-testing under Swift 6.3.2), `#expect` mis-resolves
    // a bare Int-literal expression compared against a CGFloat property,
    // reporting a spurious failure even though both sides are exactly 605.0.
    // Confirmed with %.20f precision printing; Double does not exhibit this.
    #expect(edges[0] == (663 - 58 as CGFloat))
}

@Test func restBodySpansLeftFlankPlusNotchPlusRightFlank() {
    let g = IslandGeometry(screen: mbp14)
    let dormant = g.frames(rightFlank: 0, tier: .rest).body
    #expect(dormant.width == (58 + 185 as CGFloat))
    #expect(dormant.height == 32)
    #expect(dormant.maxY == 982)

    let running = g.frames(rightFlank: 35, tier: .rest).body
    #expect(running.width == (58 + 185 + 35 as CGFloat))
}

/// The island's right edge always clears the cutout by at least one corner
/// radius, in every collapsed state — including the emptiest one.
///
/// This is the geometric content of "both corners should be ours". Our
/// bottom-right corner curve occupies the last `bottomRadius` of the body, so
/// while the body ends exactly on `notch.maxX` that curve is drawn into the
/// same points as the hardware's own notch corner, and the two — 15pt against
/// a measured ~14 — leave a seam. Clearing by a full radius puts our curve
/// entirely to the right of theirs, so at every row our black is at or beyond
/// their edge and their corner is covered rather than competed with.
///
/// Stated against `notch.maxX` rather than against the flank constant, so it
/// keeps holding if the minimum is ever expressed some other way.
@Test func theBodyAlwaysClearsTheCutoutByACornerRadius() {
    let g = IslandGeometry(screen: mbp14)
    let states: [CollapsedLayout] = [
        CollapsedLayout(right: .nothing, hovering: false),
        CollapsedLayout(right: .nothing, hovering: true),
        CollapsedLayout(right: .sessionCount(0), hovering: false),
        CollapsedLayout(right: .sessionCount(1), hovering: false),
        CollapsedLayout(right: .sessionCount(999), hovering: true),
        CollapsedLayout(right: .agentIcon, hovering: false),
    ]
    for layout in states {
        let body = g.frames(rightFlank: layout.rightFlankWidth, tier: .rest).body
        #expect(body.maxX >= g.notch.maxX + IslandGeometry.bottomRadius,
                "\(layout.right) hovering=\(layout.hovering): the body ends \(body.maxX - g.notch.maxX)pt past the cutout, inside our own \(IslandGeometry.bottomRadius)pt corner — the hardware's corner shows through")
    }
}

/// The left edge is pinned (design §5.3) and the corner minimum must not have
/// quietly moved it. It cannot — `frames` derives the left edge from
/// `notch.minX` and the right flank cancels out — but that is the invariant
/// the whole fix leans on, so it is worth stating where the fix is.
@Test func theCornerMinimumDoesNotMoveTheLeftEdge() {
    let g = IslandGeometry(screen: mbp14)
    let empty = g.frames(rightFlank: CollapsedLayout(right: .nothing, hovering: false).rightFlankWidth,
                         tier: .rest).body
    #expect(empty.minX == g.notch.minX - IslandGeometry.leftFlank)
}

/// The aura blooms outside the shape, and never above the notch.
@Test func thePanelIsInflatedForTheAuraOnThreeSidesOnly() {
    let g = IslandGeometry(screen: mbp14)
    let f = g.frames(rightFlank: 35, tier: .rest)
    #expect(f.panel.maxY == f.body.maxY)                       // no top margin
    #expect(f.panel.minX == f.body.minX - IslandGeometry.auraMargin)
    #expect(f.panel.maxX == f.body.maxX + IslandGeometry.auraMargin)
    #expect(f.panel.minY == f.body.minY - IslandGeometry.auraMargin)
}

/// Panel-local coordinates are flipped (SwiftUI y grows downward) and there
/// is no top margin, so the shape starts flush with the panel's top edge.
@Test func bodyInPanelIsTheBodyExpressedInPanelLocalCoordinates() {
    let g = IslandGeometry(screen: mbp14)
    let f = g.frames(rightFlank: 35, tier: .rest)
    #expect(f.bodyInPanel.origin == CGPoint(x: IslandGeometry.auraMargin, y: 0))
    #expect(f.bodyInPanel.size == f.body.size)
}

@Test func theDrawerGrowsDownwardAndKeepsItsTopAtTheScreenEdge() {
    let g = IslandGeometry(screen: mbp14)
    let f = g.frames(rightFlank: 35, tier: .drawer(face: .question))
    #expect(f.body.height == (32 + 288 as CGFloat))
    #expect(f.body.maxY == 982)
    #expect(f.body.minX == (663 - 58 as CGFloat))   // still pinned
}

/// A notchless display gets a floating pill in the same place, with no
/// dead zone to route content around. Design §5.1.
@Test func aNotchlessDisplayGetsAFallbackPill() {
    let g = IslandGeometry(screen: externalDisplay)
    #expect(g.isFallbackPill)
    #expect(g.notch.width == 0)
    let f = g.frames(rightFlank: 40, tier: .rest)
    #expect(f.body.width == (58 + 40 as CGFloat))
    #expect(f.body.midX == externalDisplay.frame.midX)
    #expect(f.body.maxY == externalDisplay.frame.maxY)
}

/// The panel must never hang off the side of the display.
@Test func thePanelIsClampedToTheScreen() {
    let g = IslandGeometry(screen: mbp14)
    let f = g.frames(rightFlank: 5000, tier: .rest)
    #expect(f.panel.minX >= mbp14.frame.minX)
    #expect(f.panel.maxX <= mbp14.frame.maxX)
}

/// The spike: content animation beats window-frame animation (p95 10.34ms vs
/// 15.16ms). So the panel is created once at its widest and never resized.
@Test func theMaximumCollapsedPanelHoldsEveryCollapsedState() {
    let g = IslandGeometry(screen: mbp14)
    let maxFrames = g.maxCollapsedFrames()

    let states: [CollapsedLayout] = [
        CollapsedLayout(right: .nothing, hovering: false),
        CollapsedLayout(right: .nothing, hovering: true),
        CollapsedLayout(right: .agentIcon, hovering: true),
        CollapsedLayout(right: .sessionCount(1), hovering: true),
        CollapsedLayout(right: .sessionCount(999), hovering: true),
    ]
    for layout in states {
        let f = g.frames(rightFlank: layout.rightFlankWidth, tier: .rest)
        #expect(f.panel.width <= maxFrames.panel.width + 0.001,
                "\(layout.right) hovering=\(layout.hovering) exceeds the fixed panel")
        #expect(f.body.maxX <= maxFrames.body.maxX + 0.001,
                "\(layout.right) hovering=\(layout.hovering) exceeds the fixed panel")
    }
}

/// Fix round 1: `RightContent.sessionCount` takes an unbounded `Int` —
/// nothing enforced the "three digits" assumption `maxCollapsedFrames()` was
/// built on, so a four-digit-or-larger count (unpruned running/waiting
/// sessions have no upper bound) would overflow the fixed panel. This probes
/// the type's actual range rather than the assumption of a small count.
///
/// Fix round 2: pairs the width assertion with a rendered-text one, in the
/// same loop over the same counts — a width-only pass is exactly what let
/// the other half of this bug (`IslandView` drawing the unclamped count and
/// clipping it against the silhouette, even though the panel itself now
/// fit) read as a complete fix.
@Test func theMaximumCollapsedPanelHoldsAbsurdSessionCounts() {
    let g = IslandGeometry(screen: mbp14)
    let maxFrames = g.maxCollapsedFrames()

    for n in [1_000, 999_999, Int.max] {
        let layout = CollapsedLayout(right: .sessionCount(n), hovering: true)
        let f = g.frames(rightFlank: layout.rightFlankWidth, tier: .rest)
        #expect(f.panel.width <= maxFrames.panel.width + 0.001,
                "sessionCount(\(n)) hovering=true exceeds the fixed panel")
        #expect(f.body.maxX <= maxFrames.body.maxX + 0.001,
                "sessionCount(\(n)) hovering=true exceeds the fixed panel")
        #expect(layout.sessionCountText?.count == 3,
                "sessionCount(\(n)) hovering=true should render as three characters")
    }
}

/// Whatever the panel's width, the left edge is where it always was.
@Test func theFixedPanelDoesNotMoveTheLeftEdge() {
    let g = IslandGeometry(screen: mbp14)
    let dormant = g.frames(rightFlank: 0, tier: .rest)
    #expect(g.maxCollapsedFrames().panel.minX == dormant.panel.minX)
    #expect(g.maxCollapsedFrames().body.minX == dormant.body.minX)
}

@Test func theFixedPanelIsWideEnoughForTheHoverReveal() {
    let g = IslandGeometry(screen: mbp14)
    let rest = g.frames(rightFlank: CollapsedLayout(right: .sessionCount(999),
                                                    hovering: false).rightFlankWidth,
                        tier: .rest)
    #expect(g.maxCollapsedFrames().body.width - rest.body.width >= CollapsedLayout.hoverReveal)
}

/// §6.3's table: "Session list — 420pt, rows scroll."
@Test func theSessionListFaceIsTheHeightTheDesignGivesIt() {
    #expect(DrawerFace.sessionList.height == 420)
}

// MARK: - Plan 6.3 Task 1: the drawer's own width

/// The prototype's own number, for every face: `island-motion.html:162–164` sets
/// `width:560px` on `ask`, `askmulti` and `list`, and `:166`
/// (`ask[data-other="true"]`) changes only the height.
///
/// Over `allCases`, not three literals: a face added later gets asked the
/// question rather than quietly defaulting.
///
/// Would fail if: `DrawerFace.width` returned anything but 560 for any face.
@Test func everyDrawerFaceIsThePrototypesFlat560() {
    for face in DrawerFace.allCases {
        #expect(face.width == 560,
                "\(face) is \(face.width)pt wide against the prototype's flat 560 (island-motion.html:162–164)")
    }
}

/// **The defect this task exists to fix.** `frames` let `tier` reach only the
/// height, so the open island was `leftFlank + notch + rightFlank` — narrower
/// than the drawer's content needs, and moving only when the session tally
/// gained a digit.
///
/// Compared against the collapsed frame rather than restated as 560, so the claim
/// is "opening widens it" rather than "the constant is the constant" — the second
/// of which `everyDrawerFaceIsThePrototypesFlat560` already covers, and which
/// would go on passing with `tier` disconnected from the width entirely.
///
/// Would fail if: `frames`'s `switch tier` lost its `.drawer` arm and fell back
/// to the flank sum (the Step 2 mutation — verified, this reddens).
@Test func openingTheDrawerWidensTheBody() {
    let g = IslandGeometry(screen: mbp14)
    let collapsed = g.frames(rightFlank: 35, tier: .rest).body
    let open = g.frames(rightFlank: 35, tier: .drawer(face: .sessionList)).body
    #expect(open.width > collapsed.width,
            "open \(open.width)pt against collapsed \(collapsed.width)pt — the drawer still has no width of its own")
    #expect(open.width == DrawerFace.sessionList.width,
            "open width \(open.width)pt is not the face's own \(DrawerFace.sessionList.width)")
}

/// It is a **face** width, not a content width: the right flank does not reach it
/// at all, so no session count and no hover reveal can move it.
///
/// `rightFlank: 5000` is the point — not a plausible value, but the one that
/// separates "ignores the flank" from "happens to be bigger than today's flank".
/// A `max(face.width, collapsedWidth)` spelling would return 5058 here and fail;
/// that spelling is what the floor in `openWidth(face:)` deliberately is not.
///
/// Would fail if: `openWidth` floored against the collapsed width instead of
/// `minimumWidth`, or the `.drawer` arm added `right` back in.
@Test func theOpenWidthIgnoresTheRightFlankEntirely() {
    let g = IslandGeometry(screen: mbp14)
    let widths: [CGFloat] = [0, 35, 180.1, 5000]
    let open = widths.map { g.frames(rightFlank: $0, tier: .drawer(face: .question)).body.width }
    #expect(Set(open).count == 1,
            "the open width moved with the right flank: \(open)")
    #expect(open[0] == DrawerFace.question.width)
}

/// **Plan 6.3 Task 2: the rule and its width consequence, tied together.**
///
/// `IslandTier.takesHoverReveal` is the sentence "an open island's width does not
/// depend on hover". This asserts that `frames` obeys it *and* that the tiers it
/// says do take the reveal actually do — one test over `takesHoverReveal`'s two
/// values, rather than a restatement of `openFace == nil`, which would be a
/// tautology.
///
/// The reveal is fed in the way production feeds it: `CollapsedLayout
/// .rightFlankWidth` adds exactly `hoverReveal` for hovering against not, at every
/// content, so the pair of flank widths handed to `frames` here is the real pair.
///
/// Would fail if: `frames`'s width expression folded `right` into the open arm
/// (the drawer's width becomes hover-dependent again while `takesHoverReveal`
/// still says it is not — the exact disagreement Task 2 exists to remove), or if
/// the collapsed arms stopped reading `right` at all (hover stops widening the
/// closed island, while `takesHoverReveal` still says it should), or if
/// `takesHoverReveal` were hardcoded either way.
@Test func onlyTheTiersThatTakeTheHoverRevealAreWidenedByIt() {
    let g = IslandGeometry(screen: mbp14)
    let content = CollapsedLayout(right: .sessionCount(3), hovering: false).rightFlankWidth
    let hovered = CollapsedLayout(right: .sessionCount(3), hovering: true).rightFlankWidth
    #expect(hovered - content == CollapsedLayout.hoverReveal,
            "setup: the two flank widths differ by \(hovered - content)pt, not the reveal's \(CollapsedLayout.hoverReveal)")

    var tiers: [IslandTier] = [.rest, .hover]
    tiers.append(contentsOf: DrawerFace.allCases.map { .drawer(face: $0) })
    for tier in tiers {
        let flat = g.frames(rightFlank: content, tier: tier).body.width
        let wide = g.frames(rightFlank: hovered, tier: tier).body.width
        if tier.takesHoverReveal {
            #expect(wide - flat == CollapsedLayout.hoverReveal,
                    "\(tier) takes the reveal but the width moved \(wide - flat)pt, not \(CollapsedLayout.hoverReveal)")
        } else {
            #expect(wide == flat,
                    "\(tier) does not take the reveal, yet its width moved from \(flat) to \(wide)")
        }
    }
}

/// §5.1's floor, at the only geometry that can make it bind: a cutout wide enough
/// that the design's 560 would end the body *inside* the hole, putting the
/// hardware's own corner back on screen.
///
/// 600pt is not a Mac — that is why it is here. `openWidth`'s floor is the reason
/// a flat 560 is safe rather than lucky, and a rule whose failing case is never
/// constructed is a rule nobody has checked. The assertion is the same one
/// `theBodyAlwaysClearsTheCutoutByACornerRadius` makes of every collapsed state,
/// so the open tier is held to §5.1 by the same standard.
///
/// **The floor is `minimumOpenWidth`, not `minimumWidth`, since Plan 6.3 Task 5.**
/// That task gave the open island the prototype's 20pt bottom radius
/// (`island-motion.html:162`/`:164`) while the collapsed one keeps its measured
/// 15 — and `minimumRightFlank` is 15 because it *is* `bottomRadius`. So on this
/// fixture the 673pt floor left the last 5pt of a 20pt curve inside the cutout,
/// which is precisely the failure §5.1 forbids, reintroduced by a radius change
/// three files away. 678 is the same rule read against the radius actually drawn.
///
/// Would fail if: `openWidth(face:)` returned `face.width` unfloored, or floored it
/// against the *collapsed* corner again.
@Test func anAbsurdlyWideCutoutTakesTheFloorRatherThanTheDesignWidth() {
    let huge = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 3000, height: 1000),
        visibleFrame: CGRect(x: 0, y: 0, width: 3000, height: 968),
        safeAreaTop: 32,
        auxLeft: CGRect(x: 0, y: 968, width: 1200, height: 32),
        auxRight: CGRect(x: 1800, y: 968, width: 1200, height: 32))
    let g = IslandGeometry(screen: huge)
    #expect(g.notch.width == 600, "setup: the fixture's cutout is not 600pt wide")

    let open = g.frames(rightFlank: 0, tier: .drawer(face: .sessionList)).body
    #expect(open.width == g.minimumOpenWidth,
            "open width \(open.width)pt took the design's \(DrawerFace.sessionList.width) over the \(g.minimumOpenWidth)pt floor")
    #expect(open.maxX >= g.notch.maxX + IslandGeometry.openBottomRadius,
            "the open body ends \(open.maxX - g.notch.maxX)pt past a \(g.notch.width)pt cutout, inside our own \(IslandGeometry.openBottomRadius)pt open corner — the hardware's corner shows through")
    // The collapsed floor is *not* enough here, and saying so is what stops
    // `openWidth` being "simplified" back onto `minimumWidth`: the difference
    // between the two floors is exactly the difference between the two radii.
    #expect(g.minimumOpenWidth - g.minimumWidth
                == IslandGeometry.openBottomRadius - IslandGeometry.bottomRadius,
            "the open floor clears the cutout by \(g.minimumOpenWidth - g.minimumWidth)pt more than the collapsed one, but the open corner is \(IslandGeometry.openBottomRadius - IslandGeometry.bottomRadius)pt rounder")
}

/// §5.1's fallback, stated rather than left to be discovered.
///
/// The open width is the same 560 on a notchless display — the number describes
/// the drawer's content, not the hardware (see `DrawerFace.width`) — and the pill
/// stays centred, so it opens symmetrically about the screen centre. **§5.3's
/// left-edge pin does not apply here and this test says so on purpose:** that
/// invariant exists so the cat keeps its place relative to the cutout, and there
/// is no cutout. Asserting `minX` held would be asserting the wrong rule.
///
/// Would fail if: `frames` centred only the collapsed pill, or `openWidth` were
/// derived as `leftFlank + notch + 316` — which gives 374pt here, below the 420pt
/// at which a session row's ink saturates, reintroducing this task's own defect
/// on exactly the display that never had a geometric reason for it.
@Test func theFallbackPillStaysCentredWhenTheDrawerOpens() {
    let g = IslandGeometry(screen: externalDisplay)
    #expect(g.isFallbackPill)
    let open = g.frames(rightFlank: 40, tier: .drawer(face: .sessionList)).body
    #expect(open.width == 560,
            "the notchless pill opens to \(open.width)pt — a notch-derived width would give 374 here")
    #expect(open.midX == externalDisplay.frame.midX,
            "the open pill is centred at \(open.midX) against a screen centre of \(externalDisplay.frame.midX)")
}

/// The panel has to cover the drawer it is showing, and until this task it did
/// not: fixed at the widest *collapsed* body (423.1pt on this fixture), it would
/// have clipped 137pt off the right of a 560pt drawer.
///
/// Stated as "the panel holds the body" rather than as a number, so it survives
/// either number being retuned.
///
/// Would fail if: `maxCollapsedFrames` stopped passing `tier` through to `frames`
/// (which is all that grows it), or `IslandModel.panelFrames` went back to
/// `.rest`.
@Test func theFixedPanelGrowsSidewaysToHoldTheOpenDrawer() {
    let g = IslandGeometry(screen: mbp14)
    let collapsed = g.maxCollapsedFrames()
    let open = g.maxCollapsedFrames(tier: .drawer(face: .sessionList))
    #expect(open.body.width == DrawerFace.sessionList.width)
    #expect(open.panel.width >= open.body.width + IslandGeometry.auraMargin * 2,
            "the panel is \(open.panel.width)pt around a \(open.body.width)pt body — the drawer's right edge is clipped")
    #expect(open.panel.width > collapsed.panel.width,
            "the panel did not grow sideways for the open drawer at all")
    #expect(open.panel.minX == collapsed.panel.minX,
            "growing the panel moved its left edge, which unpins §5.3")
}
