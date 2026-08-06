# Handoff — 2026-08-06 (end of Plan 9)

Where VibeCat is, what to decide next, and the things a newcomer would otherwise
have to rediscover the hard way.

> Supersedes the 2026-08-03 handoff (end of Plan 5), which reported **419 tests** and
> "Plans 1–5 done". Since then 6.1–6.6, 7 and 9 landed. Its warnings all still hold;
> the two most expensive ones are repeated below rather than left for someone to find
> in a superseded file.

## State

`main`, clean, **942 tests**, MIT licensed. **Plans 1–5, 6.1–6.6, 7 and 9 done.**

```bash
Scripts/test.sh                              # 942, ~32s — serial, and that is not optional
Scripts/build-app.sh && open .build/VibeCat.app
```

`open`, never the binary inside the bundle: launching it from a shell makes the shell
the responsible process and the app loses its own permission identity.

For anything that does not touch Screen Recording, Automation or Focus — including
everything below — `swift run vibecat` is enough and much faster:

```bash
VIBECAT_SOCKET=/tmp/vibecat-dev.sock swift run vibecat
VIBECAT_SOCKET=/tmp/vibecat-dev.sock Scripts/replay.sh permission   # | stop | notification
```

---

## Do these first — three open reports from the owner, on hardware

These came from the owner running the app on 2026-08-06 and are the most valuable
items in this file, because nothing headless found them.

### 1. Hover should grow the notch *downward*, not sideways — and one question blocks it

**Ruled by the owner:** the cat (left) and the count (right) must not move; the notch's
background should expand **downward, symmetrically**, instead of widening to the right.

Today hover widens rightward because §5.3 holds `LW = 58pt` constant — that is what pins
the island's left edge, since the centring shift cancels `RW` out. `:382` records the
alternative having been observed: the left edge crept `599.5 → 605.0` across six rows
while the right sat still. So *keeping the cat still* and *growing rightward* are the same
decision, and reversing it is a real geometry change, not a tweak.

**The question that has to be answered before any code moves:** the hover reveal currently
*shows the most urgent session's detail text* in the width it gains. If the island stops
widening, that text either moves into the new space below or stops existing. Those are
different features. Ask the owner which; do not pick one.

`IslandGeometry`, `IslandMotion.hoverRevealDuration`, `IslandModel.revealed` and §9.1's
reveal are the surfaces. Expect golden churn.

### 2. The session list could not be found in the running app

Unresolved, and the diagnosis stopped at two unanswered questions — **ask them before
changing anything**, because three different causes fit the report equally well:

- Was the pointer still **on** the island when it was clicked? `NotchController.swift:558`
  gates every click on `model.hovering &&
  (question != nil || !sessions.isEmpty || drawerOpen)`. That conjunct exists so the menu
  bar underneath stays clickable. Click with the pointer off the island and **nothing at
  all happens** — no feedback, by design.
- Did the drawer open **empty**, or open **onto a question**? A question always wins the
  face until it is parked, which is Plan 9's own behaviour: press **Escape** to park it,
  then click again to get the list. That is correct, and it is also easy to mistake for
  the list being broken.

### 3. "The real icons never appear in the app" — and this one is understood

**Item 3 is the cause of it.** The bundled brand marks are drawn *only* by `SessionRow`,
in the session list. The collapsed island always draws `CLIMark`'s geometry, deliberately:
it speaks for a mixed set of CLIs and no single brand mark is true of several
(`SessionRow.swift:170-177`). So if the list is not visible, no brand icon can be.

Verified separately: the PNGs are present at
`.build/debug/VibeCat_VibeCatCore.bundle/Icons/` under `swift run`, and
`ClaudeCodeAdapter.icon` resolves.

**One real hazard remains even once the list is visible**, and it is recorded as a
deliberate trade rather than a bug — read `SourceIcon.swift`'s doc comment before
"fixing" it. The read is capped at 50ms on a dedicated thread; on timeout it draws the
geometric fallback, the background read keeps going and caches, and **nothing invalidates
the view**. So a first render can show geometry and never update. The async-with-
invalidation shape is the right one and was declined because it would turn every
synchronous golden in `SourceIconTests` and `SessionRowTests` into an
eventually-consistent assertion, which `ImageRenderer` has no second pass for. It has
already bitten a test — see the caution about `anIconFromACustomSourceReachesARenderedRow`
below.

