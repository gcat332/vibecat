# Notch Shell Spike

**Date:** 2026-08-01
**Status:** Complete. Spike code discarded; every load-bearing snippet is reproduced below.
**Purpose:** Answer, on real hardware, the questions Plan 2 (notch shell) cannot be written without.

**Hardware:** MacBook Pro 14″, Apple M3 Pro, built-in Liquid Retina XDR, 3024×1964 native.
**OS:** macOS 26.5.2 (build 25F84). **Toolchain:** Swift 6.3.2, language mode v6, strict concurrency.

Every number below was measured by a throwaway SwiftPM executable, not read from documentation.
Where a test turned out to be invalid, that is recorded as such rather than dressed up as a result.

---

## 1. The notch is fully derivable from `NSScreen`

No per-model table is needed. `safeAreaInsets` and the auxiliary areas are enough.

| Property | Value |
|---|---|
| `screen.frame` | `0, 0, 1512 × 982` |
| `screen.visibleFrame` | `0, 0, 1512 × 949` |
| `backingScaleFactor` | `2` |
| `safeAreaInsets.top` | `32` |
| `auxiliaryTopLeftArea` | `x 0, y 950, w 663, h 32` |
| `auxiliaryTopRightArea` | `x 848, y 950, w 664, h 32` |
| **derived notch** | `x 663, y 950, w 185, h 32` |

```swift
// The only geometry code Plan 2 needs. Returns nil on a notchless display.
func notchRect(of s: NSScreen) -> NSRect? {
    guard s.safeAreaInsets.top > 0,
          let l = s.auxiliaryTopLeftArea,
          let r = s.auxiliaryTopRightArea else { return nil }
    return NSRect(x: l.maxX,
                  y: s.frame.maxY - s.safeAreaInsets.top,
                  width: r.minX - l.maxX,
                  height: s.safeAreaInsets.top)
}
```

### Two traps in those numbers

**The notch is not centred.** Left flank 663 pt, right flank 664 pt. Notch centre is 755.5,
screen centre is 756.0 — off by half a point. Plan 2 must position the island from
`auxiliaryTopLeftArea.maxX`, never from `screen.frame.midX`. This is the same conclusion the
prototype reached by different means: with the left flank pinned at a constant `LW`, the
island's left edge is `notch.minX − LW` and the right flank width drops out of the equation.

**The menu bar is one point taller than the notch.** `frame.maxY − visibleFrame.maxY = 33`,
but `safeAreaInsets.top = 32`. So there is a 1 pt strip at `y = 949…950` that is menu bar but
not notch. A collapsed island matching the notch height exactly stops 1 pt short of the
content area. Harmless, but the island must not be sized from `menuBarHeight`.

---

## 2. AppKit will move your window out of the menu bar

This was the first thing the spike found, and it invalidated the entire first probe run.

Asked for `y = 950`. Got `y = 917` — flush under `visibleFrame.maxY`. `NSWindow` runs
`constrainFrameRect(_:to:)` on every `setFrame` and clamps the frame to the visible area.
Refusing it is the whole trick:

```swift
final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect                     // no super call — that is the clamp
    }
    override var canBecomeKey: Bool { true }   // borderless panels need this to take text
}
```

Proven load-bearing by flipping it inside one process:

| | resulting frame |
|---|---|
| constraint active | `x 605, y 917, w 301, h 32` |
| constraint refused | `x 605, y 950, w 301, h 32` ← what we asked for |

---

## 3. Window level must be ≥ 25

The menu bar is a Window Server window named `Menubar` at layer **24**. Probed five levels,
hit-testing the notch centre and both flanks against the system-wide `CGWindowList` z-order:

| level | raw | notch centre | flanks |
|---|---|---|---|
| `.floating` | 3 | Menubar wins | Menubar wins |
| `.mainMenu` | 24 | Menubar wins | Menubar wins |
| **`.statusBar`** | **25** | **ours** | **ours** |
| `.popUpMenu` | 101 | ours | ours |
| `.screenSaver` | 1000 | ours | ours |

`.statusBar` (25) is the lowest level that works, so it is the right one — going higher buys
nothing and starts fighting menus and alerts. Note Control Center's own status items also sit
at 25 and were unaffected, because our footprint does not reach them.

**The dead zone is a drawing rule, not an interaction rule.** At level 25 we own the notch
centre outright, and the cursor can be placed there. The camera housing hides *pixels*; it does
not block *events*. So the design constraint stands as written — no content under the cutout —
but hover and click across the full island width are available.

---

## 4. The island survives fullscreen

Toggled a throwaway window to fullscreen and re-probed:

- `hostIsFullscreen: true`
- island still visible, frame still at `y = 950`
- notch centre hit test: **ours**, layer 25, above the fullscreen host at layer 0

Required collection behaviour:

```swift
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
panel.hidesOnDeactivate = false
```

