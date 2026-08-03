# Handoff — 2026-08-03

Where VibeCat is, what to do next, and the three things a newcomer would
otherwise have to rediscover.

## State

`main`, clean, **373 tests**, **168 commits ahead of `origin/main` and
deliberately unpushed**. Plans 1–4 done.

```bash
swift test                                   # 373, ~2s
Scripts/build-app.sh && open .build/VibeCat.app
```

`open`, not the binary inside the bundle — launching it from a shell makes the
shell the responsible process and the app loses its own permission identity.

## What works, verified on hardware rather than argued

On 2026-08-02, from a signed bundle, with a real `rm -rf build/` permission
event through the real hook and socket:

- The island sits in the notch, click-through, at 0.35% of a core when idle.
- A question does **not** open the drawer by itself. Clicking the island does —
  the panel grew from `y 0..56` to `y 0..344`, which is notch 32 + face 288 +
  `auraMargin` 24, exactly.
- **Focus is never stolen.** Finder was activated first so the reading was not
  confounded, and stayed frontmost through the island click, the row click and
  the confirming tap.
- The round trip completes: two taps — pick, then confirm, because §10.3's second
  ask fired for real — and the hook printed claude-code's own
  `permissionDecision`.

Fail-open was enumerated across all ten ways a question can end. Every one
reaches `nil`, so a crashed or silent island can never hang a terminal.

## Do these first

In this order. The first is the only one that touches safety.

1. **`.truncationMode(.middle)` on the drawer's command body.** `.lineLimit(1)`
   stopped the confirmation banner clipping, but SwiftUI's default `.tail`
   truncation eats the *destination*: `rm -rf /Users/dev/projects/vibe…`. A
   person is asked to authorise a destructive command unable to see its target.
2. **Measure the badge transforms with `getrusage`.** Every badge now animates as
   a SwiftUI transform on the assumption that a repeating `.scaleEffect` does not
   re-invoke the `Canvas` renderer. That assumption is load-bearing in shipped
   code and has never been measured. If it is wrong, the idle island's 0.35% is
   gone. `Badge.pulse` says so in the source.
3. **Run `KeyDownProbe`** on an unlocked machine
   (`VIBECAT_KEYDOWN_PROBE=1`). It settles the plan's one genuine unknown —
   whether a `.nonactivatingPanel` at `.statusBar` can take *key* events without
   stealing terminal focus. Mouse input was measured and does not. The probe
   prints `frontmostApplication` before and after and aborts on `loginwindow`,
   because an earlier attempt at that measurement was void for exactly that
   reason and nearly became a recorded fact.
4. `@MainActor` on `theConfirmationBannerNamesTheControlThatActuallyConfirms` —
   the branch's one compiler warning.
5. **Cache `CatPalette`'s five accent-derived tones.** `ground` and `white` are
   already cached; the rest rebuild on every subscript access, 210 cells a frame.

## Then the plans

[plans/README.md](superpowers/plans/README.md) is the map — it says which plan
owns what and, for everything that once had no owner, where it went and why.
Short version: **Plan 4.5 (match the prototype) → Plan 5 (session list) → Plan 6
(sound, jump, settings) → Plan 7 (generic adapter) → Plan 8 (motion cost)**, with
Plan 7 and the fix-now items safe to run in parallel and Plan 4.5 deliberately
not, because 5 and 6 build surface on the foundations it tunes.

## Three things that would otherwise be rediscovered

**The tools already exist. Use them.**
`Tests/VibeCatUITests/Raster.swift` renders any SwiftUI view offscreen with
`ImageRenderer` — no window server, works on a locked machine, and it *does* run
`Canvas` renderer closures. `ContactSheet.swift` dumps every badge, coat, mood
and drawer state to one PNG (`VIBECAT_CONTACT_SHEET=…`), a filmstrip
(`VIBECAT_FILMSTRIP=…`), and an animated GIF (`VIBECAT_GIF=…`). Three plans
shipped artwork nobody had looked at; two of the three defects that found were
invisible to a green suite. Open the PNG.

**This project's tests agree with its code unless forced not to.**
Over twenty tests that would have passed against a broken implementation were
found during Plan 4 alone, several by implementers on their own work, one in a
*reviewer's suggested fix*. Mutate anything you claim. If a test does not fail
against the specific breakage it names, it is decoration.

**A measurement can be honest and still be the wrong measurement.**
Badge animation was ruled out by a real `getrusage` figure — 3.6–4.1% of a core
against 0.35%. That figure priced a `TimelineView` re-evaluating a `Canvas`,
which is how *this implementation* animated, not how the design asks. The
prototype animates by transform, which needs no timeline. Two plans treated it as
settled. Ask what mechanism a measurement priced, especially when the
implementation came first.

## Still open, and known

- **No licence.** `main` is unpushed on purpose; pushing publishes.
- **The cat's motion is the badge mistake one layer down.** `call` scales 1.09,
  `happy` pops, `dead` rotates ±4° in the prototype, and none is implemented
  because `ResolvedCat` moves in whole cells to keep the pixel grid crisp. Item 2
  above decides whether that constraint is real.
- **The hover sliver**: 150pt of opaque colour over ~92% of the open drawer,
  appearing with hover. Plan 5 owns it, because fixing it means changing the same
  hover-reveal mechanism Plan 5 fills.
- `Other…` is cut until keyboard input works; number-key routing exists and is
  wired to nothing, pending item 3.
- §6.2's right flank is not actually configurable, and §16's AppleScript hint
  cannot exist before jump does. Both Plan 6.
