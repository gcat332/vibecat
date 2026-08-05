# Generic Adapter and Custom Sources Implementation Plan (Plan 7, §3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make VibeCat work with a CLI nobody wrote code for. Today it supports
**one** — `Sources/VibeCatCore/Adapters/` contains a single file — and §18 puts a
generic adapter and custom sources in **v1**.

**Architecture:** `SourceAdapter` is a protocol, so a source a *person* defines
cannot be a new type. The generic adapter is therefore **data-driven**: one struct
configured by values, conforming to the same protocol, which is also exactly what a
custom source is. The registry already resolves a duplicate id in favour of the
later adapter — deliberately, so a custom source can shadow a built-in — so this
fills a designed hole rather than opening one.

**Tech Stack:** Swift 6, `Foundation`, `AppKit` only for loading an icon file. **No
package may be added.**

## Why this comes before 6.7 and 6.8

The register put Plan 7 after Plan 6 for one reason: *"a custom source is one a
person configures, and there is nowhere to configure anything until Settings
exists."* Settings now exists — 6.4 built the shell, 6.5 and 6.6 two of its four
pages. **The remaining pages are §14 controls; this is the product working with more
than one CLI**, which is worth more than another page of switches.

The half that genuinely needs 6.7's Integrations page is the *UI* for adding a
source. **That is out of scope here and named as such.** A source defined in a
config file is already useful, already testable, and already the mechanism the UI
will drive — the same "reachable, not dead" standard Plan 6.1 used for the right
flank before its picker existed.

## Global Constraints

- **No external dependencies.** Swift 6, macOS 14 floor. `AppKit` for `NSImage` is a
  system framework and is fine.
- **A source is config, not code (§3).** *"A source is configuration, not code: the
  differences between CLIs live in `parse` and `jumpStrategy`, and nothing above this
  line learns their names"* — `SourceAdapter.swift`'s own doc comment. **New CLI
  support must fill the designed hole, never add a branch to the core.**
- **Third-party logos are not bundled, and this is a licence matter, not taste.**
  §3: *"VibeCat ships neutral geometric marks and lets a source point at its own icon
  file. Bundling third-party logos is a trademark question we do not need to answer to
  ship."* The repo is **public and MIT**, and MIT cannot grant trademark rights.
  **No vendor logo may be committed.** The icon is a *path*, resolved at runtime.
- **§4.3: colour means state and only state; shape says which agent is speaking.**
  A full-colour vendor logo puts a second meaning on hue. **Task 1 rules on this and
  it is the plan's central design decision, not a detail.**
- **Fail open (§2.3).** A crashed or absent island must never hang a terminal. A
  custom source is **user input** — a malformed definition, a missing icon, a parse
  rule that matches nothing must all degrade, never crash and never block. The
  registry already refuses to trap on a duplicate id for exactly this reason.
- **A test that cannot fail is not a test.** Across eight plans: 6.4 shipped seven;
  6.5 caught three in its own new tests; every task of 6.3 and all six of 6.6
  reported a green mutation rather than patching it. **Report a mutation that stays
  green rather than adjusting the test.**
- **`LaunchWiringTests`' enumerating guard does not catch a disconnected reader** —
  Plan 6.6's Task 3 measured that and its Task 4 hit it in its own first test. A
  dictionary entry is documentation; the test that binds renders or runs the real
  thing.
- **Rasterise anything visual.** `rasterise(_:scale:)` is a **free function**;
  `Raster` is **not** `Equatable`; `ImageRenderer` cannot render a `ScrollView` or a
  `Menu` — the session list has one, so use `rasteriseHosted(_:size:)`. **Count a
  colour inside a box you predicted, never across the render.**
- **Run the suite with `Scripts/test.sh`** (`swift test --no-parallel`; its header
  says why). Current total is **788**, ~19s. Zero warnings in debug and `-c release`.
- Commit subjects state the insight. Trailer
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Never `git push`.** Ask, every time.

## What exists, verified rather than assumed

| Thing | State |
|---|---|
| `SourceAdapter` | A protocol: `id`, `displayName`, `jumpStrategy`, `reports`, `parse(_:origin:)`. **No `icon`**, though §3's shape lists one |
| `SourceRegistry` | Built to take many; **resolves a duplicate id in favour of the later adapter, on purpose** |
| `Adapters/` | **One file**, `ClaudeCodeAdapter` — id `claude-code`, `.terminalSession`, five kinds |
| §3's `hookInstall` | **Does not exist anywhere.** Neither does a hook-snippet generator |
| `CLIMark` | Four neutral geometries, ported from the prototype, tinted by the state accent |
| The owner's icons | Six files in `~/Downloads/icon`, converted to 256×256 PNG, **outside the repo and staying there** |

