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
2. ~~**Measure the badge transforms with `getrusage`.**~~ **Done 2026-08-03 —
   and the idle island's 0.35% is gone.** [The
   spike](spikes/2026-08-03-badge-transform-cost.md) has the numbers, the
   decomposition, and the two wrong turns. The `Canvas` half of the assumption
   held exactly (0.0 draws/s, against 47.9/s once a timeline is involved); the
   cost half did not. **Dormant now measures 12.26% of a core in release against
   0.35% before badges animated — 35× — and roughly 3× worse than the
   cell-swapping badges the transform replaced.** Reproduced in debug (10.63%),
   so it is not a build artefact. `BadgeCanvas` also never consults
   `MotionPreference`, so no setting turns it off.

   **This is now the thing to decide, and it is a decision, not a fix:** revert
   to still badges and lose the fidelity, gate them on `MotionPreference` so the
   cost is at least a choice, find a mechanism that is genuinely
   render-server-only, or accept 12% knowingly and write that down. The probe
   that produced these numbers is `Sources/VibeCatApp/BadgeCPUProbe.swift` — its
   doc comment says how to run it, and re-running it is how any of those options
   gets checked.
3. ~~**Run `KeyDownProbe`** on an unlocked machine.~~ **Done 2026-08-03 —
   Path A.** [The spike](spikes/2026-08-03-notch-panel-key-input.md): the panel
   becomes key, takes every keystroke **exclusively** (verified with a TextEdit
   witness and a control run, not just `isKeyWindow`), and
   `frontmostApplication` never changes. Plan 6's keyboard items are unblocked —
   with one constraint the brief never anticipated: **key status may be held only
   while a question is open**, because exclusive delivery plus an unchanged
   `frontmost` means a resting key panel silently eats everything typed into a
   terminal that still looks focused. Also: `NSApp.isActive` is not a usable
   proxy, it read `true` in every run.

   It settled the plan's one genuine unknown —
   whether a `.nonactivatingPanel` at `.statusBar` can take *key* events without
   stealing terminal focus. Mouse input was measured and does not. The probe
   prints `frontmostApplication` before and after and aborts on `loginwindow`,
   because an earlier attempt at that measurement was void for exactly that
   reason and nearly became a recorded fact.

   **Corrected 2026-08-03.** This said `VIBECAT_KEYDOWN_PROBE=1`, and so did
   `plans/README.md`. No such environment variable exists anywhere in the
   source: `main.swift` gates the probe on a **command-line argument**, under
   `#if DEBUG`. The invocation, from `KeyDownProbe`'s own doc comment, which
   records why each part of it is necessary — click some other app first, so
   "did frontmost change" is a real question:

   ```bash
   Scripts/build-app.sh
   open -n --stdout /tmp/keydown-probe.log --stderr /tmp/keydown-probe.log \
        .build/VibeCat.app --args --keydown-probe
   tail -f /tmp/keydown-probe.log
   ```

   `-n` matters: without it `open` re-activates the running instance instead of
   launching a process that takes the probe branch. `open`'s own flags must
   come *before* `--args`, or they silently become the app's argv instead —
   both already learned the hard way once.
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
