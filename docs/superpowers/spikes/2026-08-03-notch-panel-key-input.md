# Can the Notch Panel Take Key Input Without Stealing Focus?

**Date:** 2026-08-03
**Status:** Complete. **Path A.** Plan 6's keyboard items are unblocked.
**Purpose:** Answer Task 9's one genuine hardware unknown, which has gated `KeyRouting.pick`, the `Other…` row and every number-key item since Plan 4.

**Hardware:** MacBook Pro 14″, built-in Liquid Retina XDR. **OS:** Darwin 25.5.0. **Toolchain:** Swift 6.3.2.
**Probe:** `Sources/VibeCatApp/KeyDownProbe.swift`, signed debug bundle, screen unlocked.

---

## The question

Can a `.nonactivatingPanel` at `.statusBar` become key and receive `keyDown`
**without stealing focus from the terminal an agent runs in?** Mouse input was
measured in Plan 2 and does not steal focus. Keyboard was never measured, and
`KeyDownProbe`'s own interpretation guide names the three possible outcomes:
Path A (key without focus — wire the number keys), Path B (becoming key
activates the app — do not wire them, `Escape` only), or unresolved.

## The answer: Path A, and input is delivered *exclusively*

| reading | value |
|---|---|
| `frontmost before` | TextEdit — not `loginwindow`, so the run is valid |
| `panel.isKeyWindow` | **true** |
| `panel.level == .statusBar` | true — the production configuration, not a re-creation |
| `NSApp.isActive` | true |
| `frontmost after` | TextEdit |
| **`frontmost changed`** | **false** |
| `keyDown` received by the panel | **yes** — `Escape` (keyCode 53) ×2, then `5`, `3`, `8` |

Reproduced across three runs, with Finder frontmost in the first and TextEdit in
the other two.

### The part the brief did not ask for, and it matters more

`isKeyWindow` and `frontmostApplication` are proxies. The probe's own doc comment
says so: they are "proxies for whether input actually arrives, not a substitute
for checking that it does". So the third run used a **witness** — an empty
TextEdit document, frontmost, whose character count answers "did the keystroke
land there instead?" directly.

| step | TextEdit chars | panel `keyDown` |
|---|---|---|
| document opened with `START` | 5 | — |
| **control:** post `7` with **no probe running** | **6** | — |
| post `8` **while the panel is key** | **6, unchanged** | **`char="8"` logged** |

The control run is what makes the second row mean anything: it proves a
synthesised digit *does* reach TextEdit when the panel is not key, so the
unchanged count during the probe is exclusion rather than a broken witness.

**Keyboard input goes to the panel and to nothing else, while the other app
remains the system's frontmost application.**

## The hazard this uncovers

Path A is the good outcome for §10.1's number keys. It is also a trap nobody had
named, and it follows directly from "exclusively":

> **While the panel holds key status, the person's terminal receives nothing —
> and still looks focused.** `frontmostApplication` never changed, so the
> terminal keeps every visual cue of having focus while its keystrokes are being
> swallowed by an island the person may not even be looking at.

So the panel must take key status **only while a question is actually open**, and
give it back the instant the question is answered, dismissed or lapses. A panel
left key at rest would make VibeCat silently eat everything the person types. That
is a Plan 6 design constraint discovered by measurement, not a preference.

Related, and recorded so it is not re-derived: **`NSApp.isActive` is not a usable
proxy here.** It read `true` in every run while `frontmostApplication` stayed on
the other app throughout. The Path B test is specifically whether `frontmost
after` names `com.gcat332.vibecat`; it never did.

## What this unblocks

- **`KeyRouting.pick` becomes reachable.** It is fully tested and, until now, was
  called from nothing in `Sources/`. It takes a `Character`, not an `NSEvent`, so
  it consumes what actually arrived without change — see the caveat below.
- **`Other…` can come back.** Plan 4 cut the row because it opened a field nobody
  could type into. Typing works.
- **Everything else in Plan 6 that was "gated on keyboard input"**, including the
  §14 General setting for number keys.

## Caveat, stated because it is the one weakness in this evidence

The keystrokes were **synthesised** with System Events (`keystroke "8"` /
`key code 53`), not typed on the physical keyboard. They arrived as
**numeric-keypad** events — keyCodes 85/87/91 with `modifiers=2097152`
(`.numericPad`) — rather than top-row digit keyCodes.

This does not weaken the conclusion for our purposes, for one specific reason:
`KeyRouting.pick` matches on `character.wholeNumberValue`, so `"8"` is `"8"`
whether it came from the keypad or the top row, and the panel logged the
character correctly either way. A design that had matched on `keyCode` would need
re-checking; ours does not.

What remains untried is a **physical** top-row keypress. If it ever matters, the
cheap check is to run the probe and press one by hand — the probe prints every
keystroke it receives, which is exactly what it was built for.