---

## What is left, by plan

`docs/superpowers/plans/README.md` is the authority and says which plan owns what.
Read it before proposing work — "what remains" has had to be re-derived from the spec
**twice**, and that file exists so it never happens again.

| Plan | What | State |
|---|---|---|
| **6.7** | The **General and Integrations** Settings pages | **plan written 2026-08-06, not started** |
| 6.8 | The Display controls with no behaviour anywhere — Clean/Detailed, Meter/Dot, the four panel-size sliders, the two notch offsets, the display picker, editable state colours | not written |
| 6 | Jump (§13) and §16's AppleScript hint | not written |
| 8 | Matching motion cost to motion content | not written |

**Two of the four Settings pages are still empty**, each showing an owner note naming
6.7 — that is why Settings looks unfinished. 6.4 built the shell, 6.5 Notifications,
6.6 Display.

**6.7's plan is written and has two things a reader must not miss.** Its Task 1 moves
`UserDefaultsPreferenceStore`'s default domain to an explicit suite, because *measured*: a
binary with no bundle identifier gets a `UserDefaults` domain named after its executable,
so `swift run vibecat` and the bundled app have been writing to two different files all
along. And its `handBackToTerminalAfter` row binds to `SocketClient
.clampedChosenByPerson`, not to a clamp of its own.

---

## Cautions — each one cost real time

### The test suite only passes serially, and that is measured

`Scripts/test.sh` is `swift test --no-parallel`. Run in parallel it fails on nearly every
run, always in the same place: tests that poll the main actor inside a bounded window.
**A full-suite-only failure is still a real bug** — this is a finding under that rule, not
an exception to it, and the fault is the test suite's. When you revisit it, **measure ten
full runs, not four**: a four-run sample of this flake read 2 failures where ten runs of
the same tree read 10.

### `Preferences.handBackToTerminalAfter` is the fourth write-only preference

Persisted, clamped, read by nothing. Recorded as `"NOTHING YET"` in
`everyPreferenceFieldHasANamedProductionReader`, which is the guard that exists because
this has happened three times before. 6.7 wires the Settings row; 6.7's own Task 7
teaches `HookRunner` to read it. Until then **the hand-back that actually runs is
`lapseCheck` on `answerDeadline`**, not this field.

### There are three deadline clamps, split by provenance rather than by size

| | range | for a value from |
|---|---|---|
| `SocketClient.clamped` | `0.02…60` s | **the wire** — `AppModel.ingest` |
| `SocketClient.clampedChosenByPerson` | `0.02…3600` s | this app's own preferences |
| `UserDefaultsPreferenceStore.clampedHandBack` | `0.5…60` **minutes** | a Settings control |

The unqualified name is deliberately the strict one. Plan 9 originally raised *the wire's*
ceiling to 3600 so a person could choose an hour; a test-premise audit caught that nothing
read the preference yet, so the only live effect was letting anything on a `0600` socket
park a hook for an hour. **Do not raise the floor.** Nine tests observe a real answer
timeout at 0.05s and 0.6s; a floor of "long enough to read a sentence" makes them
impossible rather than slow.

### `ImageRenderer` is not trustworthy in three specific ways

It reuses its backing store, it paints **nothing** for a `ScrollView` (use
`rasteriseHosted`, which is itself unreliable for flat fills), and `--filter` regularly
reports zero tests for a name that exists — if it does, run the whole target.

**And a render can pass for reasons that have nothing to do with the code.**
`anIconFromACustomSourceReachesARenderedRow` was green in the full suite and red on its
own; adding nine unrelated tests changed what ran before it and it went red in the suite
too. Cause: it rendered once, immediately after writing a fresh PNG, betting on winning
`SourceIcon`'s 50ms read race against a cold page cache. It now renders until the cache is
warm, bounded. **Widening a pixel threshold would have hidden the race instead of removing
it.**

### The dominant defect here is a test that passes against broken code

Plan 9's own audit ran 28 mutations and two survived — both in tests written specifically
to guard the thing they failed to guard:

- A truncation test whose command was short enough that **no truncation happened**, so
  `.middle` versus `.tail` was unobservable.
- A `§10.2` test that compared whole renders, which differ at `sendRow` — so hardcoding
  `isMulti: false`, the actual violation, left the suite entirely green. Fixing it needed
  a **crop**, because `isMulti` legitimately drives two things and comparing wholes proves
  only that one changed.

