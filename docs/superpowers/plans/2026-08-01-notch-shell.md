# Notch Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put a correctly shaped, correctly positioned, state-coloured island in the notch that reacts to real hook events and to hover.

**Architecture:** A borderless non-activating `NSPanel` pinned over the menu bar at level 25, hosting SwiftUI through `NSHostingView`. All geometry, state and hover logic lives in pure value types in a `VibeCatUI` library so it is unit-testable without a window server; the executable target is wiring only, mirroring how `VibeCatHookKit` and `VibeCatHook` are split in Plan 1. Events arrive on the existing `SocketServer` and land in the existing `SessionStore`.

**Tech Stack:** Swift 6 (language mode v6), SwiftUI + AppKit interop, swift-testing. No external dependencies.

**Scope:** The shell only. Left-flank content is a placeholder rectangle — the cat sprite is Plan 3. The drawer opens to an empty face — answering is Plan 4 and the session list is Plan 5. Nothing here reads or writes settings — that is Plan 6.

**Prerequisite reading:** [the notch shell spike](../spikes/2026-08-01-notch-shell-spike.md). Every AppKit value in this plan was measured there, not assumed. Sections 5, 6 and 9 of [the design doc](../specs/2026-07-31-vibecat-design.md) are the source for the visual numbers.

## Global Constraints

- Swift 6 language mode, `platforms: [.macOS(.v14)]`, **no external dependencies**.
- Tests use **swift-testing** (`import Testing`, `@Test`, `#expect`, `#require`) — never XCTest.
- Window level is exactly `.statusBar` (raw 25). The menu bar is layer 24; 24 and below lose to it. Higher levels buy nothing and start fighting menus and alerts.
- **`isFloatingPanel = true` must be assigned before `level`.** Its setter reassigns `level` to `.floating` (3) as a side effect, silently undoing the line above. Pin it with a test.
- `NotchPanel.constrainFrameRect(_:to:)` **must not call `super`**. At level 25 AppKit does not clamp, so this changes nothing on the happy path — it is a backstop for the case where the level is wrong, which turns a wrong-level bug into a wrong-level-*and*-displaced-33pt bug. See spike §2.
- The collapsed island sets `ignoresMouseEvents = true`. A menu title can reach within ~30pt of the island's left edge, and an opaque flank eats its clicks.
- Hover is detected by sampling `NSEvent.mouseLocation`, never by `NSTrackingArea` — a click-through window receives no events for a tracking area to observe.
- Show the panel with `orderFrontRegardless()`, never `makeKeyAndOrderFront(_:)`. The app must never steal focus.
- Never gate rendering, animation or polling on `occlusionState` — it reports `false` for this panel while it is demonstrably frontmost.
- Geometry is always derived from `NSScreen`; no per-model tables. Recompute on `NSApplication.didChangeScreenParametersNotification`.
- State colours, exact: idle `#3FD99B`, running `#5B9DF9`, waiting `#FFA63C`, failed `#FF5C5C`.
- `LW = 58` — the left flank is a constant, so the island's left edge never moves.
- Corners: `9pt` concave fillet at the top, `15pt` radius at the bottom. Suppress the right fillet when the right flank is empty.
- Motion: width spring response `0.42` damping `0.72`; drawer-height spring response `0.42` damping `0.78`; hover reveal `280ms`; aura `900ms` peaking at `14%`.
- Public API on every type the app target or a later plan touches — the library is consumed across module boundaries.

---

## File Structure

All new files under `Sources/VibeCatUI/` unless stated.

| File | Responsibility |
|---|---|
| `ScreenMetrics.swift` | A `Sendable` snapshot of the one screen we care about, plus notch derivation. The only file that knows `NSScreen` exists. |
| `IslandGeometry.swift` | Pure maths: body and panel frames for every tier, the `LW` invariant, the notchless fallback pill. |
| `IslandState.swift` | Display state (adds `dormant`) and the accent palette. |
| `NotchPanel.swift` | The `NSPanel` subclass and its configuration. |
| `HoverMonitor.swift` | Dwell-gated cursor tracking against a frame, with injected cursor source and clock. |
| `IslandShape.swift` | The SwiftUI `Shape`: concave top fillets, rounded bottom, right-fillet suppression. |
| `AuraTrigger.swift` | Fires a bloom on state *change* only. A testable state machine. |
| `IslandView.swift` | The SwiftUI collapsed layout, thin over `CollapsedLayout` from `IslandGeometry`. |
| `AppModel.swift` | `@Observable`. Owns `SessionStore`, runs `SocketServer`, prunes. |
| `NotchController.swift` | Owns the panel, the geometry, the hover monitor; observes screen changes. |
| `Sources/VibeCatApp/main.swift` | Wiring only. |
| `Tests/VibeCatUITests/*` | One test file per source file above that has logic. |

---

## Task 1: UI target scaffolding and screen metrics

**Files:**
- Modify: `Package.swift`
- Create: `Sources/VibeCatUI/ScreenMetrics.swift`
- Create: `Sources/VibeCatApp/main.swift`
- Test: `Tests/VibeCatUITests/ScreenMetricsTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `public struct ScreenMetrics: Sendable, Equatable` with `public let frame: CGRect`, `public let visibleFrame: CGRect`, `public let safeAreaTop: CGFloat`, `public let auxLeft: CGRect?`, `public let auxRight: CGRect?`; `public init(frame:visibleFrame:safeAreaTop:auxLeft:auxRight:)`; `public var notch: CGRect?`; `public var hasNotch: Bool`; and `@MainActor public static func current() -> ScreenMetrics?`.

- [ ] **Step 1: Add the two targets to `Package.swift`**

Add to `products:`:

```swift
        .library(name: "VibeCatUI", targets: ["VibeCatUI"]),
        .executable(name: "vibecat", targets: ["VibeCatApp"]),
```

Add to `targets:`:

```swift
        // The UI logic lives in a library for the same reason the hook's does:
        // an executable target with a main.swift cannot be @testable imported.
        .target(name: "VibeCatUI", dependencies: ["VibeCatCore", "VibeCatTransport"]),
        .executableTarget(name: "VibeCatApp",
                          dependencies: ["VibeCatUI", "VibeCatCore", "VibeCatTransport"]),
        .testTarget(name: "VibeCatUITests", dependencies: ["VibeCatUI", "VibeCatCore"]),
```

- [ ] **Step 2: Write the failing test**

Create `Tests/VibeCatUITests/ScreenMetricsTests.swift`. The numbers are the spike's measurements from a 14″ M3 Pro on macOS 26.5.2 — treat them as a fixture, not as constants to hardcode in the implementation.

```swift
import Testing
import CoreGraphics
@testable import VibeCatUI

/// Measured on a 14" M3 Pro, macOS 26.5.2. See docs/superpowers/spikes/.
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

@Test func derivesTheNotchFromTheAuxiliaryAreas() throws {
    let notch = try #require(mbp14.notch)
    #expect(notch == CGRect(x: 663, y: 950, width: 185, height: 32))
}

@Test func aDisplayWithoutANotchReportsNone() {
    #expect(externalDisplay.notch == nil)
    #expect(externalDisplay.hasNotch == false)
}

/// The notch is not centred: 663pt of flank on the left, 664 on the right.
/// Anything positioned from screen.midX drifts half a point.
@Test func theNotchIsNotCentredOnTheScreen() throws {
    let notch = try #require(mbp14.notch)
    #expect(notch.midX == 755.5)
    #expect(mbp14.frame.midX == 756)
    #expect(notch.midX != mbp14.frame.midX)
}

/// The menu bar is 33pt but the notch is 32pt. Sizing the island from
/// menu bar height would make it a point too tall.
@Test func theMenuBarIsOnePointTallerThanTheNotch() {
    #expect(mbp14.frame.maxY - mbp14.visibleFrame.maxY == 33)
    #expect(mbp14.safeAreaTop == 32)
}

/// safeAreaTop > 0 but a missing auxiliary area must not produce a garbage rect.
@Test func aPartialReportYieldsNoNotchRatherThanNonsense() {
    let broken = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
        safeAreaTop: 32, auxLeft: nil, auxRight: nil)
    #expect(broken.notch == nil)
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter ScreenMetricsTests`
Expected: FAIL — `cannot find 'ScreenMetrics' in scope`.

- [ ] **Step 4: Write the implementation**

Create `Sources/VibeCatUI/ScreenMetrics.swift`:

```swift
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif

/// A snapshot of everything the island needs to know about a display.
///
/// Value type on purpose: the geometry maths is the part worth testing, and it
/// should not need a window server to run. This is the only file in VibeCatUI
/// that touches NSScreen.
public struct ScreenMetrics: Sendable, Equatable {
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let safeAreaTop: CGFloat
    public let auxLeft: CGRect?
    public let auxRight: CGRect?

    public init(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat,
                auxLeft: CGRect?, auxRight: CGRect?) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxLeft = auxLeft
        self.auxRight = auxRight
    }

    /// The cutout, in screen coordinates. `nil` on any display that does not
    /// report one — an external monitor, or a machine reporting partially.
    public var notch: CGRect? {
        guard safeAreaTop > 0, let l = auxLeft, let r = auxRight, r.minX > l.maxX
        else { return nil }
        return CGRect(x: l.maxX,
                      y: frame.maxY - safeAreaTop,
                      width: r.minX - l.maxX,
                      height: safeAreaTop)
    }

    public var hasNotch: Bool { notch != nil }
}

#if canImport(AppKit)
extension ScreenMetrics {
    public init(_ screen: NSScreen) {
        self.init(frame: screen.frame,
                  visibleFrame: screen.visibleFrame,
                  safeAreaTop: screen.safeAreaInsets.top,
                  auxLeft: screen.auxiliaryTopLeftArea,
                  auxRight: screen.auxiliaryTopRightArea)
    }

