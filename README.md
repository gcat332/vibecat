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

Headless event pipeline implemented and tested — the hook binary, the socket
transport, the session store and the Claude Code adapter. No UI yet.

## Contents

| | |
|---|---|
| [Design doc](docs/superpowers/specs/2026-07-31-vibecat-design.md) | Architecture, geometry, sprite spec, settings schema — with the reasoning behind each decision |
| [Island prototype](docs/superpowers/prototypes/island-motion.html) | Every state, mood, coat and Display option, live. Open in a browser |
| [Settings prototype](docs/superpowers/prototypes/settings.html) | All four settings sections, every control interactive |
| [Notch shell spike](docs/superpowers/spikes/2026-08-01-notch-shell-spike.md) | Window level, notch geometry and hit-testing, measured on real hardware rather than assumed |

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
swift build          # builds VibeCatCore, VibeCatTransport and vibecat-hook
swift test           # the whole pipeline, headless
```

Replay a hook payload by hand:

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
