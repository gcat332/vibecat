import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func session(_ state: Kind, project: String = "api",
                     cli: String = "claude-code") -> Session {
    var e = VibeEvent(id: "e", cli: cli, kind: state, session: "s",
                      cwd: "/Users/dev/\(project)")
    e.worktree = "auth-hardening"
    e.model = "Opus 4.8"
    e.effort = "high"
    e.title = "Asking to run"
    e.body = "rm -rf build/"
    return Session(event: e, now: t0)
}

@MainActor private func row(_ s: Session, now: Date = t0,
                            options: SessionRow.Options = .all,
                            highlight: SessionRow.Highlight = []) throws -> Raster {
    try rasterise(SessionRow(session: s, now: now, options: options, highlight: highlight)
        .frame(width: 388))
}

/// `session(_:)` plus §11's line 3, and **deliberately no Tasks and no Agents.**
///
/// Two tests below measure a colour that the blocks also draw — `--dim`, and the
/// 13% white of line 3's rule, which a task marker's antialiased border passes
/// through. Both were written against a fixture carrying blocks and both survived
/// the mutation they exist to catch, because the blocks kept the count up on their
/// own. A three-line row is the smallest fixture that can answer a question about
/// the three lines.
@MainActor private func threeLineSession(_ state: Kind = .permission) -> Session {
    var s = session(state)
    s.lastUserMessage = "clean the build and rebuild from scratch"
    return s
}

/// Every optional field populated, including both blocks.
@MainActor private func richSession(_ state: Kind = .permission) -> Session {
    var e = VibeEvent(id: "e", cli: "claude-code", kind: state, session: "s",
                      cwd: "/Users/dev/api")
    e.worktree = "auth-hardening"
    e.model = "Opus 4.8"
    e.effort = "high"
    e.origin = Origin(app: "com.googlecode.iterm2")
    e.title = "Asking to run"
    e.body = "rm -rf build/"
    e.tasks = [TaskItem(title: "Audit authentication flow", status: .doing),
               TaskItem(title: "Add regression coverage", status: .open),
               TaskItem(title: "Map session state", status: .done)]
    e.agents = [AgentItem(name: "Explore (Search API endpoints)", elapsed: "8s",
                          model: "Sonnet 4.6", activity: "Grep: handleRequest"),
                AgentItem(name: "Explore (Read config files)", elapsed: "Done",
                          model: "Sonnet 4.6", finished: true)]
    var s = Session(event: e, now: t0)
    s.lastUserMessage = "clean the build and rebuild from scratch"
    return s
}

/// Does an `n`×`n` square of pixels all within `tolerance` of `colour` exist
/// anywhere? The point of the square is that **text cannot fake it**: at 11pt a
/// glyph stem is one or two pixels wide, so a solid 5×5 patch of one exact hue
/// is a filled shape and nothing else. That is what makes it usable as evidence
/// for "a pip was drawn" as opposed to "the state's word was drawn in the
/// state's colour", which `pixelCount(near:)` alone cannot tell apart.
extension Raster {
    func containsSolidSquare(of colour: RGBA, side n: Int, tolerance: Int = 6) -> Bool {
        func near(_ x: Int, _ y: Int) -> Bool {
            let p = self[x, y]
            let t = (Int((colour.r * 255).rounded()),
                     Int((colour.g * 255).rounded()),
                     Int((colour.b * 255).rounded()))
            return p.a > 200 && abs(Int(p.r) - t.0) <= tolerance
                && abs(Int(p.g) - t.1) <= tolerance && abs(Int(p.b) - t.2) <= tolerance
        }
        guard width >= n, height >= n else { return false }
        for y in 0...(height - n) {
            for x in 0...(width - n) where near(x, y) {
                if (0..<n).allSatisfy({ dy in (0..<n).allSatisfy { dx in near(x + dx, y + dy) } }) {
                    return true
                }
            }
        }
        return false
    }

    /// One vertical band of every scanline — a single field's own column.
    func differingPixelCount(from other: Raster, inColumns xs: Range<Int>) -> Int {
        guard width >= xs.upperBound, other.width >= xs.upperBound, height == other.height else {
            return max(width * height, other.width * other.height)
        }
        var n = 0
        for y in 0..<height {
            for x in xs where self[x, y] != other[x, y] { n += 1 }
        }
        return n
    }

    /// How many pixels in a band are *covered* in one raster and not the other,
    /// ignoring colour entirely.
    ///
    /// This is the only way to ask "is it the same shape?" separately from "is it
    /// the same colour?", and §4.3 needs exactly that question asked twice with
    /// different answers: the mark's shape must not move with the session's state
    /// and its hue must.
    func differingCoverageCount(from other: Raster, inColumns xs: Range<Int>) -> Int {
        guard width >= xs.upperBound, other.width >= xs.upperBound, height == other.height else {
            return max(width * height, other.width * other.height)
        }
        var n = 0
        for y in 0..<height {
            for x in xs where self[x, y].isTransparent != other[x, y].isTransparent { n += 1 }
        }
        return n
    }

