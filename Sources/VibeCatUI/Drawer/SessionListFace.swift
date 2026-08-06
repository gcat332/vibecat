import SwiftUI
import VibeCatCore

/// §11's list. Face-level only: the ordering is `SessionStore.mostUrgentFirst`'s
/// and the row is `SessionRow`'s, so this file owns nothing but the scroll, the
/// clock and the rows' outer inset.
/// F10 of Plan 5's final whole-branch review removed two parameters from here,
/// and the two removals are not the same kind of thing:
///
/// - `now:` was **genuinely dead** — threaded down to `SessionRow` and never
///   read by anything, because no line of §11 is a duration.
/// - `options:` was read and forwarded, but **nothing anywhere ever passed it**,
///   test or production, so no render ever exercised a value other than `.all`.
///   `SessionRow.Options` itself stays: it is §11's "every line is individually
///   switchable in Settings" switch point, and `sessionRowForwardsItsOptionsTo
///   SessionBlocks` pins its forwarding by mutation one level down. Plan 6 has
///   to re-thread one parameter through here when it wires Settings up; that is
///   a deliberate one-line cost, recorded in plans/README.md, rather than a
///   parameter kept alive on the strength of a caller that does not exist.
///
/// **Re-threaded, Plan 6.6's Task 4.** `DrawerView` now forwards its own
/// `options` here, which `IslandView` sets from `IslandModel.cardOptions` —
/// itself read at launch from `Preferences.cardOptions` via
/// `SessionRow.Options.init(_:)`. `aStoredCardOptionsReachesARenderedRow`
/// (`LaunchWiringTests`) drives that whole path end to end and checks a
/// rendered pixel, not just that the property changed.
struct SessionListFace: View {
    /// Plan 9's parked and handed-back questions, keyed the way `IslandModel` publishes
    /// them. Defaulted so `HookLoopProbe` and every golden keeps compiling and rendering
    /// unchanged.
    /// Ruling B's `Dismiss` used to be a second closure parameter forwarded to
    /// every `SessionRow` alongside `onAnswer`. Review round 2 removed it — each
    /// `IslandModel.RowQuestion` in this dictionary already carries its own
    /// `onDismiss`, so `SessionRow` reads it straight off `questions` rather than
    /// needing a row-level parameter this face would have to keep forwarding.
    var questions: [SessionKey: [IslandModel.RowQuestion]] = [:]
    var onAnswer: (Reply) -> Void = { _ in }

    let sessions: [Session]
    /// Forwarded straight to every `SessionRow`. Defaulted to `.all` so the
    /// existing call sites in this file's own tests, none of which cares about
    /// a non-default switch set, keep compiling unchanged.
    var options: SessionRow.Options = .all

    /// A running row's state field is an elapsed time, not a word (the mockup's
    /// `SESSIONS` gives one `state:'2m 14s'`), so the list needs a clock.
    ///
    /// **A real branch, not a paused timeline** — the same shape, and the same
    /// measurement, as `IslandView.body`: a paused-but-present `TimelineView`
    /// still costs ~6% of a core, and removing it costs 0.0%. With nothing
    /// running there is no duration on screen to advance, so there is nothing
    /// for a timeline to do and it is not created. This also satisfies the
    /// condition the removal of `SessionRow.now` was recorded under: "a `now`
    /// that never advances is worse than no `now` at all."
    ///
    /// Not gated on `MotionPreference`: a clock ticking is information, not
    /// motion, and §7's reduce-motion rule is about movement.
    private var needsClock: Bool { sessions.contains { $0.state == .running } }

    /// One second. `RevealContent.elapsed` only resolves finer than a minute
    /// below the first minute, so this is as fast as any visible digit changes.
    private static let clockInterval: Double = 1

