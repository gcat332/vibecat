import CoreGraphics
import Foundation
import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

/// **The right flank while a drawer is open** — `island-motion.html:474–476` and
/// `:115–118`. Plan 6.3 Task 6; found by Task 1, which recorded that "the
/// prototype right-aligns it and shows a label where we show a number".
@Suite("Open right flank")
struct OpenFlankTests {
    @MainActor private static func permission(cli: String) -> QuestionModel {
        QuestionModel(event: VibeEvent(id: "q", cli: cli, kind: .permission, session: "s",
                                      cwd: "/tmp/proj", title: "Bash command", body: "pnpm install",
                                      choices: [Choice(id: "allow", label: "Allow once"),
                                                Choice(id: "deny", label: "Deny")],
                                      wantsReply: true))
    }

    @MainActor private static func sessions(_ n: Int, cli: String = "claude-code") -> [Session] {
        (0..<n).map {
            Session(event: VibeEvent(id: "e\($0)", cli: cli, kind: .running,
                                     session: "s\($0)", cwd: "/Users/dev/p\($0)"),
                    now: Date(timeIntervalSince1970: 1_000_000))
        }
    }

    /// **What the label says, per face.** The prototype's own two strings:
    /// `Claude Code` on `ask`/`askmulti`, `4 sessions` on `list`.
    ///
    /// The singular is ours and is asserted because it is the one thing here a
    /// reader cannot check against the mockup — it has only its own four-session
    /// fixture.
    ///
    /// Would fail if: the label were keyed to something other than the face (a
    /// question's name showing over a list, or the count showing over a question);
    /// if the count came from `model.sessionCount` — the *collapsed* tally, which is
    /// a different number from the rows the list actually holds, and the fixture
    /// below sets them apart deliberately; or if the pluralisation went away.
    @MainActor @Test func theLabelIsTheCLIsNameForAQuestionAndTheRowCountForTheList() {
        let m = IslandGoldenTests.model(.waiting, count: 7)
        m.sessions = Self.sessions(3)
        let view = IslandBody(model: m, now: Date(timeIntervalSince1970: 1_000_000))

        // A count of 7 against 3 rows: the label describes the list, not the tally.
        #expect(view.openLabel(face: .sessionList) == "3 sessions",
                "the list's label is '\(view.openLabel(face: .sessionList))' where the list holds 3 rows and the collapsed tally says 7 — it is reading the wrong number")

