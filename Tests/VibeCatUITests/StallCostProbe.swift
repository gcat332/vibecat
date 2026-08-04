import Testing
import Foundation
@testable import VibeCatUI
import VibeCatCore

// MARK: - What an unconditional stall tick would cost, measured rather than assumed

/// Env-gated, like `SoundCostProbe.swift`: prints numbers and asserts nothing about
/// them, because a CPU figure is a property of the machine that ran it.
///
///     VIBECAT_STALL_COST=1 swift test --filter stallTickCost
///
/// `getrusage(RUSAGE_SELF)`, never `ps %cpu` — the latter is a decaying average and
/// has produced a false failure in this repo before.
///
/// §6.1 says an idle machine must cost nothing, and Plan 6.5's Task 5 is the first
/// thing in the app that could quietly break that with a *tick* rather than a
/// render loop: `AppModel.prune` rides its own 60s `Timer` regardless of whether
/// anything is stale, so whatever it does on every tick is a permanent cost, not a
/// one-off. The shipped implementation guards both of the ways that could go
/// wrong — `StallDetector.stalled` already excludes anything in `stalledReported`,
/// and `prune` only calls `onStall` for what that leaves — so a steady-state idle
/// tick with nothing newly stalled should cost one array scan and call nothing.
///
/// This measures that steady state against the mutation the plan asks for: what if
/// `prune` called `onStall` for *every* still-stalled session on *every* tick,
/// rather than only the newly-stalled ones? `steady (guarded)` is the shipped code.
/// `unconditional (mutated)` is measured by hand: temporarily deleting the
/// `stalledReported.formUnion`/`!newlyStalled.isEmpty` guard in `AppModel.prune`,
/// rebuilding, and rerunning this same probe — never a mutation this file applies
/// itself, because a toggle for it would be exactly the "shipped code path for a
/// measurement" `cpu-measurer.md` rules out.
///
/// **What this can and cannot tell you.** `onStall` is wired to a plain counter
/// here because nothing in the app consumes it yet — Task 7's `Notifier` is the
/// first real consumer, and posting a system notification is not measured by this
/// probe. So this isolates the cost of the *mechanism this task adds* (the extra
/// `StallDetector.stalled` scan and the extra closure calls), not the cost of
/// whatever Task 7 eventually wires `onStall` to. Plan 4's bloom-end nudge is the
/// precedent for why that gap matters: an equal write there looked free in
/// isolation and cost 3.3% of a core once something downstream (a still `zzz`
/// timeline) was actually listening.
@Test @MainActor func stallTickCost() {
    guard ProcessInfo.processInfo.environment["VIBECAT_STALL_COST"] != nil else { return }

    let sessionCount = 50
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let store = InMemoryPreferenceStore(Preferences(alerts: AlertPolicy(onStall: true)))
    let m = AppModel(socketPath: "/tmp/vibecat-stallcost-unused.sock", preferences: store)

    for i in 0..<sessionCount {
        _ = m.ingest(VibeEvent(id: "e\(i)", cli: "claude-code", kind: .running,
                               session: "s\(i)", cwd: "/tmp/p\(i)"), now: t0)
    }

    var stallCount = 0
    m.onStall = { _ in stallCount += 1 }

    // Warm: the first past-threshold tick is where every session is newly
    // stalled and genuinely fires — that one-time cost is not what this probe
    // is measuring, and it must not be folded into the steady-state sample.
    let quiet = t0.addingTimeInterval(StallDetector.threshold)
    m.prune(now: quiet)
    #expect(stallCount == sessionCount, "warm-up must actually report every session once")
    stallCount = 0

    let iterations = 20_000
    let before = cpuSeconds()
    let clockBefore = ContinuousClock.now
    for _ in 0..<iterations {
        m.prune(now: quiet)   // steady state: nothing newly stalled, on the shipped code
    }
    let elapsed = (ContinuousClock.now - clockBefore).asStallSeconds
    let cpu = cpuSeconds() - before

    print(String(format: """

    stall tick cost — %d sessions, %d iterations, getrusage(RUSAGE_SELF)
    onStall firings during the timed loop: %d (0 means every tick was correctly guarded)
    wall clock: %.3fs | CPU: %.4fs | per-tick: %.2fµs | %.3f%% of one core
    """, sessionCount, iterations, stallCount, elapsed, cpu,
        (cpu / Double(iterations)) * 1_000_000, (cpu / elapsed) * 100))
}

