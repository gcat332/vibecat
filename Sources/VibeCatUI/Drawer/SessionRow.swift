import AppKit
import SwiftUI
import VibeCatCore

/// §11: three lines per row, most urgent information first.
///
/// ```
/// ✳  api  ⑂ auth-hardening                     Needs you ●
///    ▶ Asking to run rm -rf build/       iTerm2 · Opus 4.8 · high
///    │ clean the build and rebuild from scratch
/// ```
///
/// The authority for *appearance* here is the design's own mockup —
/// `docs/superpowers/prototypes/island-motion.html`, `renderRows` at line 839 —
/// not the ASCII sketch above, which is §11's and is a summary. Plan 5 built
/// this whole view against the sketch alone and diverged from the mockup in
/// eleven places; the ones this file now matches are called out where they
/// happen.
struct SessionRow: View {
    /// §11: "Every line is individually switchable in Settings." Settings is
    /// Plan 6; the switch points have to exist here or Plan 6 rewrites this
    /// view.
    ///
    /// Aligned to the mockup's own switch set (`card`, line 813:
    /// `project, worktree, model, effort, said, tasks, agents, activity`) rather
    /// than to Plan 5's guess at it. Two deliberate differences, both recorded:
    ///
    /// - `lastMessage` keeps its name instead of the mockup's `said` — it names
    ///   the thing (§11: "the last thing **you** asked it") rather than the
    ///   grammar of the sentence describing it.
    /// - `subagents` has no counterpart in the mockup, which has a single
    ///   `agents` switch. It stays, because §11 spells out a behaviour that one
    ///   switch cannot express: hiding subagents *collapses* the block to a
    ///   count instead of removing it.
    struct Options: OptionSet, Sendable {
        let rawValue: Int
        static let activity = Options(rawValue: 1 << 0)
        static let lastMessage = Options(rawValue: 1 << 1)
        static let tasks = Options(rawValue: 1 << 2)
        static let agents = Options(rawValue: 1 << 3)
        /// §11: when Subagents are hidden the block collapses to a count rather
        /// than vanishing, "because approvals and questions from a child agent
        /// still need to surface".
        static let subagents = Options(rawValue: 1 << 4)
        /// Off substitutes the terminal's name for the project's — the mockup's
        /// `${card.project ? s.proj : s.term}`. It does **not** blank line 1's
        /// leading field: a row with nothing there is not a row, which is the
        /// true half of Plan 5's reasoning for declaring line 1 unswitchable.
        static let project = Options(rawValue: 1 << 5)
        static let worktree = Options(rawValue: 1 << 6)
        /// Individually switchable, per the mockup's `metaLine` (line 816) —
        /// `bits = [s.term]`, then model and effort each gated on their own.
        static let model = Options(rawValue: 1 << 7)
        static let effort = Options(rawValue: 1 << 8)
        static let all: Options = [.activity, .lastMessage, .tasks, .agents, .subagents,
                                   .project, .worktree, .model, .effort]
    }

    let session: Session
    /// Reintroduced by the mockup-fidelity pass, and the previous version of
    /// this comment is the reason it is worth explaining twice: `now:` was here
    /// under Plan 5, was **never read**, and was removed on the grounds that
    /// "none of §11's three lines is a duration". The mockup says otherwise —
    /// `SESSIONS` (line **797**, the `codex` record — `:788` is the `'Needs you'` one, and
    /// this comment cited it for four plans) gives a running session `state:'2m 14s'`, not the
    /// word "Running" — so line 1's state field *is* a duration for exactly one
    /// of the four states.
    ///
    /// That removal note also carried a condition: "a `now` that never advances
    /// is worse than no `now` at all." `SessionListFace` honours it with a
    /// `TimelineView` that exists only while some session is actually running —
    /// see its own doc comment.
    let now: Date
    var options: Options = .all

    /// The two interactive skins the mockup gives a row — `.row:hover` and
    /// `.row:focus-visible` — **as a value, alongside the live state that
    /// normally drives them.**
    ///
    /// It is a parameter because an offscreen render has neither a pointer nor a
    /// focus system: `ImageRenderer` never delivers `onHover` and never resolves
    /// `@FocusState` to `true`, so a focus ring reachable only through
    /// `@FocusState` is a thing no test in this suite could ever see. Two earlier
    /// waves of this file lost real defects exactly there — a switch that was
    /// threaded and then ignored, a mark that was drawn and never varied — and
    /// both were caught only once the state in question could be *asked for*.
    ///
    /// Production passes nothing and gets the live behaviour. Nothing branches on
    /// whether the value or the live state supplied the skin; they are OR-ed.
    struct Highlight: OptionSet, Sendable {
        let rawValue: Int
        static let hovered = Highlight(rawValue: 1 << 0)
        static let focused = Highlight(rawValue: 1 << 1)
    }
    var highlight: Highlight = []