    /// Ink within `t` points of the raster's outer edge — where an inset outline
    /// draws and where nothing else in a row does.
    func opaquePixelCount(inBorderOfWidth t: Int) -> Int {
        var n = 0
        for y in 0..<height {
            for x in 0..<width where x < t || x >= width - t || y < t || y >= height - t {
                if !self[x, y].isTransparent { n += 1 }
            }
        }
        return n
    }

    /// The leftmost column holding a pixel at least `minimumAlpha` opaque.
    ///
    /// The threshold is the point: a panel drawn at 3.5% white has an alpha of 9,
    /// so counting *any* non-transparent pixel would just measure the panel's own
    /// left edge. Above 100 is content — text, a marker — and nothing else.
    func leftmostInkedColumn(minimumAlpha: UInt8 = 100) -> Int? {
        for x in 0..<width {
            for y in 0..<height where self[x, y].a >= minimumAlpha { return x }
        }
        return nil
    }

    /// The tallest unbroken vertical run of one colour at a single x.
    ///
    /// Distinguishes a **drawn rule** from a glyph that looks like one: both are
    /// thin and vertical, but they cannot be the same colour, because a glyph
    /// takes the text's ink and a rule takes its own.
    func longestVerticalRun(of colour: RGBA, tolerance: Int = 6) -> Int {
        let t = (Int((colour.r * 255).rounded()),
                 Int((colour.g * 255).rounded()),
                 Int((colour.b * 255).rounded()))
        func near(_ p: Pixel) -> Bool {
            p.a > 200 && abs(Int(p.r) - t.0) <= tolerance
                && abs(Int(p.g) - t.1) <= tolerance && abs(Int(p.b) - t.2) <= tolerance
        }
        var best = 0
        for x in 0..<width {
            var run = 0
            for y in 0..<height {
                run = near(self[x, y]) ? run + 1 : 0
                best = max(best, run)
            }
        }
        return best
    }
}

/// §11's line 1 carries "Project, worktree, state" — and the state is carried
/// by colour (§4.3), so the row must paint the accent of the state it is in and
/// not of any other.
///
/// **Scoped to a session with no Tasks and no Agents, and that is now load-bearing
/// rather than incidental.** The mockup's `.rblock` markers are tinted by the
/// *item's* state, not the row's — `.tk.doing i` is `var(--running)` and
/// `.ag i.ok` is `var(--idle)`, both of which stay themselves inside an amber or a
/// red row. So "one hue per row" is a claim about the row's own three lines: a
/// task in progress is running whatever has become of the session around it. See
/// `TaskMarker` in `SessionBlocks.swift`.
@MainActor @Test func theRowWearsItsOwnStatesAccent() throws {
    for (kind, state) in [(Kind.permission, IslandState.waiting),
                          (.failed, .failed), (.running, .running)] {
        let raster = try row(session(kind))
        #expect(raster.pixelCount(near: state.accent) > 0,
                "\(kind): no \(state) accent in the row at all")
        for other in IslandState.allCases where other != state && other != .dormant {
            #expect(raster.pixelCount(near: other.accent) == 0,
                    "\(kind): the row also painted \(other)'s accent — colour must mean one state")
        }
    }
}

// MARK: - The leading position belongs to the CLI, not to the state

/// The mockup's `renderRows` opens each row with `markSVG(s.mark)` — §4.3's
/// "which agent is speaking is carried by its **icon shape**". Until the
/// mockup-fidelity pass this position held a state dot, and the state was then
/// repeated in words beside it, so a row said *how* twice and *which CLI* not at
/// all.
///
/// Four CLIs, one state: every pair of renders must differ. Mutation-verified —
/// hardcoding `CLIMark.generic` in `SessionRow.body` (the shape of the bug this
/// exists to catch: a mark that is drawn but never varies) makes all six pairs
/// identical and fails with six messages. Before: passes. After: fails.
@MainActor @Test func theRowLeadsWithItsOwnCLIsMark() throws {
    let clis = ["claude-code", "codex", "gemini-cli", "aider"]
    let rasters = try clis.map { try row(session(.running, cli: $0)) }
    for i in clis.indices {
        for j in clis.indices where j > i {
            #expect(rasters[i].differingPixelCount(from: rasters[j]) > 0,
                    "`\(clis[i])` and `\(clis[j])` rendered identical rows — the leading mark does not vary with the CLI, so the row cannot say which agent it belongs to")
        }
    }
}

/// `CLIMark(cli:)`'s fallback is the whole reason the leading position can never
/// be empty. An unknown CLI is the *common* case for anything but the three
/// vendors named in the mockup.
@Test func anUnknownCLIStillGetsAMark() {
    #expect(CLIMark(cli: "claude-code") == .claude)
    #expect(CLIMark(cli: "Claude") == .claude)
    #expect(CLIMark(cli: "codex") == .codex)
    #expect(CLIMark(cli: "gemini-cli") == .gemini)
    #expect(CLIMark(cli: "aider") == .generic)
    #expect(CLIMark(cli: "") == .generic)
}

