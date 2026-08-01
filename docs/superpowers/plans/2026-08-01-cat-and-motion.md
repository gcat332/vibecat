# The Cat, Badges and Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put the pixel cat in the notch — five moods, five coats, five badges — and give the island the motion the design specifies, without an idle machine ever animating.

**Architecture:** Everything about the cat is a pure value type: a tone ramp derived from the state accent, a cell grid, a mood, a coat. A single `Canvas` renders that grid. The render path is restructured so the hosting view's root is assigned **once** and a `TimelineView` inside it reads observable state — the current `render()`, which hands AppKit a freshly built SwiftUI tree per change, cannot survive sprite frame rates. The panel is sized once for the widest collapsed state and the silhouette animates *inside* it.

**Tech Stack:** Swift 6, SwiftUI `Canvas` + `TimelineView`, AppKit interop. No external dependencies.

**Prerequisite reading:** [the animation spike](../spikes/2026-08-01-animation-spike.md). Every performance number and every architectural choice below came from it. Design §7 (the cat), §8 (badges) and §9 (motion) are the source for the visual values.

**Scope:** Collapsed island only. The drawer stays empty — answering is Plan 4, the session list Plan 5. Settings expose none of this yet; the Full/Reduced/Off motion *preference* is Plan 6, but respecting the **system** Reduce Motion setting is here, because it gates whether a timeline runs at all.

## Global Constraints

- Swift 6 language mode, `platforms: [.macOS(.v14)]`, **no external dependencies**.
- Tests use **swift-testing** (`import Testing`, `@Test`, `#expect`, `#require`) — never XCTest.
- **An idle machine must not animate.** Measured: any live `TimelineView` costs ~6% of a core even at 8 fps; removing it entirely costs **0.0%**. Stopping is the only mechanism that reaches zero.
- **The sprite runs at 8–12 fps**, never the display rate. Measured: 8 fps ~6%, 30 fps ~9–10%, 120 fps ~15–18%. Pixel art steps; it does not ease.
- **`TimelineView(.animation)` must always be given a `minimumInterval`.** Without one it runs at the display's rate — 118 draws/s on this 120 Hz panel, not 60.
- **The hosting view's root is assigned once.** Everything that changes per frame changes inside it. Do not assign `NSHostingView.rootView` from AppKit on a per-frame path.
- **Animate content, not the window.** Measured p95 10.34 ms vs 15.16 ms, worst 10.41 vs 16.93. The panel is sized once; the silhouette's width animates inside it.
- Motion values, exact: width spring response `0.42` damping `0.72`; drawer spring response `0.42` damping `0.78`; face crossfade `190ms`; hover reveal `280ms`, 0 → `150pt`.
- Sprite grid is `18 × 14` cells. The badge box is a fixed `14pt` whatever it contains.
- **Colour means state and only state.** A coat changes markings, never hue — it repaints cells with a tone already in the ramp. Coat overrides apply first, mood overrides second: the eyes always win over a marking.
- State accents, exact: idle `#3FD99B`, running `#5B9DF9`, waiting `#FFA63C`, failed `#FF5C5C`. Ground `#05070B`.
- `public` API on everything later plans consume across module boundaries.

---

## File Structure

All new files under `Sources/VibeCatUI/Cat/` unless stated.

| File | Responsibility |
|---|---|
| `CatPalette.swift` | The five accent-derived tones plus the fixed pinks, whites and pupil. Pure colour maths. |
| `CatGrid.swift` | The 18×14 cell table and the coat overrides. Pure data. |
| `CatMood.swift` | The five moods: eye and mouth overrides, and each mood's motion profile (rate, cycle, whether it animates at all). |
| `CatCanvas.swift` | The SwiftUI `Canvas` that draws a resolved grid. |
| `Badge.swift` | The five badges: their cells per animation phase, and their motion profiles. |
| `BadgeCanvas.swift` | The `Canvas` that draws a badge inside the fixed 14pt box. |
| `MotionPreference.swift` | Reads the system Reduce Motion setting; decides whether a timeline may run. |
| `Sources/VibeCatUI/IslandView.swift` | Restructured: root assigned once, `TimelineView` inside, observable state. |
| `Sources/VibeCatUI/NotchController.swift` | Restructured: panel sized once, no per-change `rootView` assignment. |
| `Sources/VibeCatUI/IslandGeometry.swift` | Gains the fixed maximum collapsed width. |
| `Tests/VibeCatUITests/Cat/*` | One test file per source file above that carries logic. |

---

## Task 1: The tone ramp

**Files:**
- Create: `Sources/VibeCatUI/Cat/CatPalette.swift`
- Test: `Tests/VibeCatUITests/Cat/CatPaletteTests.swift`

**Interfaces:**
- Consumes: `RGBA` from `IslandState.swift` — `public let r/g/b: Double`, `public init(r:g:b:)`, `public init?(hex:)`, `public var hex: String`.
- Produces: `public enum Tone: Character, Sendable, CaseIterable` with cases `outline = "O"`, `shadow = "S"`, `body = "B"`, `highlight = "H"`, `lightest = "L"`, `innerEar = "E"`, `nose = "N"`, `eyeWhite = "W"`, `sparkle = "K"`, `pupil = "P"`; and `public struct CatPalette: Sendable, Equatable` with `public init(accent: RGBA)`, `public subscript(_ tone: Tone) -> RGBA`.

Design §7.1 derives five of the tones from the state accent so the cat is always the state's colour, and fixes the rest so the face reads as a face at any hue.

| Tone | Derivation |
|---|---|
| `O` outline | accent at 20% over `#05070B` |
| `S` shadow | accent at 60% over `#05070B` |
| `B` body | the accent itself |
| `H` highlight | accent at 64% over `#FFFFFF` |
| `L` lightest | accent at 36% over `#FFFFFF` |
| `E` inner ear | `#F2A0B6` |
| `N` nose | `#F08098` |
| `W` eye white / `K` sparkle | `#FFFFFF` |
| `P` pupil | `#12131A` |

"accent at 20% over X" means the accent composited onto X at 0.2 alpha: `0.2 * accent + 0.8 * X`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import VibeCatUI

private let running = RGBA(hex: "#5B9DF9")!
private let ground = RGBA(hex: "#05070B")!
private let white = RGBA(hex: "#FFFFFF")!

private func mix(_ a: RGBA, _ b: RGBA, _ t: Double) -> RGBA {
    RGBA(r: a.r * t + b.r * (1 - t),
         g: a.g * t + b.g * (1 - t),
         b: a.b * t + b.b * (1 - t))
}
private func close(_ a: RGBA, _ b: RGBA) -> Bool {
    abs(a.r - b.r) < 0.002 && abs(a.g - b.g) < 0.002 && abs(a.b - b.b) < 0.002
}

@Test func theBodyToneIsTheAccentItself() {
    #expect(CatPalette(accent: running)[.body] == running)
}

@Test func theDarkTonesAreTheAccentOverTheGround() {
    let p = CatPalette(accent: running)
    #expect(close(p[.outline], mix(running, ground, 0.20)))
    #expect(close(p[.shadow], mix(running, ground, 0.60)))
}

@Test func theLightTonesAreTheAccentOverWhite() {
    let p = CatPalette(accent: running)
    #expect(close(p[.highlight], mix(running, white, 0.64)))
    #expect(close(p[.lightest], mix(running, white, 0.36)))
}

/// The face must read as a face at any hue, so these do not follow the accent.
@Test func theFacialTonesAreFixedWhateverTheAccent() {
    let a = CatPalette(accent: RGBA(hex: "#5B9DF9")!)
    let b = CatPalette(accent: RGBA(hex: "#FF5C5C")!)
    for tone: Tone in [.innerEar, .nose, .eyeWhite, .sparkle, .pupil] {
        #expect(a[tone] == b[tone], "\(tone) should not follow the accent")
    }
    #expect(a[.innerEar].hex == "#F2A0B6")
    #expect(a[.nose].hex == "#F08098")
    #expect(a[.eyeWhite].hex == "#FFFFFF")
    #expect(a[.pupil].hex == "#12131A")
}

/// A ramp with no ordering is not a ramp. Darkest to lightest, by luminance.
@Test func theAccentTonesFormAMonotonicRamp() {
    func luma(_ c: RGBA) -> Double { 0.299 * c.r + 0.587 * c.g + 0.114 * c.b }
    for state in IslandState.allCases {
        let p = CatPalette(accent: state.accent)
        let ramp: [Tone] = [.outline, .shadow, .body, .highlight, .lightest]
        let values = ramp.map { luma(p[$0]) }
        #expect(values == values.sorted(), "\(state) ramp is not monotonic: \(values)")
    }
}