    @State private var hovering = false
    /// **Separate from `hovering` since review round 2.** `hovering` still
    /// drives the whole-row fill; this drives only the pointing-hand cursor,
    /// scoped to `headline` — see that property's own `.onHover`. Two
    /// independent booleans rather than one, because a single `pointingHand`
    /// stack has to balance its own pushes and pops (`NSCursor.pointingHand
    /// .push()`/`.pop()` is a literal stack, not a set-and-clear flag), and two
    /// `.onHover` regions delivering edges into one shared `Bool` would let a
    /// pointer crossing from the header into the rest of the row read as "still
    /// hovering" and never pop.
    @State private var hoveringHeader = false
    @FocusState private var keyboardFocus: Bool

    private var accent: Color { Color(IslandState(session.state).accent) }

    /// The mockup's `s.state`: a word for three of the four states and an
    /// elapsed time for the fourth (`SESSIONS`, line 797 — `state:'2m 14s'`
    /// with `live:true`). Measured from `updatedAt`, which is what
    /// `RevealContent` measures and for §1's reason: time *in the current
    /// state* is the number that matters.
    ///
    /// `RevealContent.elapsed` and not a second formatter — it is already
    /// `nonisolated` precisely so it can be called from anywhere, and two
    /// duration formatters in one app is how the collapsed bar and the list
    /// start disagreeing about how long a run has taken.
    ///
    /// `precision: .fine`, which is a **granularity on the shared formatter** and
    /// not a widening of the reveal's format. The mockup's running rows read
    /// `2m 14s` and `0m 38s`; the reveal, which shows the same duration, must stay
    /// at one unit because it has 150pt for a project name as well. One formatter,
    /// two callers, each asking for what its own width can carry.
    ///
    /// A `nonisolated static` pure function rather than a computed property, so
    /// a test can assert the *string* — "a running row shows `2m` and a waiting
    /// one shows `Needs you`" — instead of inferring it from a pixel diff, which
    /// is the strongest form this particular rule can be pinned in. (`nonisolated`
    /// for the reason `RevealContent.elapsed` is: `View` conformance otherwise
    /// infers `@MainActor` onto every member of the type.)
    nonisolated static func stateLabel(for session: Session, now: Date) -> String {
        switch session.state {
        case .running: RevealContent.elapsed(now.timeIntervalSince(session.updatedAt),
                                            precision: .fine)
        case .idle, .waiting, .failed: IslandState(session.state).label
        }
    }

    /// The mockup's `s.term`, used in two places: as `metaLine`'s first bit and
    /// as line 1's leading field when `.project` is off.
    private var terminalName: String? { session.origin.app.map(originName) }

    /// The outstanding questions for *this* session — Plan 9. Defaulted so every
    /// existing call site (goldens, previews, `HookLoopProbe`) keeps compiling and
    /// keeps rendering exactly what it rendered before.
    var questions: [IslandModel.RowQuestion] = []
    /// Fires with the `Reply` a tap in one of those blocks produced.
    var onAnswer: (Reply) -> Void = { _ in }
    /// §13's jump to the session's own terminal — Plan 9 Task 6 defines the hit
    /// region and calls this; **making it do anything is a later plan's job**
    /// ("Out of scope, deliberately" in
    /// `docs/superpowers/plans/2026-08-06-parking-questions.md`). No production
    /// call site passes one — `SessionListFace` never threads it — so this stays
    /// at its default everywhere the app actually runs. Said here, in the
    /// declaration, because an unwired closure that looks wired is a defect this
    /// project has shipped before.
    var onJump: () -> Void = {}

