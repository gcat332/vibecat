# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS notch app that reports what your AI coding agents are doing and lets you
answer a blocked one without leaving what you are looking at. Swift 6, SwiftUI
with AppKit interop, **no external dependencies** — that is a design constraint,
not an accident. Do not add a package.

The authority on behaviour is
[`docs/superpowers/specs/2026-07-31-vibecat-design.md`](docs/superpowers/specs/2026-07-31-vibecat-design.md),
referenced everywhere as `§n`. The authority on *what is left* is
[`docs/superpowers/plans/README.md`](docs/superpowers/plans/README.md) — read it
before proposing work, because "what remains" has already had to be re-derived
from the spec twice and that file exists so it never happens again.

## Commands

```bash
swift build                                  # all five products
Scripts/test.sh                              # 647 cases, headless, ~21s — USE THIS
Scripts/test.sh --filter theWorstStateWins   # one case, by function name
Scripts/test.sh --filter VibeCatCoreTests    # one target
swift run vibecat                            # the app, bare binary
```

**`Scripts/test.sh`, not bare `swift test`.** It is `swift test --no-parallel`, and
the wrapper exists so the reason travels with the command. Run in parallel the
suite fails on nearly every run — always in the same place, always the tests that
poll the main actor inside a bounded window. Serially it is 647/647 green, and
those same tests pass alone in 0.11s, so **nothing in the product is broken**: what
fails is scheduling latency. Plans 6.4 and 6.5 took `@MainActor` in `Tests/` from
264 to 375 occurrences (+42%) against 13% more tests, because a SwiftUI view can
only be rasterised on the main actor.

This does not retire the rule below that a full-suite-only failure is a real bug —
it is a finding under it. The discipline at fault is the **test suite's**, and
reworking those tests to not depend on main-actor latency is the better fix,
recorded in `plans/README.md`. Twenty-one seconds buys a result you can trust
until then. When you revisit it, **measure ten full runs, not four**: a four-run
sample of this flake read 2 failures where ten runs of the same tree read 10.

Bare-binary runs cannot hold macOS permissions — no bundle identifier means TCC
attributes every request to the launching terminal, and the grant dies the moment
the app is opened any other way. For anything touching Screen Recording or
Automation:

```bash
Scripts/build-app.sh && open .build/VibeCat.app   # `open`, never the binary inside
```

Drive it with real hook payloads instead of waiting for an agent:

```bash
VIBECAT_SOCKET=/tmp/vibecat-dev.sock swift run vibecat
VIBECAT_SOCKET=/tmp/vibecat-dev.sock Scripts/replay.sh permission   # | stop | notification
```

### Looking at the UI without a screen

`Tests/VibeCatUITests/Raster.swift` rasterises any SwiftUI view through
`ImageRenderer`, which needs no window server and works on a locked machine.
Env-gated preview tools write real files — use them, do not guess at pixels:

```bash
VIBECAT_CONTACT_SHEET=/tmp/sheet.png swift test --filter contactSheet
VIBECAT_FILMSTRIP=/tmp/strip.png     swift test --filter filmstrip
VIBECAT_GIF=/tmp/motion.gif          swift test --filter gif        # motion, not just frames
VIBECAT_AURA_SWEEP=/tmp/aura.png     swift test --filter auraSweep
```

There is no linter or formatter. Match the surrounding file.

## Architecture

Dependency direction is strict and one-way:

```
VibeCatCore ── domain: VibeEvent, WireCodec, SessionState, SessionStore,
    │                  SourceAdapter + registry, SocketPath, OriginReader
    ├── VibeCatTransport ── SocketServer (app side), SocketClient (hook side)
    │       ├── VibeCatHookKit ── HookRunner            → vibecat-hook (wiring only)
    │       └── VibeCatUI ────── AppModel, NotchController, all views
    │                                                    → vibecat (wiring only)
```

Both executables are deliberately empty shells. An `executableTarget` with a
`main.swift` cannot be `@testable import`ed reliably, so all logic lives in a
library and the binary is nothing but wiring. Keep it that way.