/// The same steady state, with **Task 7's real consumer attached** — which is
/// the gap `stallTickCost`'s own doc comment names and refuses to guess at.
///
///     VIBECAT_STALL_COST=1 swift test --filter stallTickCostWithTheNotifier
///
/// `Notifier.postStalls(from:preferences:)` is what `main.swift` installs, so
/// this measures the shipped closure and not a counter standing in for it: on a
/// guarded tick it reads `Preferences.postsSystemNotification` from the store and
/// then does nothing, and that store read is the only cost this task adds to a
/// quiet machine. Two arms, because the interesting question is whether *having*
/// a consumer changes the steady-state price at all:
///
/// - `switch off` — `postsSystemNotification: false`, the shipping default. The
///   closure never posts.
/// - `switch on` — `postsSystemNotification: true`. Still nothing posts in the
///   steady state, because `StallDetector` excludes what is already reported.
///
/// The `Notifier` here is the fixed-state initialiser, so nothing in this loop
/// touches `UNUserNotificationCenter` (it could not: no bundle) or Apple events.
@Test @MainActor func stallTickCostWithTheNotifier() {
    guard ProcessInfo.processInfo.environment["VIBECAT_STALL_COST"] != nil else { return }

    let sessionCount = 50
    let iterations = 20_000
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func measure(postsSystemNotification: Bool) -> (cpu: Double, elapsed: Double, posts: Int) {
        let store = InMemoryPreferenceStore(
            Preferences(alerts: AlertPolicy(onStall: true),
                        postsSystemNotification: postsSystemNotification))
        let m = AppModel(socketPath: "/tmp/vibecat-stallcost-notifier-unused.sock",
                         preferences: store)
        let notifier = Notifier(notification: .granted, automation: .granted)
        notifier.postStalls(from: m, preferences: store)

        for i in 0..<sessionCount {
            _ = m.ingest(VibeEvent(id: "e\(i)", cli: "claude-code", kind: .running,
                                   session: "s\(i)", cwd: "/tmp/p\(i)"), now: t0)
        }
        // Warm: the one tick where every session is newly stalled and genuinely
        // posts. Not part of the sample — the same discipline `stallTickCost` uses.
        let quiet = t0.addingTimeInterval(StallDetector.threshold)
        m.prune(now: quiet)
        let warmPosts = notifier.postedForTesting.count

        let before = cpuSeconds()
        let clockBefore = ContinuousClock.now
        for _ in 0..<iterations { m.prune(now: quiet) }
        let elapsed = (ContinuousClock.now - clockBefore).asStallSeconds
        return (cpuSeconds() - before, elapsed, warmPosts)
    }

    let off = measure(postsSystemNotification: false)
    let on = measure(postsSystemNotification: true)

    print(String(format: """

    stall tick cost WITH Notifier.postStalls attached — %d sessions, %d iterations,
    getrusage(RUSAGE_SELF)
    switch off: CPU %.4fs | per-tick %.2fµs | at the real 60s cadence %.7f%% of one core | warm-up posts %d
    switch on:  CPU %.4fs | per-tick %.2fµs | at the real 60s cadence %.7f%% of one core | warm-up posts %d
    (the loop runs flat out, so a "%% of one core" taken over the loop's own wall clock is
     ~100%% by construction and means nothing; the cadence figure is the one that does.
     Warm-up posts are capped at Notifier.postHistoryLimit = %d, so 20 here means all 50
     stalls fired and the ring buffer kept the last 20. A 0 would mean the consumer is
     not wired at all, and every per-tick number would be measuring nothing.)
    """, sessionCount, iterations,
        off.cpu, (off.cpu / Double(iterations)) * 1_000_000,
        ((off.cpu / Double(iterations)) / 60) * 100, off.posts,
        on.cpu, (on.cpu / Double(iterations)) * 1_000_000,
        ((on.cpu / Double(iterations)) / 60) * 100, on.posts,
        Notifier.postHistoryLimit))
}

private func cpuSeconds() -> Double {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return .nan }
    func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
    return seconds(usage.ru_utime) + seconds(usage.ru_stime)
}

private extension Duration {
    var asStallSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
