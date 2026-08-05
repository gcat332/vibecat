import AppKit
import SwiftUI
import VibeCatCore

/// §3's *"a swappable runtime asset"*, drawn — with `CLIMark` as the fallback
/// §2.3 requires whenever the asset cannot be trusted.
///
/// ## The §4.3 ruling this task owns
///
/// `CLIMarkView` is `currentColor` geometry tinted by the state accent: shape
/// says who, hue says what state, both on one mark. A brand icon arrives with
/// its own colour — `#D97757`, `#5D74FF`, a green circle, a blue square — which
/// puts a second meaning on hue the moment it is drawn in full colour, and the
/// plan is explicit that there may be no answer that satisfies both halves of
/// §4.3 at once. So the decision is **split by context**, not resolved in one
/// direction:
///
/// - **`.brandColour`** — the icon's own pixels, untouched. Correct wherever
///   §4.3's state signal is carried by something else on screen. `SessionRow`
///   is that case: line 1 already states the state twice, in a word
///   (`Self.stateLabel`) and a pip six points from the mark
///   (`SessionRow.headline`'s `Circle().fill(accent)`) — so the mark's hue is
///   spare capacity there, not the sole carrier of state, and spending it on
///   identity instead costs §4.3 nothing that was not already paid for twice.
/// - **`.tinted`** — a mask tinted by `accent`, via `Image
///   .renderingMode(.template)`: every non-transparent pixel takes the tint,
///   exactly as `CLIMarkView.colour` already does. Correct wherever the icon
///   may be the *only* thing on screen — the collapsed flank, where nothing
///   else states the session's state at all. §4.3 holds there exactly as
///   written, at the cost the plan itself names: a filled circular background
///   (`claude.png`, `openai.png` — measured, not assumed, against the owner's
///   set) becomes a solid state-coloured disc, which may read as a badge
///   rather than a mark. Accepted rather than avoided, because the
///   alternative in that spot is a full-colour logo the eye cannot separate
///   from a genuinely different state.
///
/// **This file does not choose between the two for any caller** — Task 5 wires
/// the row (`.brandColour`, per the reasoning above); a future collapsed-flank
/// caller wires `.tinted`. Neither call site exists yet, so this is the
/// decision recorded and the mechanism built, not the wiring — that is
/// deliberate rather than a gap this task left open.
///
/// No §4.3 correction is filed against the spec: nothing here draws in full
/// colour merely to look pretty. `.brandColour` is used exactly where the
/// state has already been said, which is the same "shape says who, hue says
/// what state" clause read one level down — a *second* field free to speak
/// once the first has done the job description already assigns state.
struct SourceIcon: View {
    /// The adapter's own `SourceAdapter.icon` — a path, or `nil` for "use the
    /// geometric mark". User input, and every way it can be wrong (missing,
    /// unreadable, a directory, a zero-byte file, an unparsable one) is
    /// `loadValidImage(atPath:)`'s problem, not this view's: `body` only ever
    /// sees "an image" or "nothing", never an error.
    let path: String?
    /// §2.3's fallback: `CLIMark(cli:)`'s own mapping, so a source with no icon
    /// — every preset in `Adapters/` today, since none may bundle a vendor
    /// logo — draws exactly what it always drew.
    let fallback: CLIMark
    var side: CGFloat = 16
    /// The session's state accent. Not defaulted, unlike `CLIMarkView.colour`:
    /// every render needs it for the fallback mark, and `.tinted` needs it for
    /// the icon itself, so there is no call site where a default would ever
    /// actually be used.
    var accent: Color
    var style: Style = .tinted

    enum Style: Sendable, Equatable {
        case brandColour
        case tinted
    }

