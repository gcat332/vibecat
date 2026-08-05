import SwiftUI
import VibeCatCore

/// One page's chrome: `settings.html`'s `.content` box (`:66`), its `.ptitle`
/// (`:69-70`) and — for as long as the page has no controls — a note naming the
/// plan that owns them.
///
/// **Plan 6.4 ships chrome and no controls**, so every pane says which plan its
/// controls belong to. `SettingsPage.ownerNote(for:)` holds the words; this draws
/// them in the prototype's own `.note`-inside-a-`.group` (`:73`, `:188-190`),
/// which is the vehicle `settings.html` already uses for a paragraph of
/// explanation sitting in a card. An empty pane that looks finished gets filed as
/// a bug; one that says "Plan 6.6 owns this" gets filed as a schedule.
///
/// Two deliberate divergences from the prototype, both consequences of a pane
/// with nothing in it yet:
///
/// - **No `h2` section heading.** `settings.html` gives every group one, but a
///   heading over a note that explains the absence of controls would be naming a
///   section that does not exist. The headings arrive with the controls, in
///   6.5–6.7.
/// - **No `box-shadow:inset 0 1px 0 var(--line)` on the note.** `.note` carries
///   that top hairline (`:189`) because in the prototype a note always follows a
///   `.row` and the line divides the two. Here the note is the group's only
///   child, so the line would divide it from nothing — `.group > .row:first-child
///   {box-shadow:none}` (`:75`) is the prototype making exactly this exemption,
///   for `.row` only because a lone `.note` never happens there.
///
/// **No `ScrollView`.** Nothing on any pane yet is tall enough to need one, and
/// `ImageRenderer` cannot render a `ScrollView` at all (`Raster.swift`) — so
/// adding one now would trade every golden assertion in
/// `SettingsSidebarTests.swift` for a scroll behaviour no content exercises. The
/// pages that will need one are 6.5's and 6.6's, and `rasteriseHosted` is what
/// they will have to use. **Plan 6.5's page is now one of them** — see
/// `NotificationsPane`'s own doc comment for the measured height and why it
/// still does not add one.
struct SettingsPaneView: View {
    let page: SettingsPage

