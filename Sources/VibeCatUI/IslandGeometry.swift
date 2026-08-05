import CoreGraphics

public enum IslandTier: Sendable, Equatable {
    case rest
    case hover
    /// A drawer is open, showing this face.
    ///
    /// **Carries the face, not a bare height** (Plan 6.3 Task 1). It used to be
    /// `.drawer(height: CGFloat)`, from when the face fixed only one of the
    /// drawer's two dimensions. It now fixes both, and two associated values
    /// would let a caller pair one face's height with another's width — a way to
    /// be wrong that this spelling does not have. `DrawerFace` is the one place
    /// either number is written down.
    case drawer(face: DrawerFace)

    var extraHeight: CGFloat {
        if case let .drawer(face) = self { face.height } else { 0 }
    }

    /// The face whose width this tier imposes on the island, or `nil` when the
    /// tier imposes none and the collapsed flanks decide the width instead.
    var openFace: DrawerFace? {
        if case let .drawer(face) = self { face } else { nil }
    }
}

/// What the drawer is showing, and how tall that makes it. Design §6.3.
///
/// The heights are the design's, verbatim. `questionWithReply` being *shorter*
/// than `question` is not a typo: opening the reply field replaces the list of
/// choices with a field, and §6.3 says the drawer follows its content rather
/// than leaving dead space.
///
/// `.sessionList` is Plan 5's (§6.3: "Session list — 420pt, rows scroll.").
public enum DrawerFace: Sendable, Equatable, CaseIterable {
    case question, questionWithReply, questionMulti, sessionList

    public var height: CGFloat {
        switch self {
        case .question:          288
        case .questionWithReply: 184
        case .questionMulti:     300
        case .sessionList:       420
        }
    }