The flow: a CLI runs `vibecat-hook` on its own events → the adapter maps the
vendor's event names onto the shared `kind` vocabulary (`idle | running | done |
permission | question | failed`) so the core never learns a vendor's terminology
→ newline-delimited JSON over a `0600` Unix socket → `AppModel.ingest` →
`SessionStore` → `NotchController`'s `NSPanel` over the notch. For a
`wantsReply` event the hook **blocks** and the island's answer is returned to it,
so replying is exact rather than simulated keystrokes.

### Invariants that must never regress

These are load-bearing. Breaking one is a product failure, not a bug.

- **Fail open (§2.3).** A crashed or absent island must never hang a terminal.
  Every failure path returns the CLI's own default and exits `0`. Two deadlines,
  bounding two different things: delivery `300ms`, answer `answerDeadline`
  (default 20s, clamped `0.02…3600` by `SocketClient.clamped`). Any interval that
  becomes a deadline goes through that one clamp — including values decoded off
  the wire, because the socket is reachable by anything running as the same user
  and an absurd value saturates a `DispatchTime` into `.distantFuture`, parking a
  thread forever.

  **The ceiling was 60 until Plan 9, and *why* it moved matters more than the
  number.** Measured against Claude Code 2.1.223: while a `PreToolUse` hook is
  blocked the CLI prints nothing at all, and its own permission prompt does not
  appear until the hook returns. So the answer deadline is not a safety net — it
  is the **hand-back**, the only mechanism by which the terminal ever gets a
  prompt. A crashed island is already harmless without it, via the 300ms delivery
  bound and via socket EOF releasing the hook. `Preferences
  .handBackToTerminalAfter` is that value in minutes (default 1), and an hour had
  to fit inside the clamp for a chosen hour not to become one minute.

  **The floor did not move with it, and there are now two clamps.**
  `SocketClient.clamped`'s only job is to reject the absurd, so `floorDeadline`
  stays `0.02` — nine tests observe a real answer timeout at 0.05s and 0.6s, and
  a floor of "long enough for a person to read a sentence" would make them
  impossible rather than slow. What a *person* may choose is bounded separately,
  by `UserDefaultsPreferenceStore.clampedHandBack` at `0.5…60` minutes.

  **"Every wait is bounded" now has one deliberate exception.**
  `handBackToTerminalAfter` may be `Never`, which the owner ruled available and
  not the default. `Never` is the *absence* of an expiry, never a very late one:
  `PendingQuestion.waitInstant(until:)` is the single place a `DispatchTime` is
  derived and the single place `.distantFuture` is produced, and its `min`
  against `ceilingDeadline` keeps a finite expiry finite. Spelling `Never` as
  `Date.distantFuture` would make the accidental forever — the saturation this
  bullet already warned about — indistinguishable from the intended one.
- **The notch is a hole (§5.1).** The black shape may span the cutout because
  the cutout is black too. **Content may not.** Everything sits in the flanks.
  Notch dimensions are read at runtime from `NSScreen`, never hardcoded; a
  notchless display falls back to a floating pill.
- **`LW = 58pt` is constant (§5.3).** The badge slot is a fixed `14pt` whatever
  it holds. Holding `LW` constant is what pins the island's left edge — the
  centring shift cancels `RW` out entirely — so the cat never walks sideways when
  the right side grows.
- **Colour means state, and only state (§4.3).** `#3FD99B` idle, `#5B9DF9`
  running, `#FFA63C` needs you, `#FF5C5C` failed. Which agent is speaking is
  carried by icon *shape*. A coat changes markings, never hue.

  **"Never by hue" is about identity, not about tinting.** §4.3's own closing
  sentence is explicit: *"Everything tinted by the current state — marks, cat,
  badge, counts, the aura — uses the same `--accent`."* So a per-CLI mark **is**
  tinted by the state accent, and the mockup agrees (`.mark{color:var(--accent)}`).
  Shape says *who*; hue says *what state*; both live on the same mark. Recorded
  because this file previously said only the first half, and a dispatch built on
  that half told an implementer the opposite of what the spec requires.
- **Worst state wins (§4.2):** `waiting > failed > running > idle`. A waiting
  agent is idling on you right now; a failed one has already stopped. The session
  list is a view, not a state — opening it must not change what the island reports.
- **No event ever comes from a GUI app (§13).** Events arrive by hook; a GUI is
  only ever a jump target.

## Dispatching visual work — the rule that failed once, written where it binds

**If you delegate work on a visual surface, the prototype path goes in the dispatch
prompt, not just in this file.**

This section exists because the rule *was already here*, phrased as "open the
prototypes before changing anything visual" — and Plan 5 still shipped eight tasks
without a single implementer or reviewer opening `island-motion.html`. Every dispatch
pointed at §11's ASCII diagram in the spec instead. The mockup contains a fully
worked session list (real records, a `card` options object, the row rendering), and at
least six divergences went unnoticed because nobody was given the reference.

**Why it failed is the useful part: a guardrail written in a document nobody re-reads
at the moment of action does not bind.** The dispatch templates say "read your brief";
the brief is extracted from the plan; and nothing in either carried this repo's own
rule. So:

- **A dispatch touching a visual surface must contain the prototype path and the
  element name** — `island-motion.html`'s `renderRows()`, `.rtop`, `tasksHTML`,
  whatever it is. Not "consult the prototype": the actual path, in the prompt.
- **A brief that cites only the spec's prose or ASCII art, for something the prototype
  implements, is incomplete.** The spec's diagrams are lossy renderings of the
  mockup — §11's `✳` reads as a state marker and is in fact a per-CLI mark. Treat the
  spec as the authority on *rules* and the prototype as the authority on *appearance*.
- **Ask the reviewer to confirm the diff happened**, and to name what it compared. A
  review that never opened the prototype cannot report fidelity, only self-consistency.
- **Plan Global Constraints must name the prototype** for any plan with a visual
  surface, because that block is what every extracted brief carries.

`.claude/agents/prototype-fidelity.md` exists for exactly this and is the right thing
to dispatch. Note it cannot be used in the session that creates it — the agent registry
is read at session start.

## UI and UX standards

The two prototypes named in the spec header are the design's own reference, and
they are runnable: [`island-motion.html`](docs/superpowers/prototypes/island-motion.html)
and [`settings.html`](docs/superpowers/prototypes/settings.html). Open them
before changing anything visual. Plan 4.5 exists because across four plans nobody
ever diffed the implementation against them, and ten minutes of reading their CSS
custom properties turned up five divergences.

- **A divergence from the prototype is either a fix or a written decision.**
  Never a silent third thing.

  **The example this rule used to give was itself a misreading, which makes it a
  better lesson than the one it replaced.** Four documents — this file among them —
  said our `15pt` bottom radius was a written divergence from "the prototype's
  `9px`". It is not. `island-motion.html:83` is `border-radius: 0 0 15px 15px`:
  **the prototype's bottom radius is 15 and always was.** The `9px` is
  `--fillet` (line 31), the concave weld where the island meets the bezel — a
  different property entirely, six lines away.

  The cost of that confusion was real. Someone read `9px` as the bottom radius,
  found the fillets beside it, and **deleted the fillets** rather than re-spelling a
  number that never needed changing — so the island met the screen at a right angle
  for four plans until the owner noticed it looked wrong. Plan 6.3 Task 6 restored
  them at the prototype's own `9pt`.

  **So: cite the line, not the recollection.** A divergence you cannot point at in
  the prototype's source may not be one.
- **Motion is the interface's grammar, not decoration.** Pixel art on a grid,
  modern easing moving it. Width morph spring `0.42/0.62`, drawer height
  `0.45/0.80` — width overshoots more so the island reads as one body with mass,
  and those numbers are Plan 4.5's measured retune plus Plan 6.3's 30ms height lag,
  not the originals. `--ease` (`cubic-bezier(.22,.9,.28,1)`) is a **third** curve for
  everything that is not a shape spring, and it lives in `IslandMotion` with them so
  the next one cannot drift 350 lines away unnoticed.
  Faces fade in *inside* a shape already at the right size; they never slide in
  from outside. The blink is the one instantaneous thing in the whole interface,
  because a blink is instantaneous.
- **Prefer a transform to a redrawn frame.** Animating by swapping cells forces
  a `TimelineView` to re-evaluate a `Canvas` N times a second (measured: 3.6–4.1%
  of a core for a drifting `zzz`, against 0.35% with no timeline). `.scaleEffect`
  and `.opacity` declared once with `.repeatForever()` are run by the render
  server. Keep `needsTimeline` false wherever the motion allows it.
- **An idle machine must look idle and cost nothing.** At rest nothing animates
  except the cat.
- **Reduced motion is a real path, not a courtesy.** Everything animated goes
  through `MotionPreference.resolve`. The system asking for less motion beats a
  user asking for more; it never drags a user who chose `off` back into motion.
- **Never truncate away the thing being decided.** A destructive command shown as
  `rm -rf /Users/dev/projects/vibe…` asks someone to authorise a target they
  cannot see. `.truncationMode(.middle)` on command bodies.
- **The control carries the meaning, not a label (§10.2).** A number badge means
  the click *is* the answer; a checkbox means it is not. Send is disabled at zero
  so a half-made selection cannot be committed by reflex.
- **The recommended answer is tinted, not filled.** A wide block of solid colour
  shouts. Choices run one per row, top to bottom, because real permission labels
  are long sentences.
- **Destructive answers ask twice** (`rm -rf`, force push, `drop table`) —
  `DestructiveGuard`, on by default.

## Production and scale standards