    /// Ruling B's `Dismiss` releases every answerable question this row holds
    /// (adjudicated in review round 2 — a row-level control acting on one
    /// unnamed question among several was the worse of the two options), so the
    /// control needs only *one* answerable question to find the shared closure
    /// through — every `RowQuestion` for this session was built with the same
    /// one (see `NotchController.syncRowQuestions()`), so it does not matter
    /// which. A handed-back question's hook is already gone, so there is
    /// nothing left for `Dismiss` to do for it — `questions.contains {
    /// !$0.isHandedBack }` is the brief's own condition for *whether* to draw
    /// the control, restated here as the question it actually reads
    /// `onDismiss` off so the view and the tap can never disagree about it.
    ///
    /// No separate `onDismiss` parameter on this row any more — round 1 had
    /// one, threaded through `SessionListFace`/`DrawerView`/`IslandModel`
    /// alongside `onAnswer`, and round 2's review measured that dropping either
    /// of two of those three threading lines left all 922 tests green. This
    /// reads the closure straight off `IslandModel.RowQuestion` instead, which
    /// already has to survive the same trip for the row to draw a question
    /// block at all — see that struct's own doc comment.
    private var firstAnswerableQuestion: IslandModel.RowQuestion? {
        questions.first { !$0.isHandedBack }
    }

    private func headerTapped() { onJump() }
    private func dismissTapped() { firstAnswerableQuestion?.onDismiss() }

    /// The one place a `QuestionBlock` is built for this row. `body`'s own
    /// `ForEach` and `answerTapForTesting` below both go through this, so a test
    /// exercising "answering a question does not jump" exercises the very same
    /// wiring a real render uses, rather than a hand-rebuilt stand-in that could
    /// quietly drift from it.
    private func questionBlock(for row: IslandModel.RowQuestion) -> QuestionBlock {
        QuestionBlock(question: row.model, accent: accent, isHandedBack: row.isHandedBack,
                      handedBackTo: terminalName, onAnswer: onAnswer)
    }

    /// **Tasks and Agents step aside for a question.** Measured: one waiting row came to
    /// 406pt against the session list's real 376pt viewport, so a single session filled
    /// the page and every other row fell below the fold. `ChoiceRow`'s compact scale
    /// recovers part of that; this recovers the rest, and it is the half with a reason
    /// beyond arithmetic — Tasks and Agents are *context* for a session, and a question
    /// is the one thing on the row asking a person to act.
    ///
    /// **The mockup licenses exactly this trade.** `island-motion.html:832`, inside
    /// `agentsHTML`: *"hidden subagents collapse to a count — approvals and questions
    /// would stay."* Questions stay; the internals are what yields.
    ///
    /// A row with no question is untouched, which is why every existing golden still
    /// renders what it rendered before.
    private var blockOptions: SessionRow.Options {
        questions.isEmpty ? options : options.subtracting([.tasks, .agents, .subagents])
    }

