# VibeCat — Design

**Date:** 2026-07-31
**Status:** Design agreed, ready for an implementation plan
**Prototypes:** [`island-motion.html`](../prototypes/island-motion.html) · [`settings.html`](../prototypes/settings.html)

---

## 1. What this is

A macOS menu-bar-less status app that lives in the notch and tells you what your
AI coding agents are doing — and lets you answer them without leaving what you
are looking at.

The problem it solves is specific: when you run several agents at once, the cost
is not that any one of them is slow. It is that **you cannot tell which one is
blocked on you** without cycling through terminal windows. An agent that asked a
question five minutes ago has been idle for five minutes.

### Goals

- Know at a glance whether anything needs you, without reading text.
- Answer a blocked agent in one or two clicks, from wherever you are.
- Jump to the exact terminal window, tab and split a session belongs to.
- Support any CLI that can run a command on an event, not a fixed list.

### Non-goals

- **AI usage or quota tracking.** Explicitly out of scope.
- Being a terminal, a session manager, or a chat client.
- Reading agent output. VibeCat only sees what a hook reports.

---

## 2. Architecture

```
  Claude Code / Codex / Gemini / any CLI
              │  runs a command on Stop, Notification, PreToolUse…
              ▼
  ┌──────────────────────────────────────────┐
  │ vibecat-hook            (universal binary)│
  │  · reads the CLI's JSON event from stdin  │
  │  · captures origin from its own env       │
  │  · connects to the socket, sends, waits   │
  └───────────────────┬──────────────────────┘
                      │ ~/Library/Application Support/VibeCat/vibecat.sock
  ┌───────────────────▼──────────────────────────────────┐
  │ VibeCat.app                                           │
  │  SocketServer → EventRouter → SessionStore (@Observable)
  │        │                            │                 │
  │  SourceRegistry              NotchController          │
  │  (presets + custom)          (NSPanel over the notch) │
  │        │                            │                 │
  │  Activator / Injector        UNUserNotificationCenter │
  └──────────────────────────────────────────────────────┘
```

### 2.1 Why a Unix domain socket

The hook must be able to **block and receive an answer**. A permission prompt in
Claude Code is a `PreToolUse` hook that the CLI waits on; if VibeCat can reply on
that same channel, answering from the island is exact — no keystroke injection,
no guessing at terminal state.

Rejected alternatives:

| Option | Why not |
|---|---|
| HTTP on localhost | Heavier, needs port management, wider attack surface, awkward blocking |
| File drop + FSEvents | One-way. Cannot carry a reply back, and adds latency |

Socket path is `~/Library/Application Support/VibeCat/vibecat.sock`, mode `0600`,
owner only.

### 2.2 Wire protocol

Newline-delimited JSON, request/response.

```jsonc
// hook → app
{ "v": 1, "id": "uuid", "cli": "claude-code",
  "kind": "permission",            // idle | running | done | permission | question | failed
  "session": "abc123",
  "cwd": "/Users/me/dev/api",
  "worktree": "auth-hardening",
  "model": "Opus 4.8", "effort": "high",
  "title": "Bash command",
  "body": "rm -rf build/",
  "choices": [ {"id":"allow","label":"Allow once"},
               {"id":"always","label":"Allow all pnpm commands in ~/dev/api this session"},
               {"id":"deny","label":"Deny"} ],
  "multi": false,                  // true → checkboxes and a Send button
  "wantsReply": true,
  "answerDeadline": 20,             // seconds; the hook's own bound on a human answer
  "tasks":  [ {"t":"Audit authentication flow","s":"doing"} ],
  "agents": [ {"n":"Explore (Search API endpoints)","t":"8s",
               "m":"Sonnet 4.6 · High","sub":"Grep: handleRequest"} ],
  "origin": { "app":"com.googlecode.iterm2",
              "termSession":"w0t1p0:UUID", "vscodePid": null } }

// app → hook (only when wantsReply)
{ "id":"uuid", "choice":"allow", "choices":["a","b"], "text":null }
```

`kind` is the shared vocabulary. Adapters map their CLI's own event names onto
it, so the core never learns a vendor's terminology.

### 2.3 Fail-open is a hard requirement

**A crashed island must never be able to hang a terminal.** Every wait the hook
makes is bounded, and on timeout or a missing socket, it returns the CLI's own
default and exits 0.

There are two deadlines, not one, because they bound two different things.
*Delivery* — confirming the app is even listening — keeps a short `300ms`
default: nothing is waiting on an answer yet at that point, so any delay there
is pure cost. A `wantsReply` event is different: the CLI would otherwise block
on its own prompt indefinitely, so a bounded wait is not a regression against
that — it is a ceiling that did not exist before. That one uses `answerDeadline`
(§2.2), defaulting to 20 seconds: long enough for a person to actually read and
answer, still bounded, still failing open the same way delivery does.

Both are settable in Settings but default on, and the copy says turning either
off is not recommended. Fail-open is the single most important safety property
in the design.