/// Every mark must actually be a *different shape*, which a table of four cases
/// that accidentally shares a path would not be. Compares the rendered glyph
/// alone, at the size the row draws it.
@MainActor @Test func everyMarkIsADistinctShape() throws {
    let rasters = try CLIMark.allCases.map { mark in
        try rasterise(CLIMarkView(mark: mark).frame(width: 16, height: 16))
    }
    for (i, m) in CLIMark.allCases.enumerated() {
        #expect(rasters[i].opaquePixelCount > 0, "\(m) drew nothing at all")
        for (j, n) in CLIMark.allCases.enumerated() where j > i {
            #expect(rasters[i].differingPixelCount(from: rasters[j]) > 0,
                    "\(m) and \(n) render identically — two of `MARKS`' four shapes were ported as the same path")
        }
    }
}

/// §4.3, and the one rule in this row that is not merely about appearance:
/// **shape says who, hue says what state, both on the same mark.**
///
/// The previous wave asserted the opposite of the first half of this — that the
/// mark's column must not change with the state at all — under an instruction not
/// to tint a mark by state, which it flagged as contradicting both §4.3's closing
/// sentence ("Everything tinted by the current state — **marks**, cat, badge,
/// counts, the aura — uses the same `--accent`") and `.mark{color:var(--accent)}`.
/// The instruction was withdrawn. What §4.3's "never by hue" actually forbids is
/// hue carrying **identity** — so the demand on the mark is that its *coverage* be
/// identical across states while its *colour* is not, which is two questions and
/// needs two measurements.
///
/// Mutation-verified, all three halves:
/// - `colour: Color(boneColour)` at the call site (the previous behaviour): the
///   mark's column differs by 0 pixels between waiting and failed, so the second
///   `#expect` fails. Before: 76 differing, passes.
/// - `CLIMarkView(mark: CLIMark(cli: session.cli), side: 12, colour: accent)` — a
///   mark whose *shape* moves with nothing but which no longer matches the other
///   render's coverage: the first `#expect` fails.
/// - Deleting the `Circle()` from `headline`: no solid 5×5 accent square survives
///   (the state's word alone cannot make one) and the third fails.
@MainActor @Test func theMarksShapeSaysWhoAndItsHueSaysWhatState() throws {
    let waiting = try row(session(.permission))
    let failed = try row(session(.failed))
    // 10pt of row padding, then the 16pt mark.
    let markColumns = 10..<26

    #expect(waiting.differingCoverageCount(from: failed, inColumns: markColumns) == 0,
            "the mark covered different pixels in a waiting row than in a failed one — its *shape* moved with the session's state, and shape is the only thing a person who cannot separate amber from red has to tell one agent from another")
    #expect(waiting.differingPixelCount(from: failed, inColumns: markColumns) > 0,
            "the mark's column is pixel-identical across two states — it is not tinted, so §4.3's `--accent` list and the mockup's `.mark{color:var(--accent)}` are both unhonoured")

    for (kind, state) in [(Kind.permission, IslandState.waiting),
                          (.failed, .failed), (.running, .running)] {
        #expect(try row(session(kind)).containsSolidSquare(of: state.accent, side: 5),
                "\(kind): no solid patch of \(state)'s accent anywhere in the row — the state's colour is carried by text alone, with no pip")
    }
}

// MARK: - The switch set

/// §11's own switch points. Turning a line off has to remove ink, not merely
/// stop reading a property — the failure this catches is an `Options` that is
/// threaded through and then ignored by the view.
@MainActor @Test func turningALineOffRemovesItsInk() throws {
    let s = session(.permission)
    let all = try row(s, options: .all)
    let bare = try row(s, options: [])
    #expect(bare.opaquePixelCount < all.opaquePixelCount,
            "switching every optional line off drew the same ink (\(bare.opaquePixelCount) against \(all.opaquePixelCount)) — Options is threaded through and then ignored")
    #expect(bare.opaquePixelCount > 0,
            "switching the optional lines off erased the row entirely — line 1 is not optional in §11")
}

/// The mockup's `${card.project ? s.proj : s.term}` — `.project` off
/// **substitutes** the terminal's name, it does not blank the field. Plan 6's
/// Settings sheet offers this switch; a row that goes blank when it is used is
/// not a row.
///
/// Mutation-verified in both directions. Ignoring `.project` (always showing
/// `session.project`) makes the first `#expect` fail. Blanking the field instead
/// of substituting makes the *second* fail — with no origin app there is nothing
/// to substitute, so a blanking implementation renders a headline the fallback
/// implementation does not. Before: passes. After: fails, one each.
@MainActor @Test func projectOffSubstitutesTheTerminalRatherThanBlanking() throws {
    var e = VibeEvent(id: "e", cli: "claude-code", kind: .running, session: "s",
                      cwd: "/Users/dev/api")
    e.origin = Origin(app: "com.googlecode.iterm2")
    let attributed = Session(event: e, now: t0)

    #expect(try row(attributed, options: .all)
        .differingPixelCount(from: try row(attributed, options: .all.subtracting(.project))) > 0,
            "`.project` off rendered the same headline — the switch is ignored, so Settings' Project toggle would do nothing")

    // No origin app: nothing to substitute, so the field must fall back to the
    // project rather than going empty.
    let anonymous = Session(event: VibeEvent(id: "e", cli: "claude-code", kind: .running,
                                             session: "s", cwd: "/Users/dev/api"), now: t0)
    #expect(try row(anonymous, options: .all)
        .differingPixelCount(from: try row(anonymous, options: .all.subtracting(.project))) == 0,
            "with no terminal to name, `.project` off changed the row — line 1's leading field went blank instead of falling back")
}

