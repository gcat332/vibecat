# The Drawer and Answering — carried follow-ups

Triaged by the whole-branch review at the end of Plan 4. Everything here was
found, judged, and deliberately deferred. The execution ledger it came from is
gone; this is the surviving record.

The branch merged with **no Critical findings**, 369 tests, and fail-open
verified across all ten ways a question can end.

## Verified on real hardware

Worth stating plainly, because three plans shipped before anyone saw this app
run. On 2026-08-02, from a signed `.app` bundle, with a real `PreToolUse`
permission event carrying `rm -rf build/` through the real hook and socket:

- A question **does not** open the drawer by itself — the panel stayed at
  `y 0..56`.
- Clicking the island opened it — the panel grew to `y 0..344`, which is
  notch 32 + question face 288 + `auraMargin` 24, exactly.
- **Focus was never stolen.** Finder was activated first so the reading was not
  confounded, and stayed frontmost through the island click, the row click and
  the confirming tap.
- The round trip completed: two taps — pick, then confirm, because §10.3's
  second ask fired for real — and the hook printed claude-code's own
  `permissionDecision`.

An earlier attempt at the focus measurement was **void** because VibeCat was
already frontmost. The lesson is now encoded in `KeyDownProbe`, which aborts
rather than reporting when `frontmostApplication` is `loginwindow`.

## Fix these first

**The footer fix hides safety-relevant information.** `QuestionFace`'s body
`Text` gained `.lineLimit(1)` to stop the §10.3 confirmation banner clipping.
SwiftUI's default truncation is `.tail`, so a long command renders as
`rm -rf /Users/dev/projects/vibe…` — **the destination is the part that
disappears**, while the person is being asked to authorise it. The short common
case is unaffected and the guard still gates the answer, so this is not a hole;
it is a one-line fix (`.truncationMode(.middle)` keeps the tail inside one
line) and it should be the first thing done.

**The hover sliver is not cosmetic.** `IslandBody`'s silhouette is one shape
spanning the whole body height including the drawer's, still drawn at the
hover-coupled width, while the drawer itself is now hover-independent. Rendered
and pixel-probed: a 150pt-wide, fully opaque, ground-coloured rectangle
covering about 92% of the drawer's height, appearing and disappearing with
hover beside the content the person is reading. Fixing it means changing
`IslandBody`'s hover-reveal mechanism, which is why it was deferred.

**One compiler warning.** `QuestionFaceTests.swift`'s
`theConfirmationBannerNamesTheControlThatActuallyConfirms` is the only test in
its file without `@MainActor` and calls a main-actor-isolated static. One line.

## Deliberate deviations, so nobody rediscovers them as bugs

| Decision | Spec | Why |
|---|---|---|
| `wantsReply` events get their own deadline (20s), not §2.3's flat 300ms | §2.3 | 300ms bounds *delivery*; it cannot bound a human answer. Without the island the CLI blocks on its own prompt indefinitely, so a bounded wait is a ceiling that did not previously exist. §2.3 has been amended to describe the split. |
| `Other…` is not rendered | §10.1 | It was inert, could not be backed out of, read as broken beside three rows that respond, and cost exactly the 44pt the confirmation banner needed. Restore it when Plan 6 brings keyboard input. |
| `Other…` carries no number badge | §10.1 vs §10.2 | §10.2 says a number badge means the click *is* the answer, which `Other…`'s is not — and `KeyRouting` indexes `QuestionModel.rows`, which excludes the synthetic row, so a numeral would have promised a dead keystroke. |
| Screen recording is used | §15 | `BackdropSampler` reads what is actually behind the island. Optional; the aura falls back to `colorScheme` without it. §15 has been amended. |

## Not done, and not defects

- **Number keys are routed but wired to nothing.** `KeyRouting.pick` is a pure,
  well-probed function reachable from no production code. It waits on the one
  genuine unknown this plan did not resolve: whether a `.nonactivatingPanel` at
  `.statusBar` can receive **key** events without stealing focus. *Mouse* input
  was measured and does not. Run `KeyDownProbe` on an unlocked machine to
  settle it — it prints the frontmost application before and after, and aborts
  rather than guessing.
- **`Escape` is the only user-initiated dismiss**, alongside `click()` now
  toggling. If the probe says the panel cannot take keys, Escape does not work
  either and the toggle is the only way out.
- The multi-select path is unreachable: no adapter sets `multi`.
- `PendingQuestion.hasLapsed` is unused. `AppModel` owns `pending` but only
  `NotchController` expires it — benign with one window.
- Task 6's guard misses `rm build/ -rf` (flags after the path) and a
  `git push` split across a shell line continuation. Both documented in the
  guard; agent-generated bash puts flags first.
- `QuestionModel.pick`/`toggle`'s mode guards are each exercised in one
  direction only. Latent until something calls them from a keystroke.

## What this plan taught, beyond the feature

**Twenty-odd tests that would have passed against broken code were found across
nine tasks** — the largest single category of defect by far, and the same
pattern recorded after Plan 3. Several were found by implementers rather than
reviewers, and three are worth remembering for how they were caught:

- A reviewer suggested a stronger assertion; the implementer *tried it and ran
  the mutation anyway*, and found the suggested assertion was itself a tautology
  of the code's own construction. Test the fix, do not transcribe it.
- Task 6's regex was verified against a regex engine and looked right. Both of
  its real bugs — bundled `-uf` flags, and `-foo` parsing as `-f` plus `-o` —
  were only found by running **real git**. Testing a tool against a model of the
  tool proves the model.
- A probe that reported "wiring correct, nothing broken" was wrong; the drawer
  was visibly misaligned. It had measured a configuration where the error
  cancelled. **A probe that finds nothing is not the same as no defect.**