        m.sessions = Self.sessions(1)
        #expect(view.openLabel(face: .sessionList) == "1 session",
                "a one-row list reads '\(view.openLabel(face: .sessionList))'")
        m.sessions = []
        #expect(view.openLabel(face: .sessionList) == "0 sessions")

        m.question = Self.permission(cli: "claude-code")
        for face in [DrawerFace.question, .questionWithReply, .questionMulti] {
            #expect(view.openLabel(face: face) == "Claude Code",
                    "the \(face) face's label is '\(view.openLabel(face: face))', not the prototype's 'Claude Code'")
        }
    }

    /// **The mark is the question's own CLI, and `generic` for the list.**
    ///
    /// `generic` for a list is the prototype's own choice (`data-face="list"
    /// data-mark="generic"`) rather than a fallback, and the fixture makes that
    /// distinguishable: every session in it is `claude-code`, so a mark derived from
    /// the rows would read `.claude` and this fails.
    ///
    /// Would fail if: an unknown CLI stopped falling back to `generic` (the
    /// `deploy.sh` case, which is §3's "an unknown CLI still gets a mark"); or if
    /// the list started claiming one CLI's identity.
    @MainActor @Test func theMarkIsTheQuestionsCLIAndGenericForAList() {
        let m = IslandGoldenTests.model(.waiting, count: 3)
        m.sessions = Self.sessions(4, cli: "claude-code")
        let view = IslandBody(model: m, now: Date(timeIntervalSince1970: 1_000_000))

        #expect(view.openMark(face: .sessionList) == .generic,
                "a list of four claude-code sessions took the \(view.openMark(face: .sessionList)) mark; the prototype's list face is data-mark=\"generic\" because a list can hold several CLIs and no one mark is true of it")

        for (cli, expected) in [("claude-code", CLIMark.claude), ("codex-cli", .codex),
                                ("gemini", .gemini), ("deploy.sh", .generic)] {
            m.question = Self.permission(cli: cli)
            #expect(view.openMark(face: .question) == expected,
                    "\(cli) took the \(view.openMark(face: .question)) mark, not \(expected)")
        }
    }

    /// The name in words, and **the honest fallback**. `CLIMark.displayName`'s own
    /// doc comment says why this table exists at all rather than reading
    /// `SourceAdapter.displayName`.
    ///
    /// Would fail if: `generic` started returning a made-up word instead of the wire
    /// value, which is the property that keeps an unsupported CLI legible; or if a
    /// version suffix stopped resolving (`claude-code-2` must still be Claude Code,
    /// which is `CLIMark(cli:)`'s substring rule and the reason this is keyed off it).
    @Test func theDisplayNameFallsThroughToTheWireValueForAnUnknownCLI() {
        #expect(CLIMark.displayName(cli: "claude-code") == "Claude Code")
        #expect(CLIMark.displayName(cli: "claude") == "Claude Code")
        #expect(CLIMark.displayName(cli: "codex-cli") == "Codex")
        #expect(CLIMark.displayName(cli: "gemini-cli") == "Gemini")
        #expect(CLIMark.displayName(cli: "deploy.sh") == "deploy.sh",
                "an unknown CLI was renamed to '\(CLIMark.displayName(cli: "deploy.sh"))' instead of showing what it called itself")
        // `ClaudeCodeAdapter.displayName` is the authority this stands in for, so it
        // has to agree with it — the one compile-checked link between the two.
        #expect(CLIMark.displayName(cli: ClaudeCodeAdapter().id) == ClaudeCodeAdapter().displayName,
                "the stand-in table disagrees with the adapter it stands in for")
    }

    /// **It is right-aligned, 15pt from the island's own right edge** — measured off
    /// the render, not read off the padding constant.
    ///
    /// The prototype's number is 15pt, measured in a browser as the gap from the
    /// island's right edge to the label's. Ours is a `Text`, so the ink stops a
    /// fraction inside its own advance width (the right side bearing of an "s" or an
    /// "e"); the tolerance below is that bearing and nothing else, and it is
    /// deliberately too tight to shrug off the alternative spellings — a flank
    /// *left*-aligned after the cutout would put the label ~250pt from the edge, and
    /// `RightFlankLayout.trailingPadding`'s 12 would read 12.
    ///
    /// Would fail if: the `Spacer` were dropped (the label packs against the
    /// cutout); if the trailing padding were taken from the collapsed flank's 12pt;
    /// or if the mark and label swapped order, which moves the accent ink to the
    /// outside.
    @MainActor @Test func theOpenFlankIsRightAlignedAtThePrototypes15pt() throws {
        let scale: CGFloat = 2
        let m = IslandGoldenTests.model(.waiting, count: 3)
        m.sessions = Self.sessions(4)
        m.drawerOpen = true
        guard case .drawer = m.tier else {
            Issue.record("the fixture never reached the drawer tier")
            return
        }
        let raster = try rasterise(IslandView(model: m), scale: scale)
        let body = IslandFrames(body: m.frames.body, panel: m.panelFrames.panel).bodyInPanel

        /// The outermost column within the collapsed bar's rows holding ink near
        /// `colour`, as a distance in points from the body's own right edge.
        func gapFromRightEdge(near colour: RGBA, tolerance: Int = 24) -> CGFloat? {
            let target = (Int((colour.r * 255).rounded()), Int((colour.g * 255).rounded()),
                          Int((colour.b * 255).rounded()))
            let bottom = min(raster.height, Int((m.geometry.notch.height * scale).rounded()))
            let edge = Int((body.maxX * scale).rounded())
            for x in stride(from: edge - 1, through: 0, by: -1) {
                for y in 0..<bottom {
                    let p = raster[x, y]
                    guard p.a > 0 else { continue }
                    if abs(Int(p.r) - target.0) <= tolerance,
                       abs(Int(p.g) - target.1) <= tolerance,
                       abs(Int(p.b) - target.2) <= tolerance {
                        return CGFloat(edge - x) / scale
                    }
                }
            }
            return nil
        }

        let label = try #require(gapFromRightEdge(near: boneColour),
                                 "no --bone ink anywhere in the collapsed bar of an open island — the label did not draw")
        // **15 as a literal, and the constant pinned separately below.** Reading
        // `OpenFlankLayout.trailingPadding` on both sides of this comparison would
        // make it evidence that the constant reaches the pixels and evidence about
        // nothing else — retuning it to 12 would move the render with it and stay
        // green. `Raster.Pixel(_:)`'s own doc comment records the general version of
        // this trap, which cost this suite four wrongly-pinned colours once.
        #expect(label >= 15 && label <= 17,
                "the label's ink stops \(label)pt from the island's right edge against the prototype's measured 15pt")

        let mark = try #require(gapFromRightEdge(near: IslandState.waiting.accent),
                                "no accent ink in the collapsed bar of an open island — the mark did not draw")
        #expect(mark > label,
                "the accent mark (\(mark)pt from the edge) is outside the label (\(label)pt) — they are in the wrong order; island-motion.html puts the mark first and the label against the edge")
    }

    /// **The four numbers, against the prototype rather than against each other.**
    /// The other half of `theOpenFlankIsRightAlignedAtThePrototypes15pt`: that test
    /// proves 15 reaches the pixels, and this says where 15 came from. Measured in a
    /// browser on the running mockup, `list` state: `.mark` 16×16, `.label`
    /// `margin-left: 9px` at `font-size: 12.5px`, and the label's right edge 15pt
    /// from the island's.
    @Test func theOpenFlanksFourNumbersAreThePrototypes() {
        #expect(IslandBody.OpenFlankLayout.markSide == 16,
                "the mark is \(IslandBody.OpenFlankLayout.markSide)pt against .mark{width:16px}")
        #expect(IslandBody.OpenFlankLayout.gap == 9,
                "the mark-to-label gap is \(IslandBody.OpenFlankLayout.gap)pt against .label{margin-left:9px}")
        #expect(IslandBody.OpenFlankLayout.trailingPadding == 15,
                "the label sits \(IslandBody.OpenFlankLayout.trailingPadding)pt from the island's right edge against the prototype's measured 15")
        #expect(IslandBody.OpenFlankLayout.labelSize == 12.5,
                "the label is \(IslandBody.OpenFlankLayout.labelSize)pt against .label{font-size:12.5px}")
        // Not the collapsed flank's own trailing padding: they are different rules
        // from different selectors (`.flank.r` vs `.flank .face.r`) and equalising
        // them is the likeliest way this drifts.
        #expect(IslandBody.OpenFlankLayout.trailingPadding != IslandBody.RightFlankLayout.trailingPadding,
                "the open flank and the collapsed flank now share a trailing padding; the prototype gives them 15 and 12")
    }
}