/// `metaLine` (mockup line 816) gates model and effort **individually**:
/// `bits = [s.term]`, then `card.model && s.model`, then `card.effort && s.effort`.
/// Ours had no switch for either.
///
/// Mutation-verified: gating `effort` on `.model` (the copy-paste mistake this
/// is for) makes `minusModel` and `minusEffort` render identically and the third
/// `#expect` fails; ignoring either bit makes its own `#expect` fail. Before:
/// all three pass. After: fails.
@MainActor @Test func modelAndEffortAreSwitchableOnTheirOwn() throws {
    let s = session(.running)
    let all = try row(s)
    let minusModel = try row(s, options: .all.subtracting(.model))
    let minusEffort = try row(s, options: .all.subtracting(.effort))

    #expect(all.differingPixelCount(from: minusModel) > 0,
            "hiding `.model` changed nothing — the meta line ignores the switch")
    #expect(all.differingPixelCount(from: minusEffort) > 0,
            "hiding `.effort` changed nothing — the meta line ignores the switch")
    #expect(minusModel.differingPixelCount(from: minusEffort) > 0,
            "hiding `.model` and hiding `.effort` produced the same row — both bits are gating the same field")
}

/// `.worktree`'s own single-bit probe — Plan 6.6's Task 4 named this gap:
/// `turningALineOffRemovesItsInk` above flips every bit at once, so it cannot
/// tell "`.worktree` gates its own field" apart from "the guard checks the
/// wrong bit entirely" (the same reasoning `eachBlockOptionGatesOnlyItsOwnBlock`
/// already gives for `.tasks`/`.agents` one level down).
///
/// Mutation-verified: gating the worktree `Text` on `.project` instead of
/// `.worktree` (the copy-paste shape this exists to catch — two fields on the
/// same headline) makes the first `#expect` fail, since hiding `.worktree`
/// would then change nothing.
@MainActor @Test func worktreeIsSwitchableOnItsOwn() throws {
    let s = session(.running)
    let all = try row(s)
    let minusWorktree = try row(s, options: .all.subtracting(.worktree))

    #expect(all.differingPixelCount(from: minusWorktree) > 0,
            "hiding `.worktree` changed nothing — the headline ignores the switch")
}

/// `.lastMessage`'s own single-bit probe, same reasoning as `.worktree`'s
/// above. **This is the switch `Session.lastUserMessage` has no producer
/// for** — see `Session.init`, which always sets it to `nil` — so this test's
/// fixture sets it by hand, the only way to exercise the switch at all. On
/// real data the row this switch gates is already absent, which
/// `SessionCardSection`'s own doc comment and this task's report both record.
///
/// Mutation-verified: dropping `options.contains(.lastMessage)` from
/// `SessionRow.body`'s `if` (always showing line 3 when `lastUserMessage` is
/// non-nil) makes the two renders identical and this fails.
@MainActor @Test func lastMessageIsSwitchableOnItsOwn() throws {
    var s = session(.running)
    s.lastUserMessage = "clean the build and rebuild from scratch"
    let all = try row(s)
    let minusLastMessage = try row(s, options: .all.subtracting(.lastMessage))

    #expect(all.differingPixelCount(from: minusLastMessage) > 0,
            "hiding `.lastMessage` changed nothing — line 3 ignores the switch")
}

// MARK: - The stored-preference conversion (Plan 6.6's Task 4)

/// `SessionRow.Options.init(_:)` is the re-thread's whole seam: `Preferences
/// .cardOptions` (nine named `Bool`s, `VibeCatCore`) has to become this
/// render-time `OptionSet` somewhere, and this is the one place it does. A
/// pure mapping test, not a render — the render-level proof that each bit
/// actually *gates* its own content is `SessionRowTests`' and
/// `SessionBlocksTests`' own per-flag probes; this is only "the right bit
/// came through", asked once per field so a transposed `if` in the
/// conversion itself (`stored.worktree` driving `.insert(.model)`, say) has
/// somewhere to fail.
///
/// Mutation-verified, one bit at a time: swapping any two of the nine `if`
/// bodies in `SessionRow.Options.init(_:)` makes exactly two of these nine
/// cases fail — the one whose bit should be set and isn't, and the one it
/// leaked into. Confirmed for all nine pairs adjacent in declaration order;
/// reverted after. See the task report.
@Test func theStoredCardOptionsConversionSetsExactlyOneBitPerField() {
    let allFields: [(WritableKeyPath<SessionCardOptions, Bool>, SessionRow.Options)] = [
        (\.activity, .activity), (\.lastMessage, .lastMessage), (\.tasks, .tasks),
        (\.agents, .agents), (\.subagents, .subagents), (\.project, .project),
        (\.worktree, .worktree), (\.model, .model), (\.effort, .effort),
    ]

    for (path, bit) in allFields {
        var stored = SessionCardOptions(activity: false, lastMessage: false, tasks: false,
                                        agents: false, subagents: false, project: false,
                                        worktree: false, model: false, effort: false)
        stored[keyPath: path] = true
        let converted = SessionRow.Options(stored)
        #expect(converted == bit,
                "turning on only `\(path)` in `SessionCardOptions` produced `\(converted)`, not exactly `\(bit)` — a bit is being crossed or dropped in `SessionRow.Options.init(_:)`")
    }
}