## The owner's icon set, and what was measured about it

The owner supplied brand marks and asked for them to be used for the session list.
Measured, so the plan can rest on facts:

- **`NSImage` loads SVG, PNG and WebP with no dependency.** All six loaded.
- **Two SVGs reported `1×1`** because they used `width="1em"` with no font context;
  their `viewBox` was already `0 0 24 24`. Converted versions are 256×256.
- **`claude_logo.png` and `codex_logo.png` are glyph-only** — transparent corners,
  the mark itself coloured (`#D97757`, `#5D74FF`).
- **`claude.png` and `openai.png` carry a filled circular background** — verified as
  a circle rather than an empty image by the edge-midpoint test: corners transparent,
  the middle of each edge fully opaque.
- **Ink extent varies**: `codex_logo` 85% of its canvas, the circles 100%. So they do
  not sit at the same visual weight without normalising.

**None of this is committed and none of it may be.** The plan's job is the
*mechanism* that points at them.

---

## Task 1: `SourceAdapter.icon`, and what a brand icon does to §4.3

**Files:**
- Modify: `Sources/VibeCatCore/SourceAdapter.swift`
- Create: `Sources/VibeCatUI/Drawer/SourceIcon.swift`
- Test: `Tests/VibeCatCoreTests/SourceAdapterTests.swift`,
  `Tests/VibeCatUITests/SourceIconTests.swift`

**Produces:** an `icon` on the protocol — §3 calls it *"a swappable runtime asset"* —
and a view that draws it with the geometric `CLIMark` as fallback.

### The design decision this task owns

`CLIMark` today is `currentColor` geometry **tinted by the state accent**: shape says
who, hue says what state, both on one mark. That is §4.3, and Plan 5's second
fidelity wave had to correct a brief that said the opposite.

**A brand icon breaks that**, because it arrives with its own colour — `#D97757`,
`#5D74FF`, a green circle, a blue square. So:

- **Template**: draw the icon as a mask tinted by the state accent. Keeps §4.3
  exactly. Loses the brand's colour, and a circular background becomes a solid
  state-coloured disc, which may read as a badge rather than a mark.
- **Full colour**: hue on that element stops meaning state. Needs a **written
  decision** and §4.3 arguably needs a dated correction saying the *mark* is the one
  exception.
- **Something else** — e.g. full colour only in the drawer where the state is already
  stated by a word and a dot, template in the collapsed flank where the mark may be
  the only thing visible.

**Decide, implement, and write the reasoning where the code is.** The measured facts
above are the input; the owner's instruction was "use these icons to indicate the
source", which is about *identity*, and §4.3 already assigns identity to shape.

### The fallback is not optional

An icon path is user input: it can be missing, unreadable, a directory, or an image
of the wrong shape. **Every one of those must fall back to `CLIMark` silently** —
§2.3's reflex applied to a picture. And **no vendor asset may be committed to make a
test pass**: build a temporary file in the test, or use one of the repo's own images.

- [ ] Tests first: an adapter with no icon draws the geometric mark; one with a valid
      icon draws something **different** (rasterise, and assert a colour only the icon
      can produce — not merely that two renders differ, which Plan 6.4 shipped as a
      test that passed with the selection inverted); a missing path, a directory and a
      zero-byte file each fall back rather than throwing.
- [ ] Implement, then mutation-verify: remove the fallback (the three bad-input tests
      must fail); ignore the state accent if you chose template (the tint test must
      fail); draw the icon at the wrong size (assert the box you predicted).
- [ ] Full suite, commit.

---

## Task 2: The generic adapter

**Files:**
- Create: `Sources/VibeCatCore/Adapters/GenericAdapter.swift`
- Test: `Tests/VibeCatCoreTests/GenericAdapterTests.swift`

**Produces:** a `SourceAdapter` whose behaviour is entirely values — id, display
name, icon path, jump strategy, reported kinds, and **a mapping from a raw payload
onto the shared `kind` vocabulary**.

§3: *"a **generic** adapter for anything that can run a command."* And §18 puts it in
v1 while leaving the Codex, Copilot and Gemini presets in **Later** — because *"the
generic adapter is what makes them cheap when they come."* So the test of this task
is whether a preset becomes data.

### The part that needs designing

`ClaudeCodeAdapter.parse` reads `hook_event_name`, `session_id`, `cwd` and maps
vendor event names onto `Kind`. A generic adapter cannot know those names, so its
mapping has to be **declared**: which JSON key holds the event name, which holds the
session, which holds the working directory, and which vendor name means which `Kind`.

