# Display Page Implementation Plan (Plan 6.6, §14 · §11 · §9.3 · §6.2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** §14's Display page, wired to the behaviour that exists — the motion
control, §11's nine session-card switches, §6.2's right flank, the cat's coat, and a
live preview that makes the switches mean something.

**Architecture:** Almost nothing new. `SessionRow.Options` was kept by Plan 5
*precisely* as this page's switch point; `Preferences.motion` and `.rightFlank`
already drive the island; `Coat` has had five cases since Plan 3. The one missing
control primitive is the prototype's segmented `.seg`, which this page needs five
times.

**Tech Stack:** Swift 6, SwiftUI. **No package may be added.**

## Scope, and why it is not all 21 controls

The Display page offers 21 controls and **roughly eight of them have no behaviour
anywhere in this repo**: Clean/Detailed island tiers, `Meter`/`Dot` as alternatives
to the cat, the four panel-size sliders, the two notch-tuning offsets, the
multi-display picker, editable state colours, Content Font Size, and Completion Card
Height. Two more — `Reveal names and timings: Always/Never` — have only their
`On hover` case built.

Plan 6.5 met this exactly once already, with `Soft`/`System`/`Blip` sound packs, and
settled it: **a menu item that silently does nothing is worse than a shorter menu.**
Plan 6.1 restated it as a rule after leaving `.agentIcon` selectable and blank:
**do not ship a picker for a placeholder.**

So this plan ships **every Display control whose behaviour exists**, and names the
rest. What is deferred is listed at the end with a reason each; **it is a plan's
worth of new features, not an oversight.**

## Global Constraints

- **No external dependencies.** Swift 6, macOS 14 floor.
- **The prototype is the authority.** [`settings.html`](../prototypes/settings.html),
  the Display pane is **lines 379–509**. The `.seg` control is lines 101–104:
  container `background:#1F1F22`, `border-radius:8px`, `padding:2px`, `gap:2px`;
  buttons `font-size:12px`, `color:var(--haze)`, `padding:5px 11px`; and the pressed
  button `background:#4A4A50; color:var(--bone)`.
- **Settings has its own palette and `--accent` means system blue there**, not the
  state colour. Nothing in `Sources/VibeCatUI/Settings/` may reach for
  `IslandState.accent`. **The exception is deliberate and on this page:** the state
  swatches and the live preview *are* showing island state, which is the one place
  those hues belong in a settings sheet.
- **§4.3: colour means state and only state.** A coat changes markings, never hue.
  The mockup's own copy says it: *"Pose reports the state; the coat is yours"* and
  *"Colour only ever means state. Which agent is speaking is carried by its icon."*
  **A coat picker that changed a hue would break the invariant the page explains.**
- **A divergence from the prototype is either a fix or a written decision** — and
  **cite the line, not the recollection.** Plan 6.3 found that four documents,
  `CLAUDE.md` among them, had called our bottom radius a divergence from "the
  prototype's `9px`" when the prototype says `15px` on line 83 and the `9px` is a
  different property six lines away. That misreading cost four plans and got a real
  feature deleted.
- **A test that cannot fail is not a test.** Across seven plans: 6.4 shipped seven;
  6.5 caught three in its own new tests; 6.1's Task 3 found one that could not fail
  against its neighbouring wiring; every task of 6.3 reported a green mutation rather
  than patching it. **Name the production change that would break each assertion, and
  report a mutation that stays green rather than adjusting the test.**
- **Reading a property proves nothing about what was drawn.** Rasterise. **Count a
  colour inside a box you predicted, never across the render** — a mid-grey drew 111
  phantom hits, and bone text landed within tolerance of a hairline blend.
  `Raster` is not `Equatable`. `ImageRenderer` cannot render a `ScrollView` **or** a
  `Menu`; `rasteriseHosted` can, and is untrustworthy for flat background colours.
- **`onAppear` *does* fire under `ImageRenderer`** — Plan 6.3 measured it, correcting
  Plan 6.5's claim. So a mutation that deletes an `.onAppear` **is** catchable; if it
  is not caught, the reason is that no test renders that view, which is fixable.