    /// The built-in display if it has a notch, otherwise the main display.
    @MainActor public static func current() -> ScreenMetrics? {
        let notched = NSScreen.screens.first {
            $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil
        }
        guard let screen = notched ?? NSScreen.main else { return nil }
        return ScreenMetrics(screen)
    }
}
#endif
```

- [ ] **Step 5: Create a placeholder executable so the package builds**

Create `Sources/VibeCatApp/main.swift`:

```swift
// Wiring only — replaced in Task 10.
import VibeCatUI

print("vibecat: shell not wired yet")
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter ScreenMetricsTests`
Expected: PASS, 5 tests. Then `swift test` — the 83 existing tests must still pass.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/VibeCatUI Sources/VibeCatApp Tests/VibeCatUITests
git commit -m "feat: add the UI target and derive notch geometry from NSScreen"
```

---

## Task 2: Island geometry

**Files:**
- Create: `Sources/VibeCatUI/IslandGeometry.swift`
- Test: `Tests/VibeCatUITests/IslandGeometryTests.swift`

**Interfaces:**
- Consumes: `ScreenMetrics` from Task 1.
- Produces:
  - `public enum IslandTier: Sendable, Equatable { case rest, hover, drawer(height: CGFloat) }`
  - `public struct IslandFrames: Sendable, Equatable` with `public let body: CGRect`, `public let shape: CGRect`, `public let panel: CGRect`, `public var shapeInPanel: CGRect`.
  - `public struct IslandGeometry: Sendable, Equatable` with `public static let leftFlank: CGFloat = 58`, `public static let fillet: CGFloat = 9`, `public static let bottomRadius: CGFloat = 15`, `public static let auraMargin: CGFloat = 24`; `public init(screen: ScreenMetrics)`; `public let notch: CGRect`; `public let isFallbackPill: Bool`; `public func frames(rightFlank: CGFloat, tier: IslandTier) -> IslandFrames`.

**Three rects, and the difference matters.** `body` is the core — `LW + notch + RW` — and it is what design §5.4's measured examples describe (dormant `244pt` at the prototype's notch width). `shape` is the core plus the fillet flares, which stick out beyond it; that is the rect handed to `IslandShape` and the rect hover tests against. `panel` is the window, which is `shape` plus room for the aura.

Two things this task locks in. First, the position invariant from design §5.3 — with `LW` constant, the body's left edge is `notch.minX − LW` and the right flank width cancels out, so growing the right side never walks the cat sideways. Second, the aura needs room outside the shape to bloom into, so the panel is inflated by `auraMargin` on the left, right and bottom but **not** the top, because the aura never appears above the notch.

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatUITests/IslandGeometryTests.swift`:

```swift
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
    #expect(edges[0] == 663 - 58)
}

@Test func restBodySpansLeftFlankPlusNotchPlusRightFlank() {
    let g = IslandGeometry(screen: mbp14)
    let dormant = g.frames(rightFlank: 0, tier: .rest).body
    #expect(dormant.width == 58 + 185)
    #expect(dormant.height == 32)
    #expect(dormant.maxY == 982)

    let running = g.frames(rightFlank: 35, tier: .rest).body
    #expect(running.width == 58 + 185 + 35)
}

/// The fillets flare outside the core, so the shape is wider than the body.
/// With an empty right flank the right fillet is suppressed and only the
/// left flare is added.
@Test func theShapeAddsAFlareOnEachSideThatHasAFillet() {
    let g = IslandGeometry(screen: mbp14)
    let f = IslandGeometry.fillet

    let running = g.frames(rightFlank: 35, tier: .rest)
    #expect(running.shape.width == running.body.width + f * 2)
    #expect(running.shape.minX == running.body.minX - f)

    let dormant = g.frames(rightFlank: 0, tier: .rest)
    #expect(dormant.shape.width == dormant.body.width + f)
    #expect(dormant.shape.maxX == dormant.body.maxX)   // no right flare
}

/// The aura blooms outside the shape, and never above the notch.
@Test func thePanelIsInflatedForTheAuraOnThreeSidesOnly() {
    let g = IslandGeometry(screen: mbp14)
    let f = g.frames(rightFlank: 35, tier: .rest)
    #expect(f.panel.maxY == f.shape.maxY)                       // no top margin
    #expect(f.panel.minX == f.shape.minX - IslandGeometry.auraMargin)
    #expect(f.panel.maxX == f.shape.maxX + IslandGeometry.auraMargin)
    #expect(f.panel.minY == f.shape.minY - IslandGeometry.auraMargin)
}

/// Panel-local coordinates are flipped (SwiftUI y grows downward) and there
/// is no top margin, so the shape starts flush with the panel's top edge.
@Test func shapeInPanelIsTheShapeExpressedInPanelLocalCoordinates() {
    let g = IslandGeometry(screen: mbp14)
    let f = g.frames(rightFlank: 35, tier: .rest)
    #expect(f.shapeInPanel.origin == CGPoint(x: IslandGeometry.auraMargin, y: 0))
    #expect(f.shapeInPanel.size == f.shape.size)
}

@Test func theDrawerGrowsDownwardAndKeepsItsTopAtTheScreenEdge() {
    let g = IslandGeometry(screen: mbp14)
    let f = g.frames(rightFlank: 35, tier: .drawer(height: 288))
    #expect(f.body.height == 32 + 288)
    #expect(f.body.maxY == 982)
    #expect(f.body.minX == 663 - 58)   // still pinned
}

