import SwiftUI

/// `.rblock` — the container the mockup uses for *"tasks and subagents: the
/// session's own internals, one indent deeper"* (`island-motion.html:369-372`).
///
/// Extracted from `SessionBlocks`, where it was two `private func`s, because Plan 9
/// gives it a third caller: a parked question renders as one of these under its own
/// row. The alternative was re-deriving `margin-top:6px`, `rgba(255,255,255,.035)`,
/// `border-radius:7px` and `padding:7px 9px` in a second file, which is how a fixed
/// metric ends up fixed in one place and not the other.
///
/// **The mockup anticipated this caller.** `agentsHTML`'s own comment
/// (`island-motion.html:832`) reads *"hidden subagents collapse to a count —
/// approvals and questions would stay"*: a question belonging inside a session's
/// blocks was the design's intent and was simply never rendered.
struct RBlock<Content: View>: View {
    @ViewBuilder let content: () -> Content

    /// `.rblock{margin-top:6px;background:rgba(255,255,255,.035);border-radius:7px;
    /// padding:7px 9px}` — a **panel**, where an early version drew a `┌` and a `│`
    /// and called it a block.
    ///
    /// The box-drawing characters were not merely a different look. They put the
    /// block's own indentation inside the *text* of two different strings, so the
    /// header's `┌ ` and an item's marker were different glyph widths and the items
    /// landed about 5pt **left of their own header** — measured off the rendered
    /// list. One padding on one container cannot produce that, which is the argument
    /// for the panel over and above matching the reference.
    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.035)))
            .padding(.top, 6)
    }
}

/// `.bh{font-size:10.5px;color:var(--haze);padding-bottom:4px;gap:6px}` with
/// `.bh em{color:var(--dim)}` — the title is a field you read, the detail beside it
/// is one you refer back to, and that is the whole difference between the two ink
/// tiers.
struct RBlockHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color(hazeColour))
            Text(detail).font(.system(size: 10.5)).foregroundStyle(Color(dimColour))
        }
        .padding(.bottom, 4)
    }
}
