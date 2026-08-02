# Notch Shell — carried follow-ups

Triaged by the whole-branch review at the end of Plan 2. Everything here was
found, judged, and deliberately deferred — none of it blocks the merge. The
ledger it came from is gone; this is the surviving record.

## Needs a decision, not just a patch

**The fallback pill breaks the pinned-left-edge rule.** On a display with no
notch, `IslandGeometry.frames` centres the island on `screen.frame.midX`
([IslandGeometry.swift](../../../Sources/VibeCatUI/IslandGeometry.swift)), so
the left edge — and therefore the cat — walks sideways as the right flank
grows. Design §5.3 calls that edge fixed. On a notched display it is, because
the edge derives from `notch.minX`; the fallback has no notch to derive from.

Either pin the pill's left edge to something stable, or amend §5.3 to say the
invariant holds only where there is a cutout. Untested either way: no test
covers left-edge stability on a notchless display.

## Verification still owed

**Nobody has seen the island.** Visual checks were attempted on real hardware
but the machine's session was locked. Confirmed by other means: the app
launches and exits cleanly, its log is silent, idle CPU is 0.1%, the window
sits at layer 25, hook round-trips work, and back-to-back events each produce a
render. The final review also re-derived the collapsed layout arithmetically
and found nothing that would render wrong.

Unconfirmed: appearance, the amber state colour, the aura bloom, hover
widening, and menu click-through.

> **Settled 2026-08-02**, on an unlocked machine, except for one item.
> Appearance, geometry (left edge at exactly `notch.minX − 58`), the amber
> state colour, and hover widening are all **confirmed correct**. The aura
> **fires** correctly — the exact `sin` curve, ~960ms — but at 0.14 was too
> faint to see, which is what this document predicted three lines further down;
> raised to 0.34 in `45e1e31`. Click-through remains **unconfirmed**:
> `ignoresMouseEvents = true` is set, but `NSWindow.windowNumber(at:)` cannot
> test it from another process (it returns 0 for windows outside the caller, so
> even the control point reads 0), and the island's footprint does not overlap
> a clickable menu item at rest anyway. It needs a real click.
>
> Worth knowing for later: this machine runs with the **menu bar auto-hidden**,
> so the island often sits over the wallpaper rather than a dark bar.
>
> **Second pass, same day.** Testing 0.34 on screen found the machine in
> **Light mode**, and the bloom lifted the halo by 8 against the 26 it was
> tuned for — the constant had been raised against a dark backdrop the design
> assumes and this machine does not always have. Fixed properly in `1ed2a31`:
> the aura's *colour* now follows the backdrop, deepening on light where a
> bright glow has nowhere to go, with both peaks measured to the same lift
> (0.34 dark, 0.30 light). On screen the light-mode bloom went 8 → 12 and
> reversed from washing out to darkening.
>
> **Still open, deliberately.** `colorScheme` describes the menu *bar*. With
> the bar auto-hidden the island sits over the wallpaper, so a dark wallpaper
> under a Light system picks the deepened glow when the bright one is right.
> Reading the pixels actually behind the island would need screen-recording
> permission — too much to ask for a glow. Revisit only if it grates in use.

Four things will look surprising but are correct as built, so they should not
be filed as bugs:

- Hover widens the right flank by **150pt of empty black**, instantly. The
  reveal content is Plans 4–5 and the 280ms transition is unimplemented, so
  what you get is a snap to a wider, emptier island.
- The aura is a 14%-alpha coloured shadow over an already-dark menu bar. It may
  be genuinely hard to see. If it looks absent, check `AuraTrigger.peakOpacity`
  before suspecting the trigger.
- Dormant and idle are visually identical — same green, same placeholder
  rectangle — until the cat lands in Plan 3.
- A **1pt sliver of menu bar** shows below the island. The menu bar is 33pt,
  the notch is 32pt, and the island is sized from the notch. Intentional, and
  pinned by `ScreenMetricsTests.theMenuBarIsOnePointTallerThanTheNotch`.

## Deferred to a later plan

**Motion (design §9.1) is unimplemented.** Width spring `0.42/0.72`, drawer
spring `0.42/0.78`, hover reveal `280ms`. Nothing on this branch animates —
`NotchPanel.apply` snaps the frame with `setFrame(_:display: true)`. This sat
in the plan's Global Constraints while appearing in neither a task nor the
out-of-scope list; it belongs with Plan 3, which brings the cat and the
per-frame animation machinery it needs.

## Small, safe, unhurried

- **Zero-width auxiliary gap.** `ScreenMetrics.notch` uses a strict
  `r.minX > l.maxX`, so a zero-width gap reports `hasNotch == false`.
  Defensible, untested.
- **Dwell uses wall-clock `Date()`.** A large backwards clock jump disables
  hover until it catches up. Self-healing and astronomically rare;
  `ContinuousClock` would fix it if the injected-clock design is revisited.
- **`CollapsedLayoutTests`' `>=` has exactly zero slack.** Whole-string widths
  match `count × advance` to the last bit today. Correct, but a one-ULP font
  change flips it red for no real reason. A comment now says so; a tolerance
  would be better.
- **Panel width clamp reads the just-mutated `origin.x`.** Correct, implicit,
  wants a comment.
- **Four unrelated assignments sit between `isFloatingPanel` and `level`** in
  `NotchPanel.init`. Comments guard both ends and `theLevelIsStatusBar` pins
  the result, but the trap already bit once.
- **The `onChange` callback trades completeness for discipline.** Any future
  `AppModel` method that mutates `store` must remember to fire it. Both current
  writers (`ingest`, `prune`) do.
- **No single-instance guard.** `SocketServer.start` unlinks before binding, so
  a second `vibecat` steals the socket and the first becomes a zombie with a
  live panel and a dead listener. Out of Plan 2's scope, but this branch is the
  first to make `vibecat` launchable.
- **Concurrent ingests are unordered.** `AppModel` hops each event onto the
  MainActor with an unordered `Task`, and `now:` defaults at execution time
  rather than arrival. Two events for one session from two connections could
  apply out of order. Realistically impossible — one CLI's hooks are
  sequential — and the fix is to capture `Date()` on the socket thread.

## Rejected, with the reason — do not "clean these up"

**`allSatisfy(\.isHexDigit)` in `RGBA(hex:)` is not redundant.** It was filed as
duplicating the `UInt32(_:radix:)` parse. It does not: that initialiser accepts
a leading sign, so `UInt32("+5B9DF", radix: 16)` succeeds and the seven-character
string `"#+5B9DF"` would parse as a valid colour without the guard. A comment in
the source now records this.
