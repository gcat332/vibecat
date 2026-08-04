import Foundation
import AVFoundation
import VibeCatCore

/// The only file in this plan that touches an audio device.
///
/// Deliberately thin. Everything that decides what VibeCat sounds like — the
/// waveforms, the envelope, the note tables, which cue fires — is a pure
/// function in a neighbouring file, because an audio render path is invisible to
/// this project's tests in exactly the way a `Canvas` renderer is: the work
/// happens somewhere no `#expect` can reach. `buffer(for:)` is exposed so the
/// gating decisions *are* testable.
///
/// **What the engine below it has and has not been shown to do.** Measured
/// 2026-08-03 from a signed `VibeCat.app` driven by real hook payloads, with a
/// throwaway probe inside `play`: a `stop` payload scheduled 39,840 frames and a
/// `permission` payload 32,639 frames — 0.83s and 0.68s at the device's own
/// 48kHz, matching §12's ~0.81s and ~0.66s plus `CueRenderer.releaseTail` —
/// into 2 channels, with `startIfNeeded()` returning `true` and
/// `engine.isRunning` `true` in both cases, and the app still alive afterwards.
/// **Nobody has listened to it.** Whether it sounds like the prototype, whether
/// a note's release clicks, and whether `done`'s held G6 carries inharmonic hash
/// are all open — they need an ear, and the agent that wrote this does not have
/// one. Recorded as open rather than assumed passed.
///
/// **What a cue costs, and why none of it is on the main actor any more.**
/// `getrusage(RUSAGE_SELF)` user CPU at 48kHz, debug build, measured 2026-08-03
/// with `VIBECAT_SOUND_COST=1 swift test --filter soundRenderCost`: `meow` 39ms,
/// `ask` 44ms, `askMulti` 47ms, `done` 59ms, `error` **858ms**.
///
/// `error` is the outlier because B♭3 = 233Hz admits 94 harmonics and a sawtooth
/// sums all of them, not just the odd ones, across 0.46s. `swiftc -O` brings the
/// same figures to 2.9–15.8ms — but **`Scripts/build-app.sh` builds debug**, and
/// that is the documented way to run this app for anything needing permissions.
/// An earlier version of this file rendered inline on the main actor, so one
/// `failed` event froze the island for most of a second and delayed the
/// `Task { @MainActor … present }` for any `wantsReply` event queued behind it,
/// inside a deadline the socket thread was already counting.
@MainActor public final class SoundPlayer {
    public var settings: SoundSettings
    private let quietHours: QuietHours
    /// `internal`, not `private`, so a test can post the real
    /// `AVAudioEngineConfigurationChange` for *this* engine. The defect being pinned
    /// is that nothing observed that notification at all, and a test that called the
    /// handler directly would not notice the observer being gone.
    let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    /// Two flags, not one, and the distinction is a crash: `AVAudioEngine.attach`
    /// raises an ObjC exception on a node it already holds, so `attached` must
    /// never be reset — whereas `connect` documents itself as *replacing* an
    /// existing connection, which is what makes re-connecting after a
    /// configuration change safe. A single `wired` flag cannot express both, and
    /// resetting it would re-attach.
    private var attached = false
    /// `internal` for the same reason as `engine`: whether the graph was dropped is
    /// the observable consequence of a configuration change.
    var connected = false
    private var configurationObserver: NSObjectProtocol?

