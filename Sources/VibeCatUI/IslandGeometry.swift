import CoreGraphics

public enum IslandTier: Sendable, Equatable {
    case rest
    case hover
    case drawer(height: CGFloat)

    var extraHeight: CGFloat {
        if case let .drawer(h) = self { h } else { 0 }
    }
}

public struct IslandFrames: Sendable, Equatable {
    /// The core: leftFlank + notch + rightFlank, in screen coordinates. This is
    /// what design §5.4's measured widths describe, and what the content is
    /// laid out against.
    public let body: CGRect
    /// The core plus the fillet flares, which stick out past it. This is the
    /// rect handed to IslandShape.
    public let shape: CGRect
    /// The window: the shape plus room for the aura to bloom into.
    public let panel: CGRect

    public init(body: CGRect, shape: CGRect, panel: CGRect) {
        self.body = body
        self.shape = shape
        self.panel = panel
    }

    /// The shape relative to the panel's own origin, in SwiftUI's flipped
    /// coordinates. There is no top margin, so y is always 0.
    public var shapeInPanel: CGRect {
        CGRect(x: shape.minX - panel.minX, y: panel.maxY - shape.maxY,
               width: shape.width, height: shape.height)
    }
}

public struct IslandGeometry: Sendable, Equatable {
    /// 12 padding + 18 cat + 4 gap + 14 badge + 10 padding. Constant so that
    /// the island's left edge — and therefore the cat — never moves.
    public static let leftFlank: CGFloat = 58
    public static let fillet: CGFloat = 9
    public static let bottomRadius: CGFloat = 15
    /// Room outside the body for the aura to bloom into.
    public static let auraMargin: CGFloat = 24
    /// Height of the fallback pill on a display with no notch.
    public static let pillHeight: CGFloat = 32

    public let screen: ScreenMetrics
    /// The real cutout, or a zero-width rect at the top centre as a stand-in.
    public let notch: CGRect
    public let isFallbackPill: Bool

    public init(screen: ScreenMetrics) {
        self.screen = screen
        if let n = screen.notch {
            notch = n
            isFallbackPill = false
        } else {
            // No dead zone to route around, so the "notch" is a zero-width
            // seam at the top centre and the flanks simply meet.
            notch = CGRect(x: screen.frame.midX,
                           y: screen.frame.maxY - Self.pillHeight,
                           width: 0, height: Self.pillHeight)
            isFallbackPill = true
        }
    }

    public func frames(rightFlank: CGFloat, tier: IslandTier) -> IslandFrames {
        let right = max(0, rightFlank)
        let width = Self.leftFlank + notch.width + right
        let height = notch.height + tier.extraHeight

        // leftEdge = notch.minX − LW. The right flank cancels out of the
        // centring shift entirely, which is why the cat holds still.
        let left = isFallbackPill ? screen.frame.midX - width / 2
                                  : notch.minX - Self.leftFlank
        let body = CGRect(x: left, y: screen.frame.maxY - height,
                          width: width, height: height)

        // A fillet welded to an empty flank pokes out past the notch as a
        // beak, so the right flare only exists when there is content. §5.5.
        let rightFlare: CGFloat = right > 0 ? Self.fillet : 0
        let shape = CGRect(x: body.minX - Self.fillet, y: body.minY,
                           width: body.width + Self.fillet + rightFlare,
                           height: body.height)

        let m = Self.auraMargin
        var panel = CGRect(x: shape.minX - m, y: shape.minY - m,
                           width: shape.width + m * 2, height: shape.height + m)
        // Clamp horizontally; the top is already the screen edge.
        panel.origin.x = max(screen.frame.minX, panel.minX)
        panel.size.width = min(panel.width, screen.frame.maxX - panel.minX)

        return IslandFrames(body: body, shape: shape, panel: panel)
    }
}

/// What the right flank is showing, and how wide that makes it.
///
/// Design §5.4: measured from content, never reserved. The island never holds
/// space it is not using.
public struct CollapsedLayout: Sendable, Equatable {
    public enum RightContent: Sendable, Equatable {
        case sessionCount(Int)
        case agentIcon
        case nothing
    }

    /// The font fact needed to size a session count without guessing.
    ///
    /// Measuring a real font touches the host's font system, which
    /// `CollapsedLayout` itself must not do — it stays a pure, Sendable value
    /// type — so the measurement is injected instead. Production code gets
    /// `.standard`, computed once from the actual right-flank font (see
    /// `RightFlankFont` in IslandView.swift); tests can inject a fixed value
    /// to stay deterministic.
    public struct Metrics: Sendable, Equatable {
        public let digitWidth: CGFloat

        public init(digitWidth: CGFloat) {
            self.digitWidth = digitWidth
        }
    }

    /// 10 leading + content + 12 trailing. Visible (not `private`) so tests
    /// can pin the no-clipping invariant without a duplicated magic number.
    static let padding: CGFloat = 22
    private static let iconWidth: CGFloat = 14
    /// Design §9.1: hover reveals name and elapsed time over 280ms, up to 150pt.
    private static let hoverReveal: CGFloat = 150

    public let right: RightContent
    public let hovering: Bool
    public let metrics: Metrics

    public init(right: RightContent, hovering: Bool, metrics: Metrics = .standard) {
        self.right = right
        self.hovering = hovering
        self.metrics = metrics
    }

    /// Design §5.4: "measured from actual content... then written back as an
    /// explicit width." `metrics.digitWidth` is a real measurement by
    /// default (see `Metrics.standard`), not a guessed constant, so this
    /// can't quietly clip a digit if the font or its size ever changes.
    public var rightFlankWidth: CGFloat {
        let content: CGFloat = switch right {
        case .nothing: 0
        case .agentIcon: Self.iconWidth
        case let .sessionCount(n):
            n <= 0 ? 0 : CGFloat(String(n).count) * metrics.digitWidth
        }
        guard content > 0 else { return 0 }
        return Self.padding + content + (hovering ? Self.hoverReveal : 0)
    }

    /// A fillet welded to an empty flank pokes out past the notch as a beak.
    public var showsRightFillet: Bool { rightFlankWidth > 0 }
}