    var body: some View {
        if let path, let image = Self.loadValidImage(atPath: path) {
            // `.renderingMode(.template)` has to land on `Image` itself —
            // it is not a member of the `some View` that `.resizable()`
            // already returns, so the two branches diverge before any
            // modifier both share, and rejoin at `.aspectRatio`/`.frame`.
            Group {
                switch style {
                case .brandColour:
                    Image(nsImage: image).resizable().interpolation(.high)
                case .tinted:
                    Image(nsImage: image).resizable().interpolation(.high)
                        .renderingMode(.template)
                        .foregroundStyle(accent)
                }
            }
            .aspectRatio(contentMode: .fit)
            .frame(width: side, height: side)
        } else {
            CLIMarkView(mark: fallback, side: side, colour: accent)
        }
    }

    /// Every way a path can be wrong that must not throw, hang or crash —
    /// §2.3 applied to a picture, and **the "hang" half of that sentence was
    /// not true until Plan 7 Task 6's hardware run made it true.** See
    /// `SourceIconLoader` for what happened and what bounds it now. This is a
    /// forward to that loader, kept under its original name because it is the
    /// name every caller and every test already uses, and because the *contract*
    /// has not changed: "an image, or nothing, never an error."
    ///
    /// A static function rather than folded into `body`, so the fallback tests
    /// can call it directly against real bad inputs without rendering anything.
    static func loadValidImage(atPath path: String) -> NSImage? {
        SourceIconLoader.shared.image(atPath: path)
    }

    /// The unbounded read, which is what `SourceIconLoader` runs on a background
    /// thread. Never call this from the main thread — that is the whole point of
    /// the loader in front of it.
    ///
    /// Measured against this read, not assumed: on this OS,
    /// `NSImage(contentsOfFile:)` already returns `nil` for a missing path, a
    /// zero-byte file and a file that is not image data at all — none of the
    /// three needed the `isValid`/size guard below to fail closed. The guard
    /// stays anyway, as a second line rather than a redundant one: it is what
    /// catches a *directory* (checked explicitly, before `NSImage` ever sees
    /// the path, because trusting an AppKit initialiser to fail closed on a
    /// directory rather than to interpret it is exactly the kind of assumption
    /// this project's testing standards rule out) and it is what would catch
    /// a future format or OS version where a broken file decodes into an
    /// `NSImage` with a zero or nonsensical size instead of `nil`.
    ///
    /// Checked against the owner's real set at `~/Downloads/icon` — read only,
    /// never copied here — which all loaded as valid, appropriately-sized
    /// images: this read is not the reason any of those six needs converting,
    /// and the plan's own SVG note (two of them reporting `1×1` for
    /// `width="1em"` with no font context) is a fact about *those files*, not
    /// about this function.
    nonisolated static func readImage(atPath path: String) -> NSImage? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return nil }
        guard let image = NSImage(contentsOfFile: path),
              image.isValid, image.size.width > 0, image.size.height > 0
        else { return nil }
        return image
    }
}

