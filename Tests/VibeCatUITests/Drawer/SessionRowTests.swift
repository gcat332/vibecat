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
                            options: SessionRow.Options = .all) throws -> Raster {
    try rasterise(SessionRow(session: s, now: now, options: options).frame(width: 388))
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

    /// The leading `w` points of every scanline — the mark's own column.
    func differingPixelCount(from other: Raster, inLeading w: Int) -> Int {
        guard width >= w, other.width >= w, height == other.height else {
            return max(width * height, other.width * other.height)
        }
        var n = 0
        for y in 0..<height {
            for x in 0..<w where self[x, y] != other[x, y] { n += 1 }
        }
        return n
    }
}

/// §11's line 1 carries "Project, worktree, state" — and the state is carried
/// by colour (§4.3), so the row must paint the accent of the state it is in and
/// not of any other.
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
/// **hue means state, shape means identity.** So the mark's own column must be
/// pixel-identical between two sessions that differ only in state, and the
/// state's colour must appear as a *filled* pip at the other end of the line.
///
/// Mutation-verified, both halves:
/// - Passing `colour: accent` to `CLIMarkView` in `SessionRow.body`: the leading
///   column differs by 72 pixels between waiting and failed and the first
///   `#expect` fails. Before: 0 differing, passes. After: fails.
/// - Deleting the `Circle()` from `headline`: no solid 5×5 accent square
///   survives (the state's word alone cannot make one) and the second `#expect`
///   fails. Before: passes for all three states. After: fails for all three.
@MainActor @Test func stateColourLivesInThePipAndNeverInTheMark() throws {
    let waiting = try row(session(.permission))
    let failed = try row(session(.failed))
    #expect(waiting.differingPixelCount(from: failed, inLeading: 16) == 0,
            "the leading 16pt column changed with the session's state — the mark is tinted by state, so the row's first glyph says *how it is doing* where §4.3 puts *which agent it is*")

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
/// in, compared by how much **bone** (the command's ink) and how much **haze**
/// (the sentence's) each contains. A view that styled the two halves alike
/// would put the same amount of each in all three.
///
/// Mutation-verified: giving the command `hazeColour` and the sentence's font
/// makes the bone counts collapse onto each other and the first two `#expect`s
/// fail. Measured — before: bone 127 in `split`, 171 in `commandOnly`, 50 in
/// `sentenceOnly` (the project name, which all three share); haze 30 in `split`
/// against 0 in `commandOnly`. After: `split` bone falls to 50, exactly
/// `sentenceOnly`'s.
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

    #expect(split.pixelCount(near: boneColour) > sentenceOnly.pixelCount(near: boneColour),
            "the same text drew no more of the command's ink when half of it arrived as the command (\(split.pixelCount(near: boneColour)) against \(sentenceOnly.pixelCount(near: boneColour))) — the command is not emphasised, so line 2 is one field again")
    #expect(commandOnly.pixelCount(near: boneColour) > sentenceOnly.pixelCount(near: boneColour),
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
@Test func onlyARunningRowShowsAnElapsedTimeAsItsState() {
    let now = t0.addingTimeInterval(134)
    #expect(SessionRow.stateLabel(for: session(.running), now: now)
            == RevealContent.elapsed(134),
            "a running row showed a word where the mockup shows how long it has been running")
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
