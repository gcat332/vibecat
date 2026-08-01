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
    /// This is also the rect handed to `IslandShape` — the silhouette has
    /// straight sides, so it occupies the core exactly and sticks out nowhere.
    public let body: CGRect
    /// The window: the body plus room for the aura to bloom into.
    public let panel: CGRect

    public init(body: CGRect, panel: CGRect) {
        self.body = body
        self.panel = panel
    }

    /// The body relative to the panel's own origin, in SwiftUI's flipped
    /// coordinates. There is no top margin, so y is always 0.
    public var bodyInPanel: CGRect {
        CGRect(x: body.minX - panel.minX, y: panel.maxY - body.maxY,
               width: body.width, height: body.height)
    }
}

public struct IslandGeometry: Sendable, Equatable {
    /// 12 padding + 18 cat + 4 gap + 14 badge + 10 padding. Constant so that
    /// the island's left edge — and therefore the cat — never moves.
    public static let leftFlank: CGFloat = 58
    public static let bottomRadius: CGFloat = 15

    /// The smallest right flank the island ever has, even with nothing to show.
    ///
    /// This is the one place design §5.4's "never reserves space it is not
    /// using" is broken on purpose, and the reason is the silhouette rather
    /// than the content. With a zero right flank the island's right edge lands
    /// exactly on `notch.maxX`, so its bottom-right corner and the *hardware's*
    /// notch corner are two curves drawn into the same fifteen points, one over
    /// the other. Measured off a real screen, the machine's corner spans about
    /// 14pt against our 15 — near enough to look intended, different enough to
    /// leave a visible seam, which is what was reported.
    ///
    /// Extending by exactly one corner radius puts our whole curve to the right
    /// of theirs: at every row our edge is at or beyond `notch.maxX`, so our
    /// black covers their corner completely and the only corner on screen is
    /// ours. Both ends of the island then match *by construction* — which is
    /// the property actually wanted, and is not what chasing Apple's radius by
    /// eye converges on.
    ///
    /// Deriving it from `bottomRadius` is not a coincidence to be tidied away:
    /// a smaller value would expose their curve again, and a larger one buys
    /// nothing.
    public static let minimumRightFlank: CGFloat = bottomRadius
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

        let m = Self.auraMargin
        var panel = CGRect(x: body.minX - m, y: body.minY - m,
                           width: body.width + m * 2, height: body.height + m)
        // Clamp horizontally; the top is already the screen edge.
        panel.origin.x = max(screen.frame.minX, panel.minX)
        panel.size.width = min(panel.width, screen.frame.maxX - panel.minX)

