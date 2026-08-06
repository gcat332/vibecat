import Foundation
import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

/// The row's real inner width: `DrawerFace.sessionList` is 560pt wide and
/// `SessionRow` insets 10pt each side, with the 16pt mark and its 10pt gap
/// indenting the block further. Rounded to 500 rather than fitted — the tests below
/// compare renders against each other at one width, so the exact number only has to
/// be realistic, and a fitted number would rot the moment the drawer's width moves.
private let blockWidth: CGFloat = 500

@MainActor private func question(body: String, choices: Int = 3, multi: Bool = false) -> QuestionModel {
    QuestionModel(event: VibeEvent(
        id: "q1", cli: "claude-code", kind: .permission, session: "s", cwd: "/tmp/proj",
        title: "Allow this command?", body: body,
        choices: (0..<choices).map { Choice(id: "c\($0)", label: "Choice \($0)") },
        multi: multi, wantsReply: true))
}

@MainActor private func render(_ block: QuestionBlock) throws -> Raster {
    try rasterise(block.frame(width: blockWidth).background(Color(islandGroundColour)), scale: 2)
}

/// **The rule with a measured history behind it, re-asserted at a new drawing site.**
/// `QuestionFace` sets `.truncationMode(.middle)` because before it did,
/// `…/build/cache/tmp` and `…/build/cache/src` rendered at **exactly 0 differing
/// pixels** at production width — a person asked to authorise `rm -rf` could not see
/// what it was aimed at. A second view that draws the same command is a second
/// chance to get that wrong, so it gets its own assertion rather than inheriting a
/// guarantee from a different file.
@MainActor @Test func aLongCommandInABlockKeepsTheTargetBeingAuthorised() throws {
    // **Long enough to actually truncate**, which the first version of this test was
    // not. At 500pt and 11pt monospace roughly 73 characters fit, so a 48-character
    // command rendered in full and `.middle` versus `.tail` made no difference at
    // all: the mutation that replaces one with the other survived. The head below is
    // 89 characters before the tail, so the ellipsis is forced and *which end* it
    // eats is the only thing left to observe.
    let head = "rm -rf /Users/dev/projects/vibecat/.build/arm64-apple-macosx/debug/ModuleCache/artifacts/"
    #expect(head.count > 80, "the head must overflow 500pt or this test proves nothing")
    let a = try render(QuestionBlock(question: question(body: head + "tmp"), accent: .orange))
    let b = try render(QuestionBlock(question: question(body: head + "src"), accent: .orange))
    #expect(a.differingPixelCount(from: b) > 0,
            "two commands differing only in their target rendered identically")
}

/// The same rule in the handed-back state, which is where it matters *most*: this is
/// the state a person reads immediately before walking to a terminal to approve
/// something. Losing the target here is worse than losing it beside the choices,
/// because there is nothing else on screen to check it against.
@MainActor @Test func theHandedBackStateAlsoKeepsTheTarget() throws {
    let head = "rm -rf /Users/dev/projects/vibecat/.build/arm64-apple-macosx/debug/ModuleCache/artifacts/"
    func handedBack(_ tail: String) throws -> Raster {
        try render(QuestionBlock(question: question(body: head + tail), accent: .orange,
                                 handedBackTo: "iTerm2"))
    }
    #expect(try handedBack("tmp").differingPixelCount(from: handedBack("src")) > 0,
            "the handed-back block dropped the command's target")
}

/// **Ruling C's two states.** The handed-back block loses its choices — the hook is
/// gone, so there is nothing here to answer — and gains one line naming where the
/// question went.
///
/// Asserted on height rather than on a colour count: the answerable state draws
/// three `ChoiceRow`s, the handed-back state draws one line of text, so the block
/// must be materially shorter. A colour assertion would be the weaker test here,
/// because both states draw the same haze and dim ink and the difference is
/// structural.
@MainActor @Test func theHandedBackStateDropsTheChoicesForOneLine() throws {
    let answerable = try render(QuestionBlock(question: question(body: "rm -rf build/"),
                                              accent: .orange))
    let handedBack = try render(QuestionBlock(question: question(body: "rm -rf build/"),
                                              accent: .orange, handedBackTo: "iTerm2"))
    #expect(handedBack.height < answerable.height,
            "the handed-back block is no shorter than one with three choices in it")
}

/// And it names the terminal it went to, not a generic phrase — the row's own
/// `metaLine` already prints `iTerm2`, so the block can be specific and the person
/// knows which window to reach for.
///
/// Two renders differing in exactly one input, which is the only way to assert on
/// text without reading a glyph: the same block with a different terminal name must
/// differ, and a block that hardcoded "the terminal" would come back identical.
@MainActor @Test func theHandedBackLineNamesTheTerminalItWentTo() throws {
    let a = try render(QuestionBlock(question: question(body: "rm -rf build/"),
                                     accent: .orange, handedBackTo: "iTerm2"))
    let b = try render(QuestionBlock(question: question(body: "rm -rf build/"),
                                     accent: .orange, handedBackTo: "Ghostty"))
    #expect(a.differingPixelCount(from: b) > 0,
            "the handed-back line ignored which terminal the question went to")
}