> **Corrected 2026-08-06, after Plan 9 measured the hook protocol.** Three things
> above are now wrong, and the third is the one that changes the design's own
> reasoning rather than a number.
>
> **1. The answer clamp's ceiling is `3600`, not `60`.** The floor stays `0.02`.
> Those two bounds exist for one purpose — rejecting a value absurd enough to
> saturate a `DispatchTime` — and a *person's* choice is bounded separately, by
> `UserDefaultsPreferenceStore.clampedHandBack` at `0.5…60` **minutes**
> (`Preferences.handBackToTerminalAfter`, default 1 minute). Two clamps, because
> "not absurd" and "a sensible thing to offer someone" are different questions;
> raising the wire floor to the product floor would make nine existing tests that
> observe a real timeout at 0.05s and 0.6s impossible rather than slow.
>
> **2. "Every wait is bounded" now has one deliberate exception.**
> `handBackToTerminalAfter` may be `Never`. It is the absence of an expiry, never
> a very late one: `PendingQuestion.waitInstant(until:)` is the only place a
> `DispatchTime` is derived from an expiry and the only place `.distantFuture` is
> produced, and its `min` against the ceiling keeps a finite expiry finite.
> Spelling `Never` as `Date.distantFuture` would make the accidental forever this
> section warns about indistinguishable from the intended one. Not the default.
>
> **3. The sentence "the CLI would otherwise block on its own prompt indefinitely,
> so a bounded wait is not a regression against that" is only half true, and the
> missing half inverts what this deadline is for.** Measured against Claude Code
> 2.1.223, twice, headless, with a `PreToolUse` hook that slept 3s and wrote to
> stderr: the CLI **blocks** on the hook and prints nothing for the duration; the
> hook's stderr never surfaces on `exit 0` or `exit 1`; and its own prompt appears
> only *after* the hook returns. The payload carries no way to retract an
> in-flight ask (`hook_event_name`, `tool_name`, `tool_input`, `tool_use_id`,
> `transcript_path`, `prompt_id`, `session_id`, `permission_mode`, `cwd`,
> `effort`).
>
> The CLI's own prompt does wait forever — but **visibly**. A blocked hook is
> invisible: the terminal simply looks idle. Same duration, opposite
> discoverability. So the answer deadline is **not a safety net; it is the
> hand-back**, and without it the terminal never gets a prompt at all. What makes
> a crashed island harmless is the other two things: the `300ms` delivery bound,
> and socket EOF — `SocketClient.readLine` falls through to `return nil` when
> `read()` returns 0. Those are untouched.
>
> A consequence worth stating: **only one party can hold the decision at a time.**
> "Answerable in the notch and in the terminal at once" is not a preference this
> design declined, it is unavailable, and the only route to it would be typing
> into the terminal on the user's behalf — which this section's own framing
> rejects, because replying through the hook is exact *because* it is not
> simulated keystrokes.

---

## 3. Source adapters

A source is config, not code:

```
SourceAdapter {
  id, displayName, icon            // icon is a swappable runtime asset
  hookInstall                      // how to write the hook into that CLI's config
  parse(rawEvent) -> VibeEvent     // map onto the shared `kind` vocabulary
  jumpStrategy                     // .terminalSession | .activateApp(bundleID) | .vscode
  report: Set<Kind>                // which events this source is allowed to raise
}
```

Presets ship for **Claude Code, Codex, Copilot, Copilot (VS Code Agent), Gemini**,
plus a **generic** adapter for anything that can run a command. Settings can add a
custom source: name, icon file, jump target, and a generated hook snippet.

On brand icons: VibeCat ships neutral geometric marks and lets a source point at
its own icon file. Bundling third-party logos is a trademark question we do not
need to answer to ship — and custom sources need the mechanism anyway.

> **Reversed 2026-08-06, on the owner's instruction, after they were told what this
> paragraph says.** VibeCat now **does** bundle brand marks, in
> `Sources/VibeCatCore/Resources/Icons/` — Claude, Codex, ChatGPT/OpenAI, iTerm2 and
> VS Code — so a session row shows the mark of the CLI that raised it without anyone
> configuring a path first.
>
> **The trademark question this paragraph declined to answer is now open, and the
> answer is "MIT does not cover it".** The repository is public under MIT, which
> grants copyright permissions and is silent on trademarks; redistributing another
> party's mark is not something we can license on their behalf. That is recorded here,
> in `README.md`'s licence section and in `BundledIcon`'s doc comment, so nobody has
> to infer it from a directory listing. A rights holder asking for a removal is a
> normal outcome, not a surprise.
>
> **What did not change is the sentence before it.** The point-at-a-file mechanism is
> still the primary path and still the only one a custom source uses: an adapter's
> `icon` is a path, `CLIMark`'s neutral geometry still draws whenever a path resolves
> to nothing, and Plan 7's Task 1 proved that for four separate shapes of bad input.
> **Deleting the icons directory degrades the app to the geometry rather than breaking
> it** — which is the property that makes the reversal cheap to reverse again.