    /// How wide the island is while this face is open.
    ///
    /// **§6.3 fixes heights per face and is silent on width. The prototype is
    /// not:** `island-motion.html:162–164` sets `width:560px` on `ask`,
    /// `askmulti` and `list` alike, and `:166` (`ask[data-other="true"]`, our
    /// `.questionWithReply`) changes only the height. So all four faces are the
    /// same width today. It is a per-face property anyway — the way the height
    /// already is — so a face that ever needs a different one has somewhere to
    /// say it, rather than a constant that has to be un-made first.
    ///
    /// Until Plan 6.3 there was no such property, and the consequence was
    /// measured: `IslandGeometry.frames` let `tier` reach only the *height*, so
    /// the open island's width was `leftFlank + notch + rightFlank` — a function
    /// of how many digits the session tally had and nothing else. 1 and 3
    /// sessions produced byte-identical widths (273.1pt on the `mbp14` fixture)
    /// and 12 gained 8.1pt only because the tally reached two digits. A session
    /// row's ink saturates at **420pt**, so line 2 truncated to `As…` at every
    /// count. See `plans/README.md`, "Carried out of the second mockup-fidelity
    /// wave".
    ///
    /// ### Why 560 is literal rather than derived from the notch
    ///
    /// The prototype hardcodes a `186px` notch (`--notch-w`) and could therefore
    /// have meant either `560` or `leftFlank + notch + 316`. Ours reads the real
    /// cutout off `NSScreen`, so the two are different rules and one had to be
    /// chosen.
    ///
    /// **Literal, because 560 is a measurement of the drawer's own content, not
    /// of the hardware above it.** The mockup gives its rows `560 − 2×18 = 524pt`
    /// against ink that saturates at 420; nothing in that arithmetic mentions a
    /// cutout, and no face's content gets wider because a machine's camera
    /// housing does. Deriving it would make the drawer wider on a 16-inch
    /// MacBook for no reason a reader could name — and, the case that actually
    /// decides it, **`58 + 0 + 316 = 374pt` on a notchless display**, which is
    /// below the 420 at which a row saturates. That is precisely the defect this
    /// property exists to remove, reintroduced on the one display where nothing
    /// about the geometry asked for it.
    ///
    /// The floor in `IslandGeometry.openWidth(face:)` is the other half of the
    /// rule, and it is what keeps "literal" from being a magic constant that
    /// happens to look right on one machine: the black must cover the hole
    /// before it obeys a design width. See that method.
    public var width: CGFloat {
        switch self {
        case .question, .questionWithReply, .questionMulti, .sessionList: 560
        }
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

    /// The narrowest the island may ever be drawn: the constant left flank, the
    /// cutout it has to span, and one corner radius clear of it.
    /// `minimumRightFlank`'s own doc comment is why the last term is not zero.
    ///
    /// Zero on a notchless display but for the corner, since `notch.width` is 0
    /// there — which is correct, there being no hole to cover.
    public var minimumWidth: CGFloat {
        Self.leftFlank + notch.width + Self.minimumRightFlank
    }

    /// The island's width while `face`'s drawer is open — **the face's own flat
    /// width, floored at `minimumWidth`.**
    ///
    /// Two rules rather than one constant, and the floor is the reason. §5.1's
    /// "the notch is a hole" only works because our black spans the cutout and
    /// our corner sits outside theirs; a design width narrower than
    /// `leftFlank + notch + minimumRightFlank` would end the body inside the
    /// cutout and put the hardware's own corner back on screen. So covering the
    /// hole wins over the design number whenever they disagree. On every notch
    /// that exists the two do not disagree — the floor is 258pt on the 14-inch
    /// fixture (58 + 185 + 15) against a 560pt face — and it would take a cutout
    /// wider than 487pt to bind. It is here because that is the *reason* 560 is
    /// safe, and a reason a reader can check beats one they have to trust.
    ///
    /// **Deliberately not `max(face.width, collapsedWidth)`.** The open width
    /// must not depend on hover (the prototype's own rule: `width:560px` is set
    /// outright, and `.detail`'s reveal is a separate transition on a separate
    /// clock), and a hovered right flank is exactly what a collapsed-width floor
    /// would let leak in.
    ///
    /// See `DrawerFace.width` for why the face's number is literal rather than
    /// derived from `notch.width`, and what that means on a notchless display.
    public func openWidth(face: DrawerFace) -> CGFloat {
        max(face.width, minimumWidth)
    }

    public func frames(rightFlank: CGFloat, tier: IslandTier) -> IslandFrames {
        let right = max(0, rightFlank)
        // `tier` reaches the width as well as the height since Plan 6.3 Task 1.
        // It used to reach only the height, which made the *open* island's width
        // a function of the session tally's digit count — see `DrawerFace.width`
        // for the measurement and for why the open number is a flat one.
        let width = switch tier {
        case .rest, .hover: Self.leftFlank + notch.width + right
        case let .drawer(face): openWidth(face: face)
        }
        let height = notch.height + tier.extraHeight

        // leftEdge = notch.minX − LW. The right flank cancels out of the
        // centring shift entirely, which is why the cat holds still — and since
        // the width no longer comes from the flanks at all while a drawer is
        // open, that now covers the open tier too: 560pt of island grows entirely
        // to the right and the cat does not move (§5.3).
        //
        // The fallback pill is the deliberate exception, and it is not a lapse in
        // §5.3: that invariant exists so the cat keeps its place *relative to the
        // cutout*, and a notchless display has no cutout to keep a place
        // relative to. §5.1 says the fallback floats, so it stays centred and
        // opens symmetrically about the screen centre — pinned by
        // `theFallbackPillStaysCentredWhenTheDrawerOpens`.
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
    /// The panel is created once at this *width* and never resized for
    /// collapsed content — measured, animating the silhouette inside a fixed
    /// window has a p95 of 10.34ms against 15.16ms for moving the window
    /// itself, and a far shorter tail. `rightFlank` is always the theoretical
    /// widest here, regardless of `tier`, which is what keeps that guarantee for
    /// every collapsed state.
    ///
    /// **It no longer holds across the open tier, and that is Plan 6.3 Task 1's
    /// doing rather than an oversight.** This comment used to end "nothing about
    /// opening the drawer should make the panel resize sideways too", which was
    /// true only while the drawer had no width of its own: the open island is now
    /// `openWidth(face:)` — 560pt — against a widest collapsed body of 423.1pt on
    /// the `mbp14` fixture, so a panel fixed at the collapsed ceiling would clip
    /// 137pt off the right of every drawer. Passing `tier` straight through to
    /// `frames` is what grows it, and `NotchController.reflow()` re-applies the
    /// frame once per tier change — the same mechanism, and the same once-per-tier
    /// cost, that the height has always used. The spike's finding is untouched:
    /// what it measured was resizing the window *per frame of content*, not once
    /// on a gesture.
    ///
    /// Widening this to cover the drawer stopped being optional the moment
    /// the island could be clicked: an oversized transparent window
    /// intercepts nothing, but `NotchPanel.acceptsClicks` (Task 4) turns that
    /// off exactly while a drawer could be clicked open, and the whole span
    /// starts taking input at that point. `tier` is what lets the *height*
    /// grow for exactly that case — `NotchController.reflow()` is what
    /// actually re-applies the grown frame, once per tier change, not this
    /// method itself.
    public func maxCollapsedFrames(tier: IslandTier = .rest) -> IslandFrames {
        let widest = CollapsedLayout(
            right: .sessionCount(CollapsedLayout.maxDisplayedSessions),
            hovering: true)
        return frames(rightFlank: widest.rightFlankWidth, tier: tier)
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