- **`save()` writes the whole `Preferences` struct**, so it is a clobber hazard:
  `load()`, mutate, `save()`, never hold a snapshot. **This page adds the most writers
  of any so far.**
- **Every new `Preferences` field needs a reader**, and there are two enumerating
  guards that will tell you if it has none: the `Mirror` round-trip test in
  `PreferenceStoreTests` and `LaunchWiringTests`. **Expect both to fail first** —
  that is them working. Update their counts deliberately.
- **Run the suite with `Scripts/test.sh`** (`swift test --no-parallel`; its header
  says why). Current total is **744**, ~22s. Zero warnings in debug and `-c release`.
- **Measure cost with `getrusage(RUSAGE_SELF)`. Never `ps %cpu`.**
- Commit subjects state the insight. Trailer
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Never `git push`.** Ask, every time.

## What already exists, verified rather than assumed

| Thing | State |
|---|---|
| `SessionRow.Options` | **Nine flags** — `activity lastMessage tasks agents subagents project worktree model effort`, plus `.all`. Plan 5 kept it *as this page's switch point* and removed `SessionListFace.options`, so **one parameter needs re-threading** |
| `Preferences.motion` | Exists, drives the island, and Plan 6.1 measured `off` at 0.38% of a core against `full`'s ~12% |
| `Preferences.rightFlank` | Exists and drives `IslandModel.layout` — but **`.agentIcon` draws an empty rounded square** |
| `Coat` | Five cases since Plan 3: `tabby plain tuxedo siamese patched` |
| `MotionPreference.systemWantsReduced` | Exists, and §9.3's precedence lives in `.effective` |
| The `.seg` segmented control | **Does not exist.** This page needs it five times |
| `Session.lastUserMessage` | Renders and **no adapter populates it** — so its switch controls a line that is always absent |

## Two conflicts to settle, not to implement around

1. **"Follow the system Reduce Motion setting" contradicts §9.3 as written.** §9.3
   says *the system asking for less motion beats a user asking for more, and it never
   drags a user who chose `off` back into motion.* A switch that can be turned **off**
   is exactly a user asking for more motion than the system wants. `MotionPreference
   .effective` currently encodes §9.3 unconditionally. **Decide: does the switch
   exist, and if it does, what does §9.3 become?** Write the answer as a dated spec
   correction if it changes §9.3. Do not ship a switch that silently does nothing, and
   do not silently drop a control §14 lists.
2. **`.agentIcon` is a placeholder.** §6.2 offers it, §4.3 says *shape* is what says
   which agent is speaking, and ours draws an empty rounded square that says nothing.
   The marks exist — `island-motion.html`'s `MARKS` (line 619) has four portable
   24×24 `currentColor` geometries, already ported once for the session list.
   **Either land the mark in the flank or leave the option out of the picker**, and say
   which. Plan 6.1 recorded this as a thing this plan must not get wrong.

## File Structure

| File | Responsibility |
|---|---|
| `Sources/VibeCatCore/Preferences.swift` | *(modify)* `coat`, the nine card flags, `followsSystemReduceMotion` if it survives |
| `Sources/VibeCatUI/Settings/SettingsSegmented.swift` | The `.seg` control, used five times |
| `Sources/VibeCatUI/Settings/DisplayPane.swift` | The page |
| `Sources/VibeCatUI/Settings/SessionCardPreview.swift` | The live preview |
| `Sources/VibeCatUI/Drawer/SessionListFace.swift` | *(modify)* the re-threaded `options` |

---

## Task 1: The preferences this page writes

**Files:** `Sources/VibeCatCore/Preferences.swift`, `PreferenceStore.swift`;
tests extend `Tests/VibeCatCoreTests/PreferenceStoreTests.swift`

**Produces:** on `Preferences` — `coat: Coat` (default `.tabby`) and
`cardOptions: SessionCardOptions`, plus `followsSystemReduceMotion: Bool` **only if
Task 3's ruling keeps it.**