> **Corrected 2026-08-06, after Plan 7 shipped.** The sketch above is right about
> the shape and wrong about two of its members. Both were found by building it and
> then running it against a second CLI on real hardware.
>
> **`hookInstall` is not a member of `SourceAdapter`, and could not usefully be
> one.** The thing a person installs is a *shell command line*, and it is the same
> line for every CLI — `HookSnippet.command(binaryPath:cli:socketPath:)` — because
> any CLI that can run a command as a hook runs this same invocation. What differs
> per CLI is the **wrapper**: Claude Code takes a `"hooks"` block in
> `~/.claude/settings.json`, Codex takes a differently-shaped `hooks.json`, another
> CLI might take TOML. Putting that wrapper on the adapter would be a per-vendor
> branch inside the core, which is exactly what this section's own first sentence
> forbids. So the generator is a free function and the wrapper is the config
> format's business, not the adapter's.
>
> **`hookInstall` also presupposed something that did not exist: an installed hook
> binary.** `vibecat-hook` was never bundled — it lived at
> `.build/{debug,release}/vibecat-hook`, which moves with the build configuration —
> so no snippet could name a path that survives. It now ships inside the app at
> `Contents/MacOS/vibecat-hook`, signed with the app, and is mirrored on launch to
> `~/Library/Application Support/VibeCat/bin/vibecat-hook`, which is the path a
> snippet names. Two locations, because a path written into another CLI's config
> file has to survive the app being moved, and only a path outside the bundle can.
>
> **`icon` is a path resolved on the *app* side, not a field on the wire.** The
> hook parses events and the app draws them, and for a while only the hook had a
> `SourceRegistry` — so `Session.icon` existed and was assigned from nowhere. The
> resolution belongs where the drawing is: `AppModel` builds a registry through the
> same factory the hook uses and resolves `cli → icon` at ingest. Adding an icon
> field to `VibeEvent` would have worked and would have put a presentation detail on
> a socket two executables speak.
>
> **The icon path is user input on a filesystem, which makes it a §2.3 hazard, not
> just a picture.** Measured: the signed app, launched with `open`, drawing an icon
> from `~/Downloads` — a TCC-protected directory — hung its **main thread inside
> `open(2)`** indefinitely, because an `LSUIElement` app cannot present the prompt
> TCC wants to show. §2.3's "every wait is bounded" applies to reading an icon file.
> `SourceIconLoader` bounds it and caches the answer; a path that does not answer
> in time draws the geometric mark instead, which is the same thing "no icon"
> already did.
>
> **Not corrected, and worth saying so: "presets ship for Claude Code, Codex,
> Copilot, Gemini" is still Later (§18), and the generic adapter is what makes them
> cheap.** Measured while proving it: Codex's payload is expressible as generic
> adapter *data* with no code at all (`hook_event_name` / `session_id` / `cwd`, the
> same three keys Claude Code uses). What is *not* expressible is Claude Code's own
> `PreToolUse` — its body needs a nested `tool_input` traversal with a preferred-key
> order, and its "always" choice label embeds the tool name into a sentence. A
> preset is therefore data plus, occasionally, a little code — not a wider config
> language.

---

## 4. State model

### 4.1 The five states

| State | Meaning |
|---|---|
| `idle` | Nothing to do |
| `running` | An agent is working |
| `waiting` | An agent needs an answer |
| `failed` | A run stopped with an error |
| `dormant` | No sessions at all |

### 4.2 The worst state wins

The island shows the **most urgent** session, not the most common:

```
waiting  >  failed  >  running  >  idle
```

`waiting` outranks `failed` because a waiting agent is idling on you *right now*,
while a failed one has already stopped. This ordering holds in the session list
too — **the list is a view, not a state**, so opening it does not change what the
island is reporting. (An early build made the list its own grey "state", which
turned a red-and-amber situation grey the moment you looked at it.)

### 4.3 Colour means state, and only state

| | Hex | Meaning |
|---|---|---|
| 🟢 | `#3FD99B` | idle / finished |
| 🔵 | `#5B9DF9` | running |
| 🟠 | `#FFA63C` | needs you |
| 🔴 | `#FF5C5C` | failed |

Which agent is speaking is carried by its **icon shape**, never by hue. That frees
all four colours to mean exactly one thing each, which is what makes the island
readable out of the corner of an eye. Everything tinted by the current state —
marks, cat, badge, counts, the aura — uses the same `--accent`.

---

## 5. Notch geometry

### 5.1 The cutout is a hole

The notch has no pixels. The rule that follows:

> **The black shape may span the cutout, because the cutout is black too.
> Content may not.**

Every glyph, number and label sits in the flank left of the cutout or the flank
right of it. Nothing is ever positioned in the middle.

Dimensions must be read at runtime from `NSScreen.safeAreaInsets` /
`auxiliaryTopLeftArea` — notch width varies by model, and changes when the user
moves the window between displays or changes resolution. The prototype's `186pt`
is a stand-in. Settings exposes a manual ±offset for machines that do not report
correctly, with `0` meaning "use the macOS value".

**Displays without a notch** fall back to a floating pill in the same position,
with no dead zone.

### 5.2 Which side holds what

| Zone | Holds |
|---|---|
| Left flank | The cat and its badge |
| Cutout | Nothing (camera only) |
| Right flank | Session count, or the agent icon; name and timings on hover |
| Drawer | Questions and the session list |

### 5.3 The left flank is a constant

`LW = 58pt` = `12` padding + `18` cat + `4` gap + `14` badge + `10` padding.

The badge box is fixed at `14pt` whatever it contains — a `zzz` is three times the
width of a `!`, and without a constant slot the flank resized on every state
change and walked the cat sideways.

Holding `LW` constant pins the island's left edge, because the centring shift
cancels the rest:

```
leftEdge = wrapCentre − W/2 + shift
         = wrapCentre − (LW + notch + RW)/2 + (RW − LW)/2
         = wrapCentre − notch/2 − LW
         = notchLeft − LW          ← RW drops out entirely
```

So the right side can grow as much as it likes and the cat never moves.

### 5.4 Widths are measured, not declared

The right flank is measured from its actual content each time the state changes
and on hover, then written back as an explicit width so the spring still has
something to animate. The island never reserves space it is not using.

Measured examples: dormant `244pt`, running `279pt`, three agents `295pt`.

### 5.5 Corners

Straight sides, `15pt` radius at the bottom. The same shape the physical cutout
has, so the island and the notch read as one object.

> **Corrected 2026-08-01, after Plan 2 shipped.** This section originally called
> for `9pt` concave fillets at the top, on the claim that "Apple's own cutout
> does not meet the bezel at a right angle", plus a rule suppressing the fillet
> on an empty flank. Both were wrong. Measured on the running app, the dormant
> island's left edge climbed `599.5 → 605.0` over six rows while its right sat
> dead straight at `847.5` — the suppression rule guaranteed the two ends could
> never match, and the flare read as a hook the real notch does not have.
> Straight sides make the ends identical and the suppression rule unnecessary.

---

## 6. The island

### 6.1 Three tiers of disclosure

