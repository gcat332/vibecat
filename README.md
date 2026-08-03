# VibeCat

A macOS notch app that tells you what your AI coding agents are doing — and lets
you answer them without leaving what you are looking at.

When you run several agents at once, the cost is not that any one of them is
slow. It is that you cannot tell **which one is blocked on you** without cycling
through terminal windows. An agent that asked a question five minutes ago has
been idle for five minutes.

A pixel cat sleeps in your notch. It trots while an agent works, sits up with a
`!` when one needs an answer, and takes X eyes when a run fails.

## Status

**Answering works, end to end, verified on hardware.** A real `rm -rf build/`
permission event travels through the hook and the socket, the island shows it,
clicking opens a drawer below the notch, two taps answer it — two, because a
destructive command asks twice — and claude-code acts on the reply. The
terminal never loses focus and never hangs: if nobody answers, the hook times
out and the CLI prompts for itself.

Done: the event pipeline and hook, the notch geometry and panel, the cat with
five moods and five coats, the badges, the aura, and the drawer. **373 tests.**

Still to come: the session list, sound, jump-to-terminal, settings, and a
generic adapter for CLIs other than Claude Code. See the
[handoff](docs/superpowers/HANDOFF.md) for what to pick up first and
[the plan map](docs/superpowers/plans/README.md) for who owns what.

## Contents

| | |
|---|---|
| [Handoff](docs/superpowers/HANDOFF.md) | Where the project is, what to do next, and what a newcomer would otherwise rediscover |
| [Design doc](docs/superpowers/specs/2026-07-31-vibecat-design.md) | Architecture, geometry, sprite spec, settings schema — with the reasoning behind each decision |
| [Island prototype](docs/superpowers/prototypes/island-motion.html) | Every state, mood, coat and Display option, live. Open in a browser |
| [Settings prototype](docs/superpowers/prototypes/settings.html) | All four settings sections, every control interactive |
| [Notch shell spike](docs/superpowers/spikes/2026-08-01-notch-shell-spike.md) | Window level, notch geometry and hit-testing, measured on real hardware rather than assumed |
| [Animation spike](docs/superpowers/spikes/2026-08-01-animation-spike.md) | What motion costs: frame rates, CPU, and which architecture to animate with |

Both prototypes are single self-contained HTML files — no build, no network.

## The short version

- **Hooks, not polling.** Each CLI runs a small binary on its own events. The
  binary talks to the app over a Unix socket and can block waiting for your
  answer, so replying from the notch is exact rather than simulated keystrokes.
- **A crashed app must never hang your terminal.** The hook fails open on a
  300 ms deadline.
- **Colour means state, and only state.** Green idle, blue running, amber needs
  you, red failed. Which agent is speaking is carried by its icon shape.
- **The notch is a hole.** The black shape may span the cutout because the cutout
  is black too. Content may not — everything sits in the flanks beside it.
- **The worst state wins.** `needs you > failed > running > idle`, because a
  waiting agent is idling on you right now while a failed one has already
  stopped.

## Running it

```bash
swift build          # builds VibeCatCore, VibeCatTransport, VibeCatUI, vibecat-hook and vibecat
swift test           # the whole pipeline, headless
```

Run the app itself:

```bash
VIBECAT_SOCKET=/tmp/vibecat-dev.sock swift run vibecat
```

That is enough for everything except permissions. A bare executable has no
bundle identifier, so macOS attributes anything it asks for to the terminal
that launched it — and a grant obtained that way disappears the moment the app
is opened any other way. For that, build the bundle:

```bash
Scripts/build-app.sh && open .build/VibeCat.app
```

`open`, not the binary inside it: launching it from a shell makes the shell the
responsible process again, which is the thing the bundle exists to avoid. The
script signs with the first Apple Development or Developer ID certificate it
finds, because TCC remembers a grant against the code's designated
requirement — ad-hoc signing puts the binary's hash there, so every rebuild
becomes a new program that has to ask again.

The island appears in the notch, dormant until an event arrives. In a second
terminal, replay a hook payload by hand:

```bash
VIBECAT_SOCKET=/tmp/vibecat-dev.sock Scripts/replay.sh permission
```

With nothing listening the hook prints nothing and exits `0` — that is the
fail-open path, and it is the behaviour to preserve above all others.

## Planned stack

Swift 6, SwiftUI with AppKit interop, no external dependencies. Developer ID and
notarisation rather than the App Store — it needs to drive terminals, open a
socket, and edit CLI config files.

## Licence

Not yet chosen.
