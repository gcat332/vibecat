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

/// §10.2's rule, at this drawing site: **a number badge means the click is the
/// answer, a checkbox means it is not.** `ChoiceRow` already implements both and
/// picks on `isMulti`; this asserts the block passes the question's own `isMulti`
/// through rather than hardcoding one. A block that always drew badges would let a
/// multi-select question be committed by a single reflex click.
@MainActor @Test func aMultiSelectQuestionDrawsCheckboxesRatherThanBadges() throws {
    let single = try render(QuestionBlock(question: question(body: "cmd", multi: false),
                                          accent: .orange))
    let multi = try render(QuestionBlock(question: question(body: "cmd", multi: true),
                                         accent: .orange))
    #expect(single.differingPixelCount(from: multi) > 0,
            "isMulti was not passed through — both states drew the same control")
}

/// A person has to look at this: the tests above compare renders against each other
/// and none of them can say whether a `.rblock` full of choices actually *reads* at
/// this size inside a row. Env-gated, like the repo's other preview tools.
///
///     VIBECAT_QUESTION_BLOCK=/tmp/qb.png Scripts/test.sh --filter questionBlockSheet
@Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAT_QUESTION_BLOCK"] != nil))
@MainActor func questionBlockSheet() throws {
    let out = try #require(ProcessInfo.processInfo.environment["VIBECAT_QUESTION_BLOCK"])
    let long = "rm -rf /Users/dev/projects/vibecat/.build/arm64-apple-macosx/debug/ModuleCache/artifacts/tmp"
    let sheet = VStack(alignment: .leading, spacing: 14) {
        QuestionBlock(question: question(body: "rm -rf build/"), accent: Color(IslandState.waiting.accent))
        QuestionBlock(question: question(body: long), accent: Color(IslandState.waiting.accent))
        QuestionBlock(question: question(body: "rm -rf build/", multi: true),
                      accent: Color(IslandState.waiting.accent))
        QuestionBlock(question: question(body: long), accent: Color(IslandState.waiting.accent),
                      handedBackTo: "iTerm2")
        QuestionBlock(question: question(body: "rm -rf build/"), accent: Color(IslandState.waiting.accent),
                      handedBackTo: nil)
    }
    .frame(width: blockWidth)
    .padding(16)
    .background(Color(islandGroundColour))
    _ = try rasterise(sheet, scale: 2).writePNG(to: out)
    print("\nsheet -> \(out)  (single, single+long, multi, handed back, handed back unnamed)")
}

/// **A measurement, not an assertion — the number is here so a later reader does not
/// have to re-derive it.** A three-choice block is tall relative to the drawer it
/// sits in, because `ChoiceRow` was designed for the 288pt `.question` face and
/// carries that face's own type size and row height into a nested 11pt block.
@Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAT_QUESTION_BLOCK"] != nil))
@MainActor func questionBlockHeights() throws {
    for (label, block) in [
        ("answerable, 3 choices", QuestionBlock(question: question(body: "rm -rf build/"), accent: .orange)),
        ("answerable, 1 choice", QuestionBlock(question: question(body: "rm -rf build/", choices: 1), accent: .orange)),
        ("handed back", QuestionBlock(question: question(body: "rm -rf build/"), accent: .orange, handedBackTo: "iTerm2")),
    ] {
        let r = try rasterise(block.frame(width: blockWidth), scale: 1)
        print("  \(label.padding(toLength: 24, withPad: " ", startingAt: 0)) \(r.height)pt")
    }
    print("  DrawerFace.sessionList is \(DrawerFace.sessionList.height)pt tall in total")
}