/// A notchless display gets a floating pill in the same place, with no
/// dead zone to route content around. Design §5.1.
@Test func aNotchlessDisplayGetsAFallbackPill() {
    let g = IslandGeometry(screen: externalDisplay)
    #expect(g.isFallbackPill)
    #expect(g.notch.width == 0)
    let f = g.frames(rightFlank: 40, tier: .rest)
    #expect(f.body.width == 58 + 40)
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter IslandGeometryTests`
Expected: FAIL — `cannot find 'IslandGeometry' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/VibeCatUI/IslandGeometry.swift`:

```swift
import CoreGraphics

public enum IslandTier: Sendable, Equatable {
    case rest
    case hover
    case drawer(height: CGFloat)

    var extraHeight: CGFloat {
        if case let .drawer(h) = self { h } else { 0 }
    }
}

public struct IslandFrames: Sendable, Equatable {
    /// The core: leftFlank + notch + rightFlank, in screen coordinates. This is
    /// what design §5.4's measured widths describe, and what the content is
    /// laid out against.
    public let body: CGRect
    /// The core plus the fillet flares, which stick out past it. This is the
    /// rect handed to IslandShape.
    public let shape: CGRect
    /// The window: the shape plus room for the aura to bloom into.
    public let panel: CGRect

    public init(body: CGRect, shape: CGRect, panel: CGRect) {
        self.body = body
        self.shape = shape
        self.panel = panel
    }

    /// The shape relative to the panel's own origin, in SwiftUI's flipped
    /// coordinates. There is no top margin, so y is always 0.
    public var shapeInPanel: CGRect {
        CGRect(x: shape.minX - panel.minX, y: panel.maxY - shape.maxY,
               width: shape.width, height: shape.height)
    }
}

public struct IslandGeometry: Sendable, Equatable {
    /// 12 padding + 18 cat + 4 gap + 14 badge + 10 padding. Constant so that
    /// the island's left edge — and therefore the cat — never moves.
    public static let leftFlank: CGFloat = 58
    public static let fillet: CGFloat = 9
    public static let bottomRadius: CGFloat = 15
    /// Room outside the body for the aura to bloom into.
    public static let auraMargin: CGFloat = 24
    /// Height of the fallback pill on a display with no notch.
    public static let pillHeight: CGFloat = 32

    public let screen: ScreenMetrics
    /// The real cutout, or a zero-width rect at the top centre as a stand-in.
    public let notch: CGRect
    public let isFallbackPill: Bool

    public init(screen: ScreenMetrics) {
        self.screen = screen
        if let n = screen.notch {
            notch = n
            isFallbackPill = false
        } else {
            // No dead zone to route around, so the "notch" is a zero-width
            // seam at the top centre and the flanks simply meet.
            notch = CGRect(x: screen.frame.midX,
                           y: screen.frame.maxY - Self.pillHeight,
                           width: 0, height: Self.pillHeight)
            isFallbackPill = true
        }
    }

    public func frames(rightFlank: CGFloat, tier: IslandTier) -> IslandFrames {
        let right = max(0, rightFlank)
        let width = Self.leftFlank + notch.width + right
        let height = notch.height + tier.extraHeight

        // leftEdge = notch.minX − LW. The right flank cancels out of the
        // centring shift entirely, which is why the cat holds still.
        let left = isFallbackPill ? screen.frame.midX - width / 2
                                  : notch.minX - Self.leftFlank
        let body = CGRect(x: left, y: screen.frame.maxY - height,
                          width: width, height: height)

        // A fillet welded to an empty flank pokes out past the notch as a
        // beak, so the right flare only exists when there is content. §5.5.
        let rightFlare: CGFloat = right > 0 ? Self.fillet : 0
        let shape = CGRect(x: body.minX - Self.fillet, y: body.minY,
                           width: body.width + Self.fillet + rightFlare,
                           height: body.height)

        let m = Self.auraMargin
        var panel = CGRect(x: shape.minX - m, y: shape.minY - m,
                           width: shape.width + m * 2, height: shape.height + m)
        // Clamp horizontally; the top is already the screen edge.
        panel.origin.x = max(screen.frame.minX, panel.minX)
        panel.size.width = min(panel.width, screen.frame.maxX - panel.minX)

        return IslandFrames(body: body, shape: shape, panel: panel)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter IslandGeometryTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Prove the invariant test is load-bearing**

Temporarily change `let left = ... : notch.minX - Self.leftFlank` to `screen.frame.midX - width / 2`. Re-run: `theLeftEdgeDoesNotMoveWhenTheRightFlankGrows` must FAIL. Revert.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/IslandGeometry.swift Tests/VibeCatUITests/IslandGeometryTests.swift
git commit -m "feat: island frame geometry with a pinned left edge"
```

---

## Task 3: Island state and palette

**Files:**
- Create: `Sources/VibeCatUI/IslandState.swift`
- Test: `Tests/VibeCatUITests/IslandStateTests.swift`

**Interfaces:**
- Consumes: `SessionStore`, `SessionState` from `VibeCatCore`.
- Produces: `public enum IslandState: String, Sendable, CaseIterable { case dormant, idle, running, waiting, failed }`; `public init(store: SessionStore)`; `public var accent: RGBA`; `public var isDormant: Bool`. Plus `public struct RGBA: Sendable, Equatable` with `public let r/g/b: Double` and `public init?(hex: String)`, `public var hex: String`.

Design §4.1 lists **five** states, but `SessionState` in Core has four — `dormant` means "no sessions at all", which is a property of the store rather than of any session. `SessionStore.aggregate` returns `.idle` for an empty store, so the distinction has to be made here. A dormant island shows a sleeping cat; an idle one shows a finished cat. Conflating them would make a machine that has never run anything look like one that just succeeded.

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatUITests/IslandStateTests.swift`:

```swift
import Foundation
import Testing
import VibeCatCore
@testable import VibeCatUI

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func event(_ kind: Kind, session: String) -> VibeEvent {
    VibeEvent(id: "e-\(session)", cli: "claude-code", kind: kind,
              session: session, cwd: "/dev/\(session)")
}

/// The distinction Core cannot make: an empty store aggregates to .idle,
/// but "nothing has ever run" is not "a run just finished".
@Test func anEmptyStoreIsDormantNotIdle() {
    #expect(SessionStore().aggregate == .idle)
    #expect(IslandState(store: SessionStore()) == .dormant)
}

@Test func aStoreWithOnlyFinishedSessionsIsIdle() {
    var store = SessionStore()
    store.apply(event(.done, session: "a"), now: t0)
    #expect(IslandState(store: store) == .idle)
}

@Test func theWorstStateWins() {
    var store = SessionStore()
    store.apply(event(.running, session: "a"), now: t0)
    store.apply(event(.failed, session: "b"), now: t0)
    store.apply(event(.permission, session: "c"), now: t0)
    #expect(IslandState(store: store) == .waiting)
}

@Test func accentsAreTheSpecColours() {
    #expect(IslandState.idle.accent.hex == "#3FD99B")
    #expect(IslandState.running.accent.hex == "#5B9DF9")
    #expect(IslandState.waiting.accent.hex == "#FFA63C")
    #expect(IslandState.failed.accent.hex == "#FF5C5C")
}

/// Dormant is a mood, not a fifth colour — an idle machine reads as idle.
@Test func dormantBorrowsTheIdleAccent() {
    #expect(IslandState.dormant.accent == IslandState.idle.accent)
    #expect(IslandState.dormant.isDormant)
}

@Test func hexRoundTrips() throws {
    let c = try #require(RGBA(hex: "#5B9DF9"))
    #expect(c.hex == "#5B9DF9")
    #expect(abs(c.r - 0x5B / 255.0) < 0.0001)
}

@Test func aMalformedHexIsRejectedRatherThanGuessed() {
    #expect(RGBA(hex: "#GGGGGG") == nil)
    #expect(RGBA(hex: "#FFF") == nil)
    #expect(RGBA(hex: "5B9DF9") == nil)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter IslandStateTests`
Expected: FAIL — `cannot find 'IslandState' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/VibeCatUI/IslandState.swift`:

```swift
import Foundation      // String(format:)
import VibeCatCore

public struct RGBA: Sendable, Equatable {
    public let r: Double
    public let g: Double
    public let b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Strict on purpose: a colour that silently decodes wrong is a bug that
    /// only shows up as a slightly off island.
    public init?(hex: String) {
        guard hex.count == 7, hex.hasPrefix("#") else { return nil }
        let digits = hex.dropFirst()
        guard digits.allSatisfy(\.isHexDigit), let v = UInt32(digits, radix: 16)
        else { return nil }
        r = Double((v >> 16) & 0xFF) / 255
        g = Double((v >> 8) & 0xFF) / 255
        b = Double(v & 0xFF) / 255
    }

    public var hex: String {
        let c = { (x: Double) in Int((x * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}

/// What the island is reporting. Adds `dormant` to Core's four session states,
/// because "no sessions at all" is a property of the store, not of a session.
public enum IslandState: String, Sendable, CaseIterable {
    case dormant, idle, running, waiting, failed

    public init(store: SessionStore) {
        guard !store.sessions.isEmpty else { self = .dormant; return }
        switch store.aggregate {
        case .idle:    self = .idle
        case .running: self = .running
        case .waiting: self = .waiting
        case .failed:  self = .failed
        }
    }

    public var isDormant: Bool { self == .dormant }

    /// Colour means state and only state. Dormant shares idle's green: it is
    /// distinguished by the cat's mood, not by a fifth hue competing for
    /// meaning. Design §4.3.
    public var accent: RGBA {
        switch self {
        case .dormant, .idle: RGBA(hex: "#3FD99B")!
        case .running:        RGBA(hex: "#5B9DF9")!
        case .waiting:        RGBA(hex: "#FFA63C")!
        case .failed:         RGBA(hex: "#FF5C5C")!
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter IslandStateTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatUI/IslandState.swift Tests/VibeCatUITests/IslandStateTests.swift
git commit -m "feat: island state with dormant, and the state palette"
```

---

## Task 4: The notch panel

**Files:**
- Create: `Sources/VibeCatUI/NotchPanel.swift`
- Test: `Tests/VibeCatUITests/NotchPanelTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `@MainActor public final class NotchPanel: NSPanel` with `public init(frames: IslandFrames)`, `public func apply(_ frames: IslandFrames)`, `public var isInteractive: Bool { get set }`, and the `constrainFrameRect` override.

This is the task where the spike's findings become code. Read the [spike report](../spikes/2026-08-01-notch-shell-spike.md) sections 2, 3 and 5 before starting.

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatUITests/NotchPanelTests.swift`. These tests construct a real `NSPanel`, which needs no window server as long as nothing is ordered front.

```swift
import AppKit
import Testing
import CoreGraphics
@testable import VibeCatUI

private let mbp14 = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
    safeAreaTop: 32,
    auxLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
    auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))

@MainActor private func panel(rightFlank: CGFloat = 35) -> (NotchPanel, IslandFrames) {
    let frames = IslandGeometry(screen: mbp14).frames(rightFlank: rightFlank, tier: .rest)
    return (NotchPanel(frames: frames), frames)
}

/// Spike §2. AppKit clamps a window out of the menu bar unless
/// constrainFrameRect refuses. Measured without the override: y=917, not 950.
@MainActor @Test func constrainFrameRectReturnsTheRequestedFrameUntouched() {
    let (p, frames) = panel()
    let asked = frames.panel
    #expect(p.constrainFrameRect(asked, to: nil) == asked)
    #expect(p.constrainFrameRect(asked, to: NSScreen.main) == asked)
}

@MainActor @Test func theFrameSurvivesBeingSet() {
    let (p, frames) = panel()
    p.setFrame(frames.panel, display: false)
    #expect(p.frame == frames.panel)
}

/// Spike §3. The menu bar is layer 24; 25 is the lowest level that clears it.
@MainActor @Test func theLevelIsStatusBar() {
    let (p, _) = panel()
    #expect(p.level == .statusBar)
    #expect(p.level.rawValue == 25)
}

@MainActor @Test func itSurvivesSpacesAndFullscreen() {
    let (p, _) = panel()
    #expect(p.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(p.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(p.collectionBehavior.contains(.stationary))
    #expect(p.hidesOnDeactivate == false)
}

@MainActor @Test func itIsTransparentAndUnadorned() {
    let (p, _) = panel()
    #expect(p.isOpaque == false)
    #expect(p.backgroundColor == .clear)
    #expect(p.hasShadow == false)
    #expect(p.isMovable == false)
}

/// Spike §5. A menu title can reach within ~30pt of the island's left edge,
/// so at rest the island must not be able to swallow a click.
@MainActor @Test func itIsClickThroughUntilMadeInteractive() {
    let (p, _) = panel()
    #expect(p.ignoresMouseEvents == true)
    #expect(p.isInteractive == false)

    p.isInteractive = true
    #expect(p.ignoresMouseEvents == false)

    p.isInteractive = false
    #expect(p.ignoresMouseEvents == true)
}

@MainActor @Test func applyMovesThePanelToTheNewFrames() {
    let (p, _) = panel(rightFlank: 0)
    let grown = IslandGeometry(screen: mbp14).frames(rightFlank: 120, tier: .rest)
    p.apply(grown)
    #expect(p.frame == grown.panel)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter NotchPanelTests`
Expected: FAIL — `cannot find 'NotchPanel' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/VibeCatUI/NotchPanel.swift`:

```swift
import AppKit

/// The window that sits in the notch.
///
/// Three of its settings are load-bearing and were measured, not assumed —
/// see docs/superpowers/spikes/2026-08-01-notch-shell-spike.md.
@MainActor public final class NotchPanel: NSPanel {

    public init(frames: IslandFrames) {
        super.init(contentRect: frames.panel,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        // Above the menu bar (layer 24). The lowest level that clears it;
        // going higher only starts fighting menus and alerts.
        level = .statusBar

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        worksWhenModal = true
        collectionBehavior = [.canJoinAllSpaces, .stationary,
                              .fullScreenAuxiliary, .ignoresCycle]

        // At rest the island is click-through: a menu title can reach within
        // about 30pt of its left edge, and an opaque flank would eat the click.
        ignoresMouseEvents = true

        setFrame(frames.panel, display: false)
    }

    /// AppKit clamps a window's frame to the screen's visible area, which drops
    /// the island 33pt out of the notch. Refusing the constraint is the whole
    /// trick — do not call super here.
    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Borderless panels refuse key status by default, and the reply field in
    /// Plan 4 needs it.
    public override var canBecomeKey: Bool { true }

    /// False while collapsed, true once the drawer is open and the island
    /// genuinely owns the space it covers.
    public var isInteractive: Bool {
        get { !ignoresMouseEvents }
        set { ignoresMouseEvents = !newValue }
    }

    public func apply(_ frames: IslandFrames) {
        setFrame(frames.panel, display: true)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter NotchPanelTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Prove the override is load-bearing**

Temporarily change the override body to `super.constrainFrameRect(frameRect, to: screen)`. Run `swift test --filter NotchPanelTests`. `theFrameSurvivesBeingSet` must FAIL, reporting a y of 917 rather than 950. Revert.

If it does **not** fail — which can happen when no window server is attached — record that in the task report as an environment limitation rather than deleting the test, and verify the override by hand with the snippet in spike §2.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/NotchPanel.swift Tests/VibeCatUITests/NotchPanelTests.swift
git commit -m "feat: NotchPanel, pinned into the menu bar and click-through at rest"
```

---

## Task 5: Hover monitor

**Files:**
- Create: `Sources/VibeCatUI/HoverMonitor.swift`
- Test: `Tests/VibeCatUITests/HoverMonitorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `@MainActor public final class HoverMonitor` with `public init(dwell: TimeInterval = 0.30, cursor: @escaping @MainActor () -> CGPoint, now: @escaping @MainActor () -> Date)`, `public var frame: CGRect`, `public var onChange: (@MainActor (Bool) -> Void)?`, `public private(set) var isHovering: Bool`, `public func sample()`, `public func start()`, `public func stop()`.

`NSTrackingArea` cannot be used: a click-through window receives no mouse events, so there is nothing for a tracking area to observe. Sampling `NSEvent.mouseLocation` needs neither a delivered event nor a permission, and the spike verified it reports correctly while `ignoresMouseEvents = true`.

The dwell gate exists because the cursor crosses the notch on its way to the menu bar constantly. `0.30s` is the design default from §14.

Both the cursor source and the clock are injected so the whole state machine is testable with no real mouse and no real time.

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatUITests/HoverMonitorTests.swift`:

```swift
import Foundation
import Testing
import CoreGraphics
@testable import VibeCatUI

@MainActor private final class Fake {
    var point = CGPoint(x: 0, y: 0)
    var clock = Date(timeIntervalSince1970: 1_000_000)
    var changes: [Bool] = []

    func monitor(dwell: TimeInterval = 0.30) -> HoverMonitor {
        let m = HoverMonitor(dwell: dwell,
                             cursor: { self.point },
                             now: { self.clock })
        m.frame = CGRect(x: 100, y: 100, width: 200, height: 32)
        m.onChange = { self.changes.append($0) }
        return m
    }

    func tick(_ seconds: TimeInterval) { clock += seconds }
}

@MainActor @Test func aCursorPassingThroughDoesNotTriggerHover() {
    let f = Fake()
    let m = f.monitor()
    f.point = CGPoint(x: 150, y: 110)   // inside
    m.sample()
    f.tick(0.1)
    f.point = CGPoint(x: 900, y: 500)   // gone again before the dwell elapses
    m.sample()
    #expect(m.isHovering == false)
    #expect(f.changes.isEmpty)
}

@MainActor @Test func restingForTheDwellTriggersHoverExactlyOnce() {
    let f = Fake()
    let m = f.monitor()
    f.point = CGPoint(x: 150, y: 110)
    m.sample()
    f.tick(0.31)
    m.sample()
    m.sample()
    m.sample()
    #expect(m.isHovering)
    #expect(f.changes == [true])
}

@MainActor @Test func leavingEndsHoverImmediatelyWithNoDwell() {
    let f = Fake()
    let m = f.monitor()
    f.point = CGPoint(x: 150, y: 110)
    m.sample()
    f.tick(0.31)
    m.sample()
    f.point = CGPoint(x: 900, y: 500)
    m.sample()
    #expect(m.isHovering == false)
    #expect(f.changes == [true, false])
}

@MainActor @Test func reEnteringRestartsTheDwell() {
    let f = Fake()
    let m = f.monitor()
    f.point = CGPoint(x: 150, y: 110)
    m.sample()
    f.tick(0.2)
    f.point = CGPoint(x: 900, y: 500)   // left at 0.2, short of the dwell
    m.sample()
    f.point = CGPoint(x: 150, y: 110)   // straight back in
    m.sample()
    f.tick(0.2)                          // 0.4 total inside, but only 0.2 since re-entry
    m.sample()
    #expect(m.isHovering == false)
    f.tick(0.15)
    m.sample()
    #expect(m.isHovering)
}

@MainActor @Test func movingTheFrameOutFromUnderTheCursorEndsHover() {
    let f = Fake()
    let m = f.monitor()
    f.point = CGPoint(x: 150, y: 110)
    m.sample()
    f.tick(0.31)
    m.sample()
    #expect(m.isHovering)
    m.frame = CGRect(x: 800, y: 100, width: 200, height: 32)
    m.sample()
    #expect(m.isHovering == false)
}

@MainActor @Test func aZeroDwellTriggersOnTheFirstSampleInside() {
    let f = Fake()
    let m = f.monitor(dwell: 0)
    f.point = CGPoint(x: 150, y: 110)
    m.sample()
    #expect(m.isHovering)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter HoverMonitorTests`
Expected: FAIL — `cannot find 'HoverMonitor' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/VibeCatUI/HoverMonitor.swift`:

```swift
import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif

/// Hover detection for a click-through window.
///
/// NSTrackingArea is unusable here: with ignoresMouseEvents = true the window
/// receives no mouse events at all, so a tracking area has nothing to observe.
/// Sampling the cursor position needs neither an event nor a permission.
@MainActor public final class HoverMonitor {
    /// How long the cursor must rest inside before this counts as hover. The
    /// cursor crosses the notch constantly on its way to the menu bar.
    public let dwell: TimeInterval

    public var frame: CGRect = .zero
    public var onChange: (@MainActor (Bool) -> Void)?
    public private(set) var isHovering = false

    private let cursor: @MainActor () -> CGPoint
    private let now: @MainActor () -> Date
    private var enteredAt: Date?
    private var timer: Timer?

    public init(dwell: TimeInterval = 0.30,
                cursor: @escaping @MainActor () -> CGPoint,
                now: @escaping @MainActor () -> Date) {
        self.dwell = dwell
        self.cursor = cursor
        self.now = now
    }

    #if canImport(AppKit)
    public convenience init(dwell: TimeInterval = 0.30) {
        self.init(dwell: dwell, cursor: { NSEvent.mouseLocation }, now: { Date() })
    }
    #endif

    /// Evaluate the cursor once. Called on a timer, and directly by tests.
    public func sample() {
        let inside = frame.contains(cursor())

        guard inside else {
            enteredAt = nil
            setHovering(false)     // leaving is immediate; only entering waits
            return
        }

        let entry = enteredAt ?? now()
        enteredAt = entry
        if now().timeIntervalSince(entry) >= dwell { setHovering(true) }
    }

    private func setHovering(_ value: Bool) {
        guard value != isHovering else { return }   // fire on edges only
        isHovering = value
        onChange?(value)
    }

    /// 30 Hz is well inside the budget and imperceptible for a hover gate.
    public func start() {
        stop()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        enteredAt = nil
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter HoverMonitorTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Prove the dwell test is load-bearing**

Temporarily change `if now().timeIntervalSince(entry) >= dwell` to `if true`. Re-run: `aCursorPassingThroughDoesNotTriggerHover` and `reEnteringRestartsTheDwell` must FAIL. Revert.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/HoverMonitor.swift Tests/VibeCatUITests/HoverMonitorTests.swift
git commit -m "feat: dwell-gated hover by cursor sampling, not tracking areas"
```

---

## Task 6: The island shape

**Files:**
- Create: `Sources/VibeCatUI/IslandShape.swift`
- Test: `Tests/VibeCatUITests/IslandShapeTests.swift`

**Interfaces:**
- Consumes: `IslandGeometry.fillet`, `IslandGeometry.bottomRadius`.
- Produces: `public struct IslandShape: Shape, Sendable` with `public init(rightFilletSuppressed: Bool)`, `public func path(in rect: CGRect) -> Path`.

Design §5.5: small concave fillets at the top where the island welds to the screen edge, a `15pt` radius at the bottom. Apple's own cutout does not meet the bezel at a right angle.

The fillet flares *outward*, so the shape is `fillet` wider than the body on each side that has one. The body therefore occupies `rect.insetBy(dx: fillet, dy: 0)` and the flares live in the margins. **Suppress the right fillet when the right flank is empty** — a weld with nothing to weld to just pokes out past the notch as a beak.

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatUITests/IslandShapeTests.swift`:

```swift
import SwiftUI
import Testing
import CoreGraphics
@testable import VibeCatUI

private let box = CGRect(x: 0, y: 0, width: 300, height: 32)
private let f = IslandGeometry.fillet          // 9
private let r = IslandGeometry.bottomRadius    // 15

@Test func theShapeFillsItsBoxAtTheTopEdge() {
    let path = IslandShape(rightFilletSuppressed: false).path(in: box)
    #expect(path.boundingRect.minY == 0)
    #expect(path.boundingRect.maxY == box.maxY)
}

/// The flare is a thin wedge that widens as it approaches the screen edge.
/// At x = 8 the boundary curve sits at y = 4, so the wedge is 4pt deep there.
@Test func theFlareFillsTheWedgeBetweenTheScreenEdgeAndTheBody() {
    let path = IslandShape(rightFilletSuppressed: false).path(in: box)
    #expect(path.contains(CGPoint(x: 8, y: 2)))     // inside the wedge
    #expect(!path.contains(CGPoint(x: 8, y: 6)))    // below it, and left of the body
}

/// The body proper is inset by the fillet on each side.
@Test func theBodyIsInsetByTheFilletBelowTheFlare() {
    let path = IslandShape(rightFilletSuppressed: false).path(in: box)
    let mid = box.height / 2
    #expect(path.contains(CGPoint(x: f + 1, y: mid)))
    #expect(path.contains(CGPoint(x: box.maxX - f - 1, y: mid)))
    #expect(!path.contains(CGPoint(x: f - 3, y: mid)))
    #expect(!path.contains(CGPoint(x: box.maxX - f + 3, y: mid)))
}

/// Design §5.5: dormant has no right-hand content, so the weld has nothing to
/// weld to and would poke out past the notch as a beak. Suppressed, the right
/// edge runs straight to the box edge instead of insetting for a flare.
@Test func theRightFilletIsSuppressedWhenAsked() {
    let mid = box.height / 2
    let flared = IslandShape(rightFilletSuppressed: false).path(in: box)
    let plain = IslandShape(rightFilletSuppressed: true).path(in: box)

    #expect(!flared.contains(CGPoint(x: box.maxX - 1, y: mid)))  // inset for the flare
    #expect(plain.contains(CGPoint(x: box.maxX - 1, y: mid)))    // runs to the edge
    #expect(plain.contains(CGPoint(x: f + 1, y: mid)))           // left side unchanged
    #expect(plain.contains(CGPoint(x: 8, y: 2)))                 // left flare still there
}

/// The fillet is concave: the corner is cut away, not filled.
@Test func theTopCornerIsConcaveNotSquare() {
    let path = IslandShape(rightFilletSuppressed: false).path(in: box)
    // A square corner would make this point solid. The curve reaches only
    // y = 0.007 at x = 0.5, so a concave fillet leaves it empty.
    #expect(!path.contains(CGPoint(x: 0.5, y: f - 0.5)))
}

@Test func theBottomCornersAreRounded() {
    let path = IslandShape(rightFilletSuppressed: false).path(in: box)
    #expect(!path.contains(CGPoint(x: f + 0.5, y: box.maxY - 0.5)))
    #expect(path.contains(CGPoint(x: f + r, y: box.maxY - 1)))
}

/// A drawer-height box must not distort the corners.
@Test func aTallBoxKeepsTheSameCornerRadii() {
    let tall = CGRect(x: 0, y: 0, width: 520, height: 320)
    let path = IslandShape(rightFilletSuppressed: false).path(in: tall)
    #expect(path.boundingRect.height == 320)
    #expect(path.contains(CGPoint(x: tall.midX, y: tall.maxY - 1)))
    #expect(!path.contains(CGPoint(x: f + 0.5, y: tall.maxY - 0.5)))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter IslandShapeTests`
Expected: FAIL — `cannot find 'IslandShape' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/VibeCatUI/IslandShape.swift`:

```swift
import SwiftUI

/// The island's silhouette.
///
/// The top corners are *concave* fillets: the island welds to the screen edge
/// rather than meeting it at a right angle, so the shape flares outward at the
/// very top. The flare lives in a `fillet`-wide margin on each side, which
/// means the body proper is `rect.insetBy(dx: fillet, dy: 0)`.
public struct IslandShape: Shape, Sendable {
    /// Dormant has no right-hand content. A weld with nothing to weld to reads
    /// as a beak poking out past the notch, so it is dropped. Design §5.5.
    public let rightFilletSuppressed: Bool

    public init(rightFilletSuppressed: Bool = false) {
        self.rightFilletSuppressed = rightFilletSuppressed
    }

    public func path(in rect: CGRect) -> Path {
        let f = IslandGeometry.fillet
        let r = min(IslandGeometry.bottomRadius, rect.height / 2)
        let rightF = rightFilletSuppressed ? 0 : f

        let left = rect.minX + f            // body's left edge
        let right = rect.maxX - rightF      // body's right edge
        let top = rect.minY
        let bottom = rect.maxY

        var p = Path()
        // Top-left: from the screen edge, curve down into the body's left side.
        p.move(to: CGPoint(x: rect.minX, y: top))
        p.addQuadCurve(to: CGPoint(x: left, y: top + f),
                       control: CGPoint(x: left, y: top))
        p.addLine(to: CGPoint(x: left, y: bottom - r))
        p.addQuadCurve(to: CGPoint(x: left + r, y: bottom),
                       control: CGPoint(x: left, y: bottom))
        p.addLine(to: CGPoint(x: right - r, y: bottom))
        p.addQuadCurve(to: CGPoint(x: right, y: bottom - r),
                       control: CGPoint(x: right, y: bottom))

        if rightFilletSuppressed {
            p.addLine(to: CGPoint(x: right, y: top))
        } else {
            p.addLine(to: CGPoint(x: right, y: top + f))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: top),
                           control: CGPoint(x: right, y: top))
        }
        p.closeSubpath()   // back along the screen edge
        return p
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter IslandShapeTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Prove the suppression test is load-bearing**

Temporarily change `let rightF = rightFilletSuppressed ? 0 : f` to `let rightF = f`. Re-run: `theRightFilletIsSuppressedWhenAsked` must FAIL. Revert.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/IslandShape.swift Tests/VibeCatUITests/IslandShapeTests.swift
git commit -m "feat: island silhouette with concave top fillets"
```

---

## Task 7: The aura trigger

**Files:**
- Create: `Sources/VibeCatUI/AuraTrigger.swift`
- Test: `Tests/VibeCatUITests/AuraTriggerTests.swift`

**Interfaces:**
- Consumes: `IslandState` from Task 3.
- Produces: `public struct AuraTrigger: Sendable, Equatable` with `public static let duration: TimeInterval = 0.9`, `public static let peakOpacity: Double = 0.14`; `public init()`; `public mutating func observe(_ state: IslandState, now: Date) -> Bool`; `public func opacity(at: Date) -> Double`; `public func isBlooming(at: Date) -> Bool`; `public var colour: RGBA?`.

Design §9.2: the aura is punctuation, not a status light. It fires on a state *change*, blooms in the new state's colour and leaves nothing behind. A glow that stayed lit would be a second indicator competing with the cat.

The first observation must **not** fire — launching the app is not a state change, and an aura on launch would announce something that did not happen.

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatUITests/AuraTriggerTests.swift`:

```swift
import Foundation
import Testing
@testable import VibeCatUI

private let t0 = Date(timeIntervalSince1970: 1_000_000)

@Test func theFirstObservationDoesNotFire() {
    var a = AuraTrigger()
    #expect(a.observe(.running, now: t0) == false)
    #expect(a.opacity(at: t0) == 0)
}

@Test func aChangeFires() {
    var a = AuraTrigger()
    _ = a.observe(.idle, now: t0)
    #expect(a.observe(.waiting, now: t0.addingTimeInterval(1)))
}

/// The same state arriving again is not news.
@Test func repeatingTheSameStateDoesNotFire() {
    var a = AuraTrigger()
    _ = a.observe(.running, now: t0)
    #expect(a.observe(.running, now: t0.addingTimeInterval(1)) == false)
    #expect(a.observe(.running, now: t0.addingTimeInterval(2)) == false)
}

@Test func itBloomsInTheNewStatesColour() {
    var a = AuraTrigger()
    _ = a.observe(.idle, now: t0)
    _ = a.observe(.failed, now: t0.addingTimeInterval(1))
    #expect(a.colour == IslandState.failed.accent)
}

/// Rises, peaks at 14%, and is gone by 900ms. Design §9.2.
@Test func theEnvelopeRisesToThePeakThenReturnsToZero() {
    var a = AuraTrigger()
    _ = a.observe(.idle, now: t0)
    let fired = t0.addingTimeInterval(1)
    _ = a.observe(.waiting, now: fired)

    #expect(a.opacity(at: fired) == 0)
    let peak = a.opacity(at: fired.addingTimeInterval(AuraTrigger.duration / 2))
    #expect(abs(peak - AuraTrigger.peakOpacity) < 0.001)
    #expect(a.opacity(at: fired.addingTimeInterval(AuraTrigger.duration)) == 0)
    #expect(a.opacity(at: fired.addingTimeInterval(AuraTrigger.duration + 5)) == 0)
}

/// It is punctuation, not a status light — nothing is left behind.
@Test func itLeavesNothingBehind() {
    var a = AuraTrigger()
    _ = a.observe(.idle, now: t0)
    _ = a.observe(.failed, now: t0.addingTimeInterval(1))
    let after = t0.addingTimeInterval(1 + AuraTrigger.duration + 0.001)
    #expect(a.opacity(at: after) == 0)
}

/// Drives whether the view needs per-frame redraws. True across the whole
/// window including its zero-opacity start, so the first frame is not skipped.
@Test func isBloomingCoversTheWholeWindowIncludingTheZeroStart() {
    var a = AuraTrigger()
    #expect(a.isBlooming(at: t0) == false)          // never fired
    _ = a.observe(.idle, now: t0)
    let fired = t0.addingTimeInterval(1)
    _ = a.observe(.waiting, now: fired)

    #expect(a.isBlooming(at: fired))                              // opacity is 0 here
    #expect(a.isBlooming(at: fired.addingTimeInterval(0.45)))
    #expect(a.isBlooming(at: fired.addingTimeInterval(AuraTrigger.duration)) == false)
}

@Test func aSecondChangeRestartsTheEnvelope() {
    var a = AuraTrigger()
    _ = a.observe(.idle, now: t0)
    _ = a.observe(.running, now: t0.addingTimeInterval(1))
    let second = t0.addingTimeInterval(1.4)         // mid-bloom
    _ = a.observe(.waiting, now: second)
    #expect(a.opacity(at: second) == 0)
    #expect(a.colour == IslandState.waiting.accent)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter AuraTriggerTests`
Expected: FAIL — `cannot find 'AuraTrigger' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/VibeCatUI/AuraTrigger.swift`:

```swift
import Foundation

/// Light blooms out of the island in the new state's colour and leaves nothing
/// behind. Design §9.2 — a glow that stayed lit would be a second indicator
/// competing with the cat, so this fires on change and only on change.
public struct AuraTrigger: Sendable, Equatable {
    public static let duration: TimeInterval = 0.9
    public static let peakOpacity: Double = 0.14

    private var lastState: IslandState?
    private var firedAt: Date?
    private var firedColour: RGBA?

    public init() {}

    /// Returns true when this observation started a bloom. The very first
    /// observation never does: launching the app is not a state change.
    public mutating func observe(_ state: IslandState, now: Date) -> Bool {
        defer { lastState = state }
        guard let previous = lastState else { return false }
        guard previous != state else { return false }
        firedAt = now
        firedColour = state.accent
        return true
    }

    public var colour: RGBA? { firedColour }

    /// Whether a bloom is in flight. The view uses this to decide if it needs
    /// per-frame redraws — an idle machine must not animate. True from the
    /// instant it fires, even though opacity is 0 there.
    public func isBlooming(at instant: Date) -> Bool {
        guard let firedAt else { return false }
        let t = instant.timeIntervalSince(firedAt)
        return t >= 0 && t < Self.duration
    }

    /// A symmetric rise and fall. Zero at both ends, so nothing is left behind.
    /// The upper bound is exclusive: `sin(.pi)` is 1.2e-16 rather than 0, and
    /// the test asserts an exact zero.
    public func opacity(at instant: Date) -> Double {
        guard let firedAt else { return 0 }
        let t = instant.timeIntervalSince(firedAt)
        guard t >= 0, t < Self.duration else { return 0 }
        let phase = t / Self.duration                     // 0…1
        return Self.peakOpacity * sin(phase * .pi)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AuraTriggerTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Prove the change-only test is load-bearing**

Temporarily remove `guard previous != state else { return false }`. Re-run: `repeatingTheSameStateDoesNotFire` must FAIL. Revert.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/AuraTrigger.swift Tests/VibeCatUITests/AuraTriggerTests.swift
git commit -m "feat: aura that fires on state change and leaves nothing behind"
```

---

## Task 8: Collapsed layout and the island view

**Files:**
- Create: `Sources/VibeCatUI/IslandView.swift`
- Modify: `Sources/VibeCatUI/IslandGeometry.swift` — append `CollapsedLayout`
- Test: `Tests/VibeCatUITests/CollapsedLayoutTests.swift`
- Test: `Tests/VibeCatUITests/IslandViewTests.swift`

**Interfaces:**
- Consumes: `IslandGeometry`, `IslandState`, `IslandShape`, `AuraTrigger`.
- Produces:
  - `public struct CollapsedLayout: Sendable, Equatable` with `public enum RightContent: Sendable, Equatable { case sessionCount(Int), agentIcon, nothing }`; `public init(right: RightContent, hovering: Bool)`; `public var rightFlankWidth: CGFloat`; `public var showsRightFillet: Bool`.
  - `public struct IslandView: View` with `public init(state: IslandState, layout: CollapsedLayout, aura: AuraTrigger, now: Date, geometry: IslandGeometry, frames: IslandFrames)` — a thin `TimelineView` wrapper.
  - `struct IslandBody: View` (internal) — the actual content, same initialiser signature. Split out so the smoke test can evaluate real content: evaluating a `TimelineView`'s `body` does not run its content closure.

Design §5.4: the right flank is measured from its content, never reserved. Design §6.2: right-flank content is configurable — session count (default), agent icon, or nothing. Dormant shows nothing, which is what makes `showsRightFillet` false.

Left-flank content is a placeholder rectangle in this plan. The cat is Plan 3.

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatUITests/CollapsedLayoutTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import VibeCatUI

@Test func nothingOnTheRightMeansNoRightFlankAndNoFillet() {
    let l = CollapsedLayout(right: .nothing, hovering: false)
    #expect(l.rightFlankWidth == 0)
    #expect(l.showsRightFillet == false)
}

@Test func aSessionCountReservesRoomForItsDigits() {
    let one = CollapsedLayout(right: .sessionCount(1), hovering: false)
    let twelve = CollapsedLayout(right: .sessionCount(12), hovering: false)
    let many = CollapsedLayout(right: .sessionCount(999), hovering: false)
    #expect(one.rightFlankWidth > 0)
    #expect(twelve.rightFlankWidth > one.rightFlankWidth)
    #expect(many.rightFlankWidth > twelve.rightFlankWidth)
    #expect(one.showsRightFillet)
}

/// A count of zero is dormant — show nothing rather than a bare "0".
@Test func aZeroCountCollapsesToNothing() {
    let l = CollapsedLayout(right: .sessionCount(0), hovering: false)
    #expect(l.rightFlankWidth == 0)
    #expect(l.showsRightFillet == false)
}

/// Design §6.1: hover widens the flanks to reveal name and elapsed time.
@Test func hoverWidensTheRightFlank() {
    let rest = CollapsedLayout(right: .sessionCount(2), hovering: false)
    let hover = CollapsedLayout(right: .sessionCount(2), hovering: true)
    #expect(hover.rightFlankWidth > rest.rightFlankWidth)
}

/// Whatever the right side does, the geometry keeps the left edge still.
@Test func noRightContentEverMovesTheLeftEdge() {
    let screen = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
        safeAreaTop: 32,
        auxLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
        auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))
    let g = IslandGeometry(screen: screen)
    let options: [CollapsedLayout] = [
        CollapsedLayout(right: .nothing, hovering: false),
        CollapsedLayout(right: .agentIcon, hovering: false),
        CollapsedLayout(right: .sessionCount(1), hovering: false),
        CollapsedLayout(right: .sessionCount(999), hovering: true),
    ]
    let edges = options.map {
        g.frames(rightFlank: $0.rightFlankWidth, tier: .rest).body.minX
    }
    #expect(Set(edges).count == 1)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CollapsedLayoutTests`
Expected: FAIL — `cannot find 'CollapsedLayout' in scope`.

- [ ] **Step 3: Append `CollapsedLayout` to `IslandGeometry.swift`**

```swift
/// What the right flank is showing, and how wide that makes it.
///
/// Design §5.4: measured from content, never reserved. The island never holds
/// space it is not using.
public struct CollapsedLayout: Sendable, Equatable {
    public enum RightContent: Sendable, Equatable {
        case sessionCount(Int)
        case agentIcon
        case nothing
    }

    /// 10 leading + content + 12 trailing.
    private static let padding: CGFloat = 22
    private static let digitWidth: CGFloat = 9
    private static let iconWidth: CGFloat = 14
    /// Design §9.1: hover reveals name and elapsed time over 280ms, up to 150pt.
    private static let hoverReveal: CGFloat = 150

    public let right: RightContent
    public let hovering: Bool

    public init(right: RightContent, hovering: Bool) {
        self.right = right
        self.hovering = hovering
    }

    public var rightFlankWidth: CGFloat {
        let content: CGFloat = switch right {
        case .nothing: 0
        case .agentIcon: Self.iconWidth
        case let .sessionCount(n):
            n <= 0 ? 0 : CGFloat(String(n).count) * Self.digitWidth
        }
        guard content > 0 else { return 0 }
        return Self.padding + content + (hovering ? Self.hoverReveal : 0)
    }

    /// A fillet welded to an empty flank pokes out past the notch as a beak.
    public var showsRightFillet: Bool { rightFlankWidth > 0 }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CollapsedLayoutTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Write the view**

Create `Sources/VibeCatUI/IslandView.swift`. Two types: `IslandView` is a thin `TimelineView` wrapper that drives the aura's per-frame redraws, and `IslandBody` is the content. They are split because evaluating a `TimelineView`'s `body` does not run its content closure — the smoke test in Step 6 would prove nothing against a single combined type.

```swift
import SwiftUI

extension Color {
    init(_ c: RGBA) { self.init(red: c.r, green: c.g, blue: c.b) }
}

/// Drives per-frame redraws while — and only while — the aura is blooming.
///
/// Design §6.1: an idle machine should look idle, so the timeline is paused at
/// rest rather than ticking forever for a 900ms effect. `paused` is fixed when
/// the view is built, so the controller renders once more at the end of a bloom
/// to pause it again.
public struct IslandView: View {
    public let state: IslandState
    public let layout: CollapsedLayout
    public let aura: AuraTrigger
    public let now: Date
    public let geometry: IslandGeometry
    public let frames: IslandFrames

    public init(state: IslandState, layout: CollapsedLayout, aura: AuraTrigger,
                now: Date, geometry: IslandGeometry, frames: IslandFrames) {
        self.state = state
        self.layout = layout
        self.aura = aura
        self.now = now
        self.geometry = geometry
        self.frames = frames
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0,
                                paused: !aura.isBlooming(at: now))) { context in
            IslandBody(state: state, layout: layout, aura: aura,
                       now: context.date, geometry: geometry, frames: frames)
        }
    }
}

/// The collapsed island. Left flank, dead zone, right flank.
///
/// Design §5.1: the black shape may span the cutout because the cutout is black
/// too — but content may not. The middle is a fixed-width spacer, never a view.
struct IslandBody: View {
    let state: IslandState
    let layout: CollapsedLayout
    let aura: AuraTrigger
    let now: Date
    let geometry: IslandGeometry
    let frames: IslandFrames

    private var accent: Color { Color(state.accent) }

    var body: some View {
        let rect = frames.shapeInPanel
        let silhouette = IslandShape(rightFilletSuppressed: !layout.showsRightFillet)

        ZStack(alignment: .topLeading) {
            Color.clear
            silhouette
                .fill(Color(red: 0.02, green: 0.027, blue: 0.043))
                .overlay(alignment: .topLeading) { content }
                .clipShape(silhouette)
                // A shadow on the shape traces its rendered alpha, fillets
                // included, so the aura follows the silhouette rather than a
                // bounding box — and follows the drawer down for free.
                .shadow(color: accent.opacity(aura.opacity(at: now)),
                        radius: 18, x: 0, y: 2)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
        .frame(width: frames.panel.width, height: frames.panel.height,
               alignment: .topLeading)
    }

    private var content: some View {
        HStack(spacing: 0) {
            // Left flank — the cat lands here in Plan 3.
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 18, height: 14)
                Color.clear.frame(width: 14, height: 14)   // fixed badge slot
            }
            .padding(.leading, 12 + IslandGeometry.fillet)
            .padding(.trailing, 10)

            // The dead zone. Never a view — just the width of the cutout.
            Color.clear.frame(width: geometry.notch.width)

            rightFlank
        }
        .frame(height: geometry.notch.height)
    }

    @ViewBuilder private var rightFlank: some View {
        switch layout.right {
        case .nothing:
            EmptyView()
        case .agentIcon:
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: 14, height: 14)
                .padding(.horizontal, 10)
        case let .sessionCount(n) where n > 0:
            Text(String(n))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
                .padding(.leading, 10)
                .padding(.trailing, 12)
        case .sessionCount:
            EmptyView()
        }
    }
}
```

- [ ] **Step 6: Write the view smoke test**

Create `Tests/VibeCatUITests/IslandViewTests.swift`. This does not assert appearance — it proves the body evaluates for every state and every right-hand content variant without trapping, which is what catches a bad force-unwrap or a nil geometry.

```swift
import Foundation
import SwiftUI
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

