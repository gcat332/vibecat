import SwiftUI

/// `settings.html:73`'s `.group`: the `--card` ground every row in this window
/// sits on, `10pt` corners, `18pt` clear below before whatever comes next.
///
/// **A recorded divergence, not a silent one.** `settings.html:75` adds
/// `.group > .row:first-child{box-shadow:none}` — the first row in a real
/// group does not draw the top hairline `.row` otherwise always carries,
/// because there is nothing above it to divide from. This type does not
/// implement that exemption: `SettingsGroup`'s `content` is opaque
/// (`some View`, built by an arbitrary `@ViewBuilder`), so there is no clean
/// way for the group to know which child came first without a
/// `_VariadicView` reflection this task did not reach for. Concretely, the
/// first row of a real multi-row group will show a redundant line right at
/// the card's own rounded top edge, which is not what `settings.html` draws.
/// `aRowsTopHairlineIsTheBlendOfThePrototypesEightPercent` in
/// `SettingsRowTests.swift` in fact depends on the *unconditional* draw — a
/// lone row wrapped in a group is that row's own first-child case, and the
/// test expects to see the hairline anyway. Task 7's browser diff is the
/// right place to decide whether this is worth a `_VariadicView` fix or an
/// acceptable one-pixel discrepancy against the card's own edge.
public struct SettingsGroup<Content: View>: View {
    let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(SettingsPalette.card))
        // `border-radius:10px` is CSS's circular radius, not Apple's squircle —
        // see `SettingsChip`'s own note on the same choice.
        .clipShape(RoundedRectangle(cornerRadius: 10))
        // `margin-bottom:18px`. Carried on the group itself, not on whoever
        // stacks groups together, so a page that lists several of these in a
        // zero-spacing `VStack` gets the prototype's gap for free.
        .padding(.bottom, 18)
    }
}

/// The detail line's measured typography — pulled out of `SettingsRow` itself
/// because a generic type cannot carry a static stored property.
private enum SettingsRowMetrics {
    /// The system font's own line height at `11.5pt`, measured (not assumed)
    /// against `SettingsPaneView.ownerNote`'s technique. A CSS property, not a
    /// font metric — see `SettingsRow`'s own doc comment.
    static let measuredSystemLineHeightAt11_5pt: CGFloat = 14
    /// `line-height:1.45` at `11.5px` — Chrome's pitch, in points.
    static let detailPitch: CGFloat = 11.5 * 1.45
    /// The gap `lineSpacing` needs to hit that pitch, given the font's own
    /// line height above. `16.675 − 14 = 2.675`, rounded to the precision the
    /// measurement in `SettingsRowTests.swift` actually supports.
    static let detailLineSpacing: CGFloat = detailPitch - measuredSystemLineHeightAt11_5pt
}

