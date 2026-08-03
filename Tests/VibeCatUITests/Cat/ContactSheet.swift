import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

/// A developer tool, not a gate. Renders every badge and every coat × mood to
/// one PNG so the artwork can be judged by eye — the thing this project could
/// not do for three plans, and the reason `plain` shipped six cells different
/// from `tabby` with a passing test.
///
/// Off by default because it writes a file and asserts nothing:
///
///     VIBECAT_CONTACT_SHEET=/tmp/sheet.png swift test --filter contactSheet
///
/// Assertions belong in the golden tests beside this file. This is for eyes.
@Suite("Contact sheet")
struct ContactSheetTool {
    /// Big enough to judge a one-cell marking, which is 1pt on the real island.
    static let cell: CGFloat = 6
    static let scale: CGFloat = 2

    @MainActor
    static func sheet() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(IslandState.allCases, id: \.self) { state in
                    VStack(spacing: 4) {
                        BadgeCanvas(badge: Badge(state: state), phase: 0,
                                    tint: state.accent, cellSize: cell)
                        Text(Badge(state: state).rawValue)
                            .font(.system(size: 7)).foregroundStyle(.white)
                    }
                }
            }
            ForEach(Coat.allCases, id: \.self) { coat in
                HStack(alignment: .bottom, spacing: 10) {
                    Text(coat.rawValue)
                        .font(.system(size: 8)).foregroundStyle(.white)
                        .frame(width: 46, alignment: .leading)
                    ForEach(IslandState.allCases, id: \.self) { state in
                        // Phase 0.2 is mid-cycle: past any at-zero special case,
                        // short of trot's blink at 0.92.
                        CatCanvas(cat: ResolvedCat(coat: coat,
                                                   mood: CatMood(state: state),
                                                   phase: 0.2),
                                  palette: CatPalette(accent: state.accent),
                                  cellSize: cell)
                    }
                }
            }

            Text("Drawer").font(.system(size: 8)).foregroundStyle(.white)
            // Task 7's own four scenarios, named in its brief: single select
            // with a label long enough to need wrapping, multi select
            // mid-pick, the reply field open, and the destructive
            // confirmation. Rendered together so one look at the PNG can
            // judge all four rather than trusting four passing assertions.
            //
            // All four wear `.waiting`'s accent, not a mix — a permission
            // event (`Kind.permission`/`.question`) always maps to
            // `SessionState.waiting` (see `SessionState.init(kind:)`), and
            // `.waiting`'s urgency (0) always beats `.failed`'s (1, see
            // `SessionState.urgency`), so a real destructive confirmation
            // cannot legitimately be red. An earlier version of this used
            // `.failed`'s accent for the fourth scenario — `DrawerView.
            // accent` is a pure pass-through, so §4.3 was never actually
            // violated in code, but this fixture would have seeded a false
            // "destructive means red" convention in the one place this
            // artwork gets looked at.
            HStack(alignment: .top, spacing: 14) {
                DrawerView(question: singleSelectLongLabel(),
                          accent: IslandState.waiting.accent, width: 300)
                DrawerView(question: multiSelectMidPick(),
                          accent: IslandState.waiting.accent, width: 300)
                DrawerView(question: replyFieldOpen(),
                          accent: IslandState.waiting.accent, width: 300)
                DrawerView(question: destructiveConfirmation(),
                          accent: IslandState.waiting.accent, width: 300)
            }
        }
        .padding(12)
        .background(Color(red: 0.02, green: 0.027, blue: 0.043))
    }

    /// §10.1: a label real permission prompts actually produce, long enough
    /// that truncating it would hide which directory it grants. Also picks
    /// the *non*-recommended row (`deny`, not row 0): this is the scenario
    /// that caught `ChoiceRow`'s single-select badge ignoring `isSelected`
    /// entirely — every other fixture in this file only ever leaves the
    /// recommended row as the pick, where a stale render happens to look
    /// plausible anyway.
    @MainActor private static func singleSelectLongLabel() -> QuestionModel {
        let m = QuestionModel(event: VibeEvent(
            id: "sheet-1", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
            title: "Bash command", body: "pnpm install",
            choices: [Choice(id: "allow", label: "Allow once"),
                      Choice(id: "always", label: "Allow all pnpm commands in ~/dev/api for this session"),
                      Choice(id: "deny", label: "Deny")],
            wantsReply: true))
        m.pick("deny")
        return m
    }

    /// §10.2: one file already ticked, so the checkbox fill, the tally and
    /// Send's enabled look are all on screen at once.
    @MainActor private static func multiSelectMidPick() -> QuestionModel {
        let m = QuestionModel(event: VibeEvent(
            id: "sheet-2", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
            title: "Stage which files?", body: "git add",
            choices: [Choice(id: "a", label: "Sources/main.swift"),
                      Choice(id: "b", label: "Tests/Fixture.swift"),
                      Choice(id: "c", label: "README.md")],
            multi: true, wantsReply: true))
        m.toggle("a")
        return m
    }

    /// §10.1: `Other…` collapses the row list into this field.
    @MainActor private static func replyFieldOpen() -> QuestionModel {
        let m = QuestionModel(event: VibeEvent(
            id: "sheet-3", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
            title: "Bash command", body: "pnpm install",
            choices: [Choice(id: "allow", label: "Allow once"),
                      Choice(id: "deny", label: "Deny")],
            wantsReply: true))
        m.beginOther()
        m.otherText = "use pnpm instead"
        return m
    }

    /// §10.3: a permissive pick against a destructive body, before
    /// `confirm()` — the state the second ask has to make legible.
    @MainActor private static func destructiveConfirmation() -> QuestionModel {
        let m = QuestionModel(event: VibeEvent(
            id: "sheet-4", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
            title: "Bash command", body: "rm -rf build/",
            choices: [Choice(id: "allow", label: "Allow once"),
                      Choice(id: "deny", label: "Deny")],
            wantsReply: true))
        m.pick("allow")
        return m
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAT_CONTACT_SHEET"] != nil))
    @MainActor func contactSheet() throws {
        let path = ProcessInfo.processInfo.environment["VIBECAT_CONTACT_SHEET"]!
        let raster = try rasterise(Self.sheet(), scale: Self.scale)
        #expect(raster.writePNG(to: path), "could not write \(path)")
        print("contact sheet: \(raster.width)x\(raster.height) -> \(path)")
    }

    /// The whole `IslandView` as the panel actually composes it, in the four
    /// combinations of hover and drawer-open — the one thing the contact sheet
    /// above cannot show, because it renders the pieces rather than the
    /// composition.
    ///
    /// Added for Plan 5's Task 1, whose entire subject was a defect *between*
    /// two composed parts: the silhouette painted at the hover-coupled width
    /// while the drawer on top of it was hover-independent, so hovering with the
    /// drawer open left 150pt of ground down its right. Nothing that renders the
    /// drawer alone, or the island alone, can show that. Kept because the rest of
    /// Plan 5 puts a second face into the same composition.
    ///
    ///     VIBECAT_ISLAND_SHOT=/tmp/island.png swift test --filter islandShot
    @MainActor
    static func islandComposition() -> some View {
        func island(_ hovering: Bool, _ open: Bool) -> some View {
            let m = IslandModel(geometry: IslandGeometry(screen: IslandGoldenTests.mbp14),
                                motion: MotionPreference(chosen: .full, systemWantsReduced: false))
            // .idle, not a continuous mood: this is a still image, and a mood
            // with a timeline samples the real wall clock per render.
            m.state = .idle
            m.sessionCount = 3
            m.hovering = hovering
            if open {
                m.question = Self.singleSelectLongLabel()
                m.drawerOpen = true
            }
            return VStack(alignment: .leading, spacing: 4) {
                Text("hover \(hovering ? "on" : "off") · drawer \(open ? "open" : "closed")")
                    .font(.system(size: 10)).foregroundStyle(Color(hazeColour))
                IslandView(model: m)
            }
        }
        return HStack(alignment: .top, spacing: 12) {
            island(false, false)
            island(true, false)
            island(false, true)
            island(true, true)
        }
        .padding(12)
        .background(Color.black)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAT_ISLAND_SHOT"] != nil))
    @MainActor func islandShot() throws {
        let path = ProcessInfo.processInfo.environment["VIBECAT_ISLAND_SHOT"]!
        let raster = try rasterise(Self.islandComposition(), scale: Self.scale)
        #expect(raster.writePNG(to: path), "could not write \(path)")
        print("island composition: \(raster.width)x\(raster.height) -> \(path)")
    }

    /// §11's assembled session list, as `DrawerView` actually composes it — the
    /// one thing on Plan 5's whole branch that nobody had ever looked at.
    ///
    /// Task 7's step 4 asked for a line-by-line check against §11's diagram and
    /// could not get one: `ImageRenderer` paints a `ScrollView`'s content as
    /// fully transparent, so every render of this face came out blank (measured:
    /// a bare `Text` gives 165 opaque pixels, the same `Text` inside a
    /// `ScrollView` gives 0). Plan 5's final whole-branch review found the route
    /// — `NSHostingView` + `cacheDisplay(in:to:)`, still headless. See
    /// `rasteriseHosted`.
    ///
    ///     VIBECAT_LIST_SHOT=/tmp/list.png swift test --filter sessionListShot
    ///
    /// Four sessions, one per state, and every optional line populated on at
    /// least one of them — because §11's diagram is three lines plus a Tasks and
    /// an Agents block, and a fixture that leaves them nil shows a one-line row
    /// and proves nothing about the layout. The `.done` row deliberately carries
    /// *nothing* optional: §11's collapse behaviour and the divider spacing
    /// between a tall row and a short one is exactly the kind of thing only an
    /// eye catches.
    ///
    /// Rendered at `DrawerFace.sessionList.height` — the real 420pt, not a
    /// height that fits the content — so whether the last row clips at the face
    /// boundary is visible rather than hidden by an accommodating frame.
    /// The wall clock, sampled once.
    ///
    /// **Deliberately not a fixed epoch date, unlike every other fixture in this
    /// file.** `SessionListFace` reads its own `Date()` — that is the whole
    /// point of its `TimelineView`, and giving it a test-only injection point
    /// would bend production API for a fixture. So the *sessions* move to the
    /// clock instead: `sessionListFixture` stamps their `updatedAt` 134 seconds
    /// before this instant, which is what makes a running row's state field read
    /// `2m` (the mockup's `state:'2m 14s'`) rather than the `20656d` the old
    /// 1970-epoch fixture produced the first time this shot was opened after the
    /// state field became a duration.
    static let listShotNow = Date()

    /// One CLI per row, so the shot shows all four of `CLIMark`'s marks side by
    /// side — the leading position now carries *which agent*, and a fixture that
    /// gave every row `claude-code` would render four identical glyphs and show
    /// nothing about the one thing §4.3 puts there.
    @MainActor
    static func sessionListFixture() -> [Session] {
        func session(_ kind: Kind, _ project: String, worktree: String?,
                     rich: Bool, cli: String = "claude-code") -> Session {
            var e = VibeEvent(id: "list-\(project)", cli: cli, kind: kind,
                              session: "s-\(project)", cwd: "/Users/dev/\(project)")
            e.worktree = worktree
            if rich {
                e.model = "Opus 4.8"
                e.effort = "high"
                e.origin = Origin(app: "com.googlecode.iterm2")
                e.title = "Asking to run"
                e.body = "rm -rf build/"
                e.tasks = [TaskItem(title: "Audit authentication flow", status: .doing),
                           TaskItem(title: "Add refresh-token rotation", status: .open),
                           TaskItem(title: "Wire the session store", status: .done)]
                // `activity:` on the first agent only: §11's diagram nests one
                // `└ Grep: handleRequest` line under a *running* subagent and
                // none under the finished one, and `SessionBlocks.agentLine`
                // draws it only when the field is populated — so a fixture that
                // left it nil everywhere would show a block §11 has four lines
                // for as two, and look correct.
                e.agents = [AgentItem(name: "Explore (Search API endpoints)",
                                      elapsed: "8s", model: "Sonnet 4.6",
                                      activity: "Grep: handleRequest"),
                            AgentItem(name: "Explore (Read config files)",
                                      elapsed: "Done", model: "Sonnet 4.6", finished: true)]
            }
            var s = Session(event: e, now: Self.listShotNow.addingTimeInterval(-134))
            // Assigned on the `Session`, not the event, and that is the point:
            // `Session.init` hardcodes `lastUserMessage = nil` and no adapter
            // populates it, so §11's line 3 has never been drawn by anything
            // reachable from real input. This fixture is the only place it gets
            // looked at. See plans/README.md's Plan 5 carried findings.
            if rich { s.lastUserMessage = "clean the build and rebuild from scratch" }
            return s
        }
        return [session(.permission, "api", worktree: "auth-hardening", rich: true),
                session(.running, "web-dashboard-with-a-long-name",
                        worktree: "feature/redesign-the-settings-panel", rich: true,
                        cli: "codex"),
                session(.failed, "infra", worktree: nil, rich: true, cli: "gemini-cli"),
                session(.done, "scripts", worktree: nil, rich: false, cli: "aider")]
    }

    /// The assembled list at its real size, beside the one thing the list itself
    /// can no longer show: §11's collapse rule. `SessionListFace` has no
    /// `options` parameter any more (F10 — nothing ever passed one), so the only
    /// way to see "Subagents hidden collapses to a count rather than vanishing"
    /// is a `SessionRow` rendered directly. Both in one image, the same way the
    /// contact sheet above puts its four drawer scenarios side by side.
    @MainActor
    static func sessionListComposition() -> some View {
        let sessions = sessionListFixture()
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("§11 · the assembled list, real 420pt face")
                    .font(.system(size: 9)).foregroundStyle(Color(hazeColour))
                DrawerView(question: nil, sessions: sessions,
                           accent: IslandState.waiting.accent, width: 388)
            }
            VStack(alignment: .leading, spacing: 12) {
                // All four of `MARKS`, at the 16pt the row draws them, because
                // the 420pt face beside this clips after two rows and the two it
                // shows are `claude` and `codex` — `gemini` and `generic` would
                // never be looked at otherwise.
                VStack(alignment: .leading, spacing: 4) {
                    Text("§4.3 · shape says which agent — CLIMark, ported from MARKS")
                        .font(.system(size: 9)).foregroundStyle(Color(hazeColour))
                    HStack(spacing: 14) {
                        ForEach(CLIMark.allCases, id: \.self) { mark in
                            HStack(spacing: 5) {
                                CLIMarkView(mark: mark)
                                Text(mark.rawValue)
                                    .font(.system(size: 9)).foregroundStyle(Color(hazeColour))
                            }
                        }
                    }
                }
                Text("§11 · Subagents hidden — collapses to a count")
                    .font(.system(size: 9)).foregroundStyle(Color(hazeColour))
                SessionRow(session: sessions[0], now: listShotNow,
                           options: .all.subtracting(.subagents))
                    .frame(width: 388)
                    .background(Color(islandGroundColour))
            }
        }
        .padding(12)
        .background(Color(red: 0.02, green: 0.027, blue: 0.043))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAT_LIST_SHOT"] != nil))
    @MainActor func sessionListShot() throws {
        let path = ProcessInfo.processInfo.environment["VIBECAT_LIST_SHOT"]!
        // Sized to hold both panels: the drawer's own 420pt face plus this
        // composition's label and padding. `rasteriseHosted` needs an explicit
        // size — a hosting view has no `sizeThatFits` step here, and this is a
        // fixture, so a measured-once number with the reason written down beats
        // machinery.
        let raster = try rasteriseHosted(Self.sessionListComposition(),
                                         size: CGSize(width: 828, height: 460))
        #expect(raster.writePNG(to: path), "could not write \(path)")
        #expect(raster.opaquePixelCount > 0,
                "the composition rendered nothing at all — if this is 0, `rasteriseHosted` has stopped working and the PNG is not worth opening")
        print("session list: \(raster.width)x\(raster.height) -> \(path)")
    }

    /// A filmstrip: every badge across one full cycle, one column per sampled
    /// phase. Shows which frames actually *differ* — which is the point, since
    /// `squares` has four distinct frames and is drawn twelve times a second,
    /// and `bang` has two.
    ///
    ///     VIBECAT_FILMSTRIP=/tmp/strip.png swift test --filter badgeFilmstrip
    @MainActor
    static func filmstrip() -> some View {
        let steps = 12
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(IslandState.allCases, id: \.self) { state in
                let badge = Badge(state: state)
                HStack(spacing: 6) {
                    Text(badge.rawValue)
                        .font(.system(size: 8)).foregroundStyle(.white)
                        .frame(width: 52, alignment: .leading)
                    ForEach(0..<steps, id: \.self) { i in
                        BadgeCanvas(badge: badge, phase: Double(i) / Double(steps),
                                    tint: state.accent, cellSize: cell)
                    }
                    Text(badge.motion.isContinuous
                         ? "\(Int(badge.motion.framesPerSecond))fps · \(badge.motion.cycle)s"
                         : "still")
                        .font(.system(size: 7)).foregroundStyle(.gray)
                }
            }
        }
        .padding(12)
        .background(Color(red: 0.02, green: 0.027, blue: 0.043))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAT_FILMSTRIP"] != nil))
    @MainActor func badgeFilmstrip() throws {
        let path = ProcessInfo.processInfo.environment["VIBECAT_FILMSTRIP"]!
        let raster = try rasterise(Self.filmstrip(), scale: Self.scale)
        #expect(raster.writePNG(to: path))
        print("filmstrip: \(raster.width)x\(raster.height) -> \(path)")
        for state in IslandState.allCases {
            let b = Badge(state: state)
            let frames = Set((0..<48).map { "\(b.cells(at: Double($0) / 48.0))" })
            print("  \(b.rawValue): \(frames.count) distinct frame(s)")
        }
    }

    /// The badges actually moving.
    ///
    ///     VIBECAT_GIF=/tmp/badges.gif swift test --filter badgeAnimation
    ///
    /// `BadgeCanvas`'s pulse is a SwiftUI implicit animation run by the render
    /// server, and `ImageRenderer` captures one static frame — so the scale and
    /// opacity are sampled here along the same easeInOut curve, over the same
    /// period, rather than captured. `phase` is real, so `squares` and `bang`
    /// turn their own cells as they do in the app. What this shows is the
    /// declared motion composed together, not a recording of it.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAT_GIF"] != nil))
    @MainActor func badgeAnimation() throws {
        let path = ProcessInfo.processInfo.environment["VIBECAT_GIF"]!
        let steps = 56
        let span = 2.8                        // the longest period, so all loop
        func easeInOut(_ t: Double) -> Double {
            t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t)
        }
        let side = Self.cell * 2 * CGFloat(Badge.size)
        var frames: [Raster] = []
        for i in 0..<steps {
            let now = Double(i) / Double(steps) * span
            let row = HStack(alignment: .center, spacing: 18) {
                ForEach(IslandState.allCases, id: \.self) { state in
                    let badge = Badge(state: state)
                    let p = badge.pulse
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(badge.parts(at: (now / badge.motion.cycle)
                            .truncatingRemainder(dividingBy: 1)).enumerated()),
                                id: \.offset) { _, part in
                            // Each part on its own delay, exactly as
                            // BadgeCanvas declares it — autoreverses, so one leg
                            // of a triangle wave per half period.
                            let local = ((now - part.delay) / p.period)
                                .truncatingRemainder(dividingBy: 1)
                            let wrapped = local < 0 ? local + 1 : local
                            let tri = wrapped < 0.5 ? wrapped * 2 : (1 - wrapped) * 2
                            let e = easeInOut(tri)
                            Canvas { ctx, _ in
                                ctx.fill(BadgeCanvas.path(part.cells, Self.cell * 2),
                                         with: .color(Color(state.accent)))
                            }
                            .frame(width: side, height: side)
                            .scaleEffect(p.scale.lowerBound + (p.scale.upperBound - p.scale.lowerBound) * e)
                            .opacity(p.opacity.lowerBound + (p.opacity.upperBound - p.opacity.lowerBound) * e)
                            .offset(y: p.rise / 2 - p.rise * e)
                        }
                    }
                    .frame(width: side * 1.3, height: side * 1.6)
                }
            }
            .padding(18)
            .background(Color(red: 0.027, green: 0.031, blue: 0.039))
            frames.append(try rasterise(row, scale: 2))
        }
        #expect(writeAnimatedGIF(frames, secondsPerFrame: span / Double(steps), to: path))
        print("gif: \(frames.count) frames -> \(path)")
    }
}