private let externalDisplay = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
    visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415),
    safeAreaTop: 0, auxLeft: nil, auxRight: nil)

@MainActor
private func evaluate(_ screen: ScreenMetrics, _ state: IslandState,
                      _ right: CollapsedLayout.RightContent,
                      hovering: Bool, tier: IslandTier) {
    let g = IslandGeometry(screen: screen)
    let layout = CollapsedLayout(right: right, hovering: hovering)
    let frames = g.frames(rightFlank: layout.rightFlankWidth, tier: tier)
    _ = IslandBody(state: state, layout: layout, aura: AuraTrigger(),
                   now: t0, geometry: g, frames: frames).body
}

@MainActor @Test func theBodyEvaluatesForEveryState() {
    for state in IslandState.allCases {
        evaluate(mbp14, state, .sessionCount(2), hovering: false, tier: .rest)
    }
}

@MainActor @Test func theBodyEvaluatesForEveryRightHandContent() {
    let variants: [CollapsedLayout.RightContent] =
        [.nothing, .agentIcon, .sessionCount(0), .sessionCount(1), .sessionCount(999)]
    for right in variants {
        evaluate(mbp14, .running, right, hovering: false, tier: .rest)
    }
}

@MainActor @Test func theBodyEvaluatesWhileHoveringAndWithTheDrawerOpen() {
    evaluate(mbp14, .waiting, .sessionCount(3), hovering: true, tier: .hover)
    evaluate(mbp14, .waiting, .sessionCount(3), hovering: false,
             tier: .drawer(height: 288))
}