**`Coat` lives in `VibeCatUI/Cat/CatGrid.swift` and `Preferences` is in
`VibeCatCore`, which must never import `VibeCatUI`.** This is the third time this
seam has come up — Plan 6.5 moved `SoundPack`'s bare enum to Core and left its
behaviour in the UI; Plan 6.1 did the same with `MotionLevel`. **Follow that shape
and report the move.**

**`SessionRow.Options` is an `OptionSet` in `VibeCatUI`.** Storing it needs the same
treatment, or a Core-side mirror. **An `OptionSet`'s `rawValue` is a stable
integer** — decide whether you persist the raw bits (compact, but silently
reinterprets if a flag is ever renumbered) or nine booleans (verbose, but a renumber
cannot corrupt them), and **say which and why.**

- [ ] Extend **both** enumerating round-trip tests. Give every new field a value that
      differs from its default **and from its type-siblings** — nine booleans that are
      all `false` cannot detect a crossed key, which is exactly what let Plan 6.5's
      original mutation through.
- [ ] Implement, then mutation-verify: drop one field from `save`; drop one from
      `load`; cross two keys of the same type; replace a fallback with a force-unwrap
      (a **crash** is the correct outcome for that one).
- [ ] Full suite, commit.

---

## Task 2: The segmented control

**Files:** `Sources/VibeCatUI/Settings/SettingsSegmented.swift`; test alongside

**Produces:** `SettingsSegmented<Value: Hashable & CaseIterable>` taking a
`Binding<Value>` and a label closure — the same shape as Task 3 of Plan 6.5's
`SettingsSelect`, which is the file to read first for house style.

`settings.html:101-104` gives every value. **Two of the five uses carry a `<b>` title
*and* an `<em>` description inside the button** (Clean/Detailed, line 395–400) while
the other three are plain labels — check whether you need one control or two, and say
which.

**Measure the native `Picker(.segmented)` before drawing your own.** Plan 6.4
measured the native `Toggle` at 54×24 against the prototype's 38×22 with a track that
never turned blue, and Plan 6.5 measured the native `Picker` drawing `#2E2E30` where
`--card2` is `#323236` — **both were rejected on evidence, and that is the standard
here.** Put the numbers in the report whichever way you go.

- [ ] Tests: the pressed segment draws `#4A4A50` and the others do not — **count
      inside the pressed segment's own predicted box**; the control reflects its
      binding rather than `allCases.first`; and **assert the rendered label**, not
      merely that two renders differ. *"Differs" is not "differs in the right
      direction"* — that exact weakness shipped in Plan 6.4's sidebar.
- [ ] Mutation-verify: ignore the binding; swap the pressed and unpressed fills;
      hardcode `allCases.first`.
- [ ] Full suite twice, commit.

---

## Task 3: The Motion group, and what §9.3 becomes

**Files:** `Sources/VibeCatUI/Settings/DisplayPane.swift` (the Motion group),
possibly `Sources/VibeCatUI/Cat/MotionPreference.swift`,
`docs/superpowers/specs/2026-07-31-vibecat-design.md`

Two rows (`settings.html:498-508`): **Status animation** `[Full | Reduced | Off]`,
and **Follow the system Reduce Motion setting** as a switch, on by default.

**This is the group whose backend is most real.** Plan 6.1 fixed three motion
bypasses and made `motion:` a required, undefaulted parameter on both canvases; Plan
6.3 gated hover's clocks and measured `off` at 0.38% of a core against `full`'s ~12%.
**Wiring the picker is what finally makes that reachable by a person.**

**Settle conflict 1 here.** Read `MotionPreference.effective` and §9.3 before writing
anything. If the switch survives, `effective` has to take it into account and §9.3
needs a dated correction in §5.5's form; if it does not, §14's row is dropped with a
written reason. **Either is defensible. Silence is not.**

Note what Plan 6.3 already recorded: the prototype has **one** reduced-motion bit
(`@media (prefers-reduced-motion:reduce)` → `animation:none` *and*
`transition-duration:1ms`) where we have three levels, and its `reduce` maps most
closely to our `off`. Our `reduced` is a middle ground the prototype does not have.

