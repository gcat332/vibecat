import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

extension Color {
    init(_ c: RGBA) { self.init(red: c.r, green: c.g, blue: c.b) }
}

/// The right flank's session-count font: `swiftUI` (used by the rendered
/// `Text` in `IslandBody.rightFlank`) and `measuredDigitWidth()` (used by
/// `CollapsedLayout.Metrics.standard`) are two independent constructions
/// kept in step deliberately, side by side in one declaration instead of
/// scattered across the file.
///
/// Only `size` is actually shared, so only `size` is compiler-enforced.
/// SwiftUI's `Font.Weight` and AppKit's `NSFont.Weight` are unrelated types
/// with no bridge between them, so `weight` and `design` are each spelled
/// out once per API rather than derived from one value — "semibold" and
/// "rounded" say the same thing in both places today, but nothing stops
/// one from being edited without the other. Change either, and change both.
enum RightFlankFont {
    static let size: CGFloat = 12
    static let swiftUI: Font = .system(size: size, weight: .semibold, design: .rounded)

    #if canImport(AppKit)
    /// AppKit's equivalent of `swiftUI`, used only to measure a digit's real
    /// advance width — `.monospacedDigitSystemFont` bakes in the same
    /// tabular-figure feature `Text.monospacedDigit()` applies on the
    /// SwiftUI side, verified by measuring "0" through "9" and finding
    /// identical widths.
    ///
    /// Not held as a stored `NSFont`: `NSFont` is a non-`Sendable` class, so
    /// a persistent `static let` of one trips Swift 6's global-mutable-state
    /// check. Returning a plain `CGFloat` instead means nothing but a
    /// number outlives this call — `Metrics.standard` below still measures
    /// exactly once, since a `static let`'s initialiser runs a single time.
    static func measuredDigitWidth() -> CGFloat {
        let monospaced = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        let font = monospaced.fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: size) } ?? monospaced
        return ("0" as NSString).size(withAttributes: [.font: font]).width
    }
    #endif
}

#if canImport(AppKit)
extension CollapsedLayout.Metrics {
    /// Design §5.4: measured from the real font, once, rather than guessed.
    /// Hover polling rebuilds `CollapsedLayout` at 30Hz, so this is computed
    /// a single time into a `static let` rather than re-measuring text on
    /// every call.
    public static let standard = CollapsedLayout.Metrics(
        digitWidth: RightFlankFont.measuredDigitWidth())
}
#else
extension CollapsedLayout.Metrics {
    /// No AppKit to measure with on this platform; falls back to the old
    /// estimate rather than failing to build.
    public static let standard = CollapsedLayout.Metrics(digitWidth: 9)
}
#endif

/// Drives per-frame redraws while — and only while — the aura is blooming.
///
/// Design §6.1: an idle machine should look idle, so the timeline is paused at
/// rest rather than ticking forever for a 900ms effect. `paused` is fixed when
/// the view is built, so the controller renders once more at the end of a bloom
/// to pause it again.
public struct IslandView: View {
    public let state: IslandState
    public let layout: CollapsedLayout
    public let aura: AuraTrigger
    public let now: Date
    public let geometry: IslandGeometry
    public let frames: IslandFrames

    public init(state: IslandState, layout: CollapsedLayout, aura: AuraTrigger,
                now: Date, geometry: IslandGeometry, frames: IslandFrames) {
        self.state = state
        self.layout = layout
        self.aura = aura
        self.now = now
        self.geometry = geometry
        self.frames = frames
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0,
                                paused: !aura.isBlooming(at: now))) { context in
            IslandBody(state: state, layout: layout, aura: aura,
                       now: context.date, geometry: geometry, frames: frames)
        }
    }
}

/// Design §7.1: the sprite ground colour, named there as `#05070B`. Kept as
/// an `RGBA(hex:)` value rather than a bare `Color(red:green:blue:)` triple
/// so it is greppable by its spec name, the same way every other colour in
/// this module is.
private let islandGroundColour = RGBA(hex: "#05070B")!