/// A notchless display has a zero-width dead zone; the spacer must cope.
@MainActor @Test func theBodyEvaluatesOnTheFallbackPill() {
    evaluate(externalDisplay, .dormant, .nothing, hovering: false, tier: .rest)
}

/// The wrapper pauses its timeline unless a bloom is in flight.
@MainActor @Test func theWrapperEvaluatesBothPausedAndRunning() {
    let g = IslandGeometry(screen: mbp14)
    let layout = CollapsedLayout(right: .sessionCount(1), hovering: false)
    let frames = g.frames(rightFlank: layout.rightFlankWidth, tier: .rest)

    var blooming = AuraTrigger()
    _ = blooming.observe(.idle, now: t0)
    _ = blooming.observe(.failed, now: t0)
    #expect(blooming.isBlooming(at: t0))

    for aura in [AuraTrigger(), blooming] {
        _ = IslandView(state: .failed, layout: layout, aura: aura,
                       now: t0, geometry: g, frames: frames).body
    }
}
```

- [ ] **Step 7: Run the tests and verify the package builds**

Run: `swift test --filter IslandViewTests`
Expected: PASS, 5 tests. Then `swift build && swift test` — build clean, whole suite green.

- [ ] **Step 8: Commit**

```bash
git add Sources/VibeCatUI/IslandGeometry.swift Sources/VibeCatUI/IslandView.swift \
        Tests/VibeCatUITests/CollapsedLayoutTests.swift \
        Tests/VibeCatUITests/IslandViewTests.swift
