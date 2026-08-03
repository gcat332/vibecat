import Foundation
import AVFoundation

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
@MainActor public final class SoundPlayer {
    public var settings: SoundSettings
    private let quietHours: QuietHours
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var wired = false

    public init(settings: SoundSettings = SoundSettings(),
                quietHours: QuietHours = NeverQuiet()) {
        self.settings = settings
        self.quietHours = quietHours
    }

    /// `nil` when nothing should be heard: sound off, the pack is silent, or the
    /// machine is asking for quiet and the user left that switch on.
    public func buffer(for cue: Cue) -> [Float]? {
        if settings.quietDuringDoNotDisturb && quietHours.isQuiet { return nil }
        let samples = CueRenderer.render(cue, settings: settings,
                                        sampleRate: outputSampleRate)
        return samples.isEmpty ? nil : samples
    }

    private var outputSampleRate: Double {
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        // A zero here means no output device is attached, which happens in CI
        // and on a headless machine. 44.1k keeps the pure renderer's arithmetic
        // well-defined; nothing will be heard either way.
        return rate > 0 ? rate : 44_100
    }

    public func play(_ cue: Cue) {
        guard let samples = buffer(for: cue) else { return }
        let format = engine.outputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format,
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
    }

    /// Attaches the node once, then makes sure the engine is running. Returns
    /// whether it is.
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
        if !wired {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode,
                           format: engine.outputNode.outputFormat(forBus: 0))
            wired = true
        }
        if engine.isRunning { return true }
        do { try engine.start(); return true }
        catch { return false }
    }
}