    /// **How deep the bottom fade runs — the overflow cue, Plan 6.3 Task 6.**
    ///
    /// ## What was wrong
    ///
    /// §6.3's "420pt, rows scroll" is right and the prototype agrees exactly
    /// (`island-motion.html:168`, `.rows{overflow-y:auto;max-height:100%}`). But
    /// twelve sessions measure **625pt of content in the 376pt** left after §6.4's
    /// footer, and the fold lands **10pt into row 8** — 2pt into that row's first
    /// text line, which is a horizontally sheared glyph. That reads as a rendering
    /// bug, not as "there is more below".
    ///
    /// ## Why a fade, and not the row snapping the register preferred
    ///
    /// The register's three options were a bottom fade, an explicit "+N more", and
    /// row-granular snapping, and it recorded snapping as "the only one that
    /// removes the sheared glyph rather than decorating it". **That is not true for
    /// this list, and the reason is worth keeping.** Snapping (`.scrollTarget
    /// Behavior(.viewAligned)`) aligns a row boundary with *one* edge of the
    /// viewport. The viewport is a fixed 376pt and the rows are **not uniform** —
    /// `SessionRow` grows by whatever `SessionBlocks` a session has (tasks,
    /// subagents, a last message), which is why the prototype's own four fixtures
    /// measure 235.5 / 134.5 / 63 / 63pt. So for any scroll offset at most one of
    /// the two folds can sit on a boundary: align the top and the bottom shears,
    /// align the bottom and the top does. Snapping moves the sheared glyph from one
    /// end to the other; it does not remove it. (The prototype's own list looks
    /// clean only by coincidence — measured in a browser, its rows end at exactly
    /// 374px, which is its viewport to the pixel.)
    ///
    /// A fade removes the *shear* proper: the cut stops being a hard horizontal
    /// edge through a letterform and becomes a dissolve. It is also the only one of
    /// the three that needs no measurement of the content, which matters more than
    /// it sounds: **a mask is only visible where there is ink to attenuate**, so the
    /// same one declaration is a cue at twelve sessions and invisible at one, with
    /// nothing anywhere having to decide whether the content overflows.
    ///
    /// ## A recorded divergence, and its cost
    ///
    /// The prototype has **no** cue — its overlay scrollbar measures 0pt wide at
    /// rest, so at four sessions it hides two of them with no affordance at all.
    /// This is therefore a deliberate divergence and not a fidelity fix, taken
    /// because the shear is ours and not the mockup's (its rows happen to end on
    /// the fold). **The cost, stated:** scrolled to the true bottom the last row
    /// fades too, where nothing is below it. Removing that needs the scroll offset,
    /// and `onScrollGeometryChange` is macOS 15 against this package's macOS 14
    /// floor. Recorded rather than hidden.
    ///
    /// ## The number
    ///
    /// 24pt: `SessionRow`'s own `.padding(.vertical, 8)` plus its tallest line box
    /// (12.5pt semibold, ~15pt), so **whatever the fold lands on is inside the ramp
    /// rather than cut by it**, which is the defect. And well under one row's 51pt,
    /// so a whole row is never dissolved.
    static let foldFade: CGFloat = 24

    var body: some View {
        if needsClock {
            TimelineView(.animation(minimumInterval: Self.clockInterval, paused: false)) { ctx in
                list(now: ctx.date)
            }
        } else {
            list(now: Date())
        }
    }

    private func list(now: Date) -> some View {
        ScrollView(.vertical) {
            // `.rows{gap:1px;padding-top:2px}`, and **no divider rule at all**.
            //
            // The hairline `Rectangle` that used to sit between rows was ours, not
            // the mockup's, and it stopped being defensible the moment a row grew
            // a rounded hover background: a full-bleed rule runs straight through
            // the 9pt corners of the two rows it separates, so the row that
            // lights up under the pointer reads as a panel with a line nailed
            // across each end of it. The hover fill is the separation now, and it
            // appears on the row you are pointing at rather than on all of them
            // at once.
            VStack(alignment: .leading, spacing: 1) {
                ForEach(sessions) { session in
                    SessionRow(session: session, now: now, options: options,
                               questions: questions[session.id] ?? [],
                               onAnswer: onAnswer)
                }
            }
            .padding(.top, 2)
            // The rows' *background* edge, which is why this stays where it is
            // rather than shrinking by the row's own new 10pt: the mockup nests
            // the same way — `.face[data-side="d"]{padding:4px 18px}` outside,
            // `.row{padding:8px 10px}` inside — so the hover panel stands clear
            // of the face's edge and the text sits 10pt inside the panel.
            .padding(.horizontal, QuestionFace.leadingPadding)
        }
        // §6.3: "420pt, rows scroll" — a fixed height with the content scrolling
        // inside it, never a height that follows the content. Growing would push
        // §6.4's reserved footer off the bottom.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollIndicators(.never)
        // The overflow cue. **Outside the `ScrollView`, and after its frame** —
        // both halves are load-bearing. Inside it the gradient would be part of
        // the scrolled content and travel with the rows instead of sitting at the
        // fold; before the `.frame` it would be handed the content's height rather
        // than the viewport's, so at one session it would fade that session's own
        // last line. See `foldFade` for why this is a fade at all.
        //
        // A flexible `Rectangle` above a fixed-height gradient, rather than a
        // single `LinearGradient` with computed stops: this way the ramp is
        // `foldFade` points deep whatever the face's height turns out to be, with
        // no `GeometryReader` and no percentage to keep in step with §6.3's 420.
        .mask {
            VStack(spacing: 0) {
                Rectangle().fill(Color.black)
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.foldFade)
            }
        }
    }
}