git commit -m "feat: collapsed layout measured from content, and the island view"
```

---

## Task 9: The app model

**Files:**
- Create: `Sources/VibeCatUI/AppModel.swift`
- Test: `Tests/VibeCatUITests/AppModelTests.swift`

**Interfaces:**
- Consumes: `SessionStore`, `VibeEvent`, `Reply` from `VibeCatCore`; `SocketServer` from `VibeCatTransport` — `init(path:readDeadline:)`, `start(handler: @escaping @Sendable (VibeEvent) -> Reply?) throws`, `stop()`.
- Produces: `@MainActor @Observable public final class AppModel` with `public init(socketPath: String)`, `public private(set) var store: SessionStore`, `public var islandState: IslandState`, `public var sessionCount: Int`, `public func ingest(_ event: VibeEvent, now: Date) -> Reply?`, `public func start() throws`, `public func stop()`, `public func prune(now: Date)`.

`SocketServer` calls its handler on a background thread, so `ingest` has to hop to the main actor. Plan 2 returns `nil` from the handler for every event — the island cannot answer anything yet, and a `nil` reply is exactly what makes the hook fall through to the CLI's own prompt. Plan 4 replaces that.

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatUITests/AppModelTests.swift`:

```swift
import Foundation
import Testing
import VibeCatCore
@testable import VibeCatUI

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func event(_ kind: Kind, session: String) -> VibeEvent {
    VibeEvent(id: "e-\(session)", cli: "claude-code", kind: kind,
              session: session, cwd: "/dev/\(session)")
}

@MainActor @Test func aFreshModelIsDormant() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    #expect(m.islandState == .dormant)
    #expect(m.sessionCount == 0)
}

@MainActor @Test func ingestingAnEventUpdatesTheIslandState() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    _ = m.ingest(event(.running, session: "a"), now: t0)
    #expect(m.islandState == .running)
    #expect(m.sessionCount == 1)

    _ = m.ingest(event(.permission, session: "b"), now: t0)
    #expect(m.islandState == .waiting)   // the worst state wins
    #expect(m.sessionCount == 2)
}

/// Plan 2 cannot answer anything yet, and nil is what makes the hook fall
/// through to the CLI's own prompt rather than hanging.
@MainActor @Test func everyEventIsAnsweredWithNoReplyForNow() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    #expect(m.ingest(event(.permission, session: "a"), now: t0) == nil)
    #expect(m.ingest(event(.question, session: "b"), now: t0) == nil)
}

@MainActor @Test func pruningDropsStaleFinishedSessionsOnly() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    _ = m.ingest(event(.done, session: "old"), now: t0)
    _ = m.ingest(event(.running, session: "busy"), now: t0)
    m.prune(now: t0.addingTimeInterval(AppModel.idleTTL + 1))
    #expect(m.sessionCount == 1)
    #expect(m.store.sessions.first?.id.session == "busy")
}

@MainActor @Test func theSameSessionUpdatesInPlace() {
    let m = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    _ = m.ingest(event(.running, session: "a"), now: t0)
    _ = m.ingest(event(.failed, session: "a"), now: t0.addingTimeInterval(1))
    #expect(m.sessionCount == 1)
    #expect(m.islandState == .failed)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter AppModelTests`