/// The collapsed island. Left flank, dead zone, right flank.
///
/// Design §5.1: the black shape may span the cutout because the cutout is black
/// too — but content may not. The middle is a fixed-width spacer, never a view.
struct IslandBody: View {
    let state: IslandState
    let layout: CollapsedLayout
    let aura: AuraTrigger
    let now: Date
    let geometry: IslandGeometry
    let frames: IslandFrames

    /// The left flank's anatomy, named instead of inlined so a test can pin
    /// their sum against `IslandGeometry.leftFlank` (see
    /// `leftAndRightFlankLiteralsAgreeWithTheGeometryConstants` in
    /// IslandViewTests.swift). `leadingPadding + catWidth + gap + badgeWidth +
    /// trailingPadding` must equal `IslandGeometry.leftFlank` — that sum is the
    /// only reason the dead-zone spacer starts precisely at the cutout's left
    /// edge. Change one side of the equation without the other and content
    /// slides under the cutout, the one rule design §5.1 calls absolute, with
    /// no test failing except the one this comment points at.
    enum LeftFlankLayout {
        static let leadingPadding: CGFloat = 12
        static let catWidth: CGFloat = 18
        static let gap: CGFloat = 4
        static let badgeWidth: CGFloat = 14
        static let trailingPadding: CGFloat = 10
    }

    /// The right flank's padding, split out for the same reason.
    /// `leadingPadding + trailingPadding` must equal `CollapsedLayout.padding`
    /// for the session-count case. `iconPadding` is derived from
    /// `CollapsedLayout.padding` rather than a second literal precisely so
    /// the icon case can't drift from what `CollapsedLayout.rightFlankWidth`
    /// actually reserves the way it once did (a 2pt discrepancy: reserved
    /// `padding + iconWidth` = 36, rendered `10 + 14 + 10` = 34).
    enum RightFlankLayout {
        static let leadingPadding: CGFloat = 10
        static let trailingPadding: CGFloat = 12
        static var iconPadding: CGFloat { CollapsedLayout.padding / 2 }
    }

    private var accent: Color { Color(state.accent) }

    var body: some View {
        let rect = frames.bodyInPanel
        let silhouette = IslandShape()

        ZStack(alignment: .topLeading) {
            Color.clear
            silhouette
                .fill(Color(islandGroundColour))
                .overlay(alignment: .topLeading) { content }
                .clipShape(silhouette)
                // A shadow on the shape traces its rendered alpha, rounded
                // corners included, so the aura follows the silhouette rather
                // than a bounding box — and follows the drawer down for free.
                .shadow(color: accent.opacity(aura.opacity(at: now)),
                        radius: 18, x: 0, y: 2)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
        .frame(width: frames.panel.width, height: frames.panel.height,
               alignment: .topLeading)
    }

    private var content: some View {
        HStack(spacing: 0) {
            // Left flank — the cat lands here in Plan 3.
            HStack(spacing: LeftFlankLayout.gap) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: LeftFlankLayout.catWidth, height: 14)
                Color.clear.frame(width: LeftFlankLayout.badgeWidth, height: 14)   // fixed badge slot
            }
            .padding(.leading, LeftFlankLayout.leadingPadding)
            .padding(.trailing, LeftFlankLayout.trailingPadding)

            // The dead zone. Never a view — just the width of the cutout.
            Color.clear.frame(width: geometry.notch.width)

            rightFlank
        }
        .frame(height: geometry.notch.height)
    }

    @ViewBuilder private var rightFlank: some View {
        switch layout.right {
        case .nothing:
            EmptyView()
        case .agentIcon:
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: CollapsedLayout.iconWidth, height: 14)
                .padding(.horizontal, RightFlankLayout.iconPadding)
        case let .sessionCount(n) where n > 0:
            Text(String(n))
                .font(RightFlankFont.swiftUI)
                .monospacedDigit()
                .foregroundStyle(accent)
                .padding(.leading, RightFlankLayout.leadingPadding)
                .padding(.trailing, RightFlankLayout.trailingPadding)
        case .sessionCount:
            EmptyView()
        }
    }
}