    /// Rendered cues, and the inputs they were rendered for.
    ///
    /// `CueRenderer.render` is pure in `(cue, settings, sampleRate)` and there are
    /// five cues, so the whole set is worth about 900kB of `Float` at 48kHz and
    /// changes only when the user changes a setting or the output device changes
    /// rate. `cacheKey` carries both, so the invalidation is not a rule someone
    /// has to remember to apply — a mismatch empties the cache on the next use.
    ///
    /// **The key is the render-relevant subset of the settings, not the whole
    /// struct, and that is a fix rather than an optimisation.** `enabled` was in the
    /// key, so muting *or* un-muting emptied the cache and the next cue of each kind
    /// re-paid its render — measured with `getrusage(RUSAGE_SELF)` at **837.8ms for
    /// `error`** in a debug build, which is what `Scripts/build-app.sh` produces.
    /// `enabled` cannot change what a cue sounds like; it decides only whether one
    /// plays, which is `wantsSilence`'s job. Same for `quietDuringDoNotDisturb`.
    ///
    /// What makes dropping `enabled` from the key safe is that **nothing renders
    /// while sound is off**: `wantsSilence` covers `enabled` and guards all three
    /// entry points, `prewarm()` included. Without that guard `CueRenderer.render`
    /// would return `[]` for a muted player and those empty buffers would be cached
    /// under a key that says nothing about muting — silence for the rest of the
    /// session. The invariant is "the cache only ever holds real samples", pinned by
    /// `aMutedPlayerCachesNothingRatherThanCachingSilence`.
    ///
    /// **The two changes turned out to be redundant on cost, and that is measured,
    /// not assumed.** `getrusage(RUSAGE_SELF)`, debug, `error`, cost of the first
    /// cue after a mute round trip:
    ///
    ///     whole-settings key, no `enabled` in `wantsSilence`   859.0ms  (as shipped)
    ///     narrowed key alone                                     0.089ms
    ///     `wantsSilence` guard alone                              0.133ms
    ///     both                                                    0.170ms
    ///
    /// The guard removes the cost by a different route: it returns before
    /// `discardCacheIfInputsChanged` is ever reached, so with the guard in place a
    /// key that still carried `enabled` could never act on it. Which means
    /// `mutingDoesNotThrowAwayTheRenderedCues` **cannot** fail if the key is widened
    /// back — reported rather than adjusted. What does fail is
    /// `flippingAGateThatCannotChangeAWaveformKeepsTheCache`: a loud machine reaches
    /// the cache with the Do Not Disturb switch in either position, so that input
    /// separates the two changes where `enabled` cannot.
    ///
    /// `internal` so a test can see whether a cache exists. There is nothing else to
    /// look at: rendering is idempotent, so "did this come from the cache?" is
    /// invisible from the outside.
    var rendered: [Cue: [Float]] = [:]
    private var cacheKey: CacheKey?
    private var renderInFlight: Set<Cue> = []

    /// The inputs `CueRenderer.render` reads to produce samples, and nothing else.
    /// `enabled` and `quietDuringDoNotDisturb` are deliberately absent — see
    /// `rendered`. Constructed from a whole `SoundSettings` so that adding a field
    /// to that type is a deliberate decision here rather than a silent omission.
    private struct CacheKey: Equatable {
        let volume: Double
        let pack: SoundPack
        let sampleRate: Double

        init(settings: SoundSettings, sampleRate: Double) {
            volume = settings.volume
            pack = settings.pack
            self.sampleRate = sampleRate
        }
    }

    /// A dedicated serial queue, deliberately **not** the cooperative pool.
    ///
    /// A cue render is hundreds of milliseconds of tight CPU in a debug build, and
    /// `Task.detached` draws from Swift's small shared cooperative pool — the same
    /// pool whose exhaustion `AppModel.applyAndNotify`'s comment records as having
    /// produced a full-suite-only flake. Occupying one of those threads with
    /// arithmetic for most of a second is the same mistake wearing different
    /// clothes. A serial queue also means five cues render one after another
    /// instead of saturating five cores at launch.
    private let renderQueue = DispatchQueue(label: "cat.vibe.sound.render",
                                            qos: .userInitiated)

    /// When the audio already handed to the player node will finish, in wall
    /// clock. See `maximumBacklog`.
    private var queueEndsAt = Date.distantPast