/// `settings.html:74`'s `.row`: a label pair on the left, one arbitrary
/// control on the right, transcribed rather than approximated — see the
/// table in this task's plan section for the line-by-line source.
///
/// **Two measured traps, both from Plan 6.4, repeated here because this is
/// where they first apply to a second value:**
///
/// - `SettingsPalette.hairline` is stored as opaque white; `RGBA` carries no
///   alpha. The `.08` half of `settings.html:14`'s `rgba(255,255,255,.08)`
///   lives in `SettingsPalette.hairlineOpacity`, applied here exactly the way
///   `SettingsSidebar`'s border already does.
/// - `line-height:1.45` at `11.5px` is not `.lineSpacing(1.45)`.
///   `SettingsPaneView.ownerNote` measured this system's own line height at
///   `11.5pt` to be `14pt` (two renders of a wrapped `.note`, `lineSpacing` 4
///   then 5.8, only fit a `2L + spacing + 20` card at `L = 14`). This task
///   measured the same `L` again against this row's own detail text — two
///   renders at `lineSpacing` 0 and 4, wrapped to four lines, gave block
///   heights 56 and 68, and `4L = 56` with `4L + 3·spacing = 68` both agree
///   only at `L = 14`. So hitting this row's `1.45` pitch (`16.675pt`) takes
///   `lineSpacing(2.675)` — confirmed by rendering, not by arithmetic alone.
///   `SettingsRowMetrics` computes it from the two measured constants rather
///   than storing the result, so the derivation stays visible in the source.
public struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String?
    let isNew: Bool
    let control: () -> Control

    public init(_ title: String, detail: String? = nil, isNew: Bool = false,
                @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.detail = detail
        self.isNew = isNew
        self.control = control
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // `.lab{flex:1;min-width:190px}`
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    // `.lab b{font-size:13px;font-weight:400;letter-spacing:-.01em}`
                    // — `-.01em` at 13pt is `-0.13pt`, which `tracking` takes in
                    // points, the same conversion `SettingsPaneView`'s `h1` uses.
                    Text(title)
                        .font(.system(size: 13, weight: .regular))
                        .tracking(-0.13)
                        .foregroundStyle(Color(SettingsPalette.bone))
                    if isNew {
                        NewBadge()
                    }
                }
                if let detail {
                    // `.lab > span{font-size:11.5px;color:var(--haze);
                    // padding-top:3px;line-height:1.45}`
                    Text(detail)
                        .font(.system(size: 11.5))
                        .lineSpacing(SettingsRowMetrics.detailLineSpacing)
                        .foregroundStyle(Color(SettingsPalette.haze))
                        .padding(.top, 3)
                        // Without this the block is flexible in both axes and
                        // grows to whatever height its container proposes —
                        // the same shape of bug `SettingsPaneView.ownerNote`'s
                        // rule already documents for its own text.
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minWidth: 190, maxWidth: .infinity, alignment: .leading)

            // `.ctlarea{flex:none;gap:8px}`
            HStack(spacing: 8) {
                control()
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            // `box-shadow:inset 0 1px 0 var(--line)` — see this type's own doc
            // comment on the first-row exemption this does not implement, and
            // `SettingsGroup`'s doc comment on the same trade.
            Rectangle()
                .fill(Color(SettingsPalette.hairline).opacity(SettingsPalette.hairlineOpacity))
                .frame(height: 1)
        }
    }
}

/// `settings.html:72`'s `h2`: a group's own section title, the same `.new`
/// badge `SettingsRow` offers, and no card of its own — `h2` sits above a
/// `.group`, not inside one.
public struct SettingsSectionHeading: View {
    let text: String
    let isNew: Bool

    public init(_ text: String, isNew: Bool = false) {
        self.text = text
        self.isNew = isNew
    }

    public var body: some View {
        HStack(spacing: 7) {
            // `h2{font-size:12px;font-weight:600;color:var(--bone);
            // letter-spacing:-.01em}` — `-.01em` at 12pt is `-0.12pt`.
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .tracking(-0.12)
                .foregroundStyle(Color(SettingsPalette.bone))
            if isNew {
                NewBadge()
            }
        }
        // `padding:0 2px 8px` — top 0, right/left 2, bottom 8.
        .padding(.horizontal, 2)
        .padding(.bottom, 8)
    }
}

/// `settings.html:82`'s `.new`: `9.5px` uppercase text at `.06em` tracking
/// (`0.57pt` at this size), a `1px` border at 45% of the same green, `4pt`
/// corners, `1/5` padding. Shared by `SettingsRow` and `SettingsSectionHeading`
/// because both draw exactly this mark and neither should carry a second,
/// hand-copied definition of it.
///
/// **The one legitimately state-coloured mark in this sheet besides the two
/// state pills** the Global Constraints call out — and, like them, it is not
/// reached from `IslandState`. See `SettingsPalette.newBadge`'s own doc
/// comment for why the token lives there instead.
private struct NewBadge: View {
    var body: some View {
        Text("NEW")
            .font(.system(size: 9.5))
            .tracking(9.5 * 0.06)
            .foregroundStyle(Color(SettingsPalette.newBadge))
            .padding(.vertical, 1)
            .padding(.horizontal, 5)
            .overlay {
                // `border:1px solid color-mix(in srgb,var(--idle) 45%,transparent)`
                // — CSS's `color-mix` against transparent is just the colour at
                // 45% alpha, the same shape of half-fact `SettingsPalette.hairline`
                // already needs a caller-applied opacity for.
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(SettingsPalette.newBadge).opacity(0.45), lineWidth: 1)
            }
    }
}