| Tier | Shows |
|---|---|
| **Rest** | A cat, a badge, a count. **No words at all.** |
| **Hover** | Flanks widen; name and elapsed time reveal over `280ms` |
| **Click** | Drawer opens below the notch line: question, or session list |

An idle machine should look idle. At rest nothing animates except the cat.

### 6.2 Collapsed anatomy

```
   ┌────────────┐              ┌──────────────┐
   │ 🐱  ▪▪     │   [ notch ]  │        1  2  │
   └────────────┘              └──────────────┘
     cat  badge                  counts by state
```

Right-flank content is configurable: **session count** (default), **agent icon**,
or **nothing**. The count is the default because a brand mark tells you what you
already know, while a count tells you how many sessions are open and its colour
tells you what they are doing.

### 6.3 Drawer heights and widths

| Face | Height | Width |
|---|---|---|
| Question | `288pt` | `560pt` |
| Question, reply field open | `184pt` | `560pt` |
| Question, multi-select | `300pt` | `560pt` |
| Session list | `420pt`, rows scroll | `560pt` |

The drawer follows its content — opening the reply field shrinks it back rather
than leaving dead space.

> **Corrected 2026-08-05, after Plan 6.2 shipped.** This section gave heights only,
> and the silence was read as "the width is whatever the collapsed island is".
> `IslandGeometry.frames` let the tier reach the height and nothing else, so the
> **open** island was `leftFlank + notch + rightFlank` — a function of how many
> digits the session tally happened to have. Measured on the `mbp14` fixture: 1 and
> 3 sessions gave byte-identical widths of `273.1pt`, and 12 sessions gained `8.1pt`
> only because the tally reached two digits. A session row's ink saturates at
> `420pt`, so §11's line 2 truncated to `As…` at every session count — a defect
> carried in `plans/README.md` for two waves while its cause sat here as an
> omission.
>
> The prototype was never silent: `island-motion.html:162–164` sets `width:560px` on
> `ask`, `askmulti` and `list` alike, and `:166` (`ask[data-other="true"]`) changes
> only the height. So the width column above is the prototype's, and it is flat.
>
> **`560pt` is literal, not derived from the cutout.** The prototype hardcodes a
> `186px` notch, so its `560` could have meant either the number or
> `LW + notch + 316`; ours reads the real cutout off `NSScreen`, which makes those
> two different rules. It is a measurement of the drawer's own content — the mockup
> gives its rows `560 − 2×18 = 524pt` against ink that saturates at `420` — and no
> face's content gets wider because a machine's camera housing does. Deriving it
> would give `58 + 0 + 316 = 374pt` on a **notchless display**, below the width at
> which a row saturates, reintroducing this very defect on the one display that
> never had a geometric reason for it.
>
> **Two rules, because one would be a magic constant.** The design width is floored
> at `leftFlank + notch + minimumRightFlank`: §5.1's "the notch is a hole" holds
> only because our black spans the cutout and our corner sits outside theirs, so
> covering the hole wins whenever the two disagree. On every notch that exists they
> do not — the floor is `258pt` on a 14-inch MacBook — and it would take a cutout
> wider than `487pt` to bind. It is written down because it is the *reason* a flat
> `560` is safe rather than lucky. See `IslandGeometry.openWidth(face:)`.
>
> **On a notchless display** the open width is the same `560pt` and §5.1's fallback
> pill stays centred, so it opens symmetrically about the screen centre. §5.3's
> pinned left edge is not violated there: that invariant exists so the cat keeps its
> place relative to the cutout, and there is no cutout. On a notched display the
> left edge is pinned as ever and all `287pt` of the expansion appear on the right.
>
> **On the `184pt` row: it was already here, and already implemented.** Plan 6.3's
> brief expected to find two rows in this table and to have to add the two the
> prototype has; all four heights were in fact already present and correct, and
> `DrawerFace.questionWithReply` is genuinely reached — `QuestionModel.face` returns
> it while `isWritingOther`. So the height correction that plan carried had already
> been made by an earlier one, and the only thing missing from this section was the
> width. Recorded rather than quietly dropped, because a plan whose premise about
> the spec is stale is worth knowing about; the width column above is the whole of
> this correction.

### 6.4 Panel footer

