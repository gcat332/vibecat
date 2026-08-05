import SwiftUI
import VibeCatCore

/// `settings.html:490+`'s live preview card — `.cardpreview`, a black card sitting
/// under the Session card group's eight switches — so the switches show their
/// effect immediately instead of asking someone to imagine it from a label. Plan
/// 6.6's Task 6.
///
/// **This *is* `SessionRow`, not a second view built to look like it.** A preview
/// that re-implemented the row's three lines and two blocks would drift from the
/// real one the first time either changed; embedding the actual view means every
/// one of the eight switches is proven to work by the same code path the drawer
/// itself runs; if it did not, the drawer would already have broken.
///
/// **One divergence from the prototype's own markup, deliberate:** `.cardpreview`
/// draws its own `padding:11px 12px` inside the black card, and this does not add
/// a second one — `SessionRow` already carries its own `8/10` padding, and adding
/// the prototype's on top would pad the identical content twice for no reason
/// beyond matching a number. Only the *outer* `margin:12px 14px 14px` is kept,
/// because that is spacing between the card and the group around it, which
/// `SessionRow` has no opinion about.
///
/// **A second divergence, also deliberate:** the prototype's `.cp1` carries its
/// own `.live` pip beside the project name — a decorative "this reflects your
/// choices" marker, always the idle green, unconnected to the row's own state.
/// Reproducing it would mean forking `SessionRow`'s headline to splice one more
/// element in before the project name, which is exactly the re-implementation
/// this type exists to avoid. `SessionRow` already draws its own state pip next
/// to its own state label, and that reads as "this row is live" well enough on
/// its own — so the pip is dropped rather than forked in.
struct SessionCardPreview: View {
    let options: SessionRow.Options
    /// Threaded through rather than read from `Date()` inside `body`, so a test
    /// can pin what the row's elapsed-time field shows — the same reason
    /// `SessionRow` itself takes `now:` instead of calling the clock, and
    /// `SessionListFace` supplies it from a `TimelineView`'s own context date.
    var now: Date = Date()

    var body: some View {
        SessionRow(session: previewSession, now: now, options: options)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .padding(.top, 12)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
    }

    /// `settings.html`'s own `.cp1` example — `vibecat`, worktree `chat-ui`,
    /// `Opus 5 · XHigh`, "Editing `chatEndpoint.ts`", the same three tasks (one
    /// done, one in progress, one open) and the same two agents (one running,
    /// one finished) — matched field for field where `SessionRow` has a field to
    /// put it in.
    ///
    /// **`lastUserMessage` is deliberately left `nil`.** `SessionCardSection`'s
    /// own doc comment already records that no adapter anywhere populates this
    /// field on a real session; a preview that faked a value here would show
    /// `Show Your Last Message` doing something no real session ever does. This
    /// is "the honest place to show that `lastMessage` has nothing to show" the
    /// plan asks for — toggling that switch on real data changes nothing, and
    /// toggling it here changes nothing too, for the same reason.
    ///
    /// Built from `now`, not a frozen date: `updatedAt` sits exactly 12 seconds
    /// before `now`, which is what makes the running row's elapsed-time field
    /// read the same duration the prototype's own copy does ("· 12s") on every
    /// render, however much wall-clock time has passed since the pane opened —
    /// rather than a number that grows for as long as Settings stays open.
    /// Same visibility reasoning as `SoundSectionModel.lastPlayedCueForTesting`:
    /// internal rather than private, purely so `SessionCardPreviewTests` can
    /// assert on the fixture's own fields — in particular that
    /// `lastUserMessage` really is `nil` — without duplicating the fixture by
    /// hand and risking the copy drifting from what `body` actually renders.
    var previewSessionForTesting: Session { previewSession }

    private var previewSession: Session {
        var event = VibeEvent(id: "preview", cli: "claude-code", kind: .running,
                              session: "preview", cwd: "/Users/dev/vibecat")
        event.worktree = "chat-ui"
        event.model = "Opus 5"
        event.effort = "XHigh"
        event.origin = Origin(app: "Ghostty")
        event.title = "Editing"
        event.body = "chatEndpoint.ts"
        event.tasks = [
            TaskItem(title: "Audit authentication flow", status: .doing),
            TaskItem(title: "Add regression coverage", status: .open),
            TaskItem(title: "Map session state", status: .done),
        ]
        event.agents = [
            AgentItem(name: "Explore (Search API endpoints)", elapsed: "8s",
                      model: "Sonnet 4.6", activity: "Grep: handleRequest"),
            AgentItem(name: "Explore (Read config files)", elapsed: "Done",
                      model: "Sonnet 4.6", finished: true),
        ]
        return Session(event: event, now: now.addingTimeInterval(-12))
    }
}