Expected: FAIL — `cannot find 'AppModel' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/VibeCatUI/AppModel.swift`:

```swift
import Foundation
import Observation
import VibeCatCore
import VibeCatTransport

/// Everything the island is reporting on. Owns the store and the socket.
@MainActor @Observable public final class AppModel {
    /// Finished sessions disappear after this long. Anything still running, or
    /// still waiting on you, stays however old it is.
    public static let idleTTL: TimeInterval = 20 * 60

    public private(set) var store = SessionStore()

    private let socketPath: String
    private var server: SocketServer?
    private var pruneTimer: Timer?

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public var islandState: IslandState { IslandState(store: store) }
    public var sessionCount: Int { store.sessions.count }

    /// Returns the reply to hand back to the hook. Always nil in Plan 2: the
    /// island cannot answer yet, and nil is what lets the hook fall through to
    /// the CLI's own prompt instead of blocking on us. Plan 4 replaces this.
    @discardableResult
    public func ingest(_ event: VibeEvent, now: Date = Date()) -> Reply? {
        store.apply(event, now: now)
        return nil
    }

    public func prune(now: Date = Date()) {
        store.prune(idleFor: Self.idleTTL, now: now)
    }

    public func start() throws {
        let server = SocketServer(path: socketPath)
        // SocketServer runs the handler on a fresh thread per connection and
        // may run it concurrently with itself, so this must hop rather than
        // assume isolation. Nothing waits on the hop: Plan 2 always replies nil.
        try server.start { [weak self] event in
            Task { @MainActor in self?.ingest(event) }
            return nil
        }
        self.server = server

        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.prune() }
        }
        RunLoop.main.add(t, forMode: .common)
        pruneTimer = t
    }

    public func stop() {
        server?.stop()
        server = nil
        pruneTimer?.invalidate()
        pruneTimer = nil
    }
}
```

> **Why the two closures differ.** The socket handler hops with a `Task`, but the prune timer uses `MainActor.assumeIsolated`. That is deliberate: `SocketServer.start` documents that it invokes the handler *on a fresh thread per connection*, so `assumeIsolated` there would trap. A `Timer` added to `RunLoop.main` fires on the main thread, so `assumeIsolated` is accurate. If you change either dispatch, re-check the pairing.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AppModelTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Verify the socket round-trip by hand**

```bash
swift build
VIBECAT_SOCKET=/tmp/vibecat-dev.sock swift run vibecat &
sleep 1
VIBECAT_SOCKET=/tmp/vibecat-dev.sock Scripts/replay.sh permission
```

The app is still a stub at this point, so this only needs to confirm the hook exits `0` and nothing crashes. Kill the background process afterwards.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatUI/AppModel.swift Tests/VibeCatUITests/AppModelTests.swift
git commit -m "feat: app model owning the session store and the socket server"
```

---

## Task 10: The controller and the executable

**Files:**
- Create: `Sources/VibeCatUI/NotchController.swift`
- Modify: `Sources/VibeCatApp/main.swift`
- Test: `Tests/VibeCatUITests/NotchControllerTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `@MainActor public final class NotchController` with `public init(model: AppModel, metrics: @escaping @MainActor () -> ScreenMetrics?)`, `public func present()`, `public func dismiss()`, `public func refreshGeometry()`, `public private(set) var geometry: IslandGeometry?`, `public private(set) var tier: IslandTier`.