Before writing an assertion, name what would have to break for it to fail. Then mutate
that line, `grep` your marker to confirm the edit landed, and watch it go red.

### Cite the line, not the recollection

`SessionRow`'s doc comment cited `SESSIONS` line 788 for `state:'2m 14s'` for four plans;
788 is the `'Needs you'` record and 797 is the running one. Worse precedent: someone read
`--fillet`'s `9px` as the island's bottom radius, deleted the fillets six lines away, and
the island met the screen at a right angle for four plans.

**And the prototype is not always right.** Plan 9 found `island-motion.html:526-527`
drawing the Settings glyph as a circle plus eight *detached* ticks — a brightness icon.
The owner said so on sight. A divergence from the prototype is a fix or a written
decision, never a silent third thing; that one is recorded on `GearRingShape`.

### Three limits no headless test in this suite can reach

Say so rather than writing a test that appears to cover them:

1. **A synthetic tap cannot reach a SwiftUI `.onTapGesture`** here — no ViewInspector, and
   none will be added. Moving the header's tap onto the whole row leaves the hit-region
   tests green. What defends against it is structural: the header and the question blocks
   are **siblings**, never ancestor/descendant. **Accepted, not deferred** — the two are
   different, and conflating them invites someone to "finally fix it".
2. **A stuck `NSCursor` is process-wide state.** `SessionRow` has an `onDisappear`
   teardown for the pointing hand, and it is **unmeasured**. Hand test: hover a row's
   header until the cursor becomes a hand, then press Escape *without moving the mouse*.
   The drawer closes, the row leaves the view tree, and the cursor must return to an
   arrow. If it stays a hand, every window on the machine keeps it.
3. **AppKit finishes window teardown inside `NSApplication.run()`**, which `swift test`
   never calls — so a weak-reference test for window release cannot work. Assert
   window-list membership by identity instead.

### Measure with `getrusage(RUSAGE_SELF)`, never `ps %cpu`

`ps` reports a decaying average and once produced a false failure that cost most of a
plan's investigation budget.

---

## Looking at things without a screen

Every one of these writes a real file. Use them instead of guessing at pixels.

```bash
VIBECAT_LIST_SHEET=/tmp/list.png     Scripts/test.sh --filter listSheet          # the whole drawer, 560×420, with parked questions
VIBECAT_QUESTION_BLOCK=/tmp/qb.png   Scripts/test.sh --filter questionBlockSheet  # both question-block states
VIBECAT_ROW_HEIGHTS=1                Scripts/test.sh --filter rowHeights          # the numbers behind Plan 9's layout
VIBECAT_ICON_WEIGHT=1                Scripts/test.sh --filter iconWeight          # what each bundled mark actually paints
VIBECAT_CONTACT_SHEET=/tmp/sheet.png swift test --filter contactSheet
VIBECAT_GIF=/tmp/motion.gif          swift test --filter gif                      # motion, not just frames
```

`IconWeightProbe`'s own doc comment is worth reading before trusting any of them: its
first two versions measured the wrong thing twice — once by counting antialiased pixels as
ink, once by measuring against a 14pt box while the view laid out in a 16pt one.

---

## Notes worth keeping

- **Plan 9's design came from measurement, not from the spec.** With a `PreToolUse` hook
  blocked, Claude Code prints nothing and its own prompt does not appear until the hook
  returns. So the answer deadline is not a safety net — it is the **hand-back**, the only
  mechanism by which the terminal ever gets a prompt, and "answerable in the notch and in
  the terminal at once" is *unavailable* rather than declined. §2.3 carries a dated
  correction saying so, because the spec's own reasoning had it half right in a way that
  inverted the conclusion.
- **Two defects nobody asked about were fixed on the way.** Two agents asking at once
  fail-opened the first without it ever being shown, and Escape threw a question away.
- **Never `git push` without asking.** The repo is public; a push publishes immediately.
  It has been pushed with the owner's explicit approval each time.
- `.worktrees/` and `.superpowers/` are gitignored scratch. Plan 9's three review reports
  live in `.superpowers/sdd/2026-08-06-parking-questions/` — the fidelity pass, the
  test-premise audit and the task review — and they are not in git, so quote what matters
  rather than pointing at them.