/// **A bounded, cached front door to reading an icon file, because an unbounded
/// one froze the real island on real hardware.**
///
/// ## What happened, measured rather than reasoned about
///
/// Plan 7 Task 6 ran the whole chain for real: Codex CLI 0.145.0 → a generated
/// hook snippet → `vibecat-hook` → the socket → the signed `VibeCat.app` → a
/// `SessionRow` drawing a custom source's icon at
/// `/Users/gcat332/Downloads/icon/codex_logo.png`. The island went dead. A
/// `sample` of the live process put the **main thread** here:
///
/// ```
/// HookLoopProbe.report → SourceIcon.loadValidImage → NSImage(contentsOfFile:)
///   → NSData(contentsOfFile:) → open (in libsystem_kernel.dylib) → __open
/// ```
///
/// blocked in `open(2)`, for over a minute, until the process was killed.
/// `~/Downloads` is a TCC-protected location. A bundle launched with `open` is
/// attributed to *itself* rather than to the terminal, so it has no inherited
/// grant; TCC therefore has to ask, the app is `LSUIElement` with no way to
/// present that prompt, and `open(2)` simply never returns. The same applies to
/// `~/Documents`, `~/Desktop`, iCloud Drive, a removable volume, and any network
/// mount that has gone away.
///
/// **This is not a slow read, it is an unbounded wait on the main thread**, and
/// it broke two rules at once: §2.3's "every wait is bounded", and this plan's
/// own Global Constraint that a custom source's *"missing icon … must degrade,
/// never crash and never block."* The old comment on `loadValidImage` claimed
/// "must not throw, hang or crash" and enumerated five bad inputs — every one of
/// them a file whose `open(2)` *returns*. A path that never answers was not in
/// the list, and no test could have found it: every fixture is a real file in
/// `/tmp`, which the test process can always read.
///
/// ## What bounds it
///
/// The read happens on a dedicated `Thread` — see `image(atPath:)` for the
/// full-suite failure that ruled out a dispatch queue; the caller waits on a
/// semaphore for
/// at most `deadline`. Three outcomes:
///
/// - **Answered in time** — the image (or `nil` for a genuinely bad file) is
///   cached and returned. A 256×256 PNG on this machine reads in well under a
///   millisecond, so the ordinary path pays the semaphore and nothing else.
/// - **Not answered in time** — the caller gets `nil`, `SourceIcon` draws
///   `CLIMark`'s geometric mark, and the background read keeps going and caches
///   the real answer if it ever lands, so a later render self-heals. A `nil`
///   here is exactly the same value "this source has no icon" produces, which is
///   why the fallback needs no new branch.
///
///   The timeout branch deliberately writes **nothing** to the cache, and that
///   is a conservative choice rather than a load-bearing one — **measured, and
///   the measurement contradicts what this comment first claimed.** Writing a
///   `nil` there instead leaves every test in `SourceIconHangTests` green,
///   because the in-flight read overwrites the cache the moment it completes, and
///   in the case where it never completes `inFlight` still holds the path so the
///   observable answer is `nil` either way. There is no input that can tell the
///   two versions apart. Kept as written because "do not record an answer you
///   did not get" is the safer shape if the cache ever stops being overwritten,
///   and recorded as unproven rather than presented as necessary.
/// - **Never answered** — the background thread stays parked on `open(2)` for the
///   life of the process. That is a leaked thread, and it is the deliberate
///   trade: one parked thread costs an idle stack, and the alternative is a
///   frozen island. `inFlight` is what stops it from becoming *one parked thread
///   per render* — the case that would matter.
///
/// ## Why synchronous-with-a-deadline rather than async-with-invalidation
///
/// The obviously "correct" shape is an `@Observable` cache that returns `nil`
/// immediately, loads in the background and invalidates the view when the image
/// arrives. It is also a larger change: `SourceIcon.body` would always draw the
/// fallback on first render, every existing golden assertion in
/// `SourceIconTests` and `SessionRowTests` that expects a brand colour in one
/// synchronous `rasterise` would have to become an eventually-consistent
/// assertion, and `ImageRenderer` has no second pass to give them. Bounding the
/// wait fixes the defect that was actually observed — an *unbounded* one — while
/// leaving the synchronous contract those tests rest on intact. Recorded as a
/// trade, not presented as ideal: if icons ever come off the network, the async
/// shape is the right one.
///
/// ## What this file's tests can and cannot reproduce
///
/// **The TCC stall itself is not reproducible in this suite, and a first attempt
/// to fake it produced four tests that could not fail.** The obvious stand-in is
/// a FIFO with no writer, since `open(2)` on one blocks. Measured: it does not
/// reach `open(2)` at all — `NSImage(contentsOfFile:)` on a FIFO returns `nil` in
/// 7ms, because Foundation `stat`s first and refuses a non-regular file. Four
/// tests written against that fixture passed in 0.001s each, which is to say they
/// would have passed against the unbounded code they were written to catch.
///
/// So `read` is injectable, and the tests drive the timeout branch with a read
/// that takes a known time. That is a faithful model of the defect — the defect
/// *is* "a read that takes arbitrarily long" — and it is falsifiable: against an
/// unbounded implementation the first call returns the image late instead of
/// `nil` early, and the assertion fails. What the injection cannot prove is that
/// the real `readImage` is the thing that can stall; the `sample` stack quoted
/// above is the evidence for that, and it came from hardware rather than from a
/// test.
final class SourceIconLoader: @unchecked Sendable {
    static let shared = SourceIconLoader()