- **Concurrency is reasoned, and the reasoning is written next to it.** Read
  `AppModel.ingest` and `applyAndNotify` before touching anything threaded. Two
  facts that cost real debugging time: `ingest` runs on `SocketServer`'s
  per-connection thread and *must* be able to park it, and
  `DispatchQueue.main.sync` from a `Task.detached` deadlocks under full-suite
  load because both draw on Swift's small shared cooperative pool — reproduced
  with an empty `sync {}` body.
- **Anything with a lifecycle tears itself down.** `AppModel` and `HoverMonitor`
  both use `isolated deinit` because `RunLoop.main` holds a `Timer` strongly and
  a listening socket's accept thread otherwise runs forever.
- **`@Observable` notifies on the write, not on the change.** Assigning an
  unchanged value still invalidates the body. Guard writes (`AppModel.prune` only
  notifies when a prune removed something).
- **Measure with `getrusage(RUSAGE_SELF)`. Never `ps %cpu`** — it is a decaying
  average and it once produced a false failure that cost most of a plan's
  investigation budget.
- **Label an unmeasured claim as unmeasured, in the source.** This project has
  been wrong about SwiftUI's rendering behaviour in both directions.
  `Badge.pulse`'s doc comment is the pattern to copy.
- **A source is config, not code (§3).** `SourceAdapter` and its registry were
  built to take more adapters — the registry resolves a duplicate id in favour of
  the later one precisely so a user's custom source can shadow a built-in. New
  CLI support fills that hole; it does not add a branch to the core.

## Testing standards

`swift-testing` (`import Testing`, `@Test`, `#expect`), not XCTest.

**The dominant defect in this repo's history is not bad implementation — it is a
test that passes against broken code.** Before writing an assertion, name what
would have to break for it to fail. If nothing would, it is not a test.

- A colour-*count* assertion is nearly worthless: a render with a sprite entirely
  emptied still produced eighty-odd colours from everything else and passed.
  Assert on a colour only the thing under test can emit, or compare two renders
  differing in exactly one input.
- Derive the expected value from the rule; do not widen slop until it passes.
- Reading a property proves nothing about a `Canvas` or `TimelineView` closure —
  those never run during `.body` access. Rasterise instead. The `#if DEBUG`
  counters in `IslandView` exist for exactly this reason, and their own comments
  state what they do and do not prove.
- The whole suite runs in parallel. A test that only fails under full-suite load
  is a real bug, usually in thread or actor discipline — do not paper over it.

## Working in this repo

- **Read `docs/superpowers/plans/README.md` first.** It says which plan owns
  what, what is next, and which items are deliberately deferred and why.
- **Cite the spec section** (`§6.3`) when implementing to it, and update the spec
  with a dated correction block when reality contradicts it — see §5.5 for the
  form.
- Commit subjects state the *insight*, not the diff: `fix: order inside a git
  push cluster decides force, not which letters appear`. Bodies explain the
  reasoning, including what was measured and what was not. Keep the
  `Co-Authored-By:` trailer consistent with existing history.
- **Never `git push`.** `main` is deliberately unpushed and hundreds of commits
  ahead of `origin/main`; the repo has **no licence yet**, so pushing publishes.
  Ask first, every time.
- `.worktrees/` and `.superpowers/` are gitignored scratch for in-progress plans.

## Subagents

Defined in `.claude/agents/`. Dispatch them rather than doing these passes
inline — each one exists because this project has been burned in that exact area.

| Agent | Model | Use it when |
|---|---|---|
| `prototype-fidelity` | opus | Anything visual changed, or before closing a plan that touched the island, cat, badges or drawer. Diffs against the prototypes' CSS and writes the divergence record. |
| `render-evidence` | sonnet | You need pixels, not opinions: rasterise a view, produce a contact sheet / filmstrip / GIF, report what was actually drawn. |
| `concurrency-auditor` | opus | Any change to `AppModel`, `SocketServer`/`SocketClient`, `HookRunner`, `PendingQuestion`, or any new `Task`, `Timer` or thread. Also the first responder to a full-suite-only flake. |
| `test-premise-auditor` | opus | Before claiming work is done. Asks of every new assertion: what would have to break for this to fail? |
| `cpu-measurer` | sonnet | Any motion or frame-rate claim. Produces `getrusage` numbers, refuses `ps %cpu`. |
| `plan-archivist` | sonnet | After work lands: fold follow-ups into the plan files, keep `plans/README.md` honest about what is left. |

Model guidance for direct work: **opus** for anything touching the socket
protocol, actor isolation, fail-open or geometry maths — the places where being
subtly wrong is expensive and has happened. **sonnet** for sprite tables, view
plumbing, test fixtures and doc upkeep. **haiku** for mechanical sweeps only.
