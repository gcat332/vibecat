import Testing
import Foundation
@testable import VibeCatUI

// MARK: - What a cue costs, measured rather than assumed

/// Env-gated, like the raster preview tools: it prints numbers and asserts nothing
/// about them, because a CPU figure is a property of the machine that ran it and a
/// threshold here would be a flake on every other machine.
///
///     VIBECAT_SOUND_COST=1 swift test --filter soundRenderCost
///
/// **`getrusage(RUSAGE_SELF)`, never `ps %cpu`** — the latter is a decaying average
/// and has produced a false failure in this repo before.
///
/// Two figures, because they answer two different questions:
///
/// - **render** is what `CueRenderer.render` costs. It is the number that used to be
///   paid on the main actor, inline inside `SoundPlayer.play`.
/// - **play, cached** is what `SoundPlayer.play` costs *on the main actor* once the
///   buffer exists: a key comparison, a dictionary lookup, a backlog check, and — on
///   a machine with no output device, which is this test and every CI machine — an
///   early return out of `schedule`. It is what remains of the freeze.
///
/// The gap between the two columns is the fix. It is not the whole story on a
/// machine that *does* have an output device, where `schedule` also allocates an
/// `AVAudioPCMBuffer` and copies the samples into it; that part was never measured
/// and is labelled here rather than guessed at.
@Test @MainActor func soundRenderCost() {
    guard ProcessInfo.processInfo.environment["VIBECAT_SOUND_COST"] != nil else { return }
    let rate = 48_000.0   // the rate the ledger records the real device running at
    let settings = SoundSettings()

    var lines = ["cue          render(ms)   play, cached(ms)"]
    for cue in Cue.allCases {
        // Warm once: the first render of the process pays for page faults and for
        // `pow`/`sin` being resolved, neither of which is per-cue cost.
        _ = CueRenderer.render(cue, settings: settings, sampleRate: rate)

        var mark = userCPUSeconds()
        _ = CueRenderer.render(cue, settings: settings, sampleRate: rate)
        let render = (userCPUSeconds() - mark) * 1000

        // `buffer(for:)` renders synchronously and populates the same cache `play`
        // reads, which is exactly the state `prewarm()` leaves the player in.
        let player = SoundPlayer(settings: settings, quietHours: NeverQuiet())
        _ = player.buffer(for: cue)
        mark = userCPUSeconds()
        player.play(cue)
        let play = (userCPUSeconds() - mark) * 1000

        lines.append(String(format: "%-10@ %11.2f %18.3f", cue.rawValue as NSString, render, play))
    }
    print(lines.joined(separator: "\n"))
}

/// Copied in spirit from `Sources/VibeCatApp/BadgeCPUProbe.swift`, which is this
/// repo's reference for how to ask this question.
private func userCPUSeconds() -> Double {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return .nan }
    return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
}

/// What a mute round trip costs, and what a volume change still costs.
///
///     VIBECAT_SOUND_COST=1 swift test --filter soundMuteRoundTripCost
///
/// The final review's carried item 3: `enabled` was part of the cache key, so
/// muting *or* un-muting emptied `rendered` and the next cue of each kind re-paid
/// its own render. `error` is the one that matters — B♭3 = 233Hz admits 94
/// harmonics and a sawtooth sums all of them.
///
/// Three figures, and the third is the point of the second:
///
/// - **cold** is the render, paid once. It is the number the ledger recorded.
/// - **after a mute round trip** is what un-muting costs now. It should be
///   arithmetic on a dictionary, because the key does not mention `enabled`.
/// - **after a volume change** must stay at roughly *cold*, because volume does
///   change what a cue sounds like. A key narrowed too far would show this at
///   zero, and that is a worse defect than the one being fixed — the wrong sound
///   rather than a late one.
///
/// `getrusage(RUSAGE_SELF)`, never `ps %cpu`.
@Test @MainActor func soundMuteRoundTripCost() {
    guard ProcessInfo.processInfo.environment["VIBECAT_SOUND_COST"] != nil else { return }
    let cue = Cue.error
    // Warm the process once: page faults and `pow`/`sin` resolution are not per-cue
    // cost. Same reason `soundRenderCost` above does it.
    _ = CueRenderer.render(cue, settings: SoundSettings(), sampleRate: 48_000)

    let player = SoundPlayer(settings: SoundSettings(), quietHours: NeverQuiet())
    var mark = userCPUSeconds()
    _ = player.buffer(for: cue)
    let cold = (userCPUSeconds() - mark) * 1000

    player.settings.enabled = false
    _ = player.buffer(for: cue)           // a use while muted, which is what used to invalidate
    player.settings.enabled = true
    mark = userCPUSeconds()
    _ = player.buffer(for: cue)
    let afterMute = (userCPUSeconds() - mark) * 1000

    player.settings.volume = 0.31
    mark = userCPUSeconds()
    _ = player.buffer(for: cue)
    let afterVolume = (userCPUSeconds() - mark) * 1000

    print(String(format: "MUTEROUNDTRIP %@: cold %.2fms | after mute round trip %.3fms | after volume change %.2fms",
                 cue.rawValue as NSString, cold, afterMute, afterVolume))
}
