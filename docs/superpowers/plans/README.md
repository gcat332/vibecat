# Which plan owns what

The plan boundaries were drawn in Plan 2 and have held since. This file exists
because the answer to "what is left" had to be re-derived from the spec and the
plan files twice; it is cheaper to keep it written down.

| Plan | Owns | Design | State |
|---|---|---|---|
| 1 | Socket, wire protocol, hook, Claude Code adapter, session store, the worst-state-wins rule | §2, §4 | done |
| 2 | Notch geometry, the panel, the collapsed island, hover, the aura | §5, §6.1–6.2, §9.2 | done |
| 3 | The cat, its moods and coats, badges, motion | §7, §8, §9.1, §9.3's rule | done |
| **4** | The drawer and answering — single and multi select, `Other…`, the destructive second ask, the reply round-trip | §6.3, §10 | **in progress** |
| 5 | The session list — three lines a row, tasks, subagents, urgency order | §11 | not written |
| 6 | Sound, jump to terminal, all four Settings sections, the Full/Reduced/Off control | §12, §13, §14, §9.3's UI | not written |

## Owned by no plan

Both are real gaps rather than deferrals — nothing in Plans 1–6 claims them.

### A. Generic adapter and custom sources (§3)

§18 lists "generic adapter and custom sources" in **v1**, and
`Sources/VibeCatCore/Adapters/` contains one file: `ClaudeCodeAdapter.swift`.
`SourceAdapter` and its registry exist and were built to take more (the registry
already resolves duplicate ids in favour of the later adapter, precisely so a
user's custom source can shadow a built-in), so this is filling a designed hole
rather than opening one. Codex/Copilot/Gemini presets are explicitly **Later**;
the generic adapter is not.

### B. Optimisation, all of it measured, none of it planned

Every item below was found and quantified during Plans 2 and 3 and recorded in
[the cat-and-motion follow-ups](2026-08-01-cat-and-motion-followups.md). None
has an owner:

- **Every animation over-samples its own artwork by 3–6×.** `squares` has 4
  distinct frames and draws 12 per cycle; `bang` has 2 and draws 13; `trot` has
  3 and draws 12. Frame rate is the *entire* CPU cost — the animation spike
  measured 8fps at ~6% of a core against 120fps at ~15–18%, with path batching
  making no measurable difference — so matching rate to distinct frames would
  cut cost proportionally with **zero visual change**.
  `MotionPreference.floorFPS = 8` blocks it, and its stated justification
  ("below this the steps read as stutter") is an uncited assertion that is
  plainly wrong for a 2-frame sprite.
- **`render()` writes `model.state`, `sessionCount` and `aura` unconditionally.**
  `@Observable` notifies on the write, not on a change, so every hook event
  invalidates the body two or three times even when nothing differs. Harmless at
  Plan 3's rates; Plan 5's session list raises those rates.
- **`CatPalette` rebuilds five `RGBA(hex:)!` values on every subscript access**
  while `ground` and `white` are cached. 210 cells a frame.
- **`IslandBody.phase` and `.badgePhase` are near-identical**; a shared helper
  taking a cycle removes the duplication.
- **`NotchController.tier` is write-only bookkeeping** — it becomes
  `model.hovering` immediately, `IslandTier.hover` has `extraHeight == 0`, and
  `frames(tier:)` is only ever called with `.rest` in production. Plan 4 changes
  the last of those, which may make this worth keeping instead.

The honest framing: none of this is urgent, because the idle island already
measures 0.35% of a core and only animates when an agent is working. It is worth
a plan because the *reason* it is cheap today is that three of five moods have no
timeline at all, and Plan 5 puts several sprites on screen at once.

## Not a plan, but not done either

- **No licence has been chosen.** The README says so. Local `main` is
  deliberately unpushed — pushing publishes, and that decision should come
  first.
- **§15 needs amending.** It lists Automation and Notifications; the app now
  also uses **screen recording**, for `BackdropSampler`. The permission is
  optional and the feature degrades without it, but the section should say so.