/// The all-true and all-false ends, so the loop above is not the only thing
/// standing between this test and vacuity.
@Test func theStoredCardOptionsConversionHandlesBothExtremes() {
    #expect(SessionRow.Options(SessionCardOptions()) == .all,
            "every field on produced \(SessionRow.Options(SessionCardOptions())), not `.all`")
    let allOff = SessionCardOptions(activity: false, lastMessage: false, tasks: false,
                                    agents: false, subagents: false, project: false,
                                    worktree: false, model: false, effort: false)
    #expect(SessionRow.Options(allOff) == [],
            "every field off produced \(SessionRow.Options(allOff)), not the empty set")
}

/// CARRIED FINDING (Task 6, review round 1): the reviewer temporarily hardcoded
/// `options: .all` at `SessionRow`'s `SessionBlocks(session:options:accent:)`
/// call site — dropping the forwarding of whatever `options` the row actually
/// received — and all 406 tests still passed. Neither this file's `session(_:)`
/// fixture (no tasks/agents, so `SessionBlocks` draws nothing regardless of
/// `options`) nor `SessionBlocksTests` (constructs `SessionBlocks` directly,
/// never going through `SessionRow`) could see the drop. This test goes
/// through `SessionRow` itself with a fixture that populates both, and fails
/// against exactly that mutation: with `options: .all` hardcoded, hiding
/// `.subagents` from the `SessionRow` call has no effect, so the two rasters
/// come out the same height instead of the collapsed one being shorter.
@MainActor @Test func sessionRowForwardsItsOptionsToSessionBlocks() throws {
    var e = VibeEvent(id: "e", cli: "claude-code", kind: .running, session: "s",
                      cwd: "/Users/dev/api")
    e.tasks = [TaskItem(title: "Audit authentication flow", status: .doing)]
    e.agents = [AgentItem(name: "Explore (Search API endpoints)", elapsed: "8s", model: "Sonnet 4.6"),
                AgentItem(name: "Explore (Read config files)", elapsed: "Done", model: "Sonnet 4.6",
                          finished: true)]
    let s = Session(event: e, now: t0)

    let all = try row(s, options: .all)
    let subagentsHidden = try row(s, options: .all.subtracting(.subagents))

    #expect(subagentsHidden.height < all.height,
            "hiding .subagents through SessionRow rendered the same height as .all — if the call site hardcodes `options: .all` instead of forwarding what it received, this passes no matter what the row was asked to show")
}

// MARK: - Line 2's two fields

/// The mockup's line 2 is `${s.act} <em>${s.code}</em>` — two fields, and the
/// command is the emphasised one (monospace, brighter ink) because in a list
/// whose job is triage at a glance "Asking to run" is boilerplate and
/// `rm -rf build/` is the thing you are being asked about. `Session.activity`
/// used to join them with a space, so no downstream view could tell them apart.
///
/// Three renders of the same words, differing only in which field they arrive
/// in, compared by how much of the command's own ink and how much **haze** (the
/// sentence's) each contains. A view that styled the two halves alike would put
/// the same amount of each in all three.
///
/// That ink is `commandColour` — `#B9C4D6` — and not `boneColour` as of the second
/// mockup-fidelity wave. `.ract em`'s hex is the only colour in the prototype's row
/// CSS that is neither a `--var` nor a state hue; substituting `--bone` kept the
/// emphasis and overstated it, letting line 2 claim the same weight as line 1's
/// project name. This test now measures the tier the field actually has, which is
/// also why it grew teeth it did not have: with both fields drawn in `--bone`, the
/// project name contributed to every count.
///
/// Mutation-verified: giving the command `hazeColour` and the sentence's font
/// makes the two counts collapse onto each other (39 → 0 of `commandColour` in
/// every render) and the first two `#expect`s fail.
@MainActor @Test func theCommandIsItsOwnEmphasisedFieldOnLineTwo() throws {
    func withActivity(_ activity: Session.Activity) throws -> Raster {
        var e = VibeEvent(id: "e", cli: "claude-code", kind: .running, session: "s",
                          cwd: "/Users/dev/api")
        e.title = activity.sentence
        e.body = activity.command
        return try row(Session(event: e, now: t0))
    }

    let split = try withActivity(.init(sentence: "Editing", command: "src/routes/pricing.tsx"))
    let sentenceOnly = try withActivity(.init(sentence: "Editing src/routes/pricing.tsx"))
    let commandOnly = try withActivity(.init(command: "Editing src/routes/pricing.tsx"))

    #expect(split.pixelCount(near: commandColour) > sentenceOnly.pixelCount(near: commandColour),
            "the same text drew no more of the command's ink when half of it arrived as the command (\(split.pixelCount(near: commandColour)) against \(sentenceOnly.pixelCount(near: commandColour))) — the command is not emphasised, so line 2 is one field again")
    #expect(commandOnly.pixelCount(near: commandColour) > sentenceOnly.pixelCount(near: commandColour),
            "a whole line 2 arriving as the command drew no more emphasis than one arriving as the sentence — the two fields are styled the same")
    #expect(split.pixelCount(near: hazeColour) > commandOnly.pixelCount(near: hazeColour),
            "the sentence contributed none of line 2's quieter ink — it is being drawn as the command is")
}