    /// **The written decision about serial scheduling.**
    ///
    /// The prototype's `cue()` creates fresh oscillators on every call
    /// (`island-motion.html:914-917`) and connects each straight to
    /// `ac.destination`, so two cues arriving close together *mix*.
    /// `AVAudioPlayerNode.scheduleBuffer` appends to a queue instead, so they play
    /// back to back. That is a divergence from the reference implementation, and
    /// this repo's standing rule is that a divergence is either a fix or a written
    /// decision, never a silent third thing. **Serial stays**, for two reasons:
    /// mixing needs a mixer graph and a player node per voice, which is real
    /// machinery for a case that is rare; and two chiptune alerts summed at full
    /// gain is louder than either, where queued ones stay at a level someone has
    /// already chosen.
    ///
    /// What could not stay is the *unbounded* queue. N events in a burst put the
    /// Nth alert 0.6…0.9s × (N−1) after the thing it announces — `.done` in
    /// particular bypasses every state-change guard (`CueSelector.swift:50`) and so
    /// has no rate limit of its own, and `SessionStore.apply` does not dedupe by
    /// `event.id`, so a retransmission cues again. An alert that arrives two
    /// seconds late is not information, it is noise, and the state it would have
    /// announced is on the island already.
    ///
    /// So: a cue that would begin more than this far in the future is **dropped,
    /// not queued**. One second is a little longer than the longest cue (`error`,
    /// 0.93s), which makes the rule "at most one cue may be waiting". The bound is
    /// wall-clock rather than a count of outstanding buffers on purpose — time
    /// passes on its own, so nothing can wedge this at "full" and silence the app
    /// for the rest of the session the way a counter with a missed completion
    /// callback would.
    public nonisolated static let maximumBacklog: TimeInterval = 1.0

    /// The backlog rule itself, as a pure function — the same reason every other
    /// decision in this plan lives outside the player: `schedule` needs an output
    /// device to reach, and this repo has no way to stage one.
    ///
    /// `nil` means drop. Otherwise, when the cue would start and when the queue
    /// would then end.
    ///
    /// `nonisolated` because it needs no actor: it reads nothing but its arguments,
    /// which is the property that makes it testable in the first place.
    nonisolated static func admission(now: Date, queueEndsAt: Date,
                          duration: TimeInterval) -> (startsAt: Date, endsAt: Date)? {
        let startsAt = max(now, queueEndsAt)
        guard startsAt.timeIntervalSince(now) < maximumBacklog else { return nil }
        return (startsAt, startsAt.addingTimeInterval(duration))
    }

    public init(settings: SoundSettings = SoundSettings(),
                quietHours: QuietHours = NeverQuiet()) {
        self.settings = settings
        self.quietHours = quietHours
        // `AVAudioEngine`'s documented contract is that a configuration change —
        // plugging or unplugging headphones is enough — stops the engine and
        // invalidates the graph's connections to the I/O nodes. Nothing observed
        // this before, and the old single `wired` flag was set once and never
        // cleared, so a device being *replaced* mid-session left the engine
        // restartable but never re-connected: either every later cue silently
        // vanished, or `scheduleBuffer` was handed a buffer whose format no longer
        // matched the connection, which is a documented `NSInvalidArgumentException`
        // and uncatchable from Swift. **A crash here can hang a terminal (§2.3)**,
        // so it is handled defensively even though it could not be reproduced from
        // this session — see `handleConfigurationChange`.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine,
            queue: .main
        ) { [weak self] _ in
            // `queue: .main` runs the block on `OperationQueue.main`, which is the
            // main thread, so the actor is genuinely held here.
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
    }

    /// `NotificationCenter`'s block observers are not auto-removed, and the centre
    /// holds the block until they are. `isolated deinit` because this class is
    /// `@MainActor` — the same shape `AppModel` and `HoverMonitor` use, and for the
    /// same reason: anything with a lifecycle tears itself down.
    isolated deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    /// `nil` when nothing should be heard: sound off, the pack is silent, or the
    /// machine is asking for quiet and the user left that switch on.
    ///
    /// **Renders on the calling actor if the cue is not cached yet.** `play` does
    /// not take this path, for the reason in this type's own doc comment; this one
    /// exists so the gating decisions are reachable from a test without an audio
    /// device, and so a caller that genuinely wants the samples in hand can have
    /// them.
    public func buffer(for cue: Cue) -> [Float]? {
        guard !wantsSilence else { return nil }
        let rate = outputSampleRate
        discardCacheIfInputsChanged(sampleRate: rate)
        if let samples = rendered[cue] { return samples.isEmpty ? nil : samples }
        let samples = CueRenderer.render(cue, settings: settings, sampleRate: rate)
        rendered[cue] = samples
        return samples.isEmpty ? nil : samples
    }