/// A fallback for a session whose origin app is unknown — `Session.origin.app` is
/// optional, so the name genuinely can be absent, and the line still has to say
/// something true. It must not silently render "Waiting for you in " either.
@MainActor @Test func anUnknownTerminalStillProducesALine() throws {
    let named = try render(QuestionBlock(question: question(body: "rm -rf build/"),
                                         accent: .orange, handedBackTo: "iTerm2"))
    let unnamed = try render(QuestionBlock(question: question(body: "rm -rf build/"),
                                           accent: .orange, handedBackTo: nil))
    #expect(unnamed.height == named.height, "the unnamed case lost or gained a line")
    #expect(unnamed.differingPixelCount(from: named) > 0, "the terminal's name was never drawn")
}

/// §10.2's rule, at this drawing site: **a number badge means the click is the answer, a
/// checkbox means it is not.** A block that always drew badges would let a multi-select
/// question be committed by one reflex click.
///
/// **Rewritten after a test-premise audit caught it passing for the wrong reason.** It
/// used to rasterise the whole block at both `isMulti` values and require the renders to
/// differ. They do — but at `sendRow`, which only a multi-select block draws. Forcing
/// `isMulti: false` on the `ChoiceRow` call, the actual §10.2 violation, left the suite
/// **entirely green**, and the failure message ("both states drew the same control")
/// would have been a lie.
///
/// So this asserts on the model instead of on pixels. `QuestionModel.tap(_:)` is the one
/// implementation both drawing sites share, and its behaviour *is* the rule: a
/// single-select tap produces a `Reply` because the click is the answer, and a
/// multi-select tap produces none because a checkbox only toggles. That distinction
/// cannot be satisfied by a difference somewhere else on screen.
@MainActor @Test func aSingleSelectTapAnswersWhileAMultiSelectTapOnlyToggles() {
    let single = question(body: "cmd", multi: false)
    #expect(single.tap("c0") != nil, "a single-select tap did not answer — §10.2's badge promises it does")
    #expect(single.selected == ["c0"])

    let multi = question(body: "cmd", multi: true)
    #expect(multi.tap("c0") == nil, "a multi-select tap answered on its own — a checkbox must only toggle")
    #expect(multi.selected == ["c0"])
    #expect(multi.tap("c1") == nil)
    #expect(multi.selected == ["c0", "c1"], "the second tick replaced the first instead of adding to it")
    #expect(multi.send()?.choices == ["c0", "c1"], "Send is the only gesture that finishes a multi-select")
}

/// And the block passes the question's own `isMulti` through to its `ChoiceRow`s, which
/// is the wiring half the model test above cannot see.
///
/// **This needs a crop, and the reason is the whole lesson of the audit that found the
/// first version.** `isMulti` legitimately drives *two* things — the control's shape and
/// whether `sendRow` exists — so comparing whole renders proves only that one of them
/// changed. The first version did exactly that, and hardcoding `isMulti: false` on the
/// `ChoiceRow` call, the actual §10.2 violation, left the whole suite green because
/// `sendRow` still differed.
///
/// **Measured with `qbProbe` below, at `scale: 2` and one choice** (kept env-gated so the
/// numbers are reproducible rather than remembered): the two renders are byte-identical
/// above `y = 84` — header and command — differ by 140 pixels between 84 and 104, which
/// is the control itself, and by 548 by `y = 124`, where `sendRow` has begun. So 104 is
/// the last row that still separates the control from everything else, and it is a
/// measurement rather than a derivation.
@MainActor @Test func theBlockPassesIsMultiThroughToItsChoiceRows() throws {
    let badge = try render(QuestionBlock(question: question(body: "cmd", choices: 1, multi: false),
                                        accent: .orange))
    let box = try render(QuestionBlock(question: question(body: "cmd", choices: 1, multi: true),
                                       accent: .orange))
    var differing = 0
    for y in 0..<104 {
        for x in 0..<badge.width where badge[x, y] != box[x, y] { differing += 1 }
    }
    #expect(differing > 0,
            "above sendRow the two renders are identical, so isMulti never reached ChoiceRow")
}


@Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAT_QB_PROBE"] != nil))
@MainActor func qbProbe() throws {
    let a = try render(QuestionBlock(question: question(body: "cmd", choices: 1, multi: false), accent: .orange))
    let b = try render(QuestionBlock(question: question(body: "cmd", choices: 1, multi: true), accent: .orange))
    print("\n  single \(a.width)x\(a.height)   multi \(b.width)x\(b.height)")
    for cut in [a.height - 20, a.height - 40, a.height - 60] {
        var d = 0
        for y in 0..<max(0, cut) { for x in 0..<a.width where a[x, y] != b[x, y] { d += 1 } }
        print("  cut at \(cut): differing = \(d)")
    }
}