// MARK: - A running row's state is an elapsed time

/// The mockup's `SESSIONS` gives the running rows `state:'2m 14s'` with
/// `live:true`, not the word "Running". The other three keep their word.
///
/// A pure function, so this can assert the string rather than infer it from
/// pixels. Mutation-verified: returning `IslandState(session.state).label`
/// unconditionally fails the first `#expect`; returning the elapsed time
/// unconditionally fails the other three. Before: passes. After: fails.
///
/// The first expectation is against the **mockup's own literal** — `SESSIONS[1]`
/// carries `state:'2m 14s'` and this fixture is 134 seconds old — rather than
/// against `RevealContent.elapsed(134)`, which it used to be. Restating the call
/// the implementation makes cannot catch the implementation calling it with the
/// wrong granularity, and that is precisely the defect this wave fixed: the row
/// read `2m`. Mutation-verified separately: dropping `precision: .fine` from
/// `stateLabel` yields `2m` and fails.
@Test func onlyARunningRowShowsAnElapsedTimeAsItsState() {
    let now = t0.addingTimeInterval(134)
    #expect(SessionRow.stateLabel(for: session(.running), now: now) == "2m 14s",
            "a running row showed `\(SessionRow.stateLabel(for: session(.running), now: now))` where the mockup's own 134-second session shows `2m 14s`")
    #expect(SessionRow.stateLabel(for: session(.permission), now: now) == "Needs you")
    #expect(SessionRow.stateLabel(for: session(.failed), now: now) == "Failed")
    #expect(SessionRow.stateLabel(for: session(.done), now: now) == "Idle")
}

/// …and the view has to actually read it. A running row must change as `now`
/// advances; a waiting one must not, because its state is a word.
///
/// Mutation-verified: dropping `now` and using `Date()` inside `stateLabel`
/// makes both renders equal and the first `#expect` fails. Before: passes.
/// After: fails.
@MainActor @Test func aRunningRowsStateFieldAdvancesWithTheClock() throws {
    let running = session(.running)
    #expect(try row(running, now: t0)
        .differingPixelCount(from: try row(running, now: t0.addingTimeInterval(134))) > 0,
            "a running row rendered identically 134 seconds later — the row is not reading `now`, so a duration on screen would be frozen")

    let waiting = session(.permission)
    #expect(try row(waiting, now: t0)
        .differingPixelCount(from: try row(waiting, now: t0.addingTimeInterval(134))) == 0,
            "a *waiting* row changed with the clock — only `running` carries a duration in the mockup")
}

// MARK: - Three lines, never four

/// §11's own first words: "**Three** lines per row." A row whose project name
/// wraps is four, and nothing here checked it.
///
/// Found by the visual fixture Plan 5's final review added
/// (`VIBECAT_LIST_SHOT`) — the first time anyone had looked at the assembled
/// list, because `ImageRenderer` renders a `ScrollView` blank and only
/// `NSHostingView` + `cacheDisplay` does not (see `rasteriseHosted`).
/// `Session.project` is `cwd`'s last path component, so its length is entirely
/// the user's, and a monorepo package directory reaches this length easily.
///
/// Compares rendered *height* against a short-named row rather than looking for
/// the wrap directly: a wrap is exactly what adds a line box, and height is the
/// property §11's "three lines" is a claim about. Everything else about the two
/// fixtures is held identical, so height is the only thing that can move.
///
/// Mutation-verified: removing `.lineLimit(1)` from `SessionRow.headline`'s
/// project `Text` renders the long-named row at 66pt against the short one's
/// 51pt — one extra line box — and this test fails with that message.
@MainActor @Test func aLongProjectNameDoesNotAddAFourthLineToTheRow() throws {
    func rowFor(_ project: String) throws -> Raster {
        var e = VibeEvent(id: "e", cli: "claude-code", kind: .running, session: "s",
                          cwd: "/Users/dev/\(project)")
        e.title = "Asking to run"
        e.body = "rm -rf build/"
        return try row(Session(event: e, now: t0))
    }

    let short = try rowFor("api")
    let long = try rowFor("web-dashboard-with-a-really-quite-long-package-name")
    #expect(long.height == short.height,
            "a long project name rendered the row \(long.height)pt tall against \(short.height)pt for a short one — the name wrapped, so §11's three lines became four")
}

