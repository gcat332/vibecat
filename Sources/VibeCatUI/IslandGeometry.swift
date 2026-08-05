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

    /// **Whether §9.1's 150pt hover reveal reaches the island's width at this
    /// tier — the one place the rule "an open island's width does not depend on
    /// hover" is written down.**
    ///
    /// Plan 6.3 Task 2. Before it, that rule was an emergent property of three
    /// separate expressions that each half-stated it and could each have been
    /// changed alone: `IslandGeometry.frames`'s `.drawer` arm not reading its
    /// `rightFlank` argument, `IslandModel.drawerWidth` going through
    /// `openWidth(face:)` rather than a `CollapsedLayout`, and
    /// `IslandBody.revealWidth` zeroing the reveal off a *height* proxy
    /// (`drawerBelowNotch > 0`). Nothing named the shared rule, so nothing could
    /// be asserted about it. Both consequences now derive from `openFace`:
    /// non-nil fixes the width from the face, and nil is exactly when hover may
    /// add to it.
    ///
    /// **The prototype states the same rule twice, in the same direction.** Its
    /// expanded states set `width:560px` outright
    /// (`island-motion.html:161–164`), which no `:hover` selector touches — and
    /// its reveal is gated on being collapsed at all:
    /// `.island[data-collapsed="true"]:hover .detail{max-width:150px}`
    /// (`island-motion.html:129`). So opening the island both fixes its width
    /// and switches the reveal off, and those are the two things this property
    /// governs here.
    ///
    /// Deliberately *not* an argument to `frames`, and not a stored flag: it is
    /// a fact about the tier, and the measured defect this replaces
    /// (hover+closed 423pt → hover+open 273pt, the island contracting on the
    /// gesture that should expand it) came from two of the three sites above
    /// disagreeing about it.
    var takesHoverReveal: Bool { openFace == nil }

    /// **The bottom radius the island's silhouette carries at this tier** —
    /// `IslandGeometry.bottomRadius` (15) collapsed, `.openBottomRadius` (20)
    /// open. Plan 6.3 Task 5; `island-motion.html:82` against `:162`/`:164`.
    ///
    /// Keyed to `openFace`, and therefore to the same predicate as
    /// `takesHoverReveal` and `IslandGeometry.frames`'s width arm — **not to
    /// `IslandBody.drawerBelowNotch > 0`**, for the reason `IslandBody.revealWidth`
    /// gives at length: "is any of the body below the notch line" is a fact about
    /// the height, and a face that ever took height 0 would silently put the
    /// collapsed radius back on an open drawer. The prototype states the rule the
    /// same way — the 20px radius is set by the `ask`/`askmulti`/`list` *states*,
    /// which are exactly the states that also set `width:560px`, and no `:hover`
    /// or height selector touches it.
    ///
    /// One property rather than a ternary at each of the three shapes that draw a
    /// bottom corner (`IslandBody`'s two silhouette halves and `DrawerView`'s own
    /// fill/clip pair): the three have to agree, because they are stacked in the
    /// same colour and the *union* of their coverage is what is visible. Two of
    /// them at 20 and one at 15 paints a 15pt corner and nothing else changes,
    /// which is a divergence with no symptom other than the pixels.
    var bottomRadius: CGFloat {
        openFace == nil ? IslandGeometry.bottomRadius : IslandGeometry.openBottomRadius
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
    /// The **collapsed** bottom radius. It matches the measured hardware corner
    /// (~14pt) so our curve sits over the machine's rather than beside it, and
    /// `minimumRightFlank` just below derives from it.
    ///
    /// **Correction, 2026-08-05 (Plan 6.3 Task 6): this is not a divergence from
    /// the prototype, and four documents say it is.** This comment used to open
    /// "a deliberate divergence from the prototype's `9px`
    /// (`island-motion.html:82`)", and `CLAUDE.md`, this plan's Global Constraints
    /// and `theOpenAndCollapsedRadiiAreTheTwoPrototypeValues` all repeat it as the
    /// model case of a divergence-as-written-decision. Read in a browser:
    /// `island-motion.html:83` is `border-radius:0 0 15px 15px` and the computed
    /// value on the dormant island is `0px 0px 15px 15px`. **The prototype's
    /// collapsed corner is 15px, exactly ours.** The `9px` is `--fillet`
    /// (`island-motion.html:31`) — the *top* weld, `filletRadius` below — and the
    /// citation "line 82" points at `.island`'s own declaration block, which is
    /// where the 15 is.
    ///
    /// The hardware measurement stands on its own and nothing about it changes;
    /// what changes is that it agrees with the design instead of overriding it. The
    /// misreading was not free: it is the most likely reason the fillets were
    /// deleted rather than re-spelled in 2026-08-01, since a document that has
    /// already told you `9px` is the bottom radius leaves nothing for a 9pt fillet
    /// to be.
    public static let bottomRadius: CGFloat = 15

    /// **`--fillet: 9px` (`island-motion.html:31`)** — the radius of the concave
    /// weld at each *top* corner, where the island meets the bezel.
    /// `IslandShape.fillets` draws it; that type's doc comment carries the
    /// removed-then-restored history.
    ///
    /// ## Why 9 and not the owner's literal "the same radius as the bottom"
    ///
    /// The instruction that restored these asked for "the same radius as the
    /// bottom", which is 15 collapsed and 20 open. The prototype says 9 and calls
    /// it "a hint of a curve, not the scoop they were before". The two disagree by
    /// 6pt, so it had to be measured rather than picked. Rendered and scanned at
    /// scale 4 on the `mbp14` fixture (`theWeldIsAHintOfACurveAndNotAScoop`):
    ///
    /// | fillet | weld's own ink | of the 32pt bar it spans | flush edge left between weld and bottom corner |
    /// |---|---|---|---|
    /// | **9** | 17.47pt² | 28.1% | **11.75pt** |
    /// | 15 | 48.31pt² | 46.9% | 5.75pt |
    /// | 20 | 85.88pt² | 62.5% | **0.75pt — the two curves meet** |
    ///
    /// The collapsed island is only `notch.height` = 32pt tall, and that is the
    /// whole of the argument. At 20 there is effectively no straight side left and
    /// each end becomes one continuous S from bezel to bottom edge — which is not a
    /// rounded corner, it is the hook the 2026-08-01 removal was reacting to; 15
    /// halves the side. **9pt is the only one of the three that leaves the island
    /// an edge**, and it paints a fifth of 20's ink. ("Flush edge" is rows whose
    /// outermost ink is the body's own edge column and reads ~3.7pt longer than
    /// `32 − fillet − radius` at every radius, because both curves leave the edge
    /// tangentially; the three are therefore compared with each other. See
    /// `IslandFilletTests.Measured.straightSide`.)
    ///
    /// Two smaller reasons, both structural rather than aesthetic:
    ///
    /// - The bottom radius **changes with the tier** (15 → 20 on open, on a 440ms
    ///   bezier). A fillet defined as "the same as the bottom" would animate at the
    ///   screen edge on every click. `--fillet` appears in no `transition` in the
    ///   prototype; it is one constant for every state, and this is a `let` with no
    ///   tier argument for that reason.
    /// - There is nothing at the top for a radius argument to *match*. 15 is a
    ///   measurement of the hardware corner our own bottom corner has to cover
    ///   (see `bottomRadius`); the bezel above has no corner, so nothing carries
    ///   that reasoning upward.
    public static let filletRadius: CGFloat = 9
    /// **The bottom radius while a drawer is open** —
    /// `island-motion.html:162` and `:164`, where the `ask`, `askmulti` and `list`
    /// states all set `border-radius: 0 0 20px 20px`. Added by Plan 6.3 Task 5;
    /// before it the island was a flat 15 at every tier, so the one radius the
    /// prototype does *not* diverge from ours was the one we did not have.
    ///
    /// Taken from the prototype verbatim, unlike `bottomRadius` above, and the
    /// asymmetry is the point rather than an inconsistency: 15 is a measurement of
    /// a *cutout* our collapsed corner has to cover, and there is no cutout beside
    /// a 288pt drawer for the open corner to match. Nothing in the hardware
    /// argument that produced 15 reaches down there, so the design's own number
    /// governs.
    ///
    /// `IslandTier.bottomRadius` is what chooses between the two, and
    /// `IslandMotion.shapeDuration`/`easeCurve` are the clock and curve the change
    /// runs on (`island-motion.html:86`: `border-radius var(--t-shape) var(--ease)`
    /// — the one shape property the prototype does *not* put on a spring).
    public static let openBottomRadius: CGFloat = 20

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

    /// `minimumWidth`'s open-tier twin: the same rule, measured against the
    /// radius the **open** silhouette actually draws.
    ///
    /// Plan 6.3 Task 5. `minimumRightFlank` is `bottomRadius` — 15 — because that
    /// is the collapsed corner, and §5.1's guarantee is "our curve starts at or
    /// beyond `notch.maxX`, so our black covers the hardware's corner rather than
    /// competing with it". Giving the open island a **20pt** corner while leaving
    /// the floor at 15 breaks exactly that: the last 20pt of the open body is a
    /// curve, so 15pt of clearance puts 5pt of it back inside the cutout.
    ///
    /// It binds on no Mac — the floor itself only binds for a cutout wider than
    /// 487pt (see `openWidth(face:)`) — and it is here for the same reason that
    /// floor is: a rule whose failing case is never constructed is a rule nobody
    /// has checked, and `anAbsurdlyWideCutoutTakesTheFloorRatherThanTheDesignWidth`
    /// constructs it.
    public var minimumOpenWidth: CGFloat {
        Self.leftFlank + notch.width + Self.openBottomRadius
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
    /// **`minimumOpenWidth`, not `minimumWidth`, since Plan 6.3 Task 5** — the open
    /// corner is 20pt, so 20pt is what has to be cleared. See that property.
    public func openWidth(face: DrawerFace) -> CGFloat {
        max(face.width, minimumOpenWidth)
    }

    public func frames(rightFlank: CGFloat, tier: IslandTier) -> IslandFrames {
        let right = max(0, rightFlank)
        // `tier` reaches the width as well as the height since Plan 6.3 Task 1.
        // It used to reach only the height, which made the *open* island's width
        // a function of the session tally's digit count — see `DrawerFace.width`
        // for the measurement and for why the open number is a flat one.
        //
        // Task 2: written as `openFace`, not as a `switch` over the three cases,
        // so that this arm and `IslandTier.takesHoverReveal` are two readings of
        // one predicate rather than two rules that can drift. `right` carries the
        // reveal (see `CollapsedLayout.rightFlankWidth`), and it is unreachable
        // here whenever a face is open — which *is* the rule.
        let width = tier.openFace.map(openWidth(face:))
            ?? (Self.leftFlank + notch.width + right)
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
