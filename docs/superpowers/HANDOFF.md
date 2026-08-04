# Handoff — 2026-08-03 (end of Plan 5)

Where VibeCat is, what to decide next, and the things a newcomer would otherwise
have to rediscover the hard way.

> Supersedes the earlier 2026-08-03 handoff, which was written mid-session and had
> gone materially stale: it reported 373 tests and 168 commits, said "Plans 1–4
> done", listed five already-finished items under "do these first", and told a
> reader `ImageRenderer` was trustworthy. That last one is now known to be false —
> see below.

## State

`main`, clean, **419 tests**, **pushed and current with `origin/main`**, **MIT
licensed** (`LICENSE` in the root). **Plans 1–5 done**, including Plan 4.5.

That push, on 2026-08-03, was the first in the project's life — 214 commits. The
licence was the one thing gating it.

```bash
Scripts/test.sh                              # 647, ~21s (serial — see CLAUDE.md)
Scripts/build-app.sh && open .build/VibeCat.app
```

`open`, not the binary inside the bundle — launching it from a shell makes the
shell the responsible process and the app loses its own permission identity.

## What works, verified on hardware rather than argued

From a signed bundle, with real hook events through the real socket:

- The island sits in the notch, click-through, and answers a real `rm -rf build/`
  permission event end to end — pick, then confirm, because §10.3's second ask
  fires for real, and the hook prints claude-code's own `permissionDecision`.
- **Focus is never stolen**, and the panel takes keyboard input **exclusively**:
  verified with a TextEdit witness plus a control run, not just `isKeyWindow`.
  [The key-input spike](spikes/2026-08-03-notch-panel-key-input.md).
- §11's session list renders and opens, and there is a committed visual fixture for
  it (`VIBECAT_LIST_SHOT=…`) — the first one, because `ImageRenderer` cannot render
  a `ScrollView` at all.

Fail-open was enumerated across all ten ways a question can end. Every one reaches
`nil`, so a crashed or silent island can never hang a terminal.

## One decision waiting on the owner

It started as two. The mains re-run on 2026-08-03 closed the first and narrowed the
second, so what is left is a single question — and it is a call only you can make, not
a bug to fix.

**The accepted ~12% resting cost survives.** Measured on mains, Low Power Mode off:
dormant reads 13.14% against the 12.26% recorded and accepted, inside the ±1.5pp noise
floor. **Plan 5 did not raise the island's resting cost**, which is what the acceptance
was about. That half is settled.

**What is new: having a session list open costs ~27% of a core** — +11.04pp over
`running`, about 2.1× resting, with `draws/s` unchanged (47.9 → 48.3) so it is not
extra badge redraws. The acceptance decision did not have this figure.

**The open question is whether that cost is per-row or fixed.** Twelve sessions cost
+11.04pp. If it were linear that is ~0.9pp per visible session, making a typical
three-session list ~+2.8pp and a non-issue — and the right response differs sharply
between the two answers. **One data point cannot establish linearity.** One more probe
row at a smaller session count settles it, in about two minutes.

Once it is settled, the options on the table are: accept and record (as was done for
the badge transform); move the drawer's content out of whatever subtree recomposites
while an animation is live (the recorded hypothesis, still unconfirmed); gate motion on
`MotionPreference` so the cost becomes the user's choice — which would also close §9.3's
three bypasses; or reduce what a row draws by default.

[The spike](spikes/2026-08-03-badge-transform-cost.md) has both runs, the noise floor,
and what the battery/mains comparison established about Low Power Mode's distortion.

## Then the plans

[plans/README.md](superpowers/plans/README.md) is the map, and it now also carries
**Plan 5's carried findings** — eleven items its final review deliberately did not
close, each with a ruling. Read that section before starting Plan 6; two of its
entries are things to fix *before* the next plan rather than during it.

Order: **Plan 6** (sound, jump, all four Settings sections, and everything that was
gated on keyboard input — now unblocked) → **Plan 7** (generic adapter and custom
sources) → **Plan 8** (matching motion cost to motion content, which Plan 5's
measurement reframes again).

## Five things that would otherwise be rediscovered

**`ImageRenderer` returns a reused backing store, and a view that draws nothing
does not clear it.** This is the big one. A blank render read `[0, 474, 474, …]`
across twelve consecutive calls — deterministic, single-threaded, under `--filter`.
It surfaced as an intermittent full-suite failure and was first misdiagnosed twice:
as "another test's pixels leaking under concurrency" (it is not a race — there is
nothing to serialise) and as escaping-inout UB in our own buffer (a correctly
allocated, longer-lived buffer read the same wrong value). `rasterise` now draws
into a context we allocate and zero ourselves. **And `--filter` is not a
trustworthy mode — it is only a quieter one.** Any new golden test must prove itself
over repeated *full-suite* runs.

**`ImageRenderer` also cannot render a `ScrollView`** — measured, a bare `Text`
gives 165 opaque pixels and the identical `Text` inside a `ScrollView` gives 0. Use
the `NSHostingView` + `cacheDisplay(in:to:)` path in `Raster.swift` for anything
that scrolls. That is what finally let anyone see §11's list, and it immediately
found a real §11 violation no test could see.

**`@Observable` gates assignment but not mutation.** A plain assignment goes through
the generated `set`, which **is** equality-gated for an `Equatable` property — so
`model.aura = model.aura` notifies nothing. A **mutating call** goes through
`_modify`, which notifies **unconditionally**. That distinction was a real bug:
the bloom-end nudge was an equal write, so it ended no bloom, so a still mood kept a
live 8fps timeline forever — about 3.3% of a core, permanently, in the state §6.1
says must look idle. Do not "simplify" `model.aura.endBloom()` back into an
assignment.

**This project's tests agree with its code unless forced not to.** Over twenty tests
that would have passed against a broken implementation were found in Plan 4 alone,
and Plan 5 replaced two more that could not fail at all — one of which *asserted the
bug it was written to prevent*. Mutate anything you claim. If a test does not fail
against the specific breakage it names, it is decoration.

**A measurement can be honest and still price the wrong mechanism.** This has now
happened four times on this project: `ps %cpu` against `getrusage`; a badge
animation figure that priced a `TimelineView` rather than the transform the design
asks for; a hover-monitor row that still contained the animation it was meant to
exclude; and the `ImageRenderer` misdiagnoses above. Ask what mechanism a number
covers before designing around it — especially when the implementation came first.

## Still open, and known

- **The cat's motion is the badge decision one layer down.** `call` scales 1.09,
  `happy` pops and `dead` rotates ±4° in the prototype; ours translate instead,
  because measured, a translate leaves the sprite at 9 distinct colours at any
  offset while `scale(1.09)` takes it to 95 at 1× and 130 at 2×. Recorded as a
  deliberate divergence, not a gap.
- **§6.2's right flank is still not configurable** and §16's AppleScript hint cannot
  exist before jump does. Both Plan 6.
- **`lastUserMessage` renders but no adapter populates it** — §11's line 3 will
  always be absent until an adapter carries the user's own prompt, which needs
  checking against a real payload first.