- [ ] Tests: each of the three levels reaches the island — **rasterise the cat and
      assert `off` is identical across two different instants** where `full` is not,
      which is the assertion Plan 6.1 used and the only one that catches a frozen
      mid-blink; the switch's state changes `effective` when the system flag is set.
- [ ] Mutation-verify: the picker writes but nothing reads it (the enumerating
      `LaunchWiringTests` guard should catch this — **confirm it does**); the switch is
      ignored; `off` and `full` produce the same island.
- [ ] Full suite, commit.

---

## Task 4: The session card's nine switches

**Files:** `Sources/VibeCatUI/Settings/DisplayPane.swift`,
`Sources/VibeCatUI/Drawer/SessionListFace.swift`; tests alongside

Eight switches in the prototype (`settings.html:445-490`) plus `project`, which
`SessionRow.Options` already has: **Show Project Name, Show Worktree, Show AI Model,
Show Reasoning Effort, Show Your Last Message, Show Tasks, Show Subagents, Show Agent
Activity Detail.**

**Plan 5 built `SessionRow.Options` for this page and said so**, and it removed
`SessionListFace.options` because nothing passed it — *"a deliberate one-line cost,
not an oversight"*. **That one parameter is the re-thread.** `SessionRow.Options` is
already pinned by `sessionRowForwardsItsOptionsToSessionBlocks`.

**Three behaviours are already decided and must not be re-invented:**
- **`project` off substitutes the terminal's name, it does not blank the field.** A
  row with nothing on line 1 is not a row.
- **`subagents` off collapses the block to a count rather than hiding it**, because
  §11 says approvals from a child agent still need to surface.
- **`lastMessage` controls a line no adapter populates.** So its switch will appear to
  do nothing on real data. **Say so on the row or in the report** — a control that
  cannot be seen working is the thing this plan exists to avoid shipping.

**Nine near-identical rows is the copy-paste defect class**, and Plan 6.5's Task 1
found a green mutation of exactly that shape. **Mutation-verify by pointing one
switch at the wrong flag, for each of the nine.**

- [ ] Tests: each flag gates only its own content — a single-bit probe per flag,
      rasterised; and the re-thread actually reaches a row.
- [ ] Full suite twice, commit.

---

## Task 5: Right of the notch, and the cat

**Files:** `Sources/VibeCatUI/Settings/DisplayPane.swift`, and whatever the
`.agentIcon` ruling touches

Three rows that have backends: **Collapsed, show** `[Count | Agent icon | Nothing]`
(`Preferences.rightFlank`), **Coat** (five swatches, `#skins`), and **State colours**
(`#swatches`).

**Settle conflict 2 here — the `.agentIcon` placeholder.** Either land the mark or
leave the option out, and say which. The `MARKS` geometries are in
`island-motion.html:619` and have been ported once already for the session list, so
landing it is not speculative work.

**`Reveal names and timings` `[On hover | Always | Never]`:** only `On hover` exists.
**Leave the row out** and record it, per the shorter-menu rule — unless you build the
other two, in which case say so.

**State colours are read-only in this plan unless you decide otherwise.** §4.3 is the
constraint: the four hues *mean* the four states, so a picker here changes what state
looks like, not what colour means. Showing them is honest; **making them editable is a
new preference and a new invariant question**, and if you defer it, the row shows the
four hues without a picker and says why.

- [ ] Tests: each `rightFlank` value produces a **visibly different collapsed
      island** (three renders differing in exactly one input); each coat differs from
      `tabby`; **and the cat's painted left edge does not move across any of them** —
      §5.3's `LW = 58pt` is what pins it and Plan 6.1's Task 5 measured it on the
      cat's own face colours rather than the silhouette edge, which is the method to
      copy.
- [ ] Mutation-verify: the coat picker writes but the cat ignores it; `rightFlank`
      hardcoded to `.sessionCount`.
- [ ] Full suite twice, commit.

---