        return IslandFrames(body: body, panel: panel)
    }

    /// The widest the collapsed island can ever be: a session count clamped
    /// to `CollapsedLayout.maxDisplayedSessions` digits, hovered. Genuinely
    /// the ceiling — not merely the assumed one — because both the reserved
    /// width (`rightFlankWidth`) and the text `IslandView` actually draws
    /// come from `CollapsedLayout.sessionCountText`, which enforces that
    /// clamp on every count, however large.
    ///
    /// The panel is created once at this size and never resized — measured,
    /// animating the silhouette inside a fixed window has a p95 of 10.34ms
    /// against 15.16ms for moving the window itself, and a far shorter tail.
    ///
    /// This is only safe while the island is click-through: an oversized
    /// transparent window intercepts nothing. Plan 4's drawer takes mouse
    /// events, so it must size the panel to what it actually covers.
    public func maxCollapsedFrames() -> IslandFrames {
        let widest = CollapsedLayout(
            right: .sessionCount(CollapsedLayout.maxDisplayedSessions),
            hovering: true)
        return frames(rightFlank: widest.rightFlankWidth, tier: .rest)
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
    /// Visible (not `private`) so `IslandBody`'s `.agentIcon` case in
    /// IslandView.swift renders the same 14pt this type reserves, rather
    /// than a second literal that could drift from it.
    static let iconWidth: CGFloat = 14
    /// Design §9.1: hover reveals name and elapsed time over 280ms, up to 150pt.
    public static let hoverReveal: CGFloat = 150
    /// The most digits the right flank ever reserves width for.
    /// `sessionCountText` clamps every session count to this before it is
    /// either measured (`rightFlankWidth`) or drawn (`IslandView`), so
    /// `IslandGeometry.maxCollapsedFrames()`'s "three-digit, hovered"
    /// ceiling is an enforced upper bound rather than an assumption a
    /// four-digit count — nothing upstream caps `sessionCount`'s `Int` —
    /// could silently exceed. A count beyond this still displays as exactly
    /// this many digits, "999" reading as "999 or more"; a different
    /// treatment for the overflow case is Plan 6's Display settings, not
    /// this type's job.
    public static let maxDisplayedSessions = 999

    public let right: RightContent
    public let hovering: Bool
    public let metrics: Metrics

    public init(right: RightContent, hovering: Bool, metrics: Metrics = .standard) {
        self.right = right
        self.hovering = hovering
        self.metrics = metrics
    }

    /// The exact text a session count renders as, clamped to
    /// `maxDisplayedSessions` here and only here — `rightFlankWidth` below
    /// and `IslandBody.rightFlank` in IslandView.swift both read this rather
    /// than clamping independently, so the reserved width and the drawn
    /// glyphs can never disagree. `nil` for every other `RightContent` case,
    /// or a non-positive count: nothing to draw.
    public var sessionCountText: String? {
        guard case let .sessionCount(n) = right, n > 0 else { return nil }
        return String(min(n, Self.maxDisplayedSessions))
    }

    /// Design §5.4: "measured from actual content... then written back as an
    /// explicit width." `metrics.digitWidth` is a real measurement by
    /// default (see `Metrics.standard`), not a guessed constant, so this
    /// can't quietly clip a digit if the font or its size ever changes.
    public var rightFlankWidth: CGFloat {
        let content: CGFloat = switch right {
        case .nothing: 0
        case .agentIcon: Self.iconWidth
        case .sessionCount:
            // Measure the CLAMPED text, never String(n). An earlier task made
            // sessionCountText the single clamp so the fixed panel is a real
            // ceiling; reformatting the raw count here reintroduces the
            // overflow it closed. This is the third time this regression has
            // been written into the plan.
            CGFloat(sessionCountText?.count ?? 0) * metrics.digitWidth
        }
        let reveal = hovering ? Self.hoverReveal : 0
        // An empty flank still clears the cutout by one corner radius, so the
        // island's own corner covers the hardware's rather than fighting it —
        // see `IslandGeometry.minimumRightFlank`. Hovering always opens the
        // reveal on top: returning early here made hover a guaranteed no-op on
        // a dormant island, which reads as the feature being broken.
        //
        // Added to the floor, not maxed against it: the reveal has to be the
        // same 150pt from every starting width, or an empty island animates a
        // different distance from a counted one. `max` made that 135 and
        // `theHoverRevealIsAConstantAdditionRegardlessOfContent` caught it.
        guard content > 0 else { return IslandGeometry.minimumRightFlank + reveal }
        // Content already carries `padding` (22), comfortably past the minimum.
        return Self.padding + content + reveal
    }

    /// Whether the right flank is showing anything. Deliberately *not*
    /// `rightFlankWidth > 0`, which it used to be: the flank now has a nonzero
    /// floor for the corner, and hovering opens the reveal regardless, so that
    /// spelling became permanently true and the name a lie. Nothing in
    /// `Sources/` reads this yet — Plan 4's drawer will, and it should get the
    /// question it is actually asking.
    public var hasRightContent: Bool {
        switch right {
        case .nothing: false
        case .agentIcon: true
        case .sessionCount: sessionCountText != nil
        }
    }
}