Once the drawer is open, a footer holds two controls: **mute** (bound to the same
setting as the app's sound toggle) and **settings**. Nothing else — usage stats
are out of scope.

---

## 7. The cat

The signature element, and the reason the product is called what it is.

### 7.1 Sprite

`18 × 14` cells at one screen pixel per cell — a finer grid than the flank needs,
so the sprite can afford real shading rather than a flat silhouette.

```
..OO..........OO..     O  outline   darkest
.OEEO........OEEO.     S  shadow
.OEEHO......OHEEO.     B  body      = --accent
.OHHHOOOOOOOOHHHO.     H  highlight
.OLLLLLLLLLLLLLLO.     L  lightest
OHHHHHHHHHHHHHHHHO     E  inner ear #F2A0B6
OHHHHHHHHHHHHHHHHO     N  nose      #F08098
OBBKWWBBBBBBKWWBBO     W  eye white #FFFFFF
OBBWPPBBBBBBWPPBBO     K  sparkle   #FFFFFF
OBBPPPBBBBBBPPPBBO     P  pupil     #12131A
OBBBBBBBNNBBBBBBBO
OSBBBBBOBBOBBBBBSO     Tones derive from --accent:
.OSSBBBBBBBBBBSSO.       O = accent 20% over #05070B
..OOOOOOOOOOOOOO..       S = accent 60% over #05070B
                         H = accent 64% over #FFFFFF
                         L = accent 36% over #FFFFFF
```

Cuteness here is proportion, not detail: eyes three rows tall with a white
sparkle in each, ears clear of the skull, a tiny nose and a soft `w` mouth.

### 7.2 Moods

| Mood | State | Eyes | Motion |
|---|---|---|---|
| `sleep` | dormant | shut | slow drowse, `3s` |
| `trot` | running | open, rare blink | quick bob, `1s` |
| `call` | waiting | open, mouth open | attention pulse, `1.1s` |
| `happy` | finished | `^ ^` arcs | one spring pop |
| `dead` | failed | `X X` | slow wobble, `2.4s` |

The blink is the one instantaneous thing in the interface — because a blink is
instantaneous. Everything else eases.

### 7.3 Coats

A coat changes **markings, never hue** — it repaints cells with the shadow or
highlight tone already in the ramp. The fur is always the state's colour, so
"colour means state" survives the customisation.

`tabby` (default) · `plain` · `tuxedo` · `siamese` · `patched`

Coat overrides apply first, mood overrides second — the eyes always win over a
marking.

---

## 8. Badges

A small animation beside the cat naming what it is doing. All sit in a fixed
`14pt` box.

| Badge | State | Motion |
|---|---|---|
| `zzz` | asleep | two z's drift up and fade, small one first |
| four squares | running | swell in turn clockwise, reading as rotation |
| `!` | needs you | pulse |
| star | finished | twinkle every `2.2s` |
| `✕` | failed | shudder, then rest |

The four squares exist because **a pixel grid cannot rotate cleanly** — but it can
take turns, which reads as rotation without anything actually rotating.

---

## 9. Motion

### 9.1 Pixel art, modern motion

The artwork is drawn on a grid. What moves it is not: easing curves and springs,
the same vocabulary as the rest of the interface.

| Property | Value |
|---|---|
| Width morph | spring, response `0.42`, damping `0.72` |
| Drawer height | spring, response `0.42`, damping `0.78` |
| Face crossfade | `190ms`, fade up 5pt with a 3pt blur |
| Hover reveal | `280ms`, `max-width` 0 → 150pt |

Width overshoots more than height, so the island reads as one body with mass
rather than a resizing box. Faces never slide in from outside; they fade in
*inside* a shape that is already the right size.

> **Corrected 2026-08-05, after Plan 6.3 Task 4 shipped.** The table's damping
> figures are stale and its "Hover reveal" row is one row where the prototype has
> three.
>
> **The damping numbers.** `0.72`/`0.78` were retuned to **`0.62`/`0.80`** by Plan
> 4.5, measured against `island-motion.html`'s own `--spring-w: cubic-bezier(.32,
> 1.5,.5,1)` and `--spring-h: cubic-bezier(.34,1.22,.5,1)`. At the old values width
> overshot 3.8% against height's 2.0% — a ratio of 1.9× where the prototype's beziers
> give 5.3× — so the numbers written here very nearly erased the rule stated
> underneath them. `IslandMotion` carries the measurement table.
>
> **"Hover reveal | 280ms" is the revealed text, not the island.** Three separate
> things move on hover and the prototype gives them three clocks on two curves:
>
> | what | prototype | duration | curve |
> |---|---|---|---|
> | the island's own width (and its recentring shift) | `.island`, lines 84–85 | `--t-shape` **440ms** | `--spring-w` |
> | the revealed text's `max-width` and `margin` | `.detail`, line 125 | `--t-hover` **280ms** | `--ease` |
> | the revealed text's `opacity` | `.detail`, line 125 | **160ms** | `--ease` |
>
> Only the middle row is the `280ms`/`max-width 0 → 150pt` written above. The other
> two were absent from this section, and the omission was read the way omissions here
> keep being read: one `.animation` modifier covered all three at `280ms`. **So the
> rule in the paragraph above this box was, on hover, not merely mismatched but
> absent** — the island's width had no overshoot at all, because `--ease` cannot
> exceed its target, while the click's width morph had been on the overshooting
> spring since Plan 6.3 Task 2. Measured: `--spring-w` peaks at **108.0%** of its
> travel at 230ms and our width spring at **108.4%** at 268ms; a `280ms` `--ease`
> peaks at exactly `100.0%`. On the `150pt` reveal that is `12.5pt` of travel past
> the hovered width and back, which is what "one body with mass" costs and what it
> buys.
>
> The trade is recorded rather than hidden: a spring accelerates where a bezier
> leaps, so the *front* of the hover now deviates from the prototype by 28.1% at 65ms
> against the single modifier's 14.7%. Matching the overshoot is what matching this
> section means — the same decision Plan 4.5 recorded for the click, for the same
> reason.

### 9.2 The aura is an event

Light blooms out of the island's silhouette in the new state's colour and leaves
nothing behind. `900ms`, peaking at 14%.

It is **not** a persistent status light: a glow that stayed lit would be a second
indicator competing with the cat. A glow that only fires on change is punctuation.

Implemented as `drop-shadow` on the island rather than a `box-shadow` on an
overlay, because drop-shadow traces the island's rendered alpha *including the
fillets* — a box-shadow only knows about the rectangle, so it cut the corners and
missed the notch edge. Tracing the shape also means it follows the panel down for
free when the drawer opens.

### 9.3 Reduced motion

Settings offers Full / Reduced / Off, and by default follows the system Reduce
Motion setting, which overrides the choice.

---

## 10. Answering

### 10.1 Single select

Choices run **top to bottom, one per row**, so a label like *"Allow all pnpm
commands in ~/dev/api for this session"* stays readable instead of being
truncated. Real permission prompts have labels this long.

The recommended answer is **tinted, not filled** — a wide block of solid colour
shouts. A number badge marks each row and the matching number key picks it.

`Other…` is the last row; clicking it collapses the list into a text field and
shrinks the drawer to match.

### 10.2 Multi select

Distinguished by **the control, not by a label**: a checkbox instead of a number
badge. A number badge means the click is the answer; a checkbox means it is not.

Multi-select questions grow a **Send** button and a running tally, and Send is
disabled at zero, so a half-made selection can never be committed by reflex.

### 10.3 Destructive answers

Anything matching `rm -rf`, `git push --force` or `drop table` asks twice. On by
default.

---

## 11. Session list

Three lines per row, most urgent information first.

```
✳  api  ⑂ auth-hardening                       Needs you ●
   ▶ Asking to run rm -rf build/         iTerm2 · Opus 4.8 · high
   │ clean the build and rebuild from scratch
   ┌ Tasks   1 done, 1 in progress, 1 open
   │ ● Audit authentication flow
   │ ☐ Add regression coverage
   │ ☑ M̶a̶p̶ ̶s̶e̶s̶s̶i̶o̶n̶ ̶s̶t̶a̶t̶e̶
   ┌ Agents  2
   │ ● Explore (Search API endpoints)       8s · Sonnet 4.6 · High
   │   └ Grep: handleRequest
   │ ● Explore (Read config files)        Done · Sonnet 4.6 · High