## Task 6: The live preview, the page, and the browser diff

**Files:** `Sources/VibeCatUI/Settings/SessionCardPreview.swift`, `DisplayPane.swift`

The prototype puts a **live preview card** under the session-card switches
(`settings.html:490+`, `.cp1` with a `.live` pip) so the nine switches show their
effect immediately. **That preview is what makes the group legible**, and it is also
the honest place to show that `lastMessage` has nothing to show.

**Reuse `SessionRow` if you can.** A preview that re-implements the row will drift
from it, and a preview that *is* the row proves the switches work. Say which you did.

- [ ] Assemble all six groups, replace Plan 6.4's owner-note placeholder for
      `display`, and confirm the other panes still announce theirs.
- [ ] **The browser diff, which is the deliverable a reviewer judges hardest.** Open
      `settings.html` in a real browser, use `getBoundingClientRect` and
      `getComputedStyle` on every element of the Display pane, and compare against
      rasterised renders. Plans 6.4, 6.5 and 6.3 each did this and each found real
      bugs no assertion would have caught — **a page that did not fit its own window
      and lost its title entirely; a `Rectangle` that dragged a 500pt card; a
      four-plan-old misreading of a radius.** Report which elements you compared and
      every difference.
- [ ] **Close what you can of Plan 6.3's six carried browser-diff differences**, since
      several are Display's: the collapsed flank order (`[detail][tally]`, not
      `[count][reveal]`), **the prototype showing one number per state in per-state
      hues, which §6.2 contradicts** — that one is a spec question this page owns —
      `.flank`'s 80ms-delayed 150ms opacity fade, and `.face`'s 190ms crossfade
      covering the flank faces where ours covers only the drawer's. **Say which you
      closed and which you did not.**
- [ ] Full suite three times, zero warnings in debug and release, commit.

---

## Out of scope, deliberately — and this is a plan's worth of work

Each of these is a Display control with **no behaviour anywhere in the repo**, so
shipping its picker would ship a lie. Recorded for a later plan:

- **Clean / Detailed island tiers.** A second collapsed presentation. §6.1's three
  tiers are about *drawer* state, not this.
- **`Meter` / `Dot` instead of the cat.** Two whole alternative left-flank renderers.
- **The four panel-size sliders** — Content Font Size, Completion Card Height, Max
  Panel Height, Max Panel Width. Plan 6.3 just made the per-face width and height
  constants; making them user-ranged is real work, and **§10.3's confirmation banner
  is still unbudgeted in the 288pt question face**, which is the same problem.
- **The two notch-tuning offsets.** `IslandGeometry` reads `NSScreen`; an offset layer
  does not exist.
- **The multi-display picker.** We recompute geometry on a display change but never
  choose a display.
- **Editable state colours.** A new preference and a §4.3 question.
- **`Reveal names and timings: Always / Never`.**
- **The `getrusage` re-measurement deferred by Plan 6.3.** Dormant cost is *expected*
  unchanged, not measured, and this page ships the control that makes `off` reachable
  — so it is a good moment to finally measure it, but the owner deferred it and it
  stays deferred until they say otherwise.

## Self-review

**Coverage.** Every Display control with existing behaviour is in Tasks 3–5, the
control primitive it needs is Task 2, its persistence is Task 1, and Task 6 assembles
and diffs. Everything omitted is listed above with the reason, which is the same
discipline Plan 6.5 used for `Soft`/`System`/`Blip`.

**Two conflicts are handed over rather than resolved in the plan**, on purpose: the
"follow the system" switch against §9.3, and `.agentIcon`'s empty square. Both need a
ruling that changes either code or the spec, and Plan 6.5 showed that inventing the
answer in a plan means defending four written decisions afterwards.

**The load-bearing guess.** `SessionRow.Options` is an `OptionSet` and I do not know
whether persisting nine booleans or one `rawValue` is right. Raw bits are compact and
silently wrong if a flag is ever renumbered; nine booleans cannot be corrupted that
way and cost nine keys. **Task 1 decides, and if it finds a third option, take it.**
