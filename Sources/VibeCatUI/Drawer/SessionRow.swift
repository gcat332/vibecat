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
    /// A `nonisolated static` pure function rather than a computed property, so
    /// a test can assert the *string* — "a running row shows `2m` and a waiting
    /// one shows `Needs you`" — instead of inferring it from a pixel diff, which
    /// is the strongest form this particular rule can be pinned in. (`nonisolated`
    /// for the reason `RevealContent.elapsed` is: `View` conformance otherwise
    /// infers `@MainActor` onto every member of the type.)
    nonisolated static func stateLabel(for session: Session, now: Date) -> String {
        switch session.state {
        case .running: RevealContent.elapsed(now.timeIntervalSince(session.updatedAt))
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
            CLIMarkView(mark: CLIMark(cli: session.cli))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                headline
                secondLine
                if options.contains(.lastMessage), let asked = session.lastUserMessage {
                    // `.lineLimit(1)`, not 2. The mockup's `.rsaid` is
                    // `white-space:nowrap` with an ellipsis, and §11's first
                    // words are "**Three** lines per row" — a two-line line 3
                    // makes four, the same defect the project name already
                    // shipped with once.
                    Text("│ \(asked)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hazeColour))
                        .lineLimit(1)
                }
                SessionBlocks(session: session, options: options, accent: accent)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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
                Text("⑂ \(worktree)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hazeColour))
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
                                .foregroundStyle(Color(boneColour))
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
                    Text(meta)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hazeColour))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
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
