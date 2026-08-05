import CoreGraphics
import Foundation
import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

/// What the island actually paints.
///
/// Everything else in this suite reasons about `IslandBody` through its
/// properties: what `restingWidth` returns, whether `body` read it. Three
/// `#if DEBUG` counters exist because an `@escaping` closure never runs during
/// `.body` access, and `IslandViewTests` says of one of them that going
/// further "would need a snapshot or view-inspection dependency, which this
/// project does not take."
///
/// `ImageRenderer` is that snapshot capability, in the standard library, with
/// no dependency to take. It renders offscreen with no window server, so it
/// works on a locked machine — which two plans wrongly recorded as blocking
/// visual verification. A counter proves a property was *touched*; these tests
/// prove it reached the pixels.
@Suite("Island golden images")
struct IslandGoldenTests {
    static let mbp14 = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
        safeAreaTop: 32,
        auxLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
        auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))

    @MainActor
    static func model(_ state: IslandState, count: Int, hovering: Bool = false,
                      coat: Coat = .tabby) -> IslandModel {
        let m = IslandModel(geometry: IslandGeometry(screen: mbp14),
                            motion: MotionPreference(chosen: .full, systemWantsReduced: false))
        m.state = state
        m.sessionCount = count
        m.hovering = hovering
        m.coat = coat
        return m
    }

    /// Columns holding at least one non-transparent pixel. The island is the
    /// only thing drawn, so this is the painted silhouette's extent — measured
    /// off the render rather than recomputed from the same constants the view
    /// used, which would just be the implementation agreeing with itself.
    static func paintedColumns(_ r: Raster) -> (first: Int, last: Int, count: Int)? {
        var first = -1, last = -1
        for x in 0..<r.width {
            let painted = (0..<r.height).contains { r[x, $0].isTransparent == false }
            if painted {
                if first < 0 { first = x }
                last = x
            }
        }
        guard first >= 0 else { return nil }
        return (first, last, last - first + 1)
    }

    /// §5.4's session count, measured off the render: accent-coloured pixels
    /// in the columns strictly to the right of the cutout.
    ///
    /// Column-limited, not whole-raster, and that is the whole point. The cat
    /// and its badge are accent-coloured too and sit *left* of the cutout, so
    /// `raster.pixelCount(near: accent)` over the whole render still read 192
    /// on the render where the count had vanished entirely — a number that
    /// looks like evidence and is not. Right of the cutout the only
    /// accent-coloured thing a `.sessionCount` layout can draw is the count:
    /// `RevealContent` paints `--bone` and `--haze` and nothing else (see that
    /// file), and `.agentIcon` is a different `layout.right` case.
    ///
    /// Row-limited to the collapsed bar as well: an open drawer's own rows can
    /// never hold the count, so scanning them would only widen what could
    /// accidentally be counted, and it keeps the `MainActor` hold to 221 × 33
    /// pixels rather than 221 × 344 in a suite whose one known flake
    /// (`aLapsedQuestionClosesTheDrawer`) is a `Task` starved of main-actor
    /// turns. Not a claimed cure for that flake — measured over 8 full-suite
    /// runs each, it fails 2/8 on the commit before this one and 3/8 with these
    /// tests added, which at that sample size says nothing either way.
    @MainActor
    static func sessionCountPixels(_ raster: Raster, _ m: IslandModel,
                                   tolerance: Int = 6) -> Int {
        let accent = m.state.accent
        let target = (Int((accent.r * 255).rounded()),
                      Int((accent.g * 255).rounded()),
                      Int((accent.b * 255).rounded()))
        let notch = IslandGeometry(screen: mbp14).notch
        let from = Int(notch.maxX - m.frames.panel.minX)
        let bottom = min(raster.height, Int(notch.height.rounded(.up)))
        var count = 0
        for x in from..<raster.width {
            for y in 0..<bottom {
                let p = raster[x, y]
                guard !p.isTransparent else { continue }
                if abs(Int(p.r) - target.0) <= tolerance,
                   abs(Int(p.g) - target.1) <= tolerance,
                   abs(Int(p.b) - target.2) <= tolerance { count += 1 }
            }
        }
        return count
    }

    @MainActor
    static func silhouette(_ m: IslandModel, scale: CGFloat = 1) throws -> (first: Int, last: Int, count: Int) {
        let raster = try rasterise(IslandBody(model: m, now: Date(timeIntervalSince1970: 1_000_000)),
                                   scale: scale)
        return try #require(paintedColumns(raster), "the island painted nothing at all")
    }

    /// The width split reaches the pixels.
    ///
    /// `bodyActuallyRoutesThroughBothHalvesOfTheWidthSplit` proves the two
    /// properties are read while `body` is built. It cannot prove the sum
    /// reached a `.frame`, and says so. This can: hovering has to widen the
    /// painted silhouette by exactly `hoverReveal` and by nothing else.
    @MainActor @Test func hoveringWidensThePaintedIslandByExactlyTheReveal() throws {
        for count in [0, 3] {
            let rest = try Self.silhouette(Self.model(.running, count: count))
            let hovered = try Self.silhouette(Self.model(.running, count: count, hovering: true))
            #expect(hovered.count - rest.count == Int(CollapsedLayout.hoverReveal),
                    "count=\(count): hover changed the painted width by \(hovered.count - rest.count)pt, not \(Int(CollapsedLayout.hoverReveal)) — the reveal is not reaching the frame")
        }
    }

    /// `IslandView` — the real top-level view, both branches of it — paints a
    /// visible island in every state.
    ///
    /// This is the shape of the worst bug this project has shipped: a guard
    /// that could never fire left `IslandView` unhosted and the island blank,
    /// and nothing noticed until a review added a build counter. A counter
    /// answers "was it built"; this answers "is anything there", which is the
    /// question that was actually wrong.
    ///
    /// It covers the `TimelineView` branch too. That closure is `@escaping`
    /// and does not run for `.body` access — but it does run for a render,
    /// which is the whole reason this file exists.
    @MainActor @Test func everyStateRendersAVisibleIsland() throws {
        for state in IslandState.allCases {
            let m = Self.model(state, count: state == .dormant ? 0 : 4)
            let raster = try rasterise(IslandView(model: m))
            let painted = try #require(Self.paintedColumns(raster),
                                       "\(state): IslandView painted nothing — the island is blank")
            #expect(painted.count >= Int(IslandGeometry.leftFlank),
                    "\(state): only \(painted.count)pt of island was painted")

            // Blank-but-for-the-ground is the other half of the failure, and
            // counting distinct colours does not catch it: with the cat's
            // `Canvas` emptied, this render still produced eighty-odd colours
            // from the badge and the antialiased session count, and a
            // colour-count assertion passed while the cat was missing.
            //
            // The fixed facial tones are the discriminator. `innerEar` and
            // `nose` are the only two colours in the palette that no accent
            // derives — they are the same pink in every state, precisely so a
            // nose reads as a nose at any hue — and nothing else on the island
            // draws in them. Finding them is proof the sprite drew.
            let palette = CatPalette(accent: state.accent)
            for tone in [Tone.innerEar, .nose] {
                #expect(raster.pixelCount(near: palette[tone]) > 0,
                        "\(state): no \(tone) pixel anywhere — the cat sprite did not draw")
            }
        }
    }

    /// Design §5.3: the left edge is fixed, so the cat never walks sideways.
    /// Asserted on the render, so it covers the layout as well as the geometry
    /// — `IslandGeometryTests` pins `body.minX`, which is a different claim
    /// from "the leftmost painted pixel does not move".
    @MainActor @Test func thePaintedLeftEdgeNeverMoves() throws {
        let edges = try [
            Self.silhouette(Self.model(.dormant, count: 0)).first,
            Self.silhouette(Self.model(.running, count: 3)).first,
            Self.silhouette(Self.model(.running, count: 999)).first,
            Self.silhouette(Self.model(.running, count: 3, hovering: true)).first,
            Self.silhouette(Self.model(.waiting, count: 1)).first,
        ]
        #expect(Set(edges).count == 1,
                "the island's painted left edge moved between states: \(edges)")
    }

    /// The leftmost column holding a pixel that only the cat's face can have
    /// painted, in the collapsed bar's own rows.
    ///
    /// **`Tone.innerEar` and `.nose`, not the silhouette's first painted column,
    /// and the two are different claims.** `paintedColumns` finds the *ground's*
    /// left edge, which `IslandGeometry.frames` pins by construction; it would
    /// hold unchanged while the bar's content re-centred inside a wider frame (an
    /// `HStack` gaining a `Spacer`, `.leading` becoming `.center`) and the cat
    /// walked sideways underneath it. These two tones are the only colours in the
    /// palette that no accent derives — they are the same pink in every state,
    /// precisely so a nose reads as a nose at any hue — and nothing else on the
    /// island draws in them, which is the fact `everyStateRendersAVisibleIsland`
    /// already leans on. So a column holding one is a column the cat is in.
    ///
    /// Row-limited to the bar (`0..<notch.height`): the drawer below is ground and
    /// content, none of it a cat, and scanning it would only widen what could
    /// accidentally be matched.
    @MainActor
    static func catLeftEdge(_ m: IslandModel) throws -> Int {
        let raster = try rasterise(IslandBody(model: m, now: Date(timeIntervalSince1970: 1_000_000)),
                                   scale: 1)
        let palette = CatPalette(accent: m.state.accent)
        let facial: [RGBA] = [palette[Tone.innerEar], palette[Tone.nose]]
        let tones: [(Int, Int, Int)] = facial.map { c in
            let r = Int((c.r * 255).rounded())
            let g = Int((c.g * 255).rounded())
            let b = Int((c.b * 255).rounded())
            return (r, g, b)
        }
        let bottom = min(raster.height, Int(m.geometry.notch.height.rounded(.up)))
        for x in 0..<raster.width {
            for y in 0..<bottom {
                let p = raster[x, y]
                guard !p.isTransparent else { continue }
                for t in tones where abs(Int(p.r) - t.0) <= 6 && abs(Int(p.g) - t.1) <= 6
                                     && abs(Int(p.b) - t.2) <= 6 {
                    return x
                }
            }
        }
        throw CatNotFound()
    }

    struct CatNotFound: Error, CustomStringConvertible {
        var description: String { "no innerEar or nose pixel in the collapsed bar — the cat did not draw, so its left edge cannot be measured" }
    }

    /// **§5.3, at the tier Plan 6.3 Task 1 could have broken it at.** The island
    /// went from 273.1pt collapsed to 560pt open on this fixture, and every one of
    /// those 287 points has to appear on the *right*. A wider drawer that moves the
    /// cat is a defect, not a side effect — CLAUDE.md names this failure mode by
    /// name, and Plan 6.1's Task 5 rasterised it across three right-flank values
    /// before there was an open width to check it against.
    ///
    /// Four renders, one input varying at a time: hover off/on × drawer
    /// closed/open. Hover is in the grid because `model.hovering` stays *true* for
    /// the whole life of an open drawer (`IslandBody.revealWidth`'s own comment),
    /// so hovered-and-open is the ordinary production state, not an edge.
    ///
    /// Anchored on the cat rather than the ground — see `catLeftEdge` for why that
    /// distinction is the whole test.
    ///
    /// Would fail if: `IslandGeometry.frames` absorbed the open width into the left
    /// flank instead of the right (the Step 3 mutation — verified, this reddens and
    /// nothing else in the suite does), or `IslandBody`'s `VStack` alignment or
    /// `content(cell:)`'s packing changed so the bar's content centred in the wider
    /// frame.
    @MainActor @Test func openingTheDrawerDoesNotMoveTheCatsPaintedLeftEdge() throws {
        var edges: [(hovering: Bool, open: Bool, x: Int)] = []
        for hovering in [false, true] {
            for open in [false, true] {
                // .idle, not .waiting: a continuous mood takes IslandView's
                // TimelineView branch and reads the wall clock, which has made
                // multi-render comparisons in this suite flake. `IslandBody`
                // takes `now` as a parameter, so this render is pinned anyway —
                // held to the same choice the drawer suite makes for the same
                // reason.
                let m = Self.model(.idle, count: 3, hovering: hovering)
                m.drawerOpen = open
                if open {
                    guard case .drawer = m.tier else {
                        Issue.record("hovering=\(hovering): the fixture never reached the drawer tier")
                        continue
                    }
                }
                edges.append((hovering, open, try Self.catLeftEdge(m)))
            }
        }
        #expect(Set(edges.map(\.x)).count == 1,
                "the cat's painted left edge moved across hover/drawer states: \(edges)")

        // …and the island really did get wider in the same renders, so the
        // invariant above is not holding because nothing changed. Without this a
        // `DrawerFace.width` of 273.1 would satisfy every assertion here.
        let closed = try Self.silhouette(Self.model(.idle, count: 3))
        let openModel = Self.model(.idle, count: 3)
        openModel.drawerOpen = true
        let open = try Self.silhouette(openModel)
        #expect(open.count > closed.count,
                "setup: the painted island is \(open.count)pt open against \(closed.count)pt closed — it did not widen, so the left-edge check above proves nothing")
        #expect(open.first == closed.first,
                "the painted ground's own left edge moved from \(closed.first) to \(open.first)")
    }

    /// **Plan 6.3 Task 2: the gesture runs the right way round, measured off the
    /// pixels rather than off the geometry that produced them.**
    ///
    /// The reported symptom was directional, not a wrong number: hover+closed
    /// painted **423** columns and hover+open painted **273**, so clicking to
    /// open *contracted* the island by 150pt where the mockup expands it by 287.
    /// Clicking always happens while hovering — `NotchPanel.acceptsClicks` is
    /// gated on `model.hovering` (see `NotchController.reflow`) — so the hovered
    /// row is the real gesture and the unhovered row is the hypothetical one.
    /// Both are here because "opening widens" has to be true from either start
    /// for the rule to be about opening rather than about hover.
    ///
    /// Three claims, and each fails against a different mistake:
    ///
    /// 1. **Opening widens, from both starts.** Reverting `IslandGeometry
    ///    .frames`'s `.drawer` arm to the flank sum — the exact pre-Task-1
    ///    shape — makes the hovered pair 423 → 273 and this reddens.
    /// 2. **The open width is the same hovered and not.** Making the open width
    ///    hover-dependent again (`openWidth` maxed against the *collapsed* width,
    ///    or `IslandBody.revealWidth` dropping its `takesHoverReveal` gate and
    ///    always returning `hoverRevealWidth`) separates the two open renders and
    ///    this reddens. That second mutation is invisible to every geometry test
    ///    in the suite, because it is in the view's own frame maths.
    /// 3. **The open width is the face's own 560, not merely "bigger".** Without
    ///    this a drawer 1pt wider than the hovered bar would satisfy claims 1 and
    ///    2 while still being 137pt short of the mockup.
    ///
    /// Whole-render columns, not the bar's rows alone: this asks what the island
    /// occupies on screen, which is what the owner was looking at.
    @MainActor @Test func openingTheDrawerWidensThePaintedIslandFromEitherStart() throws {
        @MainActor func painted(hovering: Bool, open: Bool) throws -> Int {
            // .idle: a continuous mood takes `IslandView`'s TimelineView branch
            // and reads the wall clock, which has flaked multi-render comparisons
            // in this suite before. Held to the same choice as
            // `openingTheDrawerDoesNotMoveTheCatsPaintedLeftEdge`.
            let m = Self.model(.idle, count: 3, hovering: hovering)
            m.drawerOpen = open
            if open {
                #expect(m.tier.openFace != nil,
                        "setup: hovering=\(hovering) never reached the drawer tier, so nothing below is about an open island")
            }
            let raster = try rasterise(IslandView(model: m), scale: 1)
            return try #require(Self.paintedColumns(raster),
                                "hovering=\(hovering) open=\(open): the island painted nothing").count
        }

        let restClosed = try painted(hovering: false, open: false)
        let restOpen = try painted(hovering: false, open: true)
        let hoverClosed = try painted(hovering: true, open: false)
        let hoverOpen = try painted(hovering: true, open: true)

        #expect(restOpen > restClosed,
                "unhovered: opening took the painted island from \(restClosed)pt to \(restOpen)pt — it did not widen")
        #expect(hoverOpen > hoverClosed,
                "hovered — the gesture that actually happens: opening took the painted island from \(hoverClosed)pt to \(hoverOpen)pt. This is the reported defect: 423 → 273.")
        #expect(restOpen == hoverOpen,
                "the open island painted \(hoverOpen)pt hovered against \(restOpen)pt not — the open width still depends on hover")
        #expect(restOpen == Int(DrawerFace.sessionList.width),
                "the open island painted \(restOpen)pt, not the face's own \(Int(DrawerFace.sessionList.width))pt")
    }

    /// The other half of Task 2's rule at the pixel level: with a drawer open,
    /// hovering must change **nothing at all** about the painted silhouette — not
    /// its width, not its left edge.
    ///
    /// `openingTheDrawerWidensThePaintedIslandFromEitherStart` above compares
    /// column *counts*, which a shape that moved and resized by offsetting
    /// amounts could still satisfy. This compares the extent itself.
    ///
    /// Would fail if `IslandBody.revealWidth` stopped consulting the tier (the
    /// reveal reappears at 150pt on the right), or if `IslandGeometry.frames`
    /// began folding `rightFlank` into the open width.
    @MainActor @Test func hoveringChangesNothingAboutTheOpenIslandsPaintedExtent() throws {
        @MainActor func extent(hovering: Bool) throws -> (first: Int, last: Int, count: Int) {
            let m = Self.model(.idle, count: 3, hovering: hovering)
            m.drawerOpen = true
            return try Self.silhouette(m)
        }
        let notHovered = try extent(hovering: false)
        let hovered = try extent(hovering: true)
        #expect(hovered == notHovered,
                "the open island's painted extent moved with the cursor: \(notHovered) not hovered against \(hovered) hovered")

        // Not vacuous: the same comparison with the drawer *closed* must differ,
        // or this pair could be identical because hover reaches nothing at all.
        let closedRest = try Self.silhouette(Self.model(.idle, count: 3))
        let closedHovered = try Self.silhouette(Self.model(.idle, count: 3, hovering: true))
        #expect(closedHovered.count - closedRest.count == Int(CollapsedLayout.hoverReveal),
                "setup: hover moved the *closed* island by \(closedHovered.count - closedRest.count)pt, not \(Int(CollapsedLayout.hoverReveal)) — the reveal is not working at all, so the open comparison above proves nothing")
    }

    /// §6.2: "configurable: session count (default), agent icon, or nothing."
    /// Design §5.3's `LW = 58pt` invariant, re-checked against the one axis
    /// that changes here — the right flank's own *content*, not merely its
    /// width, which `thePaintedLeftEdgeNeverMoves` above already varies via
    /// session count. `IslandModel.rightFlank` (Task 5's addition) selects
    /// between three visibly different right-side contents; this pins that
    /// doing so never drags the cat sideways with it, exactly the failure
    /// mode CLAUDE.md's own §5.3 section calls out by name.
    @MainActor @Test func thePaintedLeftEdgeNeverMovesAcrossRightFlankChoices() throws {
        let edges = try RightFlank.allCases.map { flank -> Int in
            let m = Self.model(.running, count: 5)
            m.rightFlank = flank
            return try Self.silhouette(m).first
        }
        #expect(Set(edges).count == 1,
                "the island's painted left edge moved across right-flank choices: \(Array(zip(RightFlank.allCases, edges)))")
    }

    /// The render-level companion to `IslandModelTests
    /// .theRightFlankPreferenceSelectsWhatLayoutRightDraws`, which only proves
    /// `layout.right` changed — not that the change reached any pixel. Three
    /// renders differing in exactly one input (`rightFlank`), session count
    /// and hovering held fixed throughout.
    ///
    /// What would have to break for this to fail: `IslandModel.layout`
    /// ignoring `rightFlank` and always deriving `.sessionCount` from
    /// `sessionCount` alone — exactly the hardcoded ternary this task
    /// replaced. The three painted widths would then collapse to one.
    @MainActor @Test func eachRightFlankChoicePaintsAVisiblyDifferentIsland() throws {
        func paintedWidth(_ flank: RightFlank) throws -> Int {
            let m = Self.model(.running, count: 5)
            m.rightFlank = flank
            return try Self.silhouette(m).count
        }
        let widths = try RightFlank.allCases.map { ($0, try paintedWidth($0)) }
        #expect(Set(widths.map(\.1)).count == 3,
                "expected three distinct painted widths, one per RightFlank case, found \(widths) — some pair rendered identically")
    }

    /// The reason the minimum right flank exists, checked where it has to be
    /// true: on a dormant island the painted silhouette must extend a full
    /// corner radius past the cutout, so our corner covers the hardware's
    /// instead of being drawn into the same points as it.
    @MainActor @Test func theDormantIslandPaintsPastTheCutout() throws {
        let m = Self.model(.dormant, count: 0)
        let painted = try Self.silhouette(m)
        // The render is panel-sized; convert the panel-local last column back
        // to screen coordinates before comparing with the cutout.
        let lastX = m.frames.panel.minX + CGFloat(painted.last) + 1
        let notch = IslandGeometry(screen: Self.mbp14).notch
        #expect(lastX >= notch.maxX + IslandGeometry.bottomRadius,
                "the dormant island stops \(lastX - notch.maxX)pt past the cutout, inside its own \(IslandGeometry.bottomRadius)pt corner — the hardware's corner is left showing")
    }

    /// Plan 4.5, colour. The prototype paints `.island` with
    /// `background: var(--void)`, and `--void` is `#07080A`. We painted it
    /// `#05070B` — which is the prototype's **sprite mix base**, the value
    /// `--sp-out`/`--sp-sh` composite the accent over, and the only place
    /// `#05070B` appears in that file at all (two occurrences, both
    /// `color-mix`). §7.1's sprite table names it for the sprite; nothing names
    /// it for the island. So the largest area of colour on screen was painted
    /// with a constant borrowed from the sprite's shading maths.
    ///
    /// **Why four plans of green tests never caught this.** Two levels a
    /// channel is under `Raster.pixelCount(near:)`'s default tolerance of 6, so
    /// no tolerance-based assertion could see it — and the assertions that
    /// *were* exact (`nothingIsDrawnInsideTheCutout` below, and three others)
    /// each hardcoded `Raster.Pixel(r: 5, g: 7, b: 11, a: 255)`. They pinned the
    /// value we happened to choose, precisely, and so locked the wrong one in
    /// rather than catching it. A test that pins an unverified constant is not
    /// evidence about that constant. All four now derive from
    /// `islandGroundColour` instead of restating it.
    ///
    /// Rendered rather than asserted against the constant directly, so this also
    /// proves the constant is the colour actually reaching the fill.
    @MainActor @Test func theIslandGroundIsThePrototypesVoidNotTheSpritesMixBase() throws {
        let void = try #require(RGBA(hex: "#07080A"), "the prototype's --void")
        #expect(islandGroundColour == void,
                "islandGroundColour is \(islandGroundColour.hex), the prototype's island background is #07080A")

        // Sampled inside the cutout's own columns, where §5.1 guarantees the
        // ground spans and no content may be drawn — the same region
        // `nothingIsDrawnInsideTheCutout` below scans, so "this is pure ground"
        // is a property this suite already relies on rather than one asserted
        // here for the first time.
        let m = Self.model(.dormant, count: 0)
        let raster = try rasterise(IslandBody(model: m, now: Date(timeIntervalSince1970: 1_000_000)))
        let notch = IslandGeometry(screen: Self.mbp14).notch
        let midCutout = Int((notch.midX - m.frames.panel.minX).rounded())
        let expected = Raster.Pixel(r: UInt8((void.r * 255).rounded()),
                                    g: UInt8((void.g * 255).rounded()),
                                    b: UInt8((void.b * 255).rounded()), a: 255)
        let sampled = raster[midCutout, 8]
        #expect(sampled == expected,
                "the island's own ground rendered \(sampled) at the middle of the cutout, not the prototype's --void \(expected)")
    }

    /// Design §5.1, the rule the whole layout exists to obey: the cutout is a
    /// hole and nothing may be drawn in it.
    ///
    /// Checked against the *content*, not the silhouette — the island's ground
    /// spans the cutout by design; what must not appear there is a cat, a
    /// badge or a digit. Any pixel differing from the island's own ground
    /// colour inside the cutout's columns is content that has slid under it.
    @MainActor @Test func nothingIsDrawnInsideTheCutout() throws {
        let ground = Raster.Pixel(islandGroundColour)   // derived, never restated — see Raster.Pixel(_:)
        for (state, count) in [(IslandState.running, 999), (.waiting, 3), (.dormant, 0)] {
            let m = Self.model(state, count: count)
            let raster = try rasterise(IslandBody(model: m, now: Date(timeIntervalSince1970: 1_000_000)))
            let notch = IslandGeometry(screen: Self.mbp14).notch
            let from = Int(notch.minX - m.frames.panel.minX)
            let to = Int(notch.maxX - m.frames.panel.minX)
            for x in from..<to {
                for y in 0..<raster.height {
                    let p = raster[x, y]
                    guard p.isTransparent == false else { continue }
                    #expect(p == ground,
                            "\(state) count=\(count): \(p) at panel column \(x) is inside the cutout — content has slid under the hole")
                }
            }
        }
    }

    /// Design §5.1 at the tier that was previously unguarded: Task 4's
    /// substitute check (`nothingIsDrawnInsideTheCutoutWithTheDrawerOpen` in
    /// `DrawerGeometryTests.swift`) rendered a scene with exactly one possible
    /// non-transparent colour — the ground fill itself, with no cat, no
    /// badge, nothing — so no realistic geometry bug could have turned it
    /// red. Now that `IslandModel` can actually hold an open drawer
    /// (`IslandModel.tier`, `.drawerOpen`), this is the real version: modelled
    /// directly on `nothingIsDrawnInsideTheCutout` just above — same
    /// ground-colour comparison, same panel-relative column arithmetic, same
    /// `IslandBody` render — except the model here has a real question open,
    /// so `IslandBody`'s own silhouette (and `panelFrames`, which its outer
    /// frame is sized against) is genuinely taller, with the cat/badge/count
    /// drawn at the top the same as every other test in this file — "actual
    /// content present," not a blank canvas.
    ///
    /// `IslandShape`'s two rounded corners live at its extreme left/right
    /// edges regardless of height (see its own `path(in:)` — the radius is
    /// `min(bottomRadius, rect.height, rect.width / 2)`, and `bottomRadius`
    /// is 15pt against every fixture's width here), so growing the shape
    /// downward for the drawer does not bring any antialiased corner pixel
    /// nearer the cutout's own columns, which sit in the middle of the
    /// width — the one artifact `DrawerGeometryTests`' own comment warns
    /// about stays confined to where it always was.
    @MainActor @Test func nothingIsDrawnInsideTheCutoutWithTheDrawerOpen() throws {
        let ground = Raster.Pixel(islandGroundColour)   // derived, never restated — see Raster.Pixel(_:)
        let event = VibeEvent(id: "q", cli: "claude-code", kind: .permission,
                              session: "s", cwd: "/tmp/proj", title: "Bash command", body: "pnpm install",
                              choices: [Choice(id: "allow", label: "Allow once"),
                                        Choice(id: "deny", label: "Deny")],
                              wantsReply: true)
        for (state, count) in [(IslandState.running, 999), (.waiting, 3), (.dormant, 0)] {
            let m = Self.model(state, count: count)
            m.question = QuestionModel(event: event)
            m.drawerOpen = true
            guard case .drawer = m.tier else {
                Issue.record("\(state) count=\(count): the fixture never reached the drawer tier — this test proves nothing")
                continue
            }

            let raster = try rasterise(IslandBody(model: m, now: Date(timeIntervalSince1970: 1_000_000)))
            let notch = IslandGeometry(screen: Self.mbp14).notch

            // The render actually reached the drawer's own height — not
            // merely that `m.tier` (an `IslandModel` property, computed
            // independently of `IslandGeometry.maxCollapsedFrames`) *reports*
            // `.drawer`. Confirmed to matter: mutating
            // `maxCollapsedFrames(tier:)` to ignore its parameter (always
            // `.rest` internally) leaves `m.tier` and `m.frames.body.height`
            // (which does not route through `maxCollapsedFrames`) untouched,
            // but silently shrinks `m.panelFrames` — and with it,
            // `IslandBody`'s own outer frame and this render's height —
            // straight back to the collapsed-only size. The loop below scans
            // `0..<raster.height`, so a render that quietly got shorter
            // checks *less*, not something that fails: every assertion below
            // still passed against that mutant. This is what actually caught
            // it.
            let expectedHeight = Int((notch.height + m.question!.face.height
                                       + IslandGeometry.auraMargin).rounded(.up))
            #expect(raster.height == expectedHeight,
                    "\(state) count=\(count): rendered \(raster.height)pt tall, expected \(expectedHeight) — the panel did not actually grow to cover the open drawer")

            // Plan 6.3 Task 1: the same guard on the other axis, and it is
            // needed for the identical reason. The open island is now 560pt wide
            // where it used to be 273.1, and the scan below runs over the
            // cutout's *own* columns — a panel that failed to widen would leave
            // every assertion here green while checking a narrower island than
            // production draws. `expectedWidth` is derived from the face, not
            // restated, so it moves with `DrawerFace.width`.
            let expectedWidth = Int((m.question!.face.width
                                      + IslandGeometry.auraMargin * 2).rounded(.up))
            #expect(raster.width == expectedWidth,
                    "\(state) count=\(count): rendered \(raster.width)pt wide, expected \(expectedWidth) — the panel did not grow sideways to cover the open drawer")

            let from = Int(notch.minX - m.frames.panel.minX)
            let to = Int(notch.maxX - m.frames.panel.minX)
            for x in from..<to {
                for y in 0..<raster.height {
                    let p = raster[x, y]
                    guard p.isTransparent == false else { continue }
                    #expect(p == ground,
                            "\(state) count=\(count), drawer open: \(p) at panel column \(x) is inside the cutout — content has slid under the hole")
                }
            }

            // "Actual content present": confirms the render is not a blank
            // canvas that would make the loop above vacuously true — the same
            // fixed facial-tone check `everyStateRendersAVisibleIsland` uses.
            let palette = CatPalette(accent: state.accent)
            for tone in [Tone.innerEar, .nose] {
                #expect(raster.pixelCount(near: palette[tone]) > 0,
                        "\(state): no \(tone) pixel anywhere — the cat sprite did not draw with the drawer open")
            }
        }
    }

    /// Carried finding from Task 2's own review: no committed test exercised
    /// `RevealContent` with an open drawer *and* a populated `model.revealed`
    /// together. A reviewer verified by hand that this is safe today — the
    /// collapsed row drops the hover reveal entirely while a drawer is open
    /// (`IslandBody.body`'s own comment on why), so the bar and the drawer
    /// stay one column and nothing widens into the cutout — but that safety
    /// rests on this file's own `clipShape` sizing, which a future refactor
    /// could break silently with nothing here to catch it. Plan 5's drawer
    /// routing is this finding's own best home (Task 7's brief, point 5).
    ///
    /// Modelled directly on `nothingIsDrawnInsideTheCutoutWithTheDrawerOpen`
    /// just above, with the two inputs that test leaves at their defaults —
    /// `hovering: false`, `revealed: nil` — both turned on instead, which is
    /// exactly the untested combination the finding names.
    @MainActor @Test func nothingIsDrawnInsideTheCutoutWithTheDrawerOpenAndTheRevealPopulated() throws {
        let ground = Raster.Pixel(islandGroundColour)   // derived, never restated — see Raster.Pixel(_:)
        let event = VibeEvent(id: "q", cli: "claude-code", kind: .permission,
                              session: "s", cwd: "/tmp/proj", title: "Bash command", body: "pnpm install",
                              choices: [Choice(id: "allow", label: "Allow once"),
                                        Choice(id: "deny", label: "Deny")],
                              wantsReply: true)
        let m = Self.model(.waiting, count: 3, hovering: true)
        m.question = QuestionModel(event: event)
        m.drawerOpen = true
        m.revealed = Session(event: VibeEvent(id: "e", cli: "claude-code", kind: .running,
                                              session: "s2", cwd: "/Users/dev/api"),
                             now: Date(timeIntervalSince1970: 1_000_000))
        guard case .drawer = m.tier else {
            Issue.record("the fixture never reached the drawer tier — this test proves nothing")
            return
        }

        // .waiting's cat/badge are both continuous — a single render at a
        // fixed `now:` (rather than routing through `IslandView`'s own
        // `TimelineView` branch) is what every other test in this file
        // already does for the identical reason: a static render must not
        // read the real wall clock.
        let raster = try rasterise(IslandBody(model: m, now: Date(timeIntervalSince1970: 1_000_030)))
        let notch = IslandGeometry(screen: Self.mbp14).notch
        let from = Int(notch.minX - m.frames.panel.minX)
        let to = Int(notch.maxX - m.frames.panel.minX)
        for x in from..<to {
            for y in 0..<raster.height {
                let p = raster[x, y]
                guard p.isTransparent == false else { continue }
                #expect(p == ground,
                        "hovering + drawer open + revealed populated: \(p) at panel column \(x) is inside the cutout — content has slid under the hole")
            }
        }

        // "Actual content present," the same reasoning
        // `nothingIsDrawnInsideTheCutoutWithTheDrawerOpen` gives for its own
        // identical check: the loop above is vacuously true against a blank
        // canvas, so this confirms the collapsed bar really painted something.
        //
        // The witness is §5.4's session count, **not** `--bone` (F2 of the
        // final whole-branch review). It was `pixelCount(near: boneColour) > 0`
        // — an assertion that the hover reveal's project name *does* draw with
        // the drawer open, which flatly contradicts this test's own doc comment
        // 25 lines above and is exactly the bug F1 fixed. It was also the one
        // test out of 128 that gating the reveal correctly failed. With the
        // reveal correctly gated `IslandBody` paints only ground in these
        // columns, so `--bone` is now 0 by design and the §5.1 loop above would
        // have gone vacuous behind a witness that could never come back.
        #expect(Self.sessionCountPixels(raster, m) > 0,
                "no accent pixel right of the cutout — §5.4's session count did not draw at all, so the §5.1 scan above proves nothing")
    }

    /// The gap that let F1 through: **nothing in this suite looked at the
    /// collapsed bar's *content* while the drawer was open.**
    /// `theDrawersContentDoesNotShiftWhenOnlyHoverChanges` starts its loop at
    /// `drawerTop`; `hoverWidensTheCollapsedRowAndLeavesTheDrawerRowAlone`
    /// measures the silhouette's painted *extent*, not what is inside it. So a
    /// change that shrank the collapsed half's frame without shrinking what was
    /// laid out inside it passed every one of them.
    ///
    /// §5.4's session count is the thing that broke, because it was the only
    /// flexible child of the overrunning `HStack` and SwiftUI squeezes those
    /// first. The assertion is equality against the same count with the drawer
    /// *closed and not hovering* — the plainest state there is, and the one
    /// §6.1's progressive tiers say an open drawer must agree with, since by
    /// then the reveal has done its job and been dropped. Equality, not `> 0`:
    /// a partially squeezed digit is still some accent pixels, and the observed
    /// failure was a "3" rendering as a clipped "p".
    ///
    /// Mutation-verified against the pre-fix behaviour — reverting
    /// `content(cell:)` to `model.hovering ? CollapsedLayout.hoverReveal : 0`
    /// gives open+hover **0** accent pixels right of the cutout against 13 for
    /// all three healthy states, and this test fails with that message.
    @MainActor @Test func theSessionCountSurvivesAnOpenDrawerWhileHovering() throws {
        let event = VibeEvent(id: "q", cli: "claude-code", kind: .permission,
                              session: "s", cwd: "/tmp/proj", title: "Bash command", body: "pnpm install",
                              choices: [Choice(id: "allow", label: "Allow once"),
                                        Choice(id: "deny", label: "Deny")],
                              wantsReply: true)

        /// `revealed` populated in every case, drawer or not: an empty
        /// `RevealContent` lays out at zero width whatever the frame says, so
        /// leaving it nil would hide the very overrun this measures.
        func count(hovering: Bool, open: Bool) throws -> Int {
            let m = Self.model(.waiting, count: 3, hovering: hovering)
            m.revealed = Session(event: VibeEvent(id: "e", cli: "claude-code", kind: .running,
                                                  session: "s2", cwd: "/Users/dev/api"),
                                 now: Date(timeIntervalSince1970: 1_000_000))
            if open {
                m.question = QuestionModel(event: event)
                m.drawerOpen = true
                guard case .drawer = m.tier else {
                    Issue.record("the fixture never reached the drawer tier — this test proves nothing")
                    return -1
                }
            }
            // A `.sessionCount` right flank is a precondition, not an
            // assumption: with `.nothing` or `.agentIcon` there is no count to
            // squeeze and every comparison below is 0 == 0.
            guard case .sessionCount = m.layout.right else {
                Issue.record("count=3 did not produce a session-count right flank — there is nothing for this test to measure")
                return -1
            }
            let raster = try rasterise(IslandBody(model: m, now: Date(timeIntervalSince1970: 1_000_030)))
            return Self.sessionCountPixels(raster, m)
        }

        let plain = try count(hovering: false, open: false)
        #expect(plain > 0,
                "the session count painted no accent pixel right of the cutout even at rest — the baseline this test compares against is vacuous")

        for (hovering, open) in [(true, false), (false, true), (true, true)] {
            #expect(try count(hovering: hovering, open: open) == plain,
                    "hover \(hovering) · drawer \(open ? "open" : "closed"): §5.4's session count painted a different number of accent pixels than at rest — the collapsed bar's content is being squeezed by something laid out wider than its own frame")
        }
    }
}