**Caveat worth carrying into Plan 2:** `occlusionState.contains(.visible)` reported `false`
while the window was demonstrably frontmost in the z-order. Do not gate rendering, animation,
or event polling on `occlusionState` for this panel — it lies for non-activating panels.

---

## 5. The menu-bar collision is real

The probe could not resolve it — every point across the menu bar reports the same single
`Window Server / Menubar` window, because menu titles are not separate windows. The
Accessibility API would have given exact title extents, but `AXIsProcessTrusted()` was `false`,
so that path was unavailable.

The screenshot settled it anyway. With VS Code frontmost, its **`Help`** menu title ends roughly
**30 pt** to the left of the island's left edge at `x = 605`. An app with more menus, longer
titles, or a non-English localisation overlaps the left flank — exactly where the cat lives.

**Consequence for Plan 2:** the collapsed island must be click-through. Not optional.

```swift
panel.ignoresMouseEvents = true    // collapsed: never eat a menu title
panel.ignoresMouseEvents = false   // expanded: we own the space, take the clicks
```

---

## 6. Hover must be polled, not tracked

`NSTrackingArea` is unusable for the collapsed island — a click-through window receives no
mouse events by definition, so there is nothing for a tracking area to observe.

*A negative result, recorded honestly:* the spike first tried to test this with
`CGWarpMouseCursorPosition`, and `mouseEntered` failed to fire in **both** the click-through and
the event-taking configuration. That does not show hover is broken. A cursor warp does not post
a mouse-moved event, so a tracking area cannot see it either way. The test was invalid; it
proves nothing about `NSTrackingArea` under normal mouse movement.

What *was* proven: polling `NSEvent.mouseLocation` needs neither a delivered event nor any
permission, and works while the panel is fully click-through. Four warp-and-read samples,
`ignoresMouseEvents = true` throughout, all agreed with the expected containment:

| cursor warped to | inside island? | agreed |
|---|---|---|
| left flank `634, 966` | yes | ✔ |
| notch centre `755, 966` | yes | ✔ |
| right flank `877, 966` | yes | ✔ |
| well outside `200, 400` | no | ✔ |

So the collapsed state polls `NSEvent.mouseLocation` against the island frame; on entry it
expands and hands mouse events back to itself. A global `NSEvent` monitor for `.mouseMoved` is
the event-driven alternative and needs no Accessibility permission either — Plan 2 should
prefer it and keep polling as the fallback.

---

## 7. Frame animation is cheap

120 frames of simultaneous width **and** height change (301×32 → 520×190) at level 25,
each with `setFrame(_:display: true)`:

| | ms |
|---|---|
| average per frame | **0.197** |
| worst single frame | **3.34** |
| 60 fps budget | 16.67 |

Roughly 5× headroom even on the worst frame. Animating the window frame directly is viable —
Plan 2 does not need the common workaround of a large always-on transparent window with an
animated sublayer.

---

## 8. Swift 6 strict concurrency is a non-issue

The spike was deliberately built with `swiftLanguageMode(.v6)`. Everything AppKit-facing is
`@MainActor`; the panel subclass, the view, and the geometry helpers all compiled clean with no
`Sendable` friction and no `@preconcurrency` escapes.

One tooling note: SourceKit reported ten actor-isolation errors in the editor that `swift build`
did not — it was not picking up the target's `swiftLanguageMode` setting. Trust the build.

Related, and consistent with what Plan 1 found: the app target should use `@main struct App`
rather than top-level `main.swift`, so it stays `@testable import`-able.

---

## 9. Recommended shape for Plan 2

```swift
let panel = NotchPanel(contentRect: frame,
                       styleMask: [.borderless, .nonactivatingPanel],
                       backing: .buffered, defer: false)
panel.level = .statusBar                  // 25 — lowest that clears the menu bar
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.isMovable = false
panel.isFloatingPanel = true
panel.hidesOnDeactivate = false
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
panel.ignoresMouseEvents = true           // until expanded
panel.setFrame(frame, display: true)      // survives, because constrainFrameRect is overridden
panel.orderFrontRegardless()              // not makeKeyAndOrderFront — never steal focus
```

Plus: observe `NSApplication.didChangeScreenParametersNotification` and recompute geometry —
display changes, resolution changes, and clamshell all arrive through it.

---

## 10. Left open

These were not measured and Plan 2 should treat them as unknowns, not assumptions.

- **Multi-display and clamshell.** Only one screen was attached. `notchRect` returns `nil` on a
  notchless display; Plan 2 must define the fallback (a synthetic island near the menu bar
  centre is the obvious candidate, but it is undecided).
- **Mission Control and Stage Manager.** Not automatable from the spike; needs a manual pass.
- **Exact menu-title extents per app.** Requires Accessibility permission. Moot if the collapsed
  island stays click-through, which is the recommendation above.
- **Menu bar auto-hide.** Untested. When the menu bar hides, `visibleFrame` grows but the notch
  stays; the island's own position should be unaffected, but that is a prediction, not a
  measurement.