    var body: some View {
        // The mark sits *outside* the three lines and they indent past it —
        // `.row{display:flex;align-items:flex-start;gap:10px}` with
        // `.row > .mark{margin-top:1px}`. §11's own sketch indents the same way.
        HStack(alignment: .top, spacing: 10) {
            // `.mark{color:var(--accent)}` (mockup line 200) with `--accent` set
            // per row from `s.colour`, and §4.3's closing sentence — "Everything
            // tinted by the current state — **marks**, cat, badge, counts, the
            // aura — uses the same `--accent`."
            //
            // The previous wave drew this in `boneColour` under an instruction
            // not to tint a mark by state, and flagged the instruction as wrong;
            // it was. §4.3's "never by hue" governs **identity** — which agent is
            // speaking must be legible without colour vision — and says nothing
            // against a mark also carrying state. Shape says who, hue says what
            // state, both on the same mark — true of the geometric fallback,
            // which is still the common case (see `Session.icon`'s own comment
            // for why real sources have no icon to give yet).
            //
            // Task 5: the row's real source, via `SourceIcon`, falling back to
            // `CLIMarkView` through the exact same call whenever `session.icon`
            // is `nil` or turns out to be a bad path. `.brandColour`, not
            // `.tinted` — `SourceIcon`'s own doc comment rules on this and this
            // is the call site it names: line 1 already states this row's state
            // twice over, in `stateLabel` below and the pip six points from it,
            // so the mark's hue is spare capacity here rather than state's only
            // carrier, and a brand icon may spend it on identity instead.
            //
            // `session.icon` is resolved upstream of this view, not read out of
            // a registry reached into from here — see `Session.icon`'s doc
            // comment for where that lookup lives and why. A view that had to
            // hold a `SourceRegistry` to draw itself could not be rasterised by
            // any test in this file without one.
            //
            // One session, one true source: unlike `IslandView`'s
            // `openMark(face:)` and `collapsedMark`, which fall back to
            // `.generic` because no single mark is true of a *mixed* set of
            // CLIs across several open sessions, a row is never asked to speak
            // for more than the one session it renders — so it never needs that
            // fallback, and the asymmetry is correct. Nobody should "fix" this
            // row to also collapse to `.generic` for some notion of mixedness;
            // there is nothing here for it to mean.
            SourceIcon(path: session.icon, fallback: CLIMark(cli: session.cli),
                       accent: accent, style: .brandColour,
                       opticalScale: BundledIcon.forSourceID(session.cli).opticalScale)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                headline
                secondLine
                if options.contains(.lastMessage), let asked = session.lastUserMessage {
                    lastMessageLine(asked)
                }
                // **Before `SessionBlocks`, deliberately.** §4.2's own reasoning is
                // that a waiting agent is idling on you *right now*, so a question
                // must never be buried under a list — and Tasks and Agents are
                // exactly that list. The mockup gives no ordering for a question
                // block because it never rendered one (`island-motion.html:832`
                // anticipates it in a comment), so this is a decision, not a
                // reading.
                ForEach(questions) { row in questionBlock(for: row) }
                SessionBlocks(session: session, options: blockOptions)
            }
        }
        // `.row{padding:8px 10px}`. The horizontal half is new with the hover
        // background: without it the background would start and end exactly at
        // the first and last glyph, where the mockup's stands 10px clear of them.
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.corner.fill(Color.white.opacity(isHovered ? Self.hoverInk : 0)))
        // `outline:2px solid var(--haze);outline-offset:-2px` — inside the row's
        // own box, not around it. `strokeBorder` draws inward from the shape's
        // edge, which is what an inset outline is.
        .overlay { if isFocused { Self.corner.strokeBorder(Color(hazeColour), lineWidth: 2) } }
        // `cursor:pointer` needs the whole padded rectangle to be the target, not
        // just the glyphs — `HStack` hit-testing would otherwise leave the gaps
        // between fields inert and make the hover flicker as the pointer crosses
        // them.
        .contentShape(Self.corner)
        // `tabindex="0"`. Focusable and legible when focused; **not** wired to any
        // key handling, which is Plan 6's — and which the key-input spike
        // constrains further (the panel may hold key status only while a question
        // is open, or it silently swallows everything the person types).
        .focusable()
        .focused($keyboardFocus)
        // `transition:background 130ms var(--ease)` (island-motion.html:346).
        // `var(--ease)` is `cubic-bezier(.22,.9,.28,1)`, which is
        // `IslandMotion.ease` and is not `.easeOut` — this line read `.easeOut`
        // until Plan 6.3 Task 3.
        .animation(IslandMotion.ease(duration: 0.13), value: isHovered)
        // **The fill only, since review round 2 — the cursor push moved to
        // `headline`'s own `.onHover` below.** This one still spans the whole
        // padded rectangle: the mockup's `.row:hover` highlight is a "this is
        // the row you are near" cue, and narrowing *that* along with the cursor
        // would have removed the only visual feedback a pointer gets anywhere
        // outside the header — over a task line, say — leaving no affordance at
        // all rather than a merely honest one. Only the promise of a click
        // needed narrowing (Important 3); the highlight was never the promise.
        .onHover { inside in
            // Guarded so this can never re-fire on the same edge SwiftUI
            // occasionally redelivers — harmless here (it would just reassign
            // the same `Bool`), kept for symmetry with `headline`'s own guard,
            // where an unguarded double-fire is not harmless.
            guard inside != hovering else { return }
            hovering = inside
        }
    }

    // MARK: - Testing hooks (Plan 9 Task 6)
    //
    // No ViewInspector, and nothing headless can prove which closure a real
    // `.onTapGesture` is bound to — same reasoning as `QuestionBlock
    // .tapForTesting`/`.sendForTesting` and `SettingsButton.actionForTesting`.
    // Each of these calls exactly what its real gesture calls, no more.

    /// What tapping the header does.
    func headerTapForTesting() { headerTapped() }

    /// What tapping the Dismiss control does. A no-op with nothing answerable
    /// (`firstAnswerableQuestion == nil`), matching the control's own absence
    /// there.
    func dismissTapForTesting() { dismissTapped() }

    /// What tapping one choice of one of this row's own question blocks does —
    /// through `questionBlock(for:)`, the same factory `body` builds that block
    /// with, so a mutation that coupled that block's `onAnswer` to `onJump`
    /// would be caught here, not just by a hand-copied stand-in for it.
    func answerTapForTesting(questionID: String, choiceID: String) {
        guard let row = questions.first(where: { $0.id == questionID }) else { return }
        questionBlock(for: row).tapForTesting(choiceID)
    }

    /// `border-radius:9px`, shared by the hover fill, the focus ring and the hit
    /// region so the three can never disagree about the row's shape.
    private static let corner = RoundedRectangle(cornerRadius: 9)
    /// `.row:hover{background:rgba(255,255,255,.05)}`.
    private static let hoverInk: Double = 0.05

    private var isHovered: Bool { hovering || highlight.contains(.hovered) }
    private var isFocused: Bool { keyboardFocus || highlight.contains(.focused) }

    /// §11's line 1 — `.rtop` — and, since Plan 9 Task 6, the row's *only* jump
    /// target.
    ///
    /// **A deliberate divergence from the prototype, recorded here because a
    /// reviewer diffing against it will find a smaller hit area and needs the
    /// reason in the file.** `island-motion.html:345` puts `cursor:pointer` on
    /// the whole `.row` — the mockup's entire card is one jump target, header to
    /// last block. Narrowing it to the header alone is Plan 9 Task 6's own
    /// ruling: a question can now render *inside* this same row, and every tap
    /// inside it — a choice, `Dismiss`, a task line — must never also mean "go
    /// to the terminal". `RowHitRegionTests.swift` is the three-test proof this
    /// reasoning demands; any one of the three alone is satisfiable by a broken
    /// implementation.
    ///
    /// `Dismiss` (ruling B) lives *inside* this same header, before `.rstate` —
    /// `.rstate` carries the mockup's own `margin-left:auto` (line 354), so
    /// whatever sits after the `Spacer` and before it shares that same
    /// right-hand edge rather than displacing it.
    ///
    /// **The divergence has a visible half too, and review round 2 is what
    /// noticed this file had only recorded the invisible one.** Narrowing the
    /// hit *region* means nothing if the pointer still promises a click
    /// everywhere the mockup's undivided `cursor:pointer` did — `NSCursor
    /// .pointingHand` used to push from the row's own `.onHover` (`body`,
    /// below), spanning `.rmid`, the last-message line, every task line and a
    /// question block's own chrome, none of which a click does anything to any
    /// more. `headline` now pushes it from its *own* `.onHover` instead, into
    /// `hoveringHeader` rather than `hovering` — see that state var's own doc
    /// comment for why the two cannot share one `Bool`. The whole-row hover
    /// *fill* stays wide on purpose: it is "this is the row you are near", not
    /// a promise of what a click there does, and narrowing it too would have
    /// left every field below the header with no hover feedback at all.
    ///
    /// **Why this split is structural rather than gesture-priority-dependent.**
    /// `.onTapGesture` here is scoped to `headline`'s own `HStack`; `ForEach
    /// (questions)`/`SessionBlocks` are its *siblings* inside `body`'s outer
    /// `VStack`, never its descendants. So a tap inside a question block has no
    /// ancestor in common with this gesture to propagate through in the first
    /// place — the header and every block simply do not share a container that
    /// carries a jump gesture. That is a stronger guarantee than getting an
    /// inner-consumes-outer priority right (which is what `dismissControl`
    /// below still needs, since `Dismiss` *is* nested inside this same header).
    ///
    /// **Recorded rather than proven by test, and that gap is real.** This
    /// project has no ViewInspector and cannot deliver a synthetic tap through a
    /// headless render (`QuestionFaceTests.swift`'s own doc comment establishes
    /// this), so every assertion in `RowHitRegionTests.swift` calls a private
    /// method directly rather than rendering and tapping. Tried and confirmed:
    /// attaching a second `.onTapGesture { headerTapped() }` to the whole row
    /// (this file's own `.contentShape(Self.corner)`, matching the prototype's
    /// undivided `.row`) leaves every test in that file green, because none of
    /// them exercises where in the tree a gesture actually attaches — only
    /// that the right closures call the right other closures. The sibling
    /// structure above is what actually defends the live app against that
    /// mutant; a reviewer moving this modifier onto the outer `VStack` is a
    /// one-line, visually obvious diff, which is the check this repo accepts in
    /// place of a test it cannot yet write (same reasoning `QuestionFaceTests`
    /// gives for `QuestionFace.rows`/`.sendRow`'s own wiring).
    private var headline: some View {
        // `.rtop{display:flex;align-items:baseline;gap:10px}` (island-motion.html
        // :351) — `baseline`, not `center`, and this `HStack` read the default
        // `.center` until review round 2's Minor 5: with every child the same
        // height that difference is invisible, and `Dismiss` was the first
        // sibling ever taller than the rest, which is exactly what made it show.
        // Baseline alignment keeps every *other* child's text sitting on the
        // same line regardless of how tall one sibling's own box is — a taller
        // `Dismiss` chip extends below the shared baseline instead of pushing
        // the row's text down to stay centred against it, which is what a
        // fixed-height `.frame` would have had to fake by re-deriving a number
        // this alignment gets for free, from the same rule the mockup states.
        //
        // **Not for free alone, though, and the correction matters more than the
        // fix did.** `theHeaderStaysOnOneBaselineWhetherOrNotDismissIsShown` also
        // dies to `dismissControl`'s `.padding(.vertical, 0)` becoming `3`: the
        // alignment holds the baseline, and that zero is what stops the chip's own
        // box growing the line box around it. Two lines carry this between them.
        // Recorded because a comment that credits one of two causes is how this
        // repo lost its bezel fillets for four plans — someone read `9px` as the
        // bottom radius, found the fillets beside it, and deleted those instead of
        // re-spelling a number that never needed changing.
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // `${card.project ? s.proj : s.term}` — a substitution, not a
            // removal. Falls back to the project when there is no origin app to
            // name: an unattributed session must not leave the field empty.
            Text(options.contains(.project) ? session.project
                                            : (terminalName ?? session.project))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color(boneColour))
                // §11 is "**three** lines per row", and without this the row is
                // four. Found by opening the assembled list for the first time
                // (`VIBECAT_LIST_SHOT`): `project` is `cwd`'s last path
                // component, entirely under the user's control, and
                // `web-dashboard-with-a-long-name` wrapped to two lines — which
                // also dragged line 1's layout crooked, because the state dot
                // centres against the taller block while the worktree and the
                // state label sit on the lower baseline. Every other `Text` in
                // this row already had `.lineLimit(1)`; this one, the row's most
                // important field, did not.
                //
                // `.middle`, matching the worktree beside it: a project name has
                // no end-or-beginning asymmetry the way a command body does (see
                // `secondLine`), so keeping both ends loses least.
                .lineLimit(1)
                .truncationMode(.middle)
            if options.contains(.worktree), let worktree = session.worktree {
                // `.rwt{font-family:…monospace;font-size:10.5px;color:var(--dim)}`
                // — mono and `--dim`, both of which this had as the sentence's
                // 11pt sans in `--haze`. A branch name is an identifier, which is
                // the same reason line 2's command is mono.
                Text("⑂ \(worktree)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color(dimColour))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            // Ruling B: only when there is something left to give up on — a
            // handed-back question's hook is already gone, so there is nothing
            // here for `Dismiss` to do.
            if firstAnswerableQuestion != nil {
                dismissControl
            }
            // `.rstate` — the word *and* a pip, `gap:6px`. The pip is where the
            // state's colour lives now that the leading position belongs to the
            // CLI's mark: §4.3 wants hue to mean state and only state, and it
            // reads better six points from the word it agrees with than sixteen
            // points away at the head of the row.
            HStack(spacing: 6) {
                Text(Self.stateLabel(for: session, now: now))
                    .font(.system(size: 11))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
            }
            .fixedSize()
        }
        // Same reasoning as the row's own `.contentShape(Self.corner)` below —
        // an `HStack` only hit-tests its children's own frames, so without this
        // the gaps between the project name, the worktree chip and `.rstate`
        // would be inert to a tap, the same way they would be to the hover
        // cursor without that one.
        .contentShape(Rectangle())
        .onTapGesture { headerTapped() }
        // The pointing hand, narrowed to match the gesture two lines up —
        // Important 3 of review round 2. Same push/pop and same double-fire
        // guard `body`'s own `.onHover` uses, into `hoveringHeader` rather than
        // `hovering` so the two regions' edges cannot stack unbalanced pushes
        // against one shared flag.
        .onHover { inside in
            guard inside != hoveringHeader else { return }
            hoveringHeader = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        // **The teardown, and it is not symmetry for its own sake.** `NSCursor`'s stack is
        // process-wide: a row that leaves the view tree while the pointer is inside its
        // header — answering a question removes it, and `prune` removes whole rows —
        // never receives `onHover(false)`, so the pushed `pointingHand` outlives the row
        // and every window in the app keeps a hand cursor until something else pops it.
        //
        // **Unmeasured**, and labelled as such: a stuck cursor is app-wide state no
        // headless test in this suite can observe, so this is reasoned from `NSCursor`'s
        // push/pop contract rather than from an observation. It is also why the guard
        // above exists — `onDisappear` must not pop a push that never happened.
        .onDisappear {
            if hoveringHeader {
                hoveringHeader = false
                NSCursor.pop()
            }
        }
    }

    /// Ruling B's control, new UI: `island-motion.html` has no `Dismiss`
    /// anywhere on a row — Plan 9 invented the whole idea — so this is designed
    /// rather than transcribed, at the same 10.5pt/`--dim` register the row's
    /// other quiet fields (`.rmeta`, `.rwt`) already use. No hue of its own:
    /// this is a housekeeping action, not a report on the session's state, and
    /// §4.3 only asks *state* to speak through `--accent`.
    ///
    /// `.highPriorityGesture`, not a second `.onTapGesture`: this view is
    /// nested inside `headline`, which already carries the header's own
    /// tap-to-jump gesture, and a plain `.onTapGesture` here would risk exactly
    /// the "gets both" trap `answeringInsideTheBlockDoesNotJump`'s own doc
    /// comment describes — the inner gesture has to *consume* the tap, not
    /// merely be recognised alongside the outer one.
    private var dismissControl: some View {
        Text("Dismiss")
            .font(.system(size: 10.5))
            .foregroundStyle(Color(dimColour))
            .padding(.horizontal, 8)
            // **Load-bearing, not a no-op to tidy away.** With any vertical padding
            // this chip's box grows the header's line box and line 1 gains height,
            // so rows stop sharing a baseline down the list — mutation-verified,
            // `3` here reddens `theHeaderStaysOnOneBaselineWhetherOrNotDismissIsShown`.
            // The `.firstTextBaseline` alignment on `headline` is the other half.
            .padding(.vertical, 0)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(dimColour), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .highPriorityGesture(TapGesture().onEnded { dismissTapped() })
    }

    /// §11's line 3, the last thing you asked — the mockup's `.rsaid`.
    ///
    /// The rule on the left is **a drawn bar, not a `│` in the string**:
    /// `.rsaid::before` is a 1.5px, 13%-white, 1px-rounded rectangle inset 2px
    /// from the line's own top and bottom, with the text starting at
    /// `padding-left:11px`. A glyph cannot be any of those things — it inherits
    /// the text's colour and its own baseline, so it lands as a `--dim` mark
    /// floating on the cap line rather than a quiet rule spanning the line.
    ///
    /// `.lineLimit(1)`, not 2. `.rsaid` is `white-space:nowrap` with an ellipsis,
    /// and §11's first words are "**Three** lines per row" — a two-line line 3
    /// makes four, the same defect the project name already shipped with once.
    /// An `.overlay` on the padded text rather than a sibling in an `HStack`, and
    /// that is the whole reason it is written this way: a bare `Shape` beside a
    /// `Text` has no height of its own and stretches to whatever the stack gives
    /// it, while `::before` on `.rsaid` is positioned against *that line's* box.
    /// The overlay inherits the text's own box, so `padding(.vertical, 2)`
    /// reproduces `top:2px;bottom:2px` exactly.
    private func lastMessageLine(_ asked: String) -> some View {
        Text(asked)
            .font(.system(size: 11))
            .foregroundStyle(Color(dimColour))
            .lineLimit(1)
            .padding(.leading, 11)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 0.75)
                    .fill(Color.white.opacity(0.13))
                    .frame(width: 1.5)
                    .padding(.vertical, 2)
                    .padding(.leading, 2)
            }
    }

    /// §11's line 2: "What the agent is doing right now · where and how it
    /// runs."
    ///
    /// Three fields, not two: `<span class="caret">▶</span>${s.act} <em>${s.code}</em>`
    /// on the left and `metaLine(s)` on the right. The command is its own `Text`
    /// in monospace and the brighter ink, because that is the field a person is
    /// actually scanning for — the sentence around it is boilerplate.
    ///
    /// `.activity` gates the left half only. The mockup never gates `.rmid` at
    /// all (its `card.activity` reaches only `agentsHTML`'s sub-line), and
    /// dropping the whole line with the switch would take "where and how it
    /// runs" — and with it any effect from `.model`/`.effort` — down with it.
    @ViewBuilder private var secondLine: some View {
        let meta = [terminalName,
                    options.contains(.model) ? session.model : nil,
                    options.contains(.effort) ? session.effort : nil]
            .compactMap { $0 }.joined(separator: " · ")
        let activity = options.contains(.activity) ? session.activity : nil
        if activity != nil || !meta.isEmpty {
            HStack(spacing: 10) {
                if let activity {
                    HStack(spacing: 5) {
                        // `.caret{color:var(--accent);font-size:9px}` — its own
                        // field, so it can be the accent and small without
                        // dragging the sentence's size or colour with it.
                        Text("▶")
                            .font(.system(size: 9))
                            .foregroundStyle(accent)
                        if let sentence = activity.sentence {
                            Text(sentence)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color(hazeColour))
                                .lineLimit(1)
                        }
                        if let command = activity.command {
                            Text(command)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(commandColour))
                                .lineLimit(1)
                                // The same reasoning as the drawer's command
                                // body: the end of a command is its target, so
                                // never elide the end.
                                .truncationMode(.middle)
                                // The command outranks the sentence beside it
                                // for whatever width is left. Without this
                                // SwiftUI splits the shortfall between the two
                                // and the emphasised field — the whole point of
                                // keeping them apart — is the one that loses.
                                .layoutPriority(1)
                        }
                    }
                }
                Spacer(minLength: 8)
                if !meta.isEmpty {
                    // `.rmeta{font-family:…monospace;font-size:10px;color:var(--dim)}`.
                    // This was 11pt sans in `--haze`, and the size is not a
                    // cosmetic difference: at 11pt the meta line is wide enough
                    // to push the sentence beside it into an ellipsis inside the
                    // drawer's content width — `Asking to r…` in the rendered
                    // list — which the mockup fits at the same width because it
                    // sets 10pt here. The truncation was a type-ladder artefact,
                    // not a layout one.
                    Text(meta)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(dimColour))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }
}

