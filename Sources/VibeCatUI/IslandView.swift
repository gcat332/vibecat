import SwiftUI

extension Color {
    init(_ c: RGBA) { self.init(red: c.r, green: c.g, blue: c.b) }
}

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

    private var accent: Color { Color(state.accent) }

    var body: some View {
        let rect = frames.shapeInPanel
        let silhouette = IslandShape(rightFilletSuppressed: !layout.showsRightFillet)

        ZStack(alignment: .topLeading) {
            Color.clear
            silhouette
                .fill(Color(red: 0.02, green: 0.027, blue: 0.043))
                .overlay(alignment: .topLeading) { content }
                .clipShape(silhouette)
                // A shadow on the shape traces its rendered alpha, fillets
                // included, so the aura follows the silhouette rather than a
                // bounding box — and follows the drawer down for free.
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
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 18, height: 14)
                Color.clear.frame(width: 14, height: 14)   // fixed badge slot
            }
            .padding(.leading, 12 + IslandGeometry.fillet)
            .padding(.trailing, 10)

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
                .frame(width: 14, height: 14)
                .padding(.horizontal, 10)
        case let .sessionCount(n) where n > 0:
            Text(String(n))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
                .padding(.leading, 10)
                .padding(.trailing, 12)
        case .sessionCount:
            EmptyView()
        }
    }
}