    /// The Notifications page's controls. **Not optional, deliberately.** A
    /// `nil` here would compile in `main.swift` and draw an empty Notifications
    /// pane in the shipped app while every test that passed its own model stayed
    /// green — the exact shape of the "persisted but never read" defect this plan
    /// has now recorded five times. Requiring it means the compiler asks the
    /// question at every call site, including the one no test can run.
    let notifications: NotificationsPaneModel
    /// The Display page's controls, Plan 6.6. Same reasoning as `notifications`
    /// above, restated because it is the second time this file has had to hold a
    /// page's model non-optionally rather than let a forgotten call site compile
    /// its way to an empty pane.
    let display: DisplayPaneModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // `.ptitle{display:flex;align-items:center;gap:10px;padding-bottom:18px}`
            HStack(spacing: 10) {
                // The same chip the sidebar row draws, from the same
                // `SettingsPage` — `settings.html:532`'s "the pane headings reuse
                // the sidebar's icon so the two always agree", done the way that
                // comment asks rather than by declaring the glyph twice.
                SettingsChip(page: page)
                // `.ptitle h1{font-size:17px;font-weight:600;letter-spacing:-.02em}`
                // — `-.02em` at 17pt is `-0.34pt`, which is what `tracking`
                // takes (points, not ems).
                Text(page.label)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.34)
                    .foregroundStyle(Color(SettingsPalette.bone))
            }
            .padding(.bottom, 18)

            // Two pages have controls now; the other two still say which plan
            // owns theirs. `SettingsPageKey.notifications`/`.display`, not
            // literals — the same keys decide `ownerNote(for:)`'s silence, and a
            // literal in both places is how one of them stops matching.
            if page.key == SettingsPageKey.notifications {
                // **The first page in this window that does not fit, and it has
                // to scroll — measured, not assumed.** The three groups render
                // 771pt tall inside a content area 552pt high (620 less
                // `.content`'s own 20/28 padding and the 42pt heading). Without a
                // scroller a `VStack` whose children exceed the proposal overflows
                // *centred*: the rendered pane lost its `.ptitle` entirely — the
                // chip's own colour appeared at no pixel in a 704×620 render, and
                // three existing chip assertions in `SettingsSidebarTests` went
                // red. That is a real bug, found exactly the way Plan 6.4's
                // doubly-flexible `Rectangle` was, and it is why `SettingsPaneView`
                // — not `NotificationsPane` — owns the `ScrollView`: the heading
                // must stay put and the rows must move under it.
                //
                // `ImageRenderer` renders a `ScrollView`'s content as fully
                // transparent (`Raster.swift`), so every golden assertion about
                // these rows renders `NotificationsPane`, `AlertsSection` or
                // `ElsewhereSection` directly instead of going through this pane —
                // and the heading, being outside the scroller, is still visible to
                // the chip tests that measure it here.
                ScrollView {
                    NotificationsPane(model: notifications)
                }
            } else if page.key == SettingsPageKey.display {
                // The same shape as the `notifications` branch above, and for the
                // identical reason: four groups plus the live preview render
                // taller than the 552pt content area, so this page gets the
                // scroller too rather than an overflowed, centred `VStack` losing
                // its own heading a second time. See `DisplayPaneTests` for the
                // rendered rows, driven directly against `DisplayPane` rather than
                // through this `ScrollView` for the same `ImageRenderer` reason
                // the comment above gives.
                ScrollView {
                    DisplayPane(model: display)
                }
            } else if let note = SettingsPage.ownerNote(for: page.key) {
                ownerNote(note)
            }
            Spacer(minLength: 0)
        }
        // `.content{padding:20px 24px 28px}`
        .padding(.top, 20)
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// `.group` (`settings.html:73`) holding one `.note` (`:188-190`): a `2pt`
    /// blue rule, a `9pt` gap, `11.5pt` haze text, `10/14` padding, on a `--card`
    /// ground with a `10pt` radius.
    private func ownerNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            // `.note i{width:2px;border-radius:2px;background:var(--blue)}`. The
            // one place `--blue` appears on these panes, and it means "read
            // this", not any session state — see `SettingsPalette`'s own note on
            // why the token is spelled `systemBlue` here.
            //
            // In CSS this is a flex item with no height of its own, so it
            // stretches to the line the text sets. A SwiftUI `Rectangle` is
            // flexible in *both* axes, which is not the same thing: rendered
            // without the `fixedSize` below, it grew to the pane's full height
            // and dragged the whole `.group` card with it — a 500pt tall card
            // holding two lines of text. Seen in the render, not reasoned about.
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(SettingsPalette.systemBlue))
                .frame(width: 2)
            Text(text)
                .font(.system(size: 11.5))
                // `line-height:1.55` at 11.5pt, which Chrome resolves to a
                // `17.825px` line box. `lineSpacing` is not that number: it is the
                // gap *between* lines, and CSS also puts half its leading above the
                // first line and below the last. Both halves were measured here
                // rather than guessed — two renders of this same note, `lineSpacing`
                // 4 then 5.8, gave `.group` cards of 52 and 54pt, and
                // `2L + spacing + 20` fits both only at `L = 14`. So the system
                // font's own line height at 11.5pt is 14, and `3.8` is what makes
                // the *baseline pitch* 17.8 — the rhythm a reader actually sees.
                //
                // **Consequence, recorded rather than chased:** the card lands 52pt
                // tall against the prototype's measured 55.64, because CSS's
                // half-leading pads outside the first and last lines and
                // `lineSpacing` cannot. Matching the block height instead would
                // need `7.65`, which would space the lines visibly wider apart than
                // the prototype does. Pitch wins.
                .lineSpacing(3.8)
                .foregroundStyle(Color(SettingsPalette.haze))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        // The text is the only thing here with a height of its own; this is what
        // makes the row take it. See the rule's own comment above.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // `border-radius:10px` — a CSS radius is circular, so this is
            // `RoundedRectangle`'s default `.circular` style rather than
            // `.continuous`. Apple's squircle is the more macOS-native shape and
            // it is *not* what the prototype draws; a divergence here would be
            // one nobody had decided.
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(SettingsPalette.card))
        }
    }
}

/// The sidebar and the selected pane, side by side on the window's own ground —
/// `settings.html:205-207`'s `.body{display:flex}` holding `.side` and
/// `.content`.
///
/// Separate from `SettingsRootView` so a test can drive `selection` directly with
/// a `Binding` instead of building a `SettingsWindowModel` and an `NSWindow` to
/// change one string. `SettingsRootView` is then only the bridge from the
/// observable model to this, which is the part that cannot be rasterised.
struct SettingsShell: View {
    @Binding var selection: String
    /// Handed straight to `SettingsPaneView` — see that type's own note on why
    /// this is not an optional.
    let notifications: NotificationsPaneModel
    /// Same reasoning as `notifications`, for the Display page.
    let display: DisplayPaneModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            SettingsSidebar(selection: $selection)
            // An unknown key resolves to the first page rather than to an empty
            // content area: `SettingsWindowController.init` already clamps what it
            // reads from the store, so reaching this fallback means something
            // wrote a key no pane answers to, and the honest response is still to
            // draw a page. See `SettingsPage.page(for:)` on why the fallback is
            // not inside that lookup.
            SettingsPaneView(page: SettingsPage.page(for: selection) ?? SettingsPage.all[0],
                             notifications: notifications, display: display)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // `.win{background:var(--bg)}` — the ground the panes sit on. The
        // sidebar paints its own `--pane` over its 196pt.
        .background(Color(SettingsPalette.background))
    }
}