**Keep it as small as it can be and still work.** A configuration language that can
express anything is a second parser, and §3 says a source is *config*. Look at what
`ClaudeCodeAdapter` actually needs and generalise **that**, not a hypothetical.

**Then prove it**: express `claude-code` itself as generic-adapter data and assert it
produces the same `VibeEvent` as `ClaudeCodeAdapter` for the same payloads. That is
the test that says the generalisation is real. **If it cannot express claude-code, it
cannot express anything, and that is the finding** — report it rather than narrowing
the assertion.

### Malformed input is the normal case

A person writes this by hand. A missing key, a wrong type, an unknown event name, a
`kind` that is not in the vocabulary — none may crash and none may hang. `parse`
already returns `nil` for *"a well-formed event this adapter deliberately ignores"*
and throws `AdapterError` otherwise; follow that, and make sure a throw is caught
somewhere that fails open.

- [ ] Tests first, including: a payload the mapping ignores returns `nil`; a missing
      declared key throws rather than inventing a value; an unknown vendor event name
      is ignored rather than mapped to a default `Kind`; **and the claude-code
      equivalence above.**
- [ ] Mutation-verify: map every unknown event to `.running`; drop a required key's
      guard; make the ignore case throw.
- [ ] Full suite, commit.

---

## Task 3: A custom source, defined and loaded

**Files:**
- Create: `Sources/VibeCatCore/CustomSource.swift`
- Modify: `Sources/VibeCatCore/SourceRegistry` if the loading belongs there
- Modify: wherever the registry is built at launch
- Test: `Tests/VibeCatCoreTests/CustomSourceTests.swift`, and a launch-wiring test

**Produces:** a persisted definition — §3: *"Settings can add a custom source: name,
icon file, jump target, and a generated hook snippet"* — decoded into a
`GenericAdapter` and registered.

**Where it lives is a decision.** `Preferences` is a flat struct of scalars and this
is a list of records, so it may not belong there. A JSON file in the app's support
directory, `UserDefaults` as encoded data, or a new type — **choose, and say why.**
Note that a file a person can edit by hand is a feature here, not a hazard, because
§3's whole point is that a source is config.

**The registry's duplicate rule is load-bearing and already tested:** later adapters
win, *"precisely so a user's custom source can deliberately override a built-in."*
**Assert that a custom source with `id == "claude-code"` shadows the preset** — that
is the designed behaviour and nothing currently proves it end to end.

**Fail open, again.** A corrupt definitions file must leave the built-in presets
working. **Not "throw and let the app die at launch"** — Plan 6.2 shipped a launch
path that `abort()`ed and 509 green tests could not see it, because no test runs
`main.swift`.

- [ ] Tests: a definition round-trips; a custom source appears in the registry and
      parses an event; **a custom source shadows a built-in with the same id**; a
      corrupt file leaves the presets intact; a definition naming an icon that does
      not exist still registers and falls back to the geometric mark.
- [ ] **A launch-wiring test that runs the real construction**, not a hand-built
      registry — the guard that a dictionary entry cannot give you.
- [ ] Mutation-verify, full suite, commit.

---

## Task 4: The hook snippet

**Files:**
- Create: `Sources/VibeCatCore/HookSnippet.swift`
- Test: `Tests/VibeCatCoreTests/HookSnippetTests.swift`

§3 lists *"a generated hook snippet"* as part of adding a source, and §14's
Integrations section shows install status per source. **Neither exists.** Generating
the snippet is this plan's; showing it is 6.7's.

**Read `Scripts/replay.sh` and the hook's own entry point first**, and whatever
documents how `vibecat-hook` is wired into Claude Code today — the snippet has to be
the real thing, and the fastest way to get it wrong is to invent a shape nobody runs.

**One hazard with precedent:** `Scripts/build-app.sh` once had a bug where bash 3.2
read `$APP…`'s ellipsis bytes as part of the variable name. A generated shell snippet
is a string this project has already been bitten by — quote deliberately, and say
what shell you are targeting.

- [ ] Tests: the snippet names the binary and the socket path; a source id with a
      space, a quote, or a `$` in it does not produce a snippet that breaks or expands
      — **assert on the escaping, because that is the part a person will hit and the
      part a happy-path test misses.**
- [ ] Mutation-verify the escaping specifically, full suite, commit.

---

## Task 5: The session list draws the real source

**Files:** `Sources/VibeCatUI/Drawer/SessionRow.swift`, `CLIMark.swift`, and Task 1's
`SourceIcon`
**Test:** extend `Tests/VibeCatUITests/SessionRowTests.swift`