    /// How long the caller waits. Chosen against a measurement, not by feel: a
    /// 256×256 PNG read plus decode is sub-millisecond on this machine, so 50ms
    /// is ~50× headroom for a cold page cache while staying under a single 60Hz
    /// frame — the island can absorb one at the moment a new source's first row
    /// appears, and the cache means it happens once per path per process.
    static let defaultDeadline: TimeInterval = 0.05

    let deadline: TimeInterval
    private let read: @Sendable (String) -> NSImage?

    init(deadline: TimeInterval = SourceIconLoader.defaultDeadline,
         read: @escaping @Sendable (String) -> NSImage? = { SourceIcon.readImage(atPath: $0) }) {
        self.deadline = deadline
        self.read = read
    }

    private let lock = NSLock()
    /// `[path: image?]` — a cached `nil` is a real answer ("that file is not a
    /// usable image"), which is why the value is a double optional and why a
    /// timeout must not write one.
    private var cache: [String: NSImage?] = [:]
    private var inFlight: Set<String> = []

    func image(atPath path: String) -> NSImage? {
        lock.lock()
        if let cached = cache[path] {
            lock.unlock()
            return cached
        }
        let alreadyRunning = inFlight.contains(path)
        if !alreadyRunning { inFlight.insert(path) }
        lock.unlock()

        // A read already in flight from an earlier render gets no new thread and
        // no wait at all: whatever it is doing, this render's answer is "not yet".
        guard !alreadyRunning else { return nil }

        // **A real `Thread`, not `DispatchQueue.async` and not `Task.detached`, and
        // this is a measured requirement rather than a preference.** The first
        // version dispatched onto a concurrent `.utility` queue. It passed alone and
        // failed **ten assertions across six tests under full-suite load** — with
        // `counter.count == 0`, i.e. the read block had not begun at all inside the
        // 50ms deadline, so every icon in the suite fell back and nothing was ever
        // cached. A shared dispatch pool under a saturated suite (or a busy machine)
        // cannot promise that a submitted block *starts*, and a deadline whose whole
        // purpose is to bound a read is worthless if the read has not begun when it
        // expires. This is the same reasoning `AppModel.applyAndNotify` already
        // records for `SocketServer`'s "real, uncounted `Thread`s" against Swift's
        // "small, shared cooperative thread pool", arrived at here independently by
        // a full-suite failure.
        //
        // Priority is set below `.userInitiated` rather than raised: a thread that
        // may park forever on `open(2)` should not hold a high-priority slot, and
        // with a dedicated thread it does not need one to *start*.
        let semaphore = DispatchSemaphore(value: 0)
        let worker = Thread { [weak self] in
            guard let self else { return }
            let image = read(path)
            lock.lock()
            cache[path] = image
            inFlight.remove(path)
            lock.unlock()
            semaphore.signal()
        }
        worker.name = "com.gcat332.vibecat.source-icon"
        worker.qualityOfService = .utility
        worker.start()

        guard semaphore.wait(timeout: .now() + deadline) == .success else {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        return cache[path] ?? nil
    }

    /// Drops everything, so a test that writes a file at a path it already
    /// asked about is not answered from the cache. Production never calls this:
    /// an icon path's contents changing mid-session is a Plan 6.7 concern (the
    /// file picker), and re-reading on every render is what this type exists to
    /// avoid.
    func clearForTesting() {
        lock.lock()
        cache.removeAll()
        inFlight.removeAll()
        lock.unlock()
    }
}
