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
    /// `SESSIONS` (line 788) gives a running session `state:'2m 14s'`, not the
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
    @FocusState private var keyboardFocus: Bool

    private var accent: Color { Color(IslandState(session.state).accent) }

    /// The mockup's `s.state`: a word for three of the four states and an
    /// elapsed time for the fourth (`SESSIONS`, line 788 — `state:'2m 14s'`
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
                       accent: accent, style: .brandColour)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                headline
                secondLine
                if options.contains(.lastMessage), let asked = session.lastUserMessage {
                    lastMessageLine(asked)
                }
                SessionBlocks(session: session, options: options)
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
        .onHover { inside in
            // Guarded so the cursor stack stays balanced: SwiftUI can deliver the
            // same edge twice, and two pushes with one pop leaves a pointing hand
            // over the whole app.
            guard inside != hovering else { return }
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    /// `border-radius:9px`, shared by the hover fill, the focus ring and the hit
    /// region so the three can never disagree about the row's shape.
    private static let corner = RoundedRectangle(cornerRadius: 9)
    /// `.row:hover{background:rgba(255,255,255,.05)}`.
    private static let hoverInk: Double = 0.05

    private var isHovered: Bool { hovering || highlight.contains(.hovered) }
    private var isFocused: Bool { keyboardFocus || highlight.contains(.focused) }

    private var headline: some View {
        HStack(spacing: 10) {
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