```

| Line | Carries |
|---|---|
| 1 | Project, worktree, state |
| 2 | What the agent is doing right now · where and how it runs |
| 3 | The last thing **you** asked it — a reminder of intent |
| Tasks | The agent's own checklist, with a done/doing/open summary |
| Agents | Subagents with model and effort, and their current activity |

Every line is individually switchable in Settings. When **Subagents** is hidden
the block does not vanish — it collapses to `Agents · 2 running`, because
approvals and questions from a child agent still need to surface.

Sort order defaults to most urgent first.

---

### 11.1 Parking a question — added 2026-08-06 (Plan 9)

**Escape, or collapsing the notch, sets a question aside rather than giving up on
it.** Before this, Escape called `dismissQuestion()`, which lapses: the hook was
released, the CLI asked in its own terminal, and a question someone had merely
glanced away from was gone.

A parked question keeps its hook waiting and renders **inline beneath its own
session's row**, as one of §11's nested blocks — `island-motion.html:370`'s
`.rblock`, the same container `tasksHTML` and `agentsHTML` use. That placement is
the prototype's own intent rather than an invention: `:832`, inside `agentsHTML`,
reads *"hidden subagents collapse to a count — approvals and questions would
stay."* It was anticipated in the mockup's source and never rendered.

**The block draws before Tasks and Agents.** §4.2's reasoning is that a waiting
agent is idling on you right now, so a question must never be buried under a
list — and those two blocks are exactly that list. The mockup gives no ordering
because it never rendered a question, so this is a decision.

**Parking is a position, not a state.** The session stays `waiting` and stays
`#FFA63C`, the count still includes it, and the cat keeps its mood. §4.2's "the
session list is a view, not a state" is what forbids the island going calm because
the drawer happens to be showing something else now.

**One question per outstanding tool call, not one per session.** Parallel tool
calls each fire their own hook and subagents share the parent's `session_id`, so a
row can carry more than one block and a person answers them in any order. An
earlier draft keyed by session and silently fail-opened all but the newest.

**Answered in place.** There is no gesture that brings a parked question back to
the drawer's larger face; the choices are in the block. §10.3's destructive second
ask binds here too — `QuestionModel.tap(_:)` is one implementation shared by both
drawing sites precisely so it cannot be forgotten in one of them.

**Giving up is a control, not a keystroke.** `Dismiss` sits in the row's header
(`.rtop`, `:351`) and releases every answerable question for that session. §10.2's
rule is that the control carries the meaning; a second Escape press would be the
opposite of it. **The row's header is also the only jump target** — a deliberate
divergence from `:345`, where the prototype makes the whole `.row` clickable — so
that answering or dismissing can never also jump to a terminal.

**When the deadline runs out the row does not change.** Still amber, still `Needs
you`, still showing the command, because all of that remains true — the agent still
needs a person, just somewhere else. The *block* changes: choices and `Dismiss`
disappear, since the hook is gone and there is nothing here to answer or give up
on, and one line takes their place naming the terminal. The command stays, per
*never truncate away the thing being decided*: someone about to walk to a terminal
still needs to know what they are approving. It clears itself when the session
leaves `waiting`.

See §2.3's 2026-08-06 correction for what that deadline actually is, which is not
what its name suggests.

---

## 12. Sound

Synthesised with oscillators, not sampled. Nothing to ship but a few dozen lines,
and a "sound pack" becomes a handful of oscillator settings rather than a folder
of files.

| Cue | Notes | Voice | Length |
|---|---|---|---|
| Needs an answer | G5 → C6 → E6, held on C6 | pulse, detuned twin | ~0.66s |
| Needs an answer, multi | the figure doubled, resolving on E6 | pulse | ~0.74s |
| Finished | C5 E5 G5 C6 E6, held on G6 | pulse | ~0.81s |
| Failed | G4 E♭4 C4 B♭3, sagging at the end | sawtooth | ~0.91s |
| Meow | two syllables of pitch-bent triangle | triangle | ~0.63s |

Hard attack (`6ms`), exponential decay — the whole character of the era.
Respects Do Not Disturb. These are the defaults; the pack is switchable.