/// The same defect one line lower, found in the mockup-fidelity pass and **not**
/// on its list: line 3 shipped with `.lineLimit(2)`, so any last message longer
/// than the row was four lines. The mockup's `.rsaid` is `white-space:nowrap`
/// with an ellipsis, and §11 says three.
///
/// Mutation-verified: restoring `.lineLimit(2)` renders the long message at 82pt
/// against the short one's 68pt and this fails. Before: both 68pt, passes.
@MainActor @Test func aLongLastMessageDoesNotAddAFourthLineToTheRow() throws {
    func rowFor(_ message: String) throws -> Raster {
        var s = session(.running)
        s.lastUserMessage = message
        return try row(s)
    }

    let short = try rowFor("clean the build")
    let long = try rowFor("clean the build and rebuild it from scratch, then run the whole suite twice and tell me which tests flake")
    #expect(long.height == short.height,
            "a long last message rendered the row \(long.height)pt tall against \(short.height)pt — it wrapped, so §11's three lines became four")
}

// MARK: - The ink hierarchy

/// The prototype's text palette is **three** rungs — `--bone`, `--haze`, `--dim` —
/// and a row spends all three plus the command's own `#B9C4D6`. Until the second
/// mockup-fidelity wave we had two: everything below `--bone` was `hazeColour`,
/// which collapsed "a field you read" and "a field you refer back to" into one
/// weight and is why the assembled list read busier than the mockup it came from.
///
/// Measured on a **three-line row with no blocks**, and the first version of this
/// test — which used a fixture carrying both blocks — is the reason that matters:
/// repointing the *row's* `--dim` fields at `--haze` still left the blocks' four
/// `--dim` fields painting, so the count stayed above the floor and the test
/// passed against the defect it was written for. A test whose fixture can satisfy
/// it by a different route than the one under examination is not a test. The
/// blocks' own share of the tier is pinned separately, in `SessionBlocksTests`.
///
/// **`tolerance: 0`, at `scale: 2`**, and this is the second thing the first
/// version of this test got wrong. Antialiasing a glyph is a gradient from the
/// text's ink to the ground behind it, so it passes through *every* intermediate
/// colour — including the tier below. Measured: with the row's `--dim` fields
/// repointed at `--haze`, `pixelCount(near: dimColour)` at this file's usual
/// tolerance of 6 still reads **93**, purely from the edges of haze glyphs. At
/// tolerance 0 the same render reads 0 against 1451 for the correct one, because a
/// gradient may pass through a value but a glyph *core* is the only thing that
/// sits on it. Scale 2 for the reason `RevealContentTests` already gives: at
/// scale 1 an 11pt glyph anti-aliases so diffusely that its core is a couple of
/// dozen pixels.
///
/// Mutation-verified, once per tier: repointing this row's `dimColour` users at
/// `hazeColour` takes dim from 1451 to **0**, and the command at `boneColour`
/// takes that count from 386 to 0. Both fail.
@MainActor @Test func theRowSpendsAllFourOfItsInkTiers() throws {
    let raster = try rasterise(
        SessionRow(session: threeLineSession(), now: t0).frame(width: 388)
            .background(Color(islandGroundColour)), scale: 2)
    for (name, colour) in [("--bone (the project)", boneColour),
                           ("--haze (the sentence)", hazeColour),
                           ("--dim (the meta, the worktree, the last message)", dimColour),
                           ("#B9C4D6 (the command)", commandColour)] {
        let n = raster.pixelCount(near: colour, tolerance: 0)
        #expect(n > 100,
                "the row drew \(n) pixels of exactly \(name) — a tier of the prototype's ink ladder is missing, so two fields that should differ in weight are being drawn at the same one")
    }
}

/// `.rmeta` and `.rwt` are `font-family:ui-monospace` in the mockup, and the row
/// drew both in the sentence's proportional face.
///
/// Asserted by **behaviour rather than by restating a font descriptor**: a
/// monospaced right-aligned field starts at the same x whatever glyphs are in it,
/// and a proportional one moves. Eight `i`s against eight `m`s is the widest such
/// pair there is.
///
/// Mutation-verified: dropping `design: .monospaced` from the meta line's font
/// moves the field's left edge from 297/296 to **331/259** — 72pt apart — and this
/// fails. Before: 1pt apart, passes.
@MainActor @Test func theMetaColumnDoesNotMoveWithTheWidthOfItsGlyphs() throws {
    func metaStart(_ model: String) throws -> Int {
        var e = VibeEvent(id: "e", cli: "claude-code", kind: .running, session: "s",
                          cwd: "/tmp/api")
        e.model = model
        let raster = try row(Session(event: e, now: t0))
        // The right half only: the meta is the sole field there, since this
        // fixture carries no activity for line 2's left half to draw.
        var leftmost = raster.width
        for y in 0..<raster.height {
            for x in (raster.width / 2)..<raster.width where raster[x, y].a > 100 {
                leftmost = min(leftmost, x)
                break
            }
        }
        return leftmost
    }

    let narrow = try metaStart("iiiiiiii")
    let wide = try metaStart("mmmmmmmm")
    #expect(abs(narrow - wide) <= 2,
            "eight `i`s and eight `m`s put the meta field's left edge \(abs(narrow - wide))pt apart (\(narrow) against \(wide)) — it is drawn in a proportional face, so the column dances as a model name changes")
}