    /// Whether anything should be produced at all: sound turned off, or the machine
    /// asking for quiet with that switch left on.
    ///
    /// **`enabled` is checked here rather than relied on inside
    /// `CueRenderer.render`.** The renderer does return `[]` for a disabled
    /// `SoundSettings`, and until the cache key stopped carrying `enabled` that was
    /// enough. It is not any more: a render that happens while muted would cache
    /// those empty buffers under a key that cannot tell muted from un-muted. So the
    /// gate is here, in front of every path that can populate the cache, and the
    /// renderer's own guard is now a second layer rather than the only one.
    private var wantsSilence: Bool {
        !settings.enabled || (settings.quietDuringDoNotDisturb && quietHours.isQuiet)
    }

    private var outputSampleRate: Double {
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        // A zero here means no output device is attached, which happens in CI
        // and on a headless machine. 44.1k keeps the pure renderer's arithmetic
        // well-defined; nothing will be heard either way.
        return rate > 0 ? rate : 44_100
    }

    public func play(_ cue: Cue) {
        guard !wantsSilence else { return }
        let rate = outputSampleRate
        discardCacheIfInputsChanged(sampleRate: rate)
        if let samples = rendered[cue] {
            schedule(samples, renderedAt: rate)
            return
        }
        render(cue, sampleRate: rate, thenSchedule: true)
    }

    /// Renders every cue off the main actor, so the first `failed` event of a
    /// session is not the one that waits 858ms for a sawtooth.
    ///
    /// Called from `Sources/VibeCatApp/main.swift` rather than from `init`, so that
    /// a test constructing a player does not start five background renders it never
    /// asked for.
    public func prewarm() {
        // Muted, or quiet hours: rendering now would fill the cache with `[]` under a
        // key that says nothing about either. See `wantsSilence`. `setEnabled(true)`
        // is what re-runs this once sound comes back.
        guard !wantsSilence else { return }
        let rate = outputSampleRate
        discardCacheIfInputsChanged(sampleRate: rate)
        for cue in Cue.allCases where rendered[cue] == nil {
            render(cue, sampleRate: rate, thenSchedule: false)
        }
    }

    /// Turns sound on or off, and re-warms the cache when turning it on.
    ///
    /// A method rather than letting `main.swift` assign `settings.enabled` directly,
    /// because the re-warm is the part that is easy to leave out and impossible to
    /// test in `main.swift`. It matters only in one case — the app launched muted, so
    /// `prewarm()` at startup rendered nothing — but that case ends with the first
    /// `error` cue arriving its own 838ms late, which is the one that matters most.
    /// A mute/un-mute round trip within a session costs nothing at all now: the key
    /// does not move, so the cache is still there.
    public func setEnabled(_ enabled: Bool) {
        guard enabled != settings.enabled else { return }
        settings.enabled = enabled
        if enabled { prewarm() }
    }