> **Corrected 2026-08-03, after Plan 6.2 shipped.** The table above is a lossy
> summary of the working synth this section was written from —
> `docs/superpowers/prototypes/island-motion.html:858-918` — and the
> implementation follows the prototype wherever the two disagree, per the
> standing rule that the prototype is the authority on how a thing looks and
> sounds. **Two things the table itself lost, and two more the implementation
> departs from on purpose** — the lead-in said "four things it lost" until
> 2026-08-03, which was wrong about its own list: only the first two below are
> losses in the table, the third is a deliberate divergence from
> `island-motion.html:957`, and the fourth is a scope note about `settings.html`:
>
> - **The Voice column omits the detuned twin on two cues.** It gives "Needs an
>   answer" a `pulse, detuned twin` and leaves "Needs an answer, multi" and
>   "Finished" as bare `pulse`, but the prototype passes `duty:8` to every note
>   of `askmulti` and `duty:6` to every note of `done` — both get the twin, at
>   8 and 6 cents respectively.
> - **The table cannot express per-note gain at all.** Against a `.07` default:
>   `done`'s held G6 is `.06`, all four notes of Failed are `.06`, and Meow is
>   `.09`.
> - **A cue fires when demand rises, never when it falls.** The prototype cues
>   on any change of its own presented state (`island-motion.html:957`), which
>   means answering one of two questions takes it `askmulti → ask` and sounds
>   the alert again — congratulating you for the thing you just did. Clicking
>   buttons in a browser hides that; a person being interrupted would not miss
>   it. VibeCat fires only when the waiting count rises, or when `waiting` or
>   `failed` is newly reached. `CueSelector` carries the same reasoning.
> - **Two of `settings.html`'s four packs, and one of its three per-cue
>   alternatives, have no defined sound anywhere.** Soft, System and Blip are
>   named in the Settings mockup and nothing in this repo says what they are —
>   no frequencies, no waveforms, nothing. They are deliberately not
>   implemented; inventing them would be inventing design. Only Chiptune and
>   Silent exist, and `SoundPack` is an enum so a later one is additive. Meow
>   *is* defined, is implemented, and has no trigger — it exists for the
>   per-cue picker Plan 6.4 owns.
>
> Two further deliberate divergences, added after this block was first written and
> recorded here so the list is the whole list:
>
> - **A note shorter than the 6ms attack has its attack shortened to half its
>   duration** (`ToneEnvelope.swift`). The prototype has no clamp and Web Audio
>   simply stops the oscillator mid-ramp, leaving the note at a non-zero amplitude
>   — the same click the `0.0001` release floor exists to prevent. No cue in the
>   chiptune pack is close to this short; it exists so a later pack cannot produce
>   a click by accident.
> - **Cues play serially, and one more than a second behind is dropped rather
>   than queued** (`SoundPlayer.maximumBacklog`). The prototype builds fresh
>   oscillators per call and mixes overlapping cues;
>   `AVAudioPlayerNode.scheduleBuffer` queues them. Serial is kept — mixing needs a
>   player node per voice and two alerts summed at full gain are louder than
>   either — but an unbounded queue would put the Nth alert of a burst
>   0.6…0.9s × (N−1) after the event it announces, which is noise rather than
>   information.
>
> **Still unheard.** Nothing in §12 has been listened to: whether each cue matches
> the prototype's own sound buttons, whether a note's release clicks, and whether
> `done`'s held G6 carries inharmonic hash all remain open. One thing a person
> doing that comparison needs to know: the prototype connects every oscillator
> straight to `ac.destination` with no master gain, while VibeCat multiplies by
> `settings.volume`, which defaults to `0.60`. **Compare at `volume: 1.0`**, or
> VibeCat will simply sound 4.4dB quieter and the difference will be the setting
> rather than the synthesis.

---

## 13. Jump

Clicking a session focuses where it lives.

| Origin | Precision |
|---|---|
| iTerm2 | window · tab · split |
| Terminal | window · tab |
| VS Code | app, or exact tab with the extension installed |
| Claude, ChatGPT, other apps | app, by bundle identifier |

Origin is captured by the hook from its own environment — `TERM_PROGRAM`,
`TERM_SESSION_ID`, `__CFBundleIdentifier`, `VSCODE_PID`, `PWD`, `PPID`. **No event
is ever read from a GUI app**; events always arrive by hook, and the GUI is only
ever a jump target.

Requires the macOS **Automation** permission; Settings shows its status and links
to System Settings.

---

## 14. Settings

Four sections, macOS-native layout.

**General** — Launch at login · Expand notch on hover (+ hover duration, `0.30s`)
· Smart suppression · Hide in fullscreen · Auto-hide with no sessions ·
Auto-collapse on mouse leave · Auto reveal dwell · Dismiss on outside click ·
Idle session cleanup · Disable click-to-jump · Number keys · Confirm destructive

**Integrations** — CLI hooks with per-source enable and install status · Add CLI
branch · Auto-configure new CLIs · Reply channel, hook timeout, fail-open · IDE
extensions · Custom jump rules · Socket · Event log

> **Corrected 2026-08-06 (Plan 9).** Two things in that Integrations line, and one
> line of the prototype's copy.
>
> **`fail-open` is not a control and the row is not built.** The prototype draws it
> at `settings.html:293-295` as a switch captioned *"A crashed island must never be
> able to hang your terminal. Turning this off is not recommended."* The first
> sentence is right; the second has nothing to recommend against. Measured, fail
> open means the hook prints **nothing** — `HookRunner.run` returns nil on every
> failure path — so the CLI prompts in its own terminal exactly as it did before
> VibeCat existed. Nothing is auto-approved. The case for wanting the switch off is
> *"VibeCat is my gate on dangerous commands; if it crashes I don't want `rm -rf`
> waved through"*, which would hold if fail open answered `allow`. It does not
> answer at all. So off protects nothing and the only thing it can accomplish is
> hanging a terminal. **The owner ruled the row removed entirely**, so this group
> has two rows where the prototype has three.
>
> **`hook timeout` is the *answer* deadline, not delivery, and the prototype puts
> one deadline's number under the other's caption.** The field holds `300` with a
> `ms` suffix (`:290-292`) — delivery's number — while its caption describes how
> long the hook waits for a *person*. The field is
> `Preferences.handBackToTerminalAfter`, in **minutes**, default 1, with `Never`
> available. Delivery stays a fixed `300ms` and is not settable.
>
> **And that caption is false.** *"How long the hook waits before letting the agent
> carry on without you"* — the agent does not carry on without you; measured, the
> CLI asks you itself. The row reads **"How long the notch holds the question
> before the terminal asks you instead."** See §2.3's correction of the same date
> for the measurements.