/// `.rsaid::before` — line 3's rule is a **1.5px drawn bar**, not a `│` inside the
/// string. A glyph takes the text's own ink; the bar takes 13% white, which no
/// text in the row uses.
///
/// The measurement is a *vertical run* of that composite rather than a count of
/// it: antialiasing a `--dim` glyph over the island's ground passes through the
/// same value in ones and twos, so a count alone would survive the glyph. A run of
/// ten pixels at one x would not.
///
/// **A row with no blocks**, for a reason that only showed up under mutation: a
/// task marker is a 9pt rounded square outlined in 22% white, and the antialiased
/// column along its own left edge is both the right colour and nine pixels tall.
/// With blocks in the fixture this test passed with line 3's rule reverted to a
/// glyph — it was measuring a task marker's border and calling it a rule.
///
/// Mutation-verified: restoring `Text("│ \(asked)")` in `dimColour` takes the run
/// from **13** to 0 and this fails. (`--dim`'s own longest run in the same render
/// is 8, which is what a glyph stem looks like — in the wrong colour.)
@MainActor @Test func lineThreesRuleIsADrawnBarAndNotAGlyph() throws {
    let raster = try rasterise(
        SessionRow(session: threeLineSession(), now: t0).frame(width: 388)
            .background(Color(islandGroundColour)))
    // `rgba(255,255,255,.13)` over `--void`, which is what the eye sees and
    // therefore what a raster can measure.
    let rule = RGBA(hex: "#26272B")!
    #expect(raster.longestVerticalRun(of: rule) >= 8,
            "the tallest run of 13%-white in the row is \(raster.longestVerticalRun(of: rule))px — line 3's rule is being drawn in the text's ink, so it is a character in the string rather than the mockup's bar")
}

// MARK: - Focusable, and legible when focused

/// `tabindex="0"`, `cursor:pointer`, `border-radius:9px`,
/// `.row:hover{background:rgba(255,255,255,.05)}` and
/// `.row:focus-visible{outline:2px solid var(--haze);outline-offset:-2px}` — **the
/// row had none of the five**, so the session list could not be reached from the
/// keyboard at all. The key-input spike settled that a non-activating panel does
/// receive keystrokes without stealing focus (Path A), which turned this from a
/// future concern into a present gap.
///
/// Three separate claims, because they fail separately:
/// - hover fills, and fills *inside a rounded corner* — the outermost corner pixel
///   stays clear while the top edge midway along does not, which is what a 9pt
///   radius is and pins it without restating the number;
/// - focus draws in the row's outermost 2pt, where no field ever draws;
/// - focus is not hover — a ring is not a fill.
///
/// Mutation-verified: deleting `.background` makes hover ink equal to plain
/// (53134 both ways) and the first fail; `RoundedRectangle(cornerRadius: 0)` puts
/// ink in the corner pixel and fails the second; deleting the `.overlay` takes
/// focus's border ink from 2328 to **0** and fails the fourth.
@MainActor @Test func aRowFillsUnderThePointerAndIsRingedWhenFocused() throws {
    let s = richSession()
    let plain = try row(s)
    let hovered = try row(s, highlight: .hovered)
    let focused = try row(s, highlight: .focused)

    #expect(hovered.opaquePixelCount > plain.opaquePixelCount,
            "the row drew the same ink under the pointer as at rest (\(hovered.opaquePixelCount) against \(plain.opaquePixelCount)) — there is no hover state, so nothing tells you which row you are about to click")
    #expect(hovered[0, 0].isTransparent && !hovered[hovered.width / 2, 0].isTransparent,
            "the hover fill reaches the row's very corner — it is a rectangle, not the mockup's 9pt rounded panel")

    #expect(plain.opaquePixelCount(inBorderOfWidth: 2) == 0,
            "an unfocused row already paints its outermost 2pt, so this test cannot tell a focus ring from a field that overflows")
    #expect(focused.opaquePixelCount(inBorderOfWidth: 2) > 0,
            "a focused row painted nothing in its outermost 2pt — there is no focus ring, so a keyboard user cannot see where they are")
    #expect(focused.pixelCount(near: hazeColour) > plain.pixelCount(near: hazeColour),
            "focusing the row drew no more `--haze` — whatever is in the border is not the mockup's `outline:2px solid var(--haze)`")
}
