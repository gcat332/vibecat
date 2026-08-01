# Animation Spike

**Date:** 2026-08-01
**Status:** Complete. Spike code discarded; the findings that shape Plan 3 are below.
**Purpose:** Answer, on real hardware, what Plan 3 (the cat, badges and motion) cannot be written without.

**Hardware:** MacBook Pro 14″, Apple M3 Pro, 120 Hz ProMotion. **OS:** macOS 26.5.2. **Toolchain:** Swift 6.3.2.

Measured, not assumed. Where a measurement turned out to be invalid it is recorded as such
rather than dressed up — the first sprite run below is a worked example of that.

---

## 1. Animate the content, not the window

Both work. Neither drops a frame. But they are not equal.

| | mean | p50 | p95 | worst | frames > 20 ms |
|---|---|---|---|---|---|
| spring on the **window frame** | 11.66 ms | 11.19 | 15.16 | 16.93 | **0** |
| spring on **content** in a fixed-size window | **9.86 ms** | **9.92** | **10.34** | **10.41** | **0** |

Same loop, same 8.33 ms pacing overhead in both, so the comparison is sound even though the
absolutes include that overhead: the real work is roughly 3.3 ms against 1.5 ms.

What matters is the tail. Window-frame animation asks the window server to move the window
every frame, and its p95 is 50 % worse with a worst case that brushes the 16.67 ms budget.
Content animation inside a window that never resizes is flat — a 0.5 ms spread across the
whole run.

**For Plan 3:** size the panel once for the largest state it can reach and animate the
silhouette inside it. This also removes a whole class of bug, because the panel frame stops
being a thing that changes 120 times a second while hover polling reads it.

The cost is a permanently larger window. That is tolerable precisely because the collapsed
island is click-through — a bigger transparent region intercepts nothing. It stops being
free the moment the drawer takes mouse events, so the expanded state still needs the frame
sized to what it actually covers.

---

## 2. Frame rate is the whole cost. Path batching is not.

The cat is 18 × 14 with 252 non-transparent cells. First instinct was that filling 252 tiny
paths per frame was the problem, so the fix would be to batch them into one path per colour.

| variant | draws/s | CPU |
|---|---|---|
| 252 individual fills, display rate | 118.3 | 20.5 % |
| **batched** to ~6 paths, display rate | 119.3 | **20.3 %** |

Batching bought nothing. The cost is per-frame overhead — SwiftUI re-evaluating the
timeline, the `Canvas`, and the hosting view — not the fills inside it.

Rate is what costs:

| rate | draws/s | CPU |
|---|---|---|
| 8 fps | 8.0 | **~6 %** |
| 30 fps | 30.1 | ~9–10 % |
| 120 fps | 119.8 | ~15–18 % |
| **static, no timeline** | **0** | **0.0 %** |

**For Plan 3:** run the sprite at **8–12 fps**. That is both authentic — pixel art steps, it
does not ease, and the prototype's `steps()` said so first — and three times cheaper than
30 fps. Do not batch paths for performance; batch them only if it reads better.

### `TimelineView(.animation)` runs at the display's rate, not 60

`.animation` with no `minimumInterval` produced **118.3 draws/s** on this 120 Hz panel. An
animation authored against a 60 fps assumption silently does twice the work here. Always
pass `minimumInterval`.

### `.periodic` is not cheaper than `.animation` — a hypothesis that failed

`.animation` is driven off the display link and `.periodic` off a timer, so the expectation
was that `.periodic` would avoid the display link's overhead at low rates. Measured at the
same 8 fps: `.animation` 6.0–6.6 %, `.periodic` 4.7–6.9 %. Indistinguishable. Pick whichever
reads better; there is no performance argument either way.

---

## 3. The floor is ~6 %, and only stopping removes it

Any live timeline costs about 6 % of a core even at 8 fps, and removing the `TimelineView`
entirely drops it to a measured **0.0 %** with zero `Canvas` draws.

So "an idle machine must not animate" is not a nicety — it is the only mechanism that gets
the cost to zero. This lands directly on design §7.2's mood table:

| mood | state | what it should cost |
|---|---|---|
| `sleep` | dormant | no timeline at all, or a 1–2 fps drowse |
| `trot` | running | 8–12 fps while an agent is actually working |
| `call` | waiting | 8–12 fps — the one state that should attract the eye |
| `happy` | finished | one spring pop, then stop |
| `dead` | failed | slow wobble, or a static frame |

Two of the five states are steady-state and should have no timeline running.

---

## 4. Rebuilding `rootView` every frame is the wrong architecture

The first sprite measurement assigned a freshly-built `AnyView` tree to
`NSHostingView.rootView` on every frame. That is what produced the 20 % figure, and it is
also **what `NotchController.render()` does today** — it constructs a new `IslandView` and
assigns it on every state change.

That is survivable at the handful of renders per second Plan 2 generates. It is not
survivable at sprite rates.

**For Plan 3:** the hosting view's root is assigned once. Everything that changes per frame
changes *inside* it, through a `TimelineView` reading observable state — not by handing
SwiftUI a new tree from AppKit.

---

## 5. A measurement that was invalid, and why

The first sprite run reported `mean=19.64 ms, p95=20.38, 20.7 % of frames over 20 ms` and
`1.8 % CPU when idle`. All of it was worthless:

- The loop drove itself with `pump(1/60)` and timed the resulting intervals, so it was
  measuring its own `sleep` — the 19.64 ms mean is 16.7 ms of sleep plus ~3 ms of work.
- The "idle" CPU sample was taken while that same busy pump loop was still spinning, so it
  measured the harness, not the app.

Replaced with: the real run loop via `app.run()`, a counter incremented inside the `Canvas`
draw closure to count actual draws, and CPU sampled externally with `ps`. The numbers in
§2 and §3 come from that.

The lesson is the same one §2 of the notch-shell spike records: a spike that measures the
wrong thing is worse than no spike, because its numbers get written into a plan.

---

## 6. Left open

- **Battery.** Every number here is on mains power. ~6 % continuous for a trotting cat may
  read differently on battery, and macOS may throttle differently.
- **External display.** All measurements are on the 120 Hz built-in panel. A 60 Hz external
  display halves the display-link rate and probably the cost.
- **Multiple sprites.** Plan 5's session list may show several agent rows at once. Only one
  sprite was measured.
- **`drawingGroup()` / Metal rasterisation** was not tried. If the ~6 % floor proves too
  expensive it is the next thing to measure.