**Notifications** — Which events alert · Sound pack and per-event cues · Volume ·
Do Not Disturb · System notification fallback · Permissions

**Display** — Notch preview, Clean/Detailed, display picker · Right-of-notch
content · Cat, coat, state colours · Panel size · Session card switches with a
live preview · Notch tuning offsets · Motion

---

## 15. Permissions and distribution

Not sandboxed — it must drive terminals, open a Unix socket, and edit CLI config
files. **Developer ID + notarisation**, not the App Store.

`LSUIElement = true` (no Dock icon). Login item via `SMAppService`.
Permissions requested: **Automation**, **Notifications**, **Screen Recording**
(used by `BackdropSampler` to measure what is actually behind the island, so
the aura's light/dark tint matches the real backdrop rather than guessing from
the system appearance alone — see §9.2).

> **Corrected 2026-08-03, after Plan 6.2 shipped.** This list is one short.
> §12's "Respects Do Not Disturb" is **a fourth permission**: macOS 14's only
> supported way to read Focus is `INFocusStatusCenter` (`Intents`), which needs
> `NSFocusStatusUsageDescription` in `Info.plist` and its own TCC
> authorization. Reading `~/Library/DoNotDisturb/DB/Assertions.json` is the
> widely-copied alternative, is unsupported, has changed shape between
> releases, and — measured on this machine — is not even readable: `cat` on it
> returns `Operation not permitted` without Full Disk Access. So the list is
> **Automation**, **Notifications**, **Screen Recording**, **Focus**.
>
> What was actually observed from a signed `VibeCat.app` (identifier
> `com.gcat332.vibecat`, Apple Development identity, `NSFocusStatusUsageDescription`
> confirmed present with `plutil -p`), rather than what was expected: on the
> first launch `authorizationStatus` read `0` (`.notDetermined`) before
> `requestAuthorization`, immediately after it returned, and still three seconds
> later — the callback is asynchronous and nothing in the unified log named the
> request. On a launch a few minutes later it read `3` (`.authorized`), so a
> prompt was presented and allowed at some point in between. **Whether a prompt
> was drawn on screen, and who dismissed it, was not observed** — the app is an
> `LSUIElement` accessory that never activates, and no window-level check was
> available.
>
> When authorization is `.notDetermined` or `.denied`, VibeCat **plays sound**.
> A user who enabled sound and never answered a fourth permission prompt should
> hear their agents; silently swallowing every cue is the worse failure. §14's
> Notifications section already carries a Permissions row, which is where the
> state belongs; Plan 6.4 wires it. The `.authorized`-and-Focus-on path — that
> `focusStatus.isFocused` actually reads `true` during a Focus session — is
> **still unverified**: with authorization granted, `isQuiet` read `false` while
> Do Not Disturb was off, which is consistent but proves only the negative half.

---

## 16. Error handling

| Failure | Behaviour |
|---|---|
| Socket missing or app not running | Hook times out fast and fails open |
| Reply slower than the deadline | CLI carries on with its default |
| AppleScript blocked | Show a hint linking to the Automation setting |
| Display change / notch resize | Recompute geometry from the API |
| No notch on this display | Fall back to a floating pill |

---

## 17. Project structure

```
VibeCat/
├─ Package.swift
├─ Sources/VibeCatCore/     VibeEvent, wire codec, SourceAdapter,
│                           SessionStore, state priority, sprite tables
├─ Sources/VibeCatHook/     the hook binary (universal, darwin/linux/freebsd)
├─ App/VibeCat.xcodeproj    NotchController, SwiftUI views, Activator, Injector
└─ Tests/VibeCatCoreTests/
```

Swift 6, SwiftUI with AppKit interop, **no external dependencies**.

### Testing

- **Unit** (Core, no UI or socket): event parsing per source → shared `kind`;
  wire encode/decode; `SessionStore` transitions; the state-priority rule;
  de-duplication; notch geometry maths including the centring shift.
- **Integration**: a mock hook client against the real `SocketServer`, checking
  the reply round-trip and the fail-open deadline.
- **Manual**: a script that replays a recorded Claude Code `PreToolUse` payload.

---

## 18. Scope

### v1

Socket and hook with Claude Code fully wired (idle / running / done / permission
/ question / failed) · notch UI with the three disclosure tiers · cat with five
moods and five coats · badges · aura · single and multi select answering through
the hook · session list with tasks and subagents · jump to terminal and app ·
chiptune cues · all four Settings sections · generic adapter and custom sources.

### Later

Codex / Copilot / Gemini presets fully wired · terminal injection fallback for
prompts that never reach a hook · JetBrains extension · multi-display sync ·
history and statistics · additional sound packs and coats.

---

## 19. Open questions

1. **Notch width across models.** The manual offset covers reporting bugs, but we
   should collect real `safeAreaInsets` values from a few machines before
   settling the default.
2. **Codex and Gemini hook contracts.** Presets are designed but the exact event
   payloads need verifying against current releases before wiring them.
3. **VS Code extension scope.** Jumping to an exact terminal tab needs the
   extension; worth confirming the API still allows it.
4. **Idle detection.** "Stalls for 5 minutes" needs a definition that does not
   fire on an agent legitimately thinking for a long time.
