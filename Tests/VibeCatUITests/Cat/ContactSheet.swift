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
        let steps = 40
        let seconds = 2.8                       // the longest period, so all loop cleanly
        func easeInOut(_ t: Double) -> Double {
            t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t)
        }
        var frames: [Raster] = []
        for i in 0..<steps {
            let t = Double(i) / Double(steps)
            let row = HStack(alignment: .center, spacing: 16) {
                ForEach(IslandState.allCases, id: \.self) { state in
                    let badge = Badge(state: state)
                    // Its own period, and autoreverses — so one leg of the
                    // triangle wave over half the period, back over the other.
                    let p = badge.pulse
                    let local = p.map { (t * seconds).truncatingRemainder(dividingBy: $0.period) / $0.period } ?? 0
                    let tri = local < 0.5 ? local * 2 : (1 - local) * 2
                    let e = easeInOut(tri)
                    let scale = p.map { $0.scale.lowerBound + ($0.scale.upperBound - $0.scale.lowerBound) * e } ?? 1
                    let alpha = p.map { $0.opacity.lowerBound + ($0.opacity.upperBound - $0.opacity.lowerBound) * e } ?? 1
                    BadgeCanvas(badge: badge,
                                phase: (t * seconds / badge.motion.cycle)
                                    .truncatingRemainder(dividingBy: 1),
                                tint: state.accent, cellSize: Self.cell * 2)
                        .scaleEffect(scale)
                        .opacity(alpha)
                        .frame(width: Self.cell * 2 * CGFloat(Badge.size) * 1.2,
                               height: Self.cell * 2 * CGFloat(Badge.size) * 1.2)
                }
            }
            .padding(16)
            .background(Color(red: 0.027, green: 0.031, blue: 0.039))
            frames.append(try rasterise(row, scale: 2))
        }
        #expect(writeAnimatedGIF(frames, secondsPerFrame: seconds / Double(steps), to: path))
        print("gif: \(frames.count) frames -> \(path)")
    }
}