The owner's request, delivered: a row shows the icon of the CLI that raised it, and
falls back to the geometric mark when there is none.

**`Session` carries `cli` as a `String`** and `CLIMark(cli:)` maps it. So the row
needs the adapter's icon for that id, which means the row needs the registry — or the
icon resolved upstream. **Decide where that lookup happens** and prefer upstream: a
view that reaches into a registry is a view that cannot be rendered in a test without
one.

**§11's three lines per row still bind.** Every text field needs `.lineLimit(1)`; a
fourth line is a defect and one has shipped that way. **An icon that is taller than
the geometric mark can grow the row** — measure it.

Also: Plan 6.3's Task 6 established that the **open** flank shows `.generic` for a
mixed set of CLIs, because no single mark is true of several, and Plan 6.6's Task 5
followed that for the collapsed flank. **A row is one session, so a row has one true
source** — that asymmetry is correct and worth a comment so nobody "fixes" it.

- [ ] Tests: a row with a known source draws its icon; an unknown `cli` draws the
      generic mark; **the row's height is unchanged by which of the two it draws.**
- [ ] Mutation-verify, then look: `VIBECAT_LIST_SHOT=/tmp/list.png Scripts/test.sh --filter sessionListShot`
      and **open the PNG.** Every plan that did this found something.
- [ ] Full suite, commit.

---

## Task 6: Prove it with a second CLI, on hardware

**Files:** docs, `Scripts/`, and whatever the verification needs

**The claim this plan makes is "VibeCat works with a CLI nobody wrote code for."
Task 6 tests that claim, and nothing else in the plan does.**

- [ ] **Define a real second source as data** — not a fixture. Codex or Gemini if you
      have one installed; otherwise a small script that emits plausible events, which
      is exactly what §3's "anything that can run a command" means.
- [ ] Generate its hook snippet with Task 4, install it, and drive it. Confirm events
      reach the island, the row shows the right source, and **the hook exits `0`** —
      §2.3 is this repo's one unbreakable invariant.
- [ ] **Launch both the bare binary and the signed bundle.** Plan 6.2 shipped a
      launch-path abort invisible to 509 green tests because no test runs `main.swift`.
- [ ] Update §3's spec section with a dated correction if the shape you built differs
      from the one it sketches — it lists `hookInstall` and `icon`, and you will have
      learned what those actually need to be.
- [ ] Update `plans/README.md`: what landed, what is still Later (the Codex, Copilot
      and Gemini presets), and what 6.7 inherits.
- [ ] Full suite three times, zero warnings in debug and release, commit.

---

## Out of scope, deliberately

- **The Integrations page's UI** — the CLI list, per-source install status, the "Add
  CLI" branch, and the icon file picker. **Plan 6.7.** This plan builds what that page
  drives.
- **Codex, Copilot and Gemini presets.** §18 puts them in **Later**, and the register
  says the generic adapter is what makes them cheap. Shipping them here would be
  shipping Later.
- **Committing any vendor icon.** Not a scope question — a licence one.
- **Jump for a custom source beyond choosing a `JumpStrategy`.** Jump itself has no
  code at all; it is Plan 6's remainder.
- **The `getrusage` re-measurement** deferred by Plan 6.3 on the owner's instruction.

## Self-review

**§3 coverage.** `icon` → Task 1. `parse` and the `kind` mapping → Task 2.
`jumpStrategy` and `reports` → already on the protocol, exercised by Tasks 2–3.
`hookInstall` → Task 4, which is the closest thing the spec's sketch has to a name
for it. Custom sources → Task 3. *"Presets ship for Claude Code, Codex, Copilot,
Gemini"* → **deliberately not**, per §18's Later column, and said so above.

**Placeholders.** None, but Tasks 1–3 each ask for a *decision* rather than
prescribing one — how a brand icon interacts with §4.3, how small the generic
mapping can be, and where a definitions file lives. Those are design choices §3 does
not settle, and Plan 6.5 showed what happens when a plan invents the answer: four
written decisions to defend afterwards.

**The load-bearing guess.** Task 2's claim that `claude-code` can be expressed as
generic-adapter data. If it cannot, the generalisation is wrong and the honest
outcome is a smaller generic adapter plus a note about what a preset still needs
hand-written — **not a wider config language.** The test is written so that failing
is informative.

**One thing I expect to be contentious.** Task 1's §4.3 ruling. Tinting a brand logo
to a state colour will look wrong to anyone expecting the brand; leaving it in full
colour puts a second meaning on hue in an interface whose whole colour system is one
meaning. **There may be no answer that satisfies both**, and if so the plan wants the
trade named in the source rather than resolved silently.