    private func render(_ cue: Cue, sampleRate: Double, thenSchedule: Bool) {
        guard renderInFlight.insert(cue).inserted else { return }
        let key = CacheKey(settings: settings, sampleRate: sampleRate)
        let settings = self.settings
        renderQueue.async { [weak self] in
            let samples = CueRenderer.render(cue, settings: settings, sampleRate: sampleRate)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.renderInFlight.remove(cue)
                    // The inputs may have moved on while this was rendering — a
                    // settings change, or the device switching rate. The key is
                    // checked rather than assumed, so a stale buffer is dropped
                    // instead of cached under inputs it does not belong to.
                    guard self.cacheKey == key else { return }
                    self.rendered[cue] = samples
                    if thenSchedule { self.schedule(samples, renderedAt: sampleRate) }
                }
            }
        }
    }

    private func discardCacheIfInputsChanged(sampleRate: Double) {
        let key = CacheKey(settings: settings, sampleRate: sampleRate)
        guard cacheKey != key else { return }
        cacheKey = key
        rendered.removeAll()
    }

    private func schedule(_ samples: [Float], renderedAt sampleRate: Double) {
        guard !samples.isEmpty else { return }
        let format = engine.outputNode.outputFormat(forBus: 0)
        // Two guards, not one. A zero rate is no output device. A rate that no
        // longer matches the one these samples were rendered for would play the
        // cue at the wrong pitch — drop it; `discardCacheIfInputsChanged` has
        // already emptied the cache, so the next cue re-renders at the new rate.
        guard format.sampleRate > 0, format.sampleRate == sampleRate else { return }

        // The backlog bound. See `maximumBacklog` for the decision this enforces.
        let duration = Double(samples.count) / sampleRate
        guard let window = Self.admission(now: Date(), queueEndsAt: queueEndsAt,
                                          duration: duration)
        else { return }

        guard let pcm = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        pcm.frameLength = AVAudioFrameCount(samples.count)
        // Mono content into however many channels the device has: §12's cues
        // are a chip's monophonic voice, and panning one would be an invention.
        for channel in 0..<Int(format.channelCount) {
            guard let data = pcm.floatChannelData?[channel] else { continue }
            samples.withUnsafeBufferPointer { data.update(from: $0.baseAddress!, count: samples.count) }
        }
        guard startIfNeeded() else { return }
        node.scheduleBuffer(pcm, completionHandler: nil)
        node.play()
        queueEndsAt = window.endsAt
    }

    /// **Not reproduced — reasoned from `AVAudioEngine`'s documented contract.**
    /// Unplugging or replacing an output device could not be done from the session
    /// that wrote this, so what follows is defensive rather than observed, and is
    /// labelled that way per this repo's rule about unmeasured claims. What is not
    /// in doubt is the shape of the contract: the engine stops, and the connections
    /// to the I/O nodes have to be made again.
    ///
    /// `node.stop()` only while the engine is running. `play()` on a node whose
    /// engine has stopped is a documented ObjC exception, and while `stop()` is not
    /// documented as raising, this whole path exists to avoid taking the app down
    /// on an audio detail — so it asks first.
    private func handleConfigurationChange() {
        connected = false
        if engine.isRunning { node.stop() }
        // Nothing is queued any more: the engine stopped and took the node's
        // playback with it. Leaving `queueEndsAt` in the future would drop the
        // next cue for a backlog that no longer exists.
        queueEndsAt = .distantPast
        // The replacement device may run at a different rate, which makes every
        // rendered buffer wrong rather than merely stale. `cacheKey` would catch it
        // on the next use anyway; clearing here means ~900kB is not held for a
        // configuration nobody is in.
        rendered.removeAll()
        cacheKey = nil
    }

    /// Attaches the node once, connects it whenever the connection is gone, then
    /// makes sure the engine is running. Returns whether it is.
    ///
    /// Two crash paths this shape exists to close, both reachable only after a
    /// failed `start()` — a device disappearing mid-session is enough:
    /// `AVAudioEngine.attach` raises on a node it already holds, so a retry must
    /// not re-attach; and `AVAudioPlayerNode.play()` raises when the engine is
    /// not running, so the caller must not schedule into a dead engine. Both
    /// are Objective-C exceptions, which Swift cannot catch — they would take
    /// the app down, and an island that dies is an island that can hang a
    /// terminal (§2.3). Failing silent is the whole contract here: nothing in
    /// §12 is worth taking the app down for.
    private func startIfNeeded() -> Bool {
        if !attached {
            engine.attach(node)
            attached = true
        }
        if !connected {
            engine.connect(node, to: engine.mainMixerNode,
                           format: engine.outputNode.outputFormat(forBus: 0))
            connected = true
        }
        if engine.isRunning { return true }
        do { try engine.start(); return true }
        catch { return false }
    }
}