@Test func everyToneHasAColour() {
    let p = CatPalette(accent: running)
    for tone in Tone.allCases { _ = p[tone] }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CatPaletteTests`
Expected: FAIL — `cannot find 'CatPalette' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
/// One cell's colour role. The raw character is the grid's own alphabet, so
/// the sprite table in CatGrid stays readable as art.
public enum Tone: Character, Sendable, CaseIterable {
    case outline = "O"
    case shadow = "S"
    case body = "B"
    case highlight = "H"
    case lightest = "L"
    case innerEar = "E"
    case nose = "N"
    case eyeWhite = "W"
    case sparkle = "K"
    case pupil = "P"
}

/// The cat's colours for one state.
///
/// Five tones derive from the accent so the fur is always the state's colour —
/// that is what keeps "colour means state" true through every coat. The facial
/// tones are fixed, because a pink nose reads as a nose at any hue and an
/// accent-tinted one does not.
public struct CatPalette: Sendable, Equatable {
    private static let ground = RGBA(hex: "#05070B")!
    private static let white = RGBA(hex: "#FFFFFF")!

    private let accent: RGBA

    public init(accent: RGBA) { self.accent = accent }

    /// `accent` composited onto `base` at `alpha`.
    private static func over(_ accent: RGBA, _ base: RGBA, _ alpha: Double) -> RGBA {
        RGBA(r: accent.r * alpha + base.r * (1 - alpha),
             g: accent.g * alpha + base.g * (1 - alpha),
             b: accent.b * alpha + base.b * (1 - alpha))
    }

    public subscript(_ tone: Tone) -> RGBA {
        switch tone {
        case .outline:   Self.over(accent, Self.ground, 0.20)
        case .shadow:    Self.over(accent, Self.ground, 0.60)
        case .body:      accent
        case .highlight: Self.over(accent, Self.white, 0.64)
        case .lightest:  Self.over(accent, Self.white, 0.36)
        case .innerEar:  RGBA(hex: "#F2A0B6")!
        case .nose:      RGBA(hex: "#F08098")!
        case .eyeWhite:  RGBA(hex: "#FFFFFF")!
        case .sparkle:   RGBA(hex: "#FFFFFF")!
        case .pupil:     RGBA(hex: "#12131A")!
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CatPaletteTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Prove the ramp test is load-bearing**

Temporarily swap `.highlight` and `.shadow`'s derivations. Re-run: `theAccentTonesFormAMonotonicRamp` must FAIL. Revert and confirm with `git diff` that nothing survives.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/Cat/CatPalette.swift Tests/VibeCatUITests/Cat/CatPaletteTests.swift
git commit -m "feat: the cat's tone ramp, derived from the state accent"
```

---

## Task 2: The sprite grid and coats

**Files:**
- Create: `Sources/VibeCatUI/Cat/CatGrid.swift`
- Test: `Tests/VibeCatUITests/Cat/CatGridTests.swift`

**Interfaces:**
- Consumes: `Tone` from Task 1.
- Produces: `public enum Coat: String, Sendable, CaseIterable` with cases `tabby, plain, tuxedo, siamese, patched`; and `public struct CatGrid: Sendable, Equatable` with `public static let width = 18`, `public static let height = 14`, `public static let base: [[Tone?]]`, `public init(coat: Coat)`, `public var cells: [[Tone?]]`, `public subscript(_ col: Int, _ row: Int) -> Tone?`.

Design §7.1's grid, verbatim. `.` is transparent.

```
..OO..........OO..
.OEEO........OEEO.
.OEEHO......OHEEO.
.OHHHOOOOOOOOHHHO.
.OLLLLLLLLLLLLLLO.
OHHHHHHHHHHHHHHHHO
OHHHHHHHHHHHHHHHHO
OBBKWWBBBBBBKWWBBO
OBBWPPBBBBBBWPPBBO
OBBPPPBBBBBBPPPBBO
OBBBBBBBNNBBBBBBBO
OSBBBBBOBBOBBBBBSO
.OSSBBBBBBBBBBSSO.
..OOOOOOOOOOOOOO..
```

Design §7.3: a coat **changes markings, never hue** — it repaints cells with a tone already in the ramp. `tabby` is the default and is the base grid unchanged.

| Coat | Markings |
|---|---|
| `tabby` | the base grid, unchanged |
| `plain` | every `S` (shadow) cell becomes `B` — no markings at all |
| `tuxedo` | the chest, rows 10–12 columns 6–11, becomes `L` |
| `siamese` | the ears (rows 0–2) and the muzzle (rows 10–11, columns 5–12) become `L`; the flanks rows 5–6 become `S` |
| `patched` | rows 5–8, columns 12–16 become `S` |

**A coat repaints fur, and only fur.** It may write over `S`, `B`, `H` and `L` — nothing else. That protects the outline and linework (`O`), the pink inner ears (`E`), the nose (`N`) and the eyes (`W`, `K`, `P`) by construction rather than by each coat's rectangle happening to miss them. Ruled by the project owner after the original eyes-only guard was found to let `tuxedo` erase the nose and mouth, and `siamese` flatten both ears' entire linework and pink interior. Task 3's mood overrides then run over the top regardless — §7.3's "the eyes always win".

- [ ] **Step 1: Write the failing test**

```swift
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

@Test func plainRemovesEveryShadowMarking() {
    let cells = CatGrid(coat: .plain).cells
    #expect(!cells.flatMap { $0 }.contains(.shadow))
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CatGridTests`
Expected: FAIL — `cannot find 'CatGrid' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
/// Which markings the cat wears. Design §7.3: a coat repaints cells with a
/// tone already in the ramp, so the fur stays the state's colour and "colour
/// means state" survives the customisation.
public enum Coat: String, Sendable, CaseIterable {
    case tabby, plain, tuxedo, siamese, patched
}

/// The cat, as cells. Design §7.1's grid verbatim — kept as character art so
/// it stays editable as art rather than as a table of enum cases.
public struct CatGrid: Sendable, Equatable {
    public static let width = 18
    public static let height = 14

    private static let art = [
        "..OO..........OO..",
        ".OEEO........OEEO.",
        ".OEEHO......OHEEO.",
        ".OHHHOOOOOOOOHHHO.",
        ".OLLLLLLLLLLLLLLO.",
        "OHHHHHHHHHHHHHHHHO",
        "OHHHHHHHHHHHHHHHHO",
        "OBBKWWBBBBBBKWWBBO",
        "OBBWPPBBBBBBWPPBBO",
        "OBBPPPBBBBBBPPPBBO",
        "OBBBBBBBNNBBBBBBBO",
        "OSBBBBBOBBOBBBBBSO",
        ".OSSBBBBBBBBBBSSO.",
        "..OOOOOOOOOOOOOO..",
    ]

    public static let base: [[Tone?]] = art.map { line in
        line.map { $0 == "." ? nil : Tone(rawValue: $0) }
    }

    /// Eye cells are off-limits to coats — §7.3's "the eyes always win".
    private static let eyeTones: Set<Tone> = [.eyeWhite, .sparkle, .pupil]

    public let coat: Coat
    public let cells: [[Tone?]]

    public init(coat: Coat) {
        self.coat = coat
        self.cells = Self.apply(coat)
    }

    public subscript(_ col: Int, _ row: Int) -> Tone? {
        guard row >= 0, row < Self.height, col >= 0, col < Self.width else { return nil }
        return cells[row][col]
    }

    private static func apply(_ coat: Coat) -> [[Tone?]] {
        var g = base
        // Repaint only where there is already fur, never an eye, never a hole.
        func paint(rows: ClosedRange<Int>, cols: ClosedRange<Int>, _ tone: Tone) {
            for row in rows where row >= 0 && row < height {
                for col in cols where col >= 0 && col < width {
                    guard let existing = g[row][col], !eyeTones.contains(existing) else { continue }
                    g[row][col] = tone
                }
            }
        }

        switch coat {
        case .tabby:
            break
        case .plain:
            for row in 0..<height {
                for col in 0..<width where g[row][col] == .shadow { g[row][col] = .body }
            }
        case .tuxedo:
            paint(rows: 10...12, cols: 6...11, .lightest)
        case .siamese:
            paint(rows: 0...2, cols: 0...width - 1, .lightest)
            paint(rows: 10...11, cols: 5...12, .lightest)
            paint(rows: 5...6, cols: 0...width - 1, .shadow)
        case .patched:
            paint(rows: 5...8, cols: 12...16, .shadow)
        }
        return g
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CatGridTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Prove the eye guard is load-bearing**

Temporarily remove the fur-tone guard from `paint`. Re-run: `noCoatTouchesTheEyes` must FAIL — `patched` paints rows 5–8 columns 12–16, and row 7 columns 12–14 are the right eye's `K`,`W`,`W`. (An earlier draft of this plan named `siamese` here; that was wrong, and the mutation output is what settles it.) Revert, then confirm by re-reading the file and re-running the test — `git diff` shows nothing while the file is still untracked.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/Cat/CatGrid.swift Tests/VibeCatUITests/Cat/CatGridTests.swift
git commit -m "feat: the cat's cell grid and its five coats"
```

---

## Task 3: Moods and motion profiles

**Files:**
- Create: `Sources/VibeCatUI/Cat/CatMood.swift`
- Test: `Tests/VibeCatUITests/Cat/CatMoodTests.swift`

**Interfaces:**
- Consumes: `Tone`, `CatGrid`, `Coat` from Tasks 1–2; `IslandState` from `IslandState.swift`.
- Produces:
  - `public enum CatMood: String, Sendable, CaseIterable { case sleep, trot, call, happy, dead }` with `public init(state: IslandState)`.
  - `public struct MotionProfile: Sendable, Equatable` with `public let framesPerSecond: Double`, `public let cycle: TimeInterval`, `public let isContinuous: Bool`, `public static let still: MotionProfile`.
  - `public extension CatMood { var motion: MotionProfile }`.
  - `public struct ResolvedCat: Sendable, Equatable` with `public init(coat: Coat, mood: CatMood, phase: Double)`, `public var cells: [[Tone?]]`, `public var verticalOffset: Int`.

Design §7.2:

| Mood | State | Eyes | Motion |
|---|---|---|---|
| `sleep` | dormant | shut | slow drowse, `3s` |
| `trot` | running | open, rare blink | quick bob, `1s` |
| `call` | waiting | open, mouth open | attention pulse, `1.1s` |
| `happy` | finished (idle) | `^ ^` arcs | one spring pop |
| `dead` | failed | `X X` | slow wobble, `2.4s` |

**Frame rates come from the spike, not the design doc.** The design gives cycle lengths; the spike gives what a rate costs. `trot` and `call` are the states where something is actively happening, so they animate at 12 fps. `sleep` and `dead` are steady states — they get `isContinuous = false` and **no timeline at all**, because that is the only thing that reaches 0.0% CPU. `happy` is one pop, so it is also not continuous.

`phase` is `0…1` through the cycle. `verticalOffset` is in whole cells — pixel art steps, it does not ease.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import VibeCatUI

@Test func eachIslandStateMapsToItsMood() {
    #expect(CatMood(state: .dormant) == .sleep)
    #expect(CatMood(state: .running) == .trot)
    #expect(CatMood(state: .waiting) == .call)
    #expect(CatMood(state: .idle) == .happy)
    #expect(CatMood(state: .failed) == .dead)
}

/// The spike's finding, encoded: any live timeline costs ~6% of a core, and
/// only removing it reaches 0.0%. Steady states must not have one.
@Test func onlyTheActiveMoodsAnimateContinuously() {
    #expect(CatMood.trot.motion.isContinuous)
    #expect(CatMood.call.motion.isContinuous)
    #expect(CatMood.sleep.motion.isContinuous == false)
    #expect(CatMood.dead.motion.isContinuous == false)
    #expect(CatMood.happy.motion.isContinuous == false)
}

/// 8–12 fps: authentic for pixel art, and 3x cheaper than 30.
@Test func continuousMoodsRunInThePixelArtRange() {
    for mood in CatMood.allCases where mood.motion.isContinuous {
        #expect(mood.motion.framesPerSecond >= 8)
        #expect(mood.motion.framesPerSecond <= 12)
    }
}

@Test func cycleLengthsMatchTheDesign() {
    #expect(CatMood.sleep.motion.cycle == 3.0)
    #expect(CatMood.trot.motion.cycle == 1.0)
    #expect(CatMood.call.motion.cycle == 1.1)
    #expect(CatMood.dead.motion.cycle == 2.4)
}

/// Design §7.2 — the eyes are what distinguish the moods.
@Test func eachMoodGivesTheCatDifferentEyes() {
    func eyeRows(_ mood: CatMood) -> [[Tone?]] {
        let c = ResolvedCat(coat: .tabby, mood: mood, phase: 0).cells
        return Array(c[7...9])
    }
    var seen: [[[Tone?]]] = []
    for mood in CatMood.allCases {
        let rows = eyeRows(mood)
        #expect(!seen.contains(rows), "\(mood) has the same eyes as an earlier mood")
        seen.append(rows)
    }
}

/// The eyes always win over a marking — §7.3.
@Test func moodOverridesBeatCoatMarkings() {
    for coat in Coat.allCases {
        let sleeping = ResolvedCat(coat: coat, mood: .sleep, phase: 0).cells
        let tabbySleeping = ResolvedCat(coat: .tabby, mood: .sleep, phase: 0).cells
        for row in 7...9 {
            #expect(sleeping[row] == tabbySleeping[row],
                    "\(coat) changed the eye rows under mood .sleep")
        }
    }
}

/// Pixel art steps. A fractional offset would blur the grid.
@Test func theVerticalOffsetIsAlwaysAWholeNumberOfCells() {
    for mood in CatMood.allCases {
        for i in 0...20 {
            let phase = Double(i) / 20.0
            let cat = ResolvedCat(coat: .tabby, mood: mood, phase: phase)
            #expect(cat.verticalOffset == Int(cat.verticalOffset))
            #expect(abs(cat.verticalOffset) <= 1, "\(mood) bobs more than one cell")
        }
    }
}

@Test func aStillMoodDoesNotMoveAcrossThePhase() {
    let a = ResolvedCat(coat: .tabby, mood: .dead, phase: 0.0).verticalOffset
    let b = ResolvedCat(coat: .tabby, mood: .dead, phase: 0.5).verticalOffset
    #expect(a == b || CatMood.dead.motion.isContinuous)
}

@Test func resolvingIsStableForTheSameInput() {
    let a = ResolvedCat(coat: .siamese, mood: .trot, phase: 0.25)
    let b = ResolvedCat(coat: .siamese, mood: .trot, phase: 0.25)
    #expect(a == b)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CatMoodTests`
Expected: FAIL — `cannot find 'CatMood' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// How often a mood needs redrawing, and whether it needs redrawing at all.
///
/// `isContinuous == false` is not an optimisation — it is the whole mechanism
/// behind "an idle machine must not animate". Measured: a live TimelineView
/// costs ~6% of a core even at 8 fps; removing it costs 0.0%.
public struct MotionProfile: Sendable, Equatable {
    public let framesPerSecond: Double
    public let cycle: TimeInterval
    public let isContinuous: Bool

    public init(framesPerSecond: Double, cycle: TimeInterval, isContinuous: Bool) {
        self.framesPerSecond = framesPerSecond
        self.cycle = cycle
        self.isContinuous = isContinuous
    }

    public static let still = MotionProfile(framesPerSecond: 0, cycle: 0, isContinuous: false)
}

/// What the cat is doing. Design §7.2.
public enum CatMood: String, Sendable, CaseIterable {
    case sleep, trot, call, happy, dead

    public init(state: IslandState) {
        switch state {
        case .dormant: self = .sleep
        case .running: self = .trot
        case .waiting: self = .call
        case .idle:    self = .happy
        case .failed:  self = .dead
        }
    }

    /// Cycle lengths are the design's. Frame rates are the spike's: 12 fps for
    /// the two moods where something is actually happening, nothing at all for
    /// the three steady ones.
    public var motion: MotionProfile {
        switch self {
        case .trot:  MotionProfile(framesPerSecond: 12, cycle: 1.0, isContinuous: true)
        case .call:  MotionProfile(framesPerSecond: 12, cycle: 1.1, isContinuous: true)
        case .sleep: MotionProfile(framesPerSecond: 0, cycle: 3.0, isContinuous: false)
        case .dead:  MotionProfile(framesPerSecond: 0, cycle: 2.4, isContinuous: false)
        case .happy: MotionProfile(framesPerSecond: 0, cycle: 0.0, isContinuous: false)
        }
    }
}

/// A coat and a mood resolved into the cells to draw at one phase.
///
/// Order matters and is §7.3's: the coat paints markings first, then the mood
/// paints the face over the top. The eyes always win.
public struct ResolvedCat: Sendable, Equatable {
    public let coat: Coat
    public let mood: CatMood
    /// 0…1 through the mood's cycle.
    public let phase: Double
    public let cells: [[Tone?]]
    /// Whole cells. Pixel art steps; a fractional offset would blur the grid.
    public let verticalOffset: Int

    public init(coat: Coat, mood: CatMood, phase: Double) {
        self.coat = coat
        self.mood = mood
        self.phase = phase
        var g = CatGrid(coat: coat).cells
        Self.applyFace(mood, phase: phase, to: &g)
        self.cells = g
        self.verticalOffset = Self.offset(mood, phase: phase)
    }

    private static func offset(_ mood: CatMood, phase: Double) -> Int {
        guard mood.motion.isContinuous else { return 0 }
        // A single-cell step, up for the first half of the cycle.
        return phase < 0.5 ? -1 : 0
    }

    /// Rows 7…9 are the eyes; row 10 columns 8…9 the nose, row 11 the mouth.
    private static func applyFace(_ mood: CatMood, phase: Double, to g: inout [[Tone?]]) {
        func setEyes(_ left: [Tone?], _ right: [Tone?], row: Int) {
            for (i, tone) in left.enumerated() { g[row][3 + i] = tone }
            for (i, tone) in right.enumerated() { g[row][12 + i] = tone }
        }

        switch mood {
        case .sleep:
            // Shut: a single dark line where the open eye's rows were.
            for row in 7...9 {
                setEyes(row == 8 ? [.pupil, .pupil, .pupil] : [.body, .body, .body],
                        row == 8 ? [.pupil, .pupil, .pupil] : [.body, .body, .body],
                        row: row)
            }
        case .trot:
            // Open, with a rare blink — instantaneous, one frame near the end
            // of the cycle. The blink is the one thing in the interface that
            // does not ease, because a blink does not.
            if phase > 0.92 {
                for row in 7...9 {
                    setEyes(row == 8 ? [.pupil, .pupil, .pupil] : [.body, .body, .body],
                            row == 8 ? [.pupil, .pupil, .pupil] : [.body, .body, .body],
                            row: row)
                }
            }
        case .call:
            // Open, mouth open: row 11's centre becomes a dark opening.
            g[11][8] = .pupil
            g[11][9] = .pupil
        case .happy:
            // ^ ^ arcs.
            for row in 7...9 {
                let arc: [Tone?] = switch row {
                case 7: [.body, .pupil, .body]
                case 8: [.pupil, .body, .pupil]
                default: [.body, .body, .body]
                }
                setEyes(arc, arc, row: row)
            }
        case .dead:
            // X X.
            for row in 7...9 {
                let x: [Tone?] = switch row {
                case 7, 9: [.pupil, .body, .pupil]
                default:   [.body, .pupil, .body]
                }
                setEyes(x, x, row: row)
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CatMoodTests`
Expected: PASS, 9 tests. If `eachMoodGivesTheCatDifferentEyes` fails because `trot` at phase 0 is identical to the base grid and some other mood also leaves rows 7–9 untouched, that is a real finding — report it rather than weakening the test.

- [ ] **Step 5: Prove the steady-state rule is load-bearing**

Temporarily set `.sleep`'s profile to `isContinuous: true`. Re-run: `onlyTheActiveMoodsAnimateContinuously` must FAIL. Revert and confirm with `git diff`.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/Cat/CatMood.swift Tests/VibeCatUITests/Cat/CatMoodTests.swift
git commit -m "feat: the cat's five moods and their motion profiles"
```

---

## Task 4: Badges

**Files:**
- Create: `Sources/VibeCatUI/Cat/Badge.swift`
- Test: `Tests/VibeCatUITests/Cat/BadgeTests.swift`

**Interfaces:**
- Consumes: `Tone`, `MotionProfile`, `IslandState`.
- Produces: `public enum Badge: String, Sendable, CaseIterable { case zzz, squares, bang, star, cross }` with `public init(state: IslandState)`, `public var motion: MotionProfile`, `public func cells(at phase: Double) -> [[Bool]]`, and `public static let size = 7`.

Design §8. All badges sit in a fixed `14pt` box — drawn on a `7 × 7` cell grid at 2pt per cell, so the box is a constant whatever the badge contains. The fixed box is why the left flank never resizes: a `zzz` is three times the width of a `!`, and without a constant slot the flank would walk the cat sideways on every state change.

| Badge | State | Motion |
|---|---|---|
| `zzz` | asleep | two z's drift up and fade, small one first |
| `squares` | running | four squares swell in turn clockwise, reading as rotation |
| `bang` | needs you | pulse |
| `star` | finished | twinkle every `2.2s` |
| `cross` | failed | shudder, then rest |

§8's note is worth keeping in the code: the four squares exist because **a pixel grid cannot rotate cleanly** — but it can take turns, which reads as rotation without anything actually rotating.

Badges are monochrome — `[[Bool]]` — and are tinted with the state accent by the view. That keeps "colour means state" true for the badge too.

- [ ] **Step 1: Write the failing test**

```swift
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
        let quadrants = [
            cells[0...2].flatMap { $0[0...2] }.filter { $0 }.count,   // top-left
            cells[0...2].flatMap { $0[4...6] }.filter { $0 }.count,   // top-right
            cells[4...6].flatMap { $0[4...6] }.filter { $0 }.count,   // bottom-right
            cells[4...6].flatMap { $0[0...2] }.filter { $0 }.count,   // bottom-left
        ]
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter BadgeTests`
Expected: FAIL — `cannot find 'Badge' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// The small animation beside the cat naming what it is doing. Design §8.
///
/// Every badge draws on the same 7×7 grid inside a fixed 14pt box. That box is
/// constant on purpose: a `zzz` is three times the width of a `!`, and without
/// a fixed slot the left flank resizes on every state change and walks the cat
/// sideways.
///
/// Monochrome by design — the view tints with the state accent, so the badge
/// carries state colour like everything else.
public enum Badge: String, Sendable, CaseIterable {
    case zzz, squares, bang, star, cross

    public static let size = 7

    public init(state: IslandState) {
        switch state {
        case .dormant: self = .zzz
        case .running: self = .squares
        case .waiting: self = .bang
        case .idle:    self = .star
        case .failed:  self = .cross
        }
    }

    public var motion: MotionProfile {
        switch self {
        case .zzz:     MotionProfile(framesPerSecond: 8, cycle: 3.0, isContinuous: true)
        case .squares: MotionProfile(framesPerSecond: 12, cycle: 1.0, isContinuous: true)
        case .bang:    MotionProfile(framesPerSecond: 12, cycle: 1.1, isContinuous: true)
        case .star:    MotionProfile(framesPerSecond: 0, cycle: 2.2, isContinuous: false)
        case .cross:   MotionProfile(framesPerSecond: 0, cycle: 0.6, isContinuous: false)
        }
    }

    public func cells(at phase: Double) -> [[Bool]] {
        var g = [[Bool]](repeating: [Bool](repeating: false, count: Self.size),
                         count: Self.size)
        func set(_ rows: [String]) {
            for (r, line) in rows.enumerated() where r < Self.size {
                for (c, ch) in line.enumerated() where c < Self.size {
                    g[r][c] = ch != "."
                }
            }
        }

        switch self {
        case .zzz:
            // Two z's drifting up, the small one leading. Its rise is the phase.
            let lift = Int((phase * 3).rounded(.down))          // 0…2
            let smallRow = max(0, 2 - lift)
            let bigRow = min(Self.size - 3, 4 - lift)
            if bigRow >= 0 && bigRow + 2 < Self.size {
                g[bigRow][1] = true; g[bigRow][2] = true; g[bigRow][3] = true
                g[bigRow + 1][2] = true
                g[bigRow + 2][1] = true; g[bigRow + 2][2] = true; g[bigRow + 2][3] = true
            }
            if smallRow >= 0 && smallRow + 1 < Self.size {
                g[smallRow][5] = true; g[smallRow][6] = true
                g[smallRow + 1][5] = true; g[smallRow + 1][6] = true
            }

        case .squares:
            // Four squares swelling in turn, clockwise. A pixel grid cannot
            // rotate cleanly — but it can take turns, and that reads as
            // rotation without anything actually rotating.
            let step = Int((phase * 4).rounded(.down)) % 4      // 0…3
            let origins = [(0, 0), (0, 4), (4, 4), (4, 0)]      // TL, TR, BR, BL
            for (i, o) in origins.enumerated() {
                let big = (i == step)
                let span = big ? 3 : 2
                let rowOffset = big ? 0 : (o.0 == 0 ? 0 : 1)
                let colOffset = big ? 0 : (o.1 == 0 ? 0 : 1)
                for r in 0..<span {
                    for c in 0..<span {
                        g[o.0 + rowOffset + r][o.1 + colOffset + c] = true
                    }
                }
            }

        case .bang:
            // A pulse: the stem grows by a cell at the peak of the cycle.
            let tall = phase < 0.5
            let top = tall ? 0 : 1
            for r in top...4 { g[r][3] = true }
            g[6][3] = true

        case .star:
            set([".......",
                 "...#...",
                 "...#...",
                 ".#####.",
                 "...#...",
                 "...#...",
                 "......."])

        case .cross:
            set(["#.....#",
                 ".#...#.",
                 "..#.#..",
                 "...#...",
                 "..#.#..",
                 ".#...#.",
                 "#.....#"])
        }
        return g
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter BadgeTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Prove the four-squares test is load-bearing**

Temporarily change `let step = Int((phase * 4).rounded(.down)) % 4` to `let step = 0`. Re-run: `theRunningBadgeLightsOneQuadrantAtATime` must FAIL on the `seenLeaders.count == 4` assertion. Revert and confirm with `git diff`.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/Cat/Badge.swift Tests/VibeCatUITests/Cat/BadgeTests.swift
git commit -m "feat: the five badges and their motion profiles"
```

---

## Task 5: Motion preference

**Files:**
- Create: `Sources/VibeCatUI/Cat/MotionPreference.swift`
- Test: `Tests/VibeCatUITests/Cat/MotionPreferenceTests.swift`

**Interfaces:**
- Consumes: `MotionProfile` from Task 3.
- Produces: `public enum MotionLevel: String, Sendable, CaseIterable { case full, reduced, off }`; `public struct MotionPreference: Sendable, Equatable` with `public init(chosen: MotionLevel = .full, systemWantsReduced: Bool)`, `public var effective: MotionLevel`, `public func resolve(_ profile: MotionProfile) -> MotionProfile`; and `@MainActor public extension MotionPreference { static func current(chosen: MotionLevel) -> MotionPreference }`.

Design §9.3: Settings offers Full / Reduced / Off and by default follows the system Reduce Motion setting, **which overrides the choice**. Plan 6 owns the Settings UI; this task owns the rule and the system read.

The override is one-directional: the system asking for less motion wins over a user asking for more, but a user choosing `off` is not overridden into motion by a system that does not care.

`resolve` turns a mood's profile into what may actually run:
- `full` — unchanged.
- `reduced` — halve the frame rate, floor 8 fps; keep continuity.
- `off` — `.still`. Nothing animates, which is the 0.0% case.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import VibeCatUI

@Test func withoutASystemPreferenceTheChoiceStands() {
    for level in MotionLevel.allCases {
        #expect(MotionPreference(chosen: level, systemWantsReduced: false).effective == level)
    }
}

/// Design §9.3: the system setting overrides the choice.
@Test func theSystemSettingOverridesAChoiceOfMoreMotion() {
    #expect(MotionPreference(chosen: .full, systemWantsReduced: true).effective == .reduced)
    #expect(MotionPreference(chosen: .reduced, systemWantsReduced: true).effective == .reduced)
}

/// But it does not drag someone who asked for none back into motion.
@Test func theSystemSettingNeverIncreasesMotion() {
    #expect(MotionPreference(chosen: .off, systemWantsReduced: true).effective == .off)
}

@Test func fullLeavesAProfileAlone() {
    let p = MotionPreference(chosen: .full, systemWantsReduced: false)
    let trot = CatMood.trot.motion
    #expect(p.resolve(trot) == trot)
}

@Test func reducedHalvesTheRateButKeepsAnimating() {
    let p = MotionPreference(chosen: .reduced, systemWantsReduced: false)
    let resolved = p.resolve(CatMood.trot.motion)
    #expect(resolved.isContinuous)
    #expect(resolved.framesPerSecond == 8)     // 12 halved is 6, floored to 8
    #expect(resolved.cycle == CatMood.trot.motion.cycle)
}

/// Off is the 0.0% case — nothing may run.
@Test func offStopsEverything() {
    let p = MotionPreference(chosen: .off, systemWantsReduced: false)
    for mood in CatMood.allCases {
        #expect(p.resolve(mood.motion).isContinuous == false)
        #expect(p.resolve(mood.motion).framesPerSecond == 0)
    }
}

/// A profile that was already still stays still at every level.
@Test func aStillProfileIsNeverMadeToMove() {
    for level in MotionLevel.allCases {
        let p = MotionPreference(chosen: level, systemWantsReduced: false)
        #expect(p.resolve(.still).isContinuous == false)
        #expect(p.resolve(CatMood.sleep.motion).isContinuous == false)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter MotionPreferenceTests`
Expected: FAIL — `cannot find 'MotionPreference' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum MotionLevel: String, Sendable, CaseIterable {
    case full, reduced, off
}

/// How much motion is allowed. Design §9.3: Settings offers the three levels
/// and by default follows the system Reduce Motion setting, which overrides
/// the choice.
///
/// The override runs one way only. A system asking for less motion beats a
/// user asking for more; it does not drag a user who chose `off` back into
/// motion, because that is not what "reduce motion" means.
public struct MotionPreference: Sendable, Equatable {
    public let chosen: MotionLevel
    public let systemWantsReduced: Bool

    public init(chosen: MotionLevel = .full, systemWantsReduced: Bool) {
        self.chosen = chosen
        self.systemWantsReduced = systemWantsReduced
    }

    public var effective: MotionLevel {
        guard systemWantsReduced else { return chosen }
        return chosen == .off ? .off : .reduced
    }

    /// The lowest rate worth running. Below this the steps read as stutter
    /// rather than as animation.
    private static let floorFPS: Double = 8

    public func resolve(_ profile: MotionProfile) -> MotionProfile {
        guard profile.isContinuous else { return profile }
        switch effective {
        case .full:
            return profile
        case .reduced:
            return MotionProfile(
                framesPerSecond: max(Self.floorFPS, profile.framesPerSecond / 2),
                cycle: profile.cycle,
                isContinuous: true)
        case .off:
            return .still
        }
    }
}

#if canImport(AppKit)
extension MotionPreference {
    @MainActor public static func current(chosen: MotionLevel = .full) -> MotionPreference {
        MotionPreference(
            chosen: chosen,
            systemWantsReduced: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}
#endif
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter MotionPreferenceTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Prove the one-directional override is load-bearing**

Temporarily change `effective` to `guard systemWantsReduced else { return chosen }; return .reduced`. Re-run: `theSystemSettingNeverIncreasesMotion` must FAIL. Revert and confirm with `git diff`.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/Cat/MotionPreference.swift Tests/VibeCatUITests/Cat/MotionPreferenceTests.swift
git commit -m "feat: motion preference, with the system setting overriding downward only"
```

---

## Task 6: Fixed panel width

**Files:**
- Modify: `Sources/VibeCatUI/IslandGeometry.swift`
- Test: `Tests/VibeCatUITests/IslandGeometryTests.swift`

**Interfaces:**
- Consumes: `IslandGeometry`, `CollapsedLayout` as they stand.
- Produces: `public func maxCollapsedFrames() -> IslandFrames` on `IslandGeometry`, and `public static let hoverReveal: CGFloat = 150` on `CollapsedLayout` (promoting the existing private constant).

The spike measured content animation as meaningfully smoother than window-frame animation — p95 `10.34ms` against `15.16ms`, worst `10.41` against `16.93`. So the panel stops resizing: it is created once at the widest collapsed state it can reach, and the silhouette's width animates inside it.

The widest collapsed state is a three-digit session count, hovered: `leftFlank + notch + (padding + 3 digits) + hoverReveal`, plus the aura margin on both sides.

This is only safe because the collapsed island is click-through — a larger transparent window intercepts nothing. **It stops being safe the moment the drawer takes mouse events**, so Plan 4 must size the panel to what the drawer actually covers. Leave a comment saying so.

The island's left edge is unaffected: the panel's origin stays at `body.minX - auraMargin` and the extra width extends rightward.

- [ ] **Step 1: Write the failing test**

Append to `Tests/VibeCatUITests/IslandGeometryTests.swift`:

```swift
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
        #expect(f.body.maxX <= maxFrames.body.maxX + 0.001)
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter IslandGeometryTests`
Expected: FAIL — `value of type 'IslandGeometry' has no member 'maxCollapsedFrames'`.

- [ ] **Step 3: Promote `hoverReveal` and add the maximum**

In `CollapsedLayout`, change `private static let hoverReveal: CGFloat = 150` to `public static let hoverReveal: CGFloat = 150`.

Add to `IslandGeometry`:

```swift
    /// The widest the collapsed island can ever be: a three-digit session
    /// count, hovered.
    ///
    /// The panel is created once at this size and never resized — measured,
    /// animating the silhouette inside a fixed window has a p95 of 10.34ms
    /// against 15.16ms for moving the window itself, and a far shorter tail.
    ///
    /// This is only safe while the island is click-through: an oversized
    /// transparent window intercepts nothing. Plan 4's drawer takes mouse
    /// events, so it must size the panel to what it actually covers.
    public func maxCollapsedFrames() -> IslandFrames {
        let widest = CollapsedLayout(right: .sessionCount(999), hovering: true)
        return frames(rightFlank: widest.rightFlankWidth, tier: .rest)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter IslandGeometryTests`
Expected: PASS — the existing tests plus 3 new.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatUI/IslandGeometry.swift Tests/VibeCatUITests/IslandGeometryTests.swift
git commit -m "feat: a fixed maximum collapsed panel, so content animates instead of the window"
```

---

## Task 7: Observable island state

**Files:**
- Create: `Sources/VibeCatUI/IslandModel.swift`
- Test: `Tests/VibeCatUITests/IslandModelTests.swift`

**Interfaces:**
- Consumes: `IslandState`, `CollapsedLayout`, `IslandGeometry`, `IslandFrames`, `AuraTrigger`, `Coat`, `CatMood`, `Badge`, `MotionPreference`, `MotionProfile`.
- Produces: `@MainActor @Observable public final class IslandModel` with `public init(geometry: IslandGeometry, coat: Coat = .tabby, motion: MotionPreference)`, `public var state: IslandState`, `public var sessionCount: Int`, `public var hovering: Bool`, `public var geometry: IslandGeometry`, `public var aura: AuraTrigger`, `public var coat: Coat`, `public var motion: MotionPreference`, and the derived `public var layout: CollapsedLayout`, `public var frames: IslandFrames`, `public var mood: CatMood`, `public var badge: Badge`, `public var activeProfile: MotionProfile`, `public var needsTimeline: Bool`.

The spike's fourth finding: `NotchController.render()` builds a fresh `IslandView` and assigns `NSHostingView.rootView` on every change. That is survivable at Plan 2's handful of renders per second and fatal at sprite rates. The fix is to hand SwiftUI an observable object once and let the view read it.

`needsTimeline` is the switch that reaches 0.0%: true only when the cat's or the badge's resolved profile is continuous, **or** an aura bloom is in flight.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
import CoreGraphics
@testable import VibeCatUI

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private let mbp14 = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
    safeAreaTop: 32,
    auxLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
    auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))

@MainActor private func model(_ state: IslandState = .dormant,
                              count: Int = 0,
                              motion: MotionLevel = .full) -> IslandModel {
    let m = IslandModel(geometry: IslandGeometry(screen: mbp14),
                        motion: MotionPreference(chosen: motion, systemWantsReduced: false))
    m.state = state
    m.sessionCount = count
    return m
}

@MainActor @Test func theModelDerivesMoodAndBadgeFromState() {
    let m = model(.running, count: 1)
    #expect(m.mood == .trot)
    #expect(m.badge == .squares)
}

@MainActor @Test func theModelDerivesTheLayoutFromTheSessionCount() {
    #expect(model(.dormant, count: 0).layout.rightFlankWidth == 0)
    #expect(model(.running, count: 2).layout.rightFlankWidth > 0)
}

/// The switch that reaches 0.0% CPU.
@MainActor @Test func aSteadyStateNeedsNoTimeline() {
    // NOT .dormant — its zzz badge drifts even though the cat is still, so a
    // dormant island genuinely does need a timeline. Asserting otherwise here
    // contradicted the very next test. Corrected during execution.
    #expect(model(.failed, count: 1).needsTimeline == false)
    #expect(model(.idle, count: 1).needsTimeline == false)
}

@MainActor @Test func anActiveStateNeedsATimeline() {
    #expect(model(.running, count: 1).needsTimeline)
    #expect(model(.waiting, count: 1).needsTimeline)
}

/// Dormant's badge is a drifting zzz, which does animate even though the cat
/// does not — so the timeline decision must consider both.
@MainActor @Test func aStillCatWithADriftingBadgeStillNeedsATimeline() {
    #expect(CatMood.sleep.motion.isContinuous == false)
    #expect(Badge.zzz.motion.isContinuous)
    let m = model(.dormant)
    m.coat = .tabby
    // The badge alone is enough to require redraws.
    #expect(m.activeProfile.isContinuous == Badge.zzz.motion.isContinuous)
}

/// A bloom must keep the timeline alive even in a steady state.
@MainActor @Test func anAuraInFlightNeedsATimeline() {
    let m = model(.failed, count: 1)
    #expect(m.needsTimeline == false)
    var aura = AuraTrigger()
    _ = aura.observe(.idle, now: t0)
    _ = aura.observe(.failed, now: Date())
    m.aura = aura
    #expect(m.needsTimeline)
}

/// Motion off is the 0.0% case, whatever the state.
@MainActor @Test func motionOffNeedsNoTimelineInAnyState() {
    for state in IslandState.allCases {
        let m = model(state, count: 1, motion: .off)
        // The aura must genuinely be blooming. A fresh AuraTrigger() makes this
        // test vacuous: with motion off, `resolve` already forces the mood and
        // badge paths still, so without a live bloom the assertion holds whether
        // or not the `.off` guard exists — and Step 5's proof proves nothing.
        var blooming = AuraTrigger()
        _ = blooming.observe(.idle, now: Date())
        _ = blooming.observe(state == .idle ? .failed : .idle, now: Date())
        m.aura = blooming
        #expect(m.needsTimeline == false, "\(state) still wants a timeline with motion off")
    }
}

@MainActor @Test func hoveringWidensTheDerivedLayout() {
    let m = model(.running, count: 2)
    let rest = m.layout.rightFlankWidth
    m.hovering = true
    #expect(m.layout.rightFlankWidth == rest + CollapsedLayout.hoverReveal)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter IslandModelTests`
Expected: FAIL — `cannot find 'IslandModel' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation
import Observation

/// Everything the island view reads, in one observable place.
///
/// This exists because the previous render path assigned a freshly built
/// SwiftUI tree to `NSHostingView.rootView` on every change. That survives a
/// handful of renders per second and nothing more; at sprite rates it is the
/// dominant cost. The hosting view's root is now assigned once and reads this.
@MainActor @Observable public final class IslandModel {
    public var state: IslandState = .dormant
    public var sessionCount: Int = 0
    public var hovering: Bool = false
    public var geometry: IslandGeometry
    public var aura = AuraTrigger()
    public var coat: Coat
    public var motion: MotionPreference

    public init(geometry: IslandGeometry, coat: Coat = .tabby, motion: MotionPreference) {
        self.geometry = geometry
        self.coat = coat
        self.motion = motion
    }

    public var layout: CollapsedLayout {
        CollapsedLayout(right: sessionCount > 0 ? .sessionCount(sessionCount) : .nothing,
                        hovering: hovering)
    }

    public var frames: IslandFrames {
        geometry.frames(rightFlank: layout.rightFlankWidth, tier: .rest)
    }

    /// The panel never resizes, so the view lays out against this.
    public var panelFrames: IslandFrames { geometry.maxCollapsedFrames() }

    public var mood: CatMood { CatMood(state: state) }
    public var badge: Badge { Badge(state: state) }

    /// Whichever of the cat and the badge wants redrawing more often.
    public var activeProfile: MotionProfile {
        let cat = motion.resolve(mood.motion)
        let badge = motion.resolve(self.badge.motion)
        if cat.isContinuous && badge.isContinuous {
            return cat.framesPerSecond >= badge.framesPerSecond ? cat : badge
        }
        return cat.isContinuous ? cat : badge
    }

    /// True only when something genuinely needs per-frame redraws. Measured: a
    /// live timeline costs ~6% of a core even at 8 fps, and removing it costs
    /// 0.0% — so this is the only thing that makes an idle machine idle.
    public var needsTimeline: Bool {
        if motion.effective == .off { return false }
        if activeProfile.isContinuous { return true }
        return aura.isBlooming(at: Date())
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter IslandModelTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Prove the motion-off short circuit is load-bearing**

Temporarily remove `if motion.effective == .off { return false }`. Re-run: `motionOffNeedsNoTimelineInAnyState` must FAIL. Revert and confirm with `git diff`.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/IslandModel.swift Tests/VibeCatUITests/IslandModelTests.swift
git commit -m "feat: observable island model, so the hosting root is assigned once"
```

---

## Task 8: The cat and badge canvases

**Files:**
- Create: `Sources/VibeCatUI/Cat/CatCanvas.swift`
- Create: `Sources/VibeCatUI/Cat/BadgeCanvas.swift`
- Test: `Tests/VibeCatUITests/Cat/CanvasTests.swift`

**Interfaces:**
- Consumes: `ResolvedCat`, `CatPalette`, `Badge`, `RGBA`, `Tone`.
- Produces: `public struct CatCanvas: View` with `public init(cat: ResolvedCat, palette: CatPalette, cellSize: CGFloat)`; `public struct BadgeCanvas: View` with `public init(badge: Badge, phase: Double, tint: RGBA, cellSize: CGFloat)`.

> **Corrected during execution.** The Step 3 code below puts the per-cell walk
> *inside* the `Canvas` renderer closure. That closure is `@escaping` and does
> not run when a test merely evaluates `.body` — so all four smoke tests would
> have caught nothing. Proven by mutation: an injected out-of-bounds index
> crashes when the walk is eager and produces zero failures when it sits in the
> closure. **What shipped hoists the walk into a private eager property**, so
> only `ctx.fill` remains inside the closure and the tests genuinely execute the
> code they cover. This is the same mechanism as Plan 2's `TimelineView` split;
> see `CatCanvas.swift` and `BadgeCanvas.swift` for the shipped shape.

Both draw with `Canvas`. The spike found path batching makes no measurable difference at any rate — the cost is per-frame overhead, not the fills — so draw the clearest way rather than the cleverest: one `fill` per cell for the cat, grouped by tone only because that is fewer colour switches, not because it is faster.

Cells are drawn on integer boundaries. Pixel art must land on the pixel grid; a fractional origin blurs every edge.

Like Task 8 of Plan 2, these tests assert nothing about appearance. They evaluate the body across every combination and catch a trap — an index out of range on a coat that repaints past the grid, a missing tone, a nil palette entry.

- [ ] **Step 1: Write the failing test**

```swift
import SwiftUI
import Testing
import CoreGraphics
@testable import VibeCatUI

@MainActor @Test func theCatCanvasEvaluatesForEveryCoatMoodAndPhase() {
    let palette = CatPalette(accent: IslandState.running.accent)
    for coat in Coat.allCases {
        for mood in CatMood.allCases {
            for i in 0...4 {
                let cat = ResolvedCat(coat: coat, mood: mood, phase: Double(i) / 4.0)
                _ = CatCanvas(cat: cat, palette: palette, cellSize: 1).body
            }
        }
    }
}

@MainActor @Test func theCatCanvasEvaluatesForEveryStatesPalette() {
    for state in IslandState.allCases {
        let cat = ResolvedCat(coat: .tabby, mood: CatMood(state: state), phase: 0.5)
        _ = CatCanvas(cat: cat, palette: CatPalette(accent: state.accent), cellSize: 1).body
    }
}

@MainActor @Test func theBadgeCanvasEvaluatesForEveryBadgeAndPhase() {
    for badge in Badge.allCases {
        for i in 0...4 {
            _ = BadgeCanvas(badge: badge, phase: Double(i) / 4.0,
                            tint: IslandState.waiting.accent, cellSize: 2).body
        }
    }
}

/// A zero or negative cell size must not trap.
@MainActor @Test func aDegenerateCellSizeDoesNotTrap() {
    let cat = ResolvedCat(coat: .tabby, mood: .trot, phase: 0)
    let palette = CatPalette(accent: IslandState.idle.accent)
    _ = CatCanvas(cat: cat, palette: palette, cellSize: 0).body
    _ = BadgeCanvas(badge: .bang, phase: 0, tint: IslandState.idle.accent, cellSize: 0).body
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CanvasTests`
Expected: FAIL — `cannot find 'CatCanvas' in scope`.

- [ ] **Step 3: Write the implementations**

`CatCanvas.swift`:

```swift
import SwiftUI

/// Draws a resolved cat.
///
/// The spike found path batching makes no measurable difference — 20.3% batched
/// against 20.5% unbatched at the same rate, because the cost is per-frame
/// overhead and not the fills. So this draws the clear way. Grouping by tone is
/// for fewer colour switches, not for speed.
public struct CatCanvas: View {
    public let cat: ResolvedCat
    public let palette: CatPalette
    public let cellSize: CGFloat

    public init(cat: ResolvedCat, palette: CatPalette, cellSize: CGFloat) {
        self.cat = cat
        self.palette = palette
        self.cellSize = cellSize
    }

    public var body: some View {
        Canvas { ctx, _ in
            guard cellSize > 0 else { return }
            let dy = CGFloat(cat.verticalOffset) * cellSize
            var byTone: [Tone: Path] = [:]
            for (row, line) in cat.cells.enumerated() {
                for (col, tone) in line.enumerated() {
                    guard let tone else { continue }
                    // Integer boundaries — pixel art must land on the grid.
                    let rect = CGRect(x: (CGFloat(col) * cellSize).rounded(),
                                      y: (CGFloat(row) * cellSize + dy).rounded(),
                                      width: cellSize, height: cellSize)
                    byTone[tone, default: Path()].addRect(rect)
                }
            }
            for (tone, path) in byTone {
                ctx.fill(path, with: .color(Color(palette[tone])))
            }
        }
        .frame(width: CGFloat(CatGrid.width) * cellSize,
               height: CGFloat(CatGrid.height) * cellSize)
    }
}
```

`BadgeCanvas.swift`:

```swift
import SwiftUI

/// Draws a badge inside the fixed box. Monochrome, tinted with the state
/// accent — the badge carries state colour like everything else.
public struct BadgeCanvas: View {
    public let badge: Badge
    public let phase: Double
    public let tint: RGBA
    public let cellSize: CGFloat

    public init(badge: Badge, phase: Double, tint: RGBA, cellSize: CGFloat) {
        self.badge = badge
        self.phase = phase
        self.tint = tint
        self.cellSize = cellSize
    }

    public var body: some View {
        Canvas { ctx, _ in
            guard cellSize > 0 else { return }
            var path = Path()
            for (row, line) in badge.cells(at: phase).enumerated() {
                for (col, lit) in line.enumerated() where lit {
                    path.addRect(CGRect(x: (CGFloat(col) * cellSize).rounded(),
                                        y: (CGFloat(row) * cellSize).rounded(),
                                        width: cellSize, height: cellSize))
                }
            }
            ctx.fill(path, with: .color(Color(tint)))
        }
        .frame(width: CGFloat(Badge.size) * cellSize,
               height: CGFloat(Badge.size) * cellSize)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CanvasTests`
Expected: PASS, 4 tests. Then `swift build && swift test` — the whole suite green.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatUI/Cat/CatCanvas.swift Sources/VibeCatUI/Cat/BadgeCanvas.swift \
        Tests/VibeCatUITests/Cat/CanvasTests.swift
git commit -m "feat: canvases for the cat and the badge"
```

---

## Task 9: The island view, restructured

**Files:**
- Modify: `Sources/VibeCatUI/IslandView.swift`
- Modify: `Sources/VibeCatUI/NotchController.swift`
- Test: `Tests/VibeCatUITests/IslandViewTests.swift`
- Test: `Tests/VibeCatUITests/NotchControllerTests.swift`

**Interfaces:**
- Consumes: `IslandModel` from Task 7, `CatCanvas` and `BadgeCanvas` from Task 8, `CollapsedLayout.hoverReveal`.
- Produces: `public struct IslandView: View` with `public init(model: IslandModel)` — replacing the six-parameter initialiser; and on `NotchController`, `public var model: IslandModel { get }`.

This is where the architecture changes. Today:

```swift
let view = IslandView(state: ..., layout: ..., aura: ..., now: ..., geometry: ..., frames: ...)
if let hosting = panel.contentView as? NSHostingView<IslandView> { hosting.rootView = view }
```

After: the controller builds one `IslandModel`, hands it to one `IslandView`, assigns `rootView` **once** in `present()`, and thereafter only mutates the model. `reflow()` stops touching the view at all — it updates `model.state`, `model.sessionCount`, `model.hovering` and `model.aura`, and SwiftUI does the rest.

The panel is created at `geometry.maxCollapsedFrames().panel` and **never resized while collapsed**. The silhouette's width comes from `model.frames.body.width` and animates with the design's spring.

Inside the view:

- The whole body is wrapped in a `TimelineView` **only when `model.needsTimeline`**; otherwise it renders once, statically. That is the 0.0% path and it must be a real branch, not a paused timeline — measured, a paused-but-present timeline still costs ~6%.
- The timeline's `minimumInterval` is `1 / model.activeProfile.framesPerSecond`, never the display rate.
- Width changes animate with `.spring(response: 0.42, dampingFraction: 0.72)`.
- The hover reveal is `.easeOut(duration: 0.28)` — design §9.1's `280ms`.

- [ ] **Step 1: Write the failing test**

Replace the smoke tests in `IslandViewTests.swift` with model-driven ones, and add the controller assertions:

```swift
@MainActor private func islandModel(_ state: IslandState, count: Int,
                                    hovering: Bool = false,
                                    motion: MotionLevel = .full) -> IslandModel {
    let m = IslandModel(geometry: IslandGeometry(screen: mbp14),
                        motion: MotionPreference(chosen: motion, systemWantsReduced: false))
    m.state = state
    m.sessionCount = count
    m.hovering = hovering
    return m
}

@MainActor @Test func theViewEvaluatesForEveryStateAndCoat() {
    for state in IslandState.allCases {
        for coat in Coat.allCases {
            let m = islandModel(state, count: state == .dormant ? 0 : 2)
            m.coat = coat
            _ = IslandView(model: m).body
        }
    }
}

@MainActor @Test func theViewEvaluatesHoveredAndWithMotionOff() {
    _ = IslandView(model: islandModel(.running, count: 3, hovering: true)).body
    _ = IslandView(model: islandModel(.running, count: 3, motion: .off)).body
}

@MainActor @Test func theViewEvaluatesOnTheFallbackPill() {
    let m = IslandModel(geometry: IslandGeometry(screen: externalDisplay),
                        motion: MotionPreference(chosen: .full, systemWantsReduced: false))
    _ = IslandView(model: m).body
}
```

And in `NotchControllerTests.swift`:

```swift
/// The spike's fourth finding: the hosting root must be assigned once, not
/// rebuilt per change. If a later refactor reintroduces per-change assignment
/// this catches it, because the hosting view's identity would change.
@MainActor @Test func theHostingRootIsAssignedOnceAndSurvivesStateChanges() throws {
    let model = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    let c = NotchController(model: model, metrics: { mbp14 })
    c.refreshGeometry()
    c.present()

    let panel = try #require(c.panelForTesting)
    let first = try #require(panel.contentView)
    model.ingest(VibeEvent(id: "e1", cli: "claude-code", kind: .running,
                           session: "a", cwd: "/dev/a"), now: t0)
    model.ingest(VibeEvent(id: "e2", cli: "claude-code", kind: .permission,
                           session: "b", cwd: "/dev/b"), now: t0)
    #expect(panel.contentView === first, "the hosting view was replaced")
    c.dismiss()
}

/// The panel is created once at its widest and never resized while collapsed.
@MainActor @Test func thePanelDoesNotResizeAsTheIslandGrows() throws {
    let model = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    let c = NotchController(model: model, metrics: { mbp14 })
    c.refreshGeometry()
    c.present()

    let panel = try #require(c.panelForTesting)
    let before = panel.frame
    model.ingest(VibeEvent(id: "e1", cli: "claude-code", kind: .running,
                           session: "a", cwd: "/dev/a"), now: t0)
    #expect(panel.frame == before, "the panel resized; content should animate instead")
    c.dismiss()
}

/// The controller's model must actually track the app model.
@MainActor @Test func ingestingAnEventUpdatesTheIslandModel() {
    let model = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    let c = NotchController(model: model, metrics: { mbp14 })
    c.refreshGeometry()
    c.present()
    #expect(c.model.state == .dormant)
    model.ingest(VibeEvent(id: "e1", cli: "claude-code", kind: .running,
                           session: "a", cwd: "/dev/a"), now: t0)
    #expect(c.model.state == .running)
    #expect(c.model.sessionCount == 1)
    c.dismiss()
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter IslandViewTests` and `swift test --filter NotchControllerTests`
Expected: FAIL — `IslandView` has no `init(model:)`, `NotchController` has no `model`.

- [ ] **Step 3: Restructure `IslandView`**

```swift
public struct IslandView: View {
    private let model: IslandModel

    public init(model: IslandModel) { self.model = model }

    public var body: some View {
        // A real branch, not a paused timeline. Measured: a paused-but-present
        // TimelineView still costs ~6% of a core; removing it costs 0.0%.
        if model.needsTimeline {
            TimelineView(.animation(minimumInterval: 1.0 / model.activeProfile.framesPerSecond,
                                    paused: false)) { ctx in
                IslandBody(model: model, now: ctx.date)
            }
        } else {
            IslandBody(model: model, now: Date())
        }
    }
}

struct IslandBody: View {
    let model: IslandModel
    let now: Date

    private var accent: Color { Color(model.state.accent) }

    /// 0…1 through the current mood's cycle.
    private var phase: Double {
        let cycle = model.mood.motion.cycle
        guard cycle > 0 else { return 0 }
        return now.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycle) / cycle
    }

    var body: some View {
        let panel = model.panelFrames
        let body = model.frames.body
        let localX = body.minX - panel.panel.minX
        let cell: CGFloat = 1

        ZStack(alignment: .topLeading) {
            Color.clear
            IslandShape()
                .fill(Color(islandGroundColour))
                .overlay(alignment: .topLeading) { content(cell: cell) }
                .clipShape(IslandShape())
                .shadow(color: accent.opacity(model.aura.opacity(at: now)),
                        radius: 18, x: 0, y: 2)
                .frame(width: body.width, height: body.height)
                .offset(x: localX, y: 0)
                // Design §9.1. Width overshoots more than height so the island
                // reads as one body with mass rather than a resizing box.
                .animation(.spring(response: 0.42, dampingFraction: 0.72),
                           value: body.width)
        }
        .frame(width: panel.panel.width, height: panel.panel.height,
               alignment: .topLeading)
    }

    @ViewBuilder private func content(cell: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: LeftFlankLayout.gap) {
                CatCanvas(cat: ResolvedCat(coat: model.coat, mood: model.mood, phase: phase),
                          palette: CatPalette(accent: model.state.accent),
                          cellSize: cell)
                    .frame(width: LeftFlankLayout.catWidth, height: 14)
                BadgeCanvas(badge: model.badge, phase: phase,
                            tint: model.state.accent, cellSize: 2)
                    .frame(width: LeftFlankLayout.badgeWidth,
                           height: LeftFlankLayout.badgeWidth)
            }
            .padding(.leading, LeftFlankLayout.leadingPadding)
            .padding(.trailing, LeftFlankLayout.trailingPadding)

            Color.clear.frame(width: model.geometry.notch.width)

            rightFlank
        }
        .frame(height: model.geometry.notch.height)
    }

    @ViewBuilder private var rightFlank: some View {
        switch model.layout.right {
        case .nothing:
            EmptyView()
        case .agentIcon:
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: CollapsedLayout.iconWidth, height: 14)
                .padding(.horizontal, RightFlankLayout.iconPadding)
        case let .sessionCount(n) where n > 0:
            Text(String(n))
                .font(RightFlankFont.swiftUI)
                .monospacedDigit()
                .foregroundStyle(accent)
                .padding(.leading, RightFlankLayout.leadingPadding)
                .padding(.trailing, RightFlankLayout.trailingPadding)
        case .sessionCount:
            EmptyView()
        }
    }
}
```

`LeftFlankLayout`, `RightFlankLayout`, `RightFlankFont` and `islandGroundColour` already exist in this file and are unchanged — only their consumer moves from stored properties to `model`.

- [ ] **Step 4: Restructure `NotchController`**

Note the naming collision this creates and do not let it bite: `NotchController` already has `private let model: AppModel`. Rename that stored property to `appModel` throughout, and let `model` be the new `IslandModel` the view reads. Leaving both named `model` is how a later edit silently wires the wrong one.

```swift
    /// The one object the view reads. Built here, handed to SwiftUI once, and
    /// mutated thereafter — never rebuilt into a fresh view tree.
    public private(set) var model: IslandModel

    public init(appModel: AppModel, metrics: @escaping @MainActor () -> ScreenMetrics?) {
        self.appModel = appModel
        self.metrics = metrics
        let geometry = IslandGeometry(screen: metrics() ?? .zeroFallback)
        self.model = IslandModel(geometry: geometry, motion: MotionPreference.current())
    }
```

In `refreshGeometry()`, update the existing model's geometry rather than replacing the object — a fresh `IslandModel` would break the observation SwiftUI already established:

```swift
    public func refreshGeometry() {
        geometry = metrics().map(IslandGeometry.init(screen:))
        guard let geometry else { return }
        model.geometry = geometry
        panel?.apply(geometry.maxCollapsedFrames())
        hover?.frame = model.frames.body
    }
```

In `present()`, size the panel from the fixed maximum and assign the root **once**:

```swift
        guard let geometry else { return }
        let frames = geometry.maxCollapsedFrames()
        let panel = self.panel ?? NotchPanel(frames: frames)
        self.panel = panel
        panel.apply(frames)
        if panel.contentView == nil {
            panel.contentView = NSHostingView(rootView: IslandView(model: model))
        }
```

`render()` becomes model mutation only — no view construction, no `rootView` assignment, no `NSHostingView` cast:

```swift
    private func render() {
        let now = Date()
        model.state = appModel.islandState
        model.sessionCount = appModel.sessionCount

        if model.aura.observe(model.state, now: now) {
            // needsTimeline reads the aura, so the view must be nudged once
            // more when the bloom ends or the timeline never stops.
            bloomEnd?.cancel()
            bloomEnd = Task { [weak self] in
                try? await Task.sleep(for: .seconds(AuraTrigger.duration))
                guard !Task.isCancelled else { return }
                self?.model.aura = self?.model.aura ?? AuraTrigger()
            }
        }
    }
```

`reflow()` stops resizing the panel — that is the whole point of the fixed frame:

```swift
    private func reflow() {
        model.hovering = (tier == .hover)
        hover?.frame = model.frames.body
        render()
    }
```

`.zeroFallback` does not exist yet. Add it to `ScreenMetrics` as a `public static let` with a zero frame and no notch, so the controller has something to build a geometry from before `refreshGeometry()` runs. Give it a doc comment saying it is a placeholder that `refreshGeometry()` immediately replaces.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test`
Expected: the whole suite green. Existing `NotchControllerTests` that asserted the panel frame *changes* on ingest will now fail — that is the intended behavioural change, so update them to assert the **body** width changed while the **panel** frame did not. Say so in the report.

- [ ] **Step 6: Prove the once-only assignment is load-bearing**

Temporarily reinstate a `panel.contentView = NSHostingView(rootView: IslandView(model: model))` line at the end of `render()`. Re-run: `theHostingRootIsAssignedOnceAndSurvivesStateChanges` must FAIL. Revert and confirm with `git diff`.

- [ ] **Step 7: Commit**

```bash
git add Sources/VibeCatUI/IslandView.swift Sources/VibeCatUI/NotchController.swift \
        Tests/VibeCatUITests/IslandViewTests.swift Tests/VibeCatUITests/NotchControllerTests.swift
git commit -m "feat: the cat in the island, with the hosting root assigned once"
```

---

## Task 10: Hover on a dormant island, and end-to-end verification

**Files:**
- Modify: `Sources/VibeCatUI/IslandGeometry.swift` — `CollapsedLayout.rightFlankWidth`
- Test: `Tests/VibeCatUITests/CollapsedLayoutTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: no new API.

Measured on the running app: hover works and widens the island by exactly `+150pt` — but only when there is a session. `rightFlankWidth` hits `guard content > 0 else { return 0 }` and returns before it ever consults `hovering`, so on a dormant island hover is a guaranteed no-op. Someone hovering an idle machine sees nothing happen and concludes the feature is broken.

With the cat now present there *is* something to reveal at rest, so the guard should let the reveal through. The rule becomes: an empty right flank stays empty at rest, but hovering always opens the reveal.

- [ ] **Step 1: Write the failing test**

```swift
/// Measured on the running app: hover was a guaranteed no-op while dormant,
/// because rightFlankWidth returned before it looked at `hovering`.
@Test func hoveringOpensTheRevealEvenWithNoRightContent() {
    let rest = CollapsedLayout(right: .nothing, hovering: false)
    let hovered = CollapsedLayout(right: .nothing, hovering: true)
    #expect(rest.rightFlankWidth == 0)
    #expect(hovered.rightFlankWidth == CollapsedLayout.hoverReveal)
}

@Test func hoveringStillAddsTheRevealOnTopOfRealContent() {
    let rest = CollapsedLayout(right: .sessionCount(2), hovering: false)
    let hovered = CollapsedLayout(right: .sessionCount(2), hovering: true)
    #expect(hovered.rightFlankWidth == rest.rightFlankWidth + CollapsedLayout.hoverReveal)
}

@Test func aZeroCountStillShowsNothingAtRest() {
    #expect(CollapsedLayout(right: .sessionCount(0), hovering: false).rightFlankWidth == 0)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CollapsedLayoutTests`
Expected: FAIL — `hoveringOpensTheRevealEvenWithNoRightContent` expects 150, gets 0.

- [ ] **Step 3: Change the guard**

```swift
    public var rightFlankWidth: CGFloat {
        let content: CGFloat = switch right {
        case .nothing: 0
        case .agentIcon: Self.iconWidth
        case let .sessionCount(n):
            n <= 0 ? 0 : CGFloat(String(n).count) * metrics.digitWidth
        }
        let reveal = hovering ? Self.hoverReveal : 0
        // An empty flank stays empty at rest — the island never reserves space
        // it is not using. But hovering always opens the reveal: returning
        // early here made hover a guaranteed no-op on a dormant island, which
        // reads as the feature being broken.
        guard content > 0 else { return reveal }
        return Self.padding + content + reveal
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test`
Expected: the whole suite green. `nothingOnTheRightMeansNoRightFlankAndNoContent` may need its hovering case checked — confirm it asserts the resting case.

- [ ] **Step 5: Verify by hand, end to end**

```bash
swift build
VIBECAT_SOCKET=/tmp/vibecat-dev.sock swift run vibecat
```

In a second terminal:

```bash
VIBECAT_SOCKET=/tmp/vibecat-dev.sock Scripts/replay.sh permission
```

Check each, and record what you saw:

1. A sleeping cat sits in the left flank, tinted green, with a drifting `zzz` beside it in a fixed box.
2. On the `permission` event the cat sits up as `call`, everything turns amber, the badge becomes a pulsing `!`, and the session count reads `1`.
3. The island widens to fit the count with a spring, and **the window itself does not jump** — the shape grows inside it.
4. An aura blooms once on the change and fades to nothing.
5. Hovering for a third of a second opens the reveal — **including on a dormant island**, which is the fix in this task.
6. Clicking a menu title under the island's left flank still opens that menu.
7. The cat never moves by a fraction of a pixel — every step is a whole cell.

- [ ] **Step 6: Verify the CPU budget**

The number that decides whether this shipped correctly. With the app running and **no events**, sample `vibecat` in Activity Monitor or with `ps -o %cpu=`:

- **Dormant** (sleeping cat, drifting `zzz`): the badge animates at 8 fps, so expect **~6%**. If it is near 20%, something is running at the display rate — check that `minimumInterval` is set.
- **After a `done` event settles to idle** (`happy` cat, static star, no aura): expect **0.0%**. Anything above ~1% means a timeline is running that should not be — `needsTimeline` is the thing to check.
- **Running** (`trot` at 12 fps): expect **~6–9%**.

Record all three. A non-zero idle figure is a failure of this plan's central constraint, not a rounding error.

- [ ] **Step 7: Commit**

```bash
git add Sources/VibeCatUI/IslandGeometry.swift Tests/VibeCatUITests/CollapsedLayoutTests.swift
git commit -m "fix: hover opens the reveal on a dormant island too"
```

---

## Self-Review

**Spec coverage.** §7.1 sprite grid and tone ramp → Tasks 1, 2. §7.2 five moods, eyes, the instantaneous blink → Task 3. §7.3 five coats, markings-not-hue, eyes-win ordering → Tasks 2, 3. §8 five badges, the fixed 14pt box, the four-squares rationale → Task 4. §9.1 width spring `0.42/0.72`, hover reveal `280ms`/`150pt` → Tasks 6, 9, 10. §9.2 aura → already shipped in Plan 2; Task 7 keeps it alive through `needsTimeline`. §9.3 reduced motion → Task 5 (the rule and the system read; the Settings control is Plan 6).

**Deliberately out of scope**, each deferred to a named plan: the drawer's contents and answering (§6.3, §10, Plan 4); the session list (§11, Plan 5); sound (§12), jump (§13) and all of Settings (§14, Plan 6), including the Full/Reduced/Off control whose *rule* Task 5 implements. The drawer-height spring `0.42/0.78` is specified in Global Constraints but has nothing to animate until Plan 4 opens a drawer — it is not implemented here.

**Three carried findings this plan closes.** The animation spike's "rebuilding `rootView` every frame is the wrong architecture" → Tasks 7 and 9. Its "animate content, not the window" → Tasks 6 and 9. And the measured dormant-hover no-op → Task 10.

**Two risks carried into execution.** The fixed maximum panel is only safe while the island is click-through; Plan 4's drawer takes mouse events and must size the panel to what it covers — Task 6 says so in a comment, but nothing enforces it. And the ~6% floor for a live timeline is measured on mains power on a 120 Hz built-in display; battery and 60 Hz external displays are unmeasured, and if the floor proves too expensive the spike names `drawingGroup()` as the next thing to try.

**One judgement call worth flagging to the human.** Design §7.2 gives `sleep` a "slow drowse, 3s" and `dead` a "slow wobble, 2.4s", which are animations — but the spike says any live timeline costs ~6% of a core, and dormant is the state a machine sits in all day. Task 3 resolves this by making both moods still, keeping their cycle lengths in the profile so they can be turned back on cheaply. The dormant island still animates, because the `zzz` badge drifts; the cat itself does not. If that reads as too static once it is on screen, the fix is one line in `CatMood.motion`.