/// The re-thread `SessionListFace`'s own doc comment names as Plan 6.6's Task
/// 4: `Preferences.cardOptions` is `SessionCardOptions`, nine named `Bool`s in
/// `VibeCatCore` — `VibeCatCore` may never import `VibeCatUI`, so the stored
/// preference cannot itself be a `SessionRow.Options`, and something on this
/// side of the seam has to turn the nine `Bool`s into these bits. This is
/// that conversion, and the only place it happens — `NotchController.init`
/// calls it once, at launch, into `IslandModel.cardOptions`.
///
/// An extension, not a second initialiser inside `Options` itself: a struct's
/// synthesized memberwise `init(rawValue:)` — the one `OptionSet` conformance
/// needs — is suppressed the moment any initialiser is written inside its
/// *primary declaration*, but not by one added in an extension. Measured, not
/// assumed: written inside `Options` first, this broke the build with "type
/// 'SessionRow.Options' does not conform to protocol 'OptionSet'" until it
/// moved out here.
extension SessionRow.Options {
    init(_ stored: SessionCardOptions) {
        self = []
        if stored.activity    { insert(.activity) }
        if stored.lastMessage { insert(.lastMessage) }
        if stored.tasks       { insert(.tasks) }
        if stored.agents      { insert(.agents) }
        if stored.subagents   { insert(.subagents) }
        if stored.project     { insert(.project) }
        if stored.worktree    { insert(.worktree) }
        if stored.model       { insert(.model) }
        if stored.effort      { insert(.effort) }
    }
}

/// A small bundle-id map for the origins §11's line 2 names by example. An
/// unknown bundle id falls back to its last dot-component so a raw identifier
/// never reaches the row — `com.example.SomeEditor` reads as "SomeEditor",
/// not as the identifier itself.
private func originName(_ bundleID: String) -> String {
    switch bundleID {
    case "com.googlecode.iterm2": "iTerm2"
    case "com.apple.Terminal":    "Terminal"
    case "com.microsoft.VSCode":  "VS Code"
    default: bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }
}