Design §16: a display change must recompute geometry from the API. `NSApplication.didChangeScreenParametersNotification` is how that arrives — resolution changes, an external display appearing, and clamshell all come through it.

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatUITests/NotchControllerTests.swift`:

```swift
import Foundation
import Testing
import CoreGraphics
import VibeCatCore
@testable import VibeCatUI

private let t0 = Date(timeIntervalSince1970: 1_000_000)

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

@MainActor private func controller(_ metrics: @escaping @MainActor () -> ScreenMetrics?)
    -> (NotchController, AppModel) {
    let model = AppModel(socketPath: "/tmp/vibecat-test-unused.sock")
    return (NotchController(model: model, metrics: metrics), model)
}

@MainActor @Test func itAdoptsTheCurrentScreensGeometry() {
    let (c, _) = controller { mbp14 }
    c.refreshGeometry()
    #expect(c.geometry?.notch.width == 185)
    #expect(c.geometry?.isFallbackPill == false)
}

/// Design §16: recompute from the API, never cache across a display change.
@MainActor @Test func aDisplayChangeSwitchesToTheFallbackPill() {
    var current = mbp14
    let (c, _) = controller { current }
    c.refreshGeometry()
    #expect(c.geometry?.isFallbackPill == false)

    current = externalDisplay
    c.refreshGeometry()
    #expect(c.geometry?.isFallbackPill == true)
}

@MainActor @Test func noScreenAtAllLeavesTheControllerIdleRatherThanCrashing() {
    let (c, _) = controller { nil }
    c.refreshGeometry()
    #expect(c.geometry == nil)
    c.present()      // must not trap
    c.dismiss()
}

@MainActor @Test func theTierStartsAtRest() {
    let (c, _) = controller { mbp14 }
    #expect(c.tier == .rest)
}

/// The island tracks the store: an event moves it off dormant.
@MainActor @Test func ingestingAnEventDrivesTheControllersState() {
    let (c, model) = controller { mbp14 }
    c.refreshGeometry()
    #expect(model.islandState == .dormant)
    model.ingest(VibeEvent(id: "e1", cli: "claude-code", kind: .running,
                           session: "a", cwd: "/dev/a"), now: t0)
    #expect(model.islandState == .running)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter NotchControllerTests`
Expected: FAIL — `cannot find 'NotchController' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/VibeCatUI/NotchController.swift`:

```swift
import AppKit
import SwiftUI
import Observation

/// Owns the panel, the geometry and the hover monitor, and keeps them in step
/// with the model and with the display.
@MainActor public final class NotchController {
    public private(set) var geometry: IslandGeometry?
    public private(set) var tier: IslandTier = .rest

    private let model: AppModel
    private let metrics: @MainActor () -> ScreenMetrics?
    private var panel: NotchPanel?
    private var hover: HoverMonitor?
    private var aura = AuraTrigger()
    private var bloomEnd: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    public init(model: AppModel, metrics: @escaping @MainActor () -> ScreenMetrics?) {
        self.model = model
        self.metrics = metrics
    }

    public convenience init(model: AppModel) {
        self.init(model: model, metrics: { ScreenMetrics.current() })
    }

    public func refreshGeometry() {
        geometry = metrics().map(IslandGeometry.init(screen:))
        guard let frames = currentFrames() else { return }
        panel?.apply(frames)
        hover?.frame = frames.shape
        render()
    }

    public func present() {
        guard let frames = currentFrames() else { return }

        let panel = self.panel ?? NotchPanel(frames: frames)
        self.panel = panel
        panel.apply(frames)

        let hover = self.hover ?? HoverMonitor()
        hover.frame = frames.shape
        hover.onChange = { [weak self] hovering in
            self?.tier = hovering ? .hover : .rest
            self?.refreshGeometry()
        }
        hover.start()
        self.hover = hover

        render()
        // Never makeKeyAndOrderFront — the app must not steal focus.
        panel.orderFrontRegardless()

        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshGeometry() }
            }
    }

    public func dismiss() {
        bloomEnd?.cancel()
        bloomEnd = nil
        hover?.stop()
        hover = nil
        panel?.orderOut(nil)
        panel = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private var layout: CollapsedLayout {
        let hovering = tier == .hover
        let count = model.sessionCount
        return CollapsedLayout(right: count > 0 ? .sessionCount(count) : .nothing,
                               hovering: hovering)
    }

    private func currentFrames() -> IslandFrames? {
        geometry?.frames(rightFlank: layout.rightFlankWidth, tier: tier)
    }

    private func render() {
        guard let geometry, let frames = currentFrames(), let panel else { return }
        let now = Date()
        let state = model.islandState

        // AuraTrigger does its own change detection, so this is called
        // unconditionally and only reports true on an actual change.
        if aura.observe(state, now: now) {
            // TimelineView fixes its paused flag when the view is built, so
            // one more render is needed to stop it ticking after the bloom.
            bloomEnd?.cancel()
            bloomEnd = Task { [weak self] in
                try? await Task.sleep(for: .seconds(AuraTrigger.duration))
                guard !Task.isCancelled else { return }
                self?.render()
            }
        }

        let view = IslandView(state: state, layout: layout, aura: aura,
                              now: now, geometry: geometry, frames: frames)
        if let hosting = panel.contentView as? NSHostingView<IslandView> {
            hosting.rootView = view
        } else {
            panel.contentView = NSHostingView(rootView: view)
        }
    }
}
```

> **Note for the implementer:** `render()` is called on discrete events, so the aura's envelope will not animate on its own — it will jump to whatever `opacity(at:)` returns at that instant. Driving it needs a display link or a `TimelineView`, which is a Plan 3 concern once the cat needs per-frame animation too. If you find the aura never appears at all, say so in your report rather than adding a timer here; a single stale frame is the expected behaviour for this plan.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter NotchControllerTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Write the executable**

Replace `Sources/VibeCatApp/main.swift`:

```swift
import AppKit
import VibeCatCore
import VibeCatUI

// No Dock icon, no menu bar of our own. The equivalent of LSUIElement for a
// target with no Info.plist.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let model = AppModel(socketPath: SocketPath.default)
let controller = NotchController(model: model)

do {
    try model.start()
} catch {
    FileHandle.standardError.write(
        Data("vibecat: could not open the socket: \(error)\n".utf8))
    exit(1)
}

controller.refreshGeometry()
controller.present()

app.run()
```

- [ ] **Step 6: Verify by hand, end to end**

```bash
swift build
VIBECAT_SOCKET=/tmp/vibecat-dev.sock swift run vibecat
```

In a second terminal:

```bash
VIBECAT_SOCKET=/tmp/vibecat-dev.sock Scripts/replay.sh permission
```

Check, and record each in the task report:
1. The island appears in the notch, welded to the top edge, with the left flank clear of the cutout.
2. Its colour turns amber on the `permission` event and the session count reads `1`.
3. An aura blooms once on that change, in amber, and fades to nothing — it does not stay lit.
4. Resting the cursor on it for a third of a second widens the right flank.
5. Clicking a menu title that sits under the island's left flank still opens that menu.
6. The hook exits `0` with no output.

Also confirm the island is genuinely idle at rest: with no events arriving, `vibecat`'s CPU use in Activity Monitor should sit near zero. A few percent means the timeline never paused.

- [ ] **Step 7: Run the full suite**

Run: `swift test`
Expected: all tests pass — the 83 from Plan 1 plus the new ones.

- [ ] **Step 8: Commit**

```bash
git add Sources/VibeCatUI/NotchController.swift Sources/VibeCatApp/main.swift \
        Tests/VibeCatUITests/NotchControllerTests.swift
git commit -m "feat: notch controller and the vibecat executable"
```

---

## Self-Review

**Spec coverage.** §4.1 five states → Task 3. §4.2 worst state wins → Tasks 3, 9. §4.3 colour means state → Task 3. §5.1 cutout is a hole, runtime dimensions, notchless fallback → Tasks 1, 2, 8. §5.2 which side holds what → Task 8. §5.3 LW constant → Task 2 (with a load-bearing test). §5.4 measured widths → Task 8. §5.5 corners and fillet suppression → Task 6. §6.1 rest and hover tiers → Tasks 2, 5, 8. §6.2 collapsed anatomy and configurable right content → Task 8. §9.2 aura → Task 7. §16 display change, notchless fallback → Tasks 1, 2, 10.

**Deliberately out of scope**, each deferred to a named plan: the cat sprite and moods (§7, Plan 3), badges (§8, Plan 3), the drawer's contents and answering (§6.3, §10, Plan 4), the session list (§11, Plan 5), sound (§12, Plan 6), jump (§13, Plan 6), settings (§14, Plan 6), reduced motion (§9.3, Plan 6 — it is a settings-driven behaviour). `IslandTier.drawer` exists and has tested geometry, but nothing opens it yet.

**Two gaps this plan closes that the spec did not name.** `SessionState` has four cases while the design describes five, so `dormant` is introduced at the UI layer in Task 3 — otherwise a machine that has never run anything looks like one that just succeeded. And the aura needs room outside the body to bloom into, so Task 2 inflates the panel on three sides.

**One risk carried into execution.** `NSHostingView` inside a borderless non-activating panel was not spiked; the fallback is a plain `NSView` with `draw(_:)`, as the spike itself used.

**Two rulings made before execution**, both on points where this plan mandated something a review rubric would call a defect:

- `IslandView` originally shipped with no test. Ruling: add a smoke test (Task 8, Step 6) that evaluates `IslandBody.body` across every state, every right-hand content variant, hover, drawer and the fallback pill. It asserts nothing about appearance — it catches traps.
- The aura was originally computed but never animated, deferred to Plan 3. Ruling: make it real now. `IslandView` became a `TimelineView` wrapper that ticks only while a bloom is in flight, `AuraTrigger` gained `isBlooming(at:)`, and `NotchController` renders once more at the end of a bloom to pause the timeline again — because an idle machine must not animate.
