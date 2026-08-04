import AppKit
import VibeCatCore
import VibeCatUI

// No Dock icon, no menu bar of our own. The equivalent of LSUIElement for a
// target with no Info.plist.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

#if DEBUG
// Task 9's own hardware unknown, measured by a person with a display — see
// KeyDownProbe's own doc comment for exactly what this prints and how to run
// it. Gated on both DEBUG and an explicit flag so this never runs by
// accident: an ordinary launch (double-click, `open` with no --args, or a
// release build regardless) always takes the normal path below.
if CommandLine.arguments.contains("--keydown-probe") {
    KeyDownProbe.run()
    app.run()   // pumps the run loop until KeyDownProbe's own Timer calls exit(0)
    // Not expected to run: every path through KeyDownProbe (both its abort
    // branches and its normal 8-second completion) ends the process with
    // `exit`, which never returns to this call site — confirmed by an actual
    // run of this binary (see KeyDownProbe's own doc comment). This exists so
    // that if a future change to KeyDownProbe ever stops doing that, this
    // fails loudly instead of silently falling through into the ordinary
    // socket-server startup below with a stray NotchPanel still on screen.
    fatalError("KeyDownProbe returned without exiting the process")
}

// The badge transforms' own unmeasured claim, gated exactly like the probe
// above and for the same reason — see BadgeCPUProbe's doc comment.
if CommandLine.arguments.contains("--badge-cpu-probe") {
    BadgeCPUProbe.run()
    app.run()   // pumps the run loop; the probe's own Task calls exit(0)
    fatalError("BadgeCPUProbe returned without exiting the process")
}
#endif

// Shows the screen-recording prompt only when explicitly asked to, with
// `VIBECAT_REQUEST_SCREEN_RECORDING=1`. Without it the app never prompts: the
// permission buys the aura a better guess at what is behind the island, and
// asking for a whole-screen grant at launch to improve the colour of a glow
// would be wildly out of proportion. Design §15 does not list it, and Plan 6's
// Settings should be where this becomes a choice rather than an env var.
BackdropSampler.requestAccessIfAskedTo()

// Plan 6.4 Task 4: the single persisted source of `Preferences.soundEnabled`
// — read once here so both the panel's own mute glyph (via `controller`) and
// the sound engine (via `soundPlayer` below) start in step with whatever was
// on disk from a previous launch, rather than each defaulting independently
// and disagreeing until the first toggle. §2.3 fail-open concern: `load()`
// is a synchronous `UserDefaults` read with no I/O that can block, so this
// cannot be the thing that hangs a terminal.
//
// Built *before* `model` now — Plan 6.5 Task 4 gives `AppModel` this same
// store so `CueSelector` gates on the user's real `Preferences.alerts`
// instead of `AppModel.init`'s own throwaway `InMemoryPreferenceStore()`
// default. That default exists for the ~20 test call sites across this
// module that predate the parameter and have no opinion on alert policy —
// this is the one call site that does, and skipping the argument here is
// exactly Plan 6.4's "persisted but never read" defect (`volume`,
// `quietDuringDoNotDisturb`, `selectedPage`, three times, six task reviews)
// recurring a fourth time, invisible to every test because none of them run
// this file.
let preferences = UserDefaultsPreferenceStore()
let model = AppModel(socketPath: SocketPath.default, preferences: preferences)
let controller = NotchController(model: model, preferences: preferences)

// §12's cues. The player is owned here rather than by AppModel or
// NotchController: AppModel stays free of AVFoundation so it remains testable
// without an audio device, and NotchController clears its callbacks on
// dismiss() — a sound is not part of the panel's lifecycle.
//
// The Focus authorization request goes next to BackdropSampler's above: both are
// permissions asked for at launch, and this one is asked for unconditionally
// because a user who turned sound on has already opted into the feature the
// permission serves. It is a no-op once the user has decided either way.
let quietHours = FocusStatusQuietHours()
quietHours.requestAuthorizationIfNeeded()
// `SoundSettings(_:)` seeded from the same `preferences` read above — see that
// `let`'s own comment. A stored mute must be honoured from the very first cue,
// not only after the first toggle of this session, and the same is true of the
// other two settings this type is the runtime home of: an earlier version of
// this line passed `enabled` alone, so `volume` and `quietDuringDoNotDisturb`
// were written to the plist by `save(_:)` and read by nothing. The mapping lives
// in `SoundSettings(_:)` rather than here because no test can run this file.
let soundPlayer = SoundPlayer(settings: SoundSettings(preferences.load()),
                              quietHours: quietHours)
// Renders all five cues on `SoundPlayer`'s own serial queue, before any event
// arrives. Measured at 858ms for `error` alone in a debug build — which is what
// `Scripts/build-app.sh` produces — so paying it here, off the main actor and once,
// is the difference between a cue that is late and an island that is frozen. See
// SoundPlayer's doc comment for the getrusage table.
soundPlayer.prewarm()
model.onCue = { [weak soundPlayer] in soundPlayer?.play($0) }
// Plan 6.4 Task 4's own seam: a mute toggle from the panel reaches
// `NotchController.toggleMute()`, which persists it and reports the fresh
// `Preferences.soundEnabled` value here — the one place that knows about
// both a `PreferenceStoring` and a `SoundPlayer`. `setEnabled(_:)` rather than
// `settings.enabled = _`, because un-muting has to be able to re-warm a cache
// that a muted launch left empty; a mute/un-mute round trip inside one session
// costs nothing, because `enabled` is no longer part of the cache key. See
// `SoundPlayer.rendered`'s own doc comment for the measurement.
controller.onSoundEnabledChanged = { [weak soundPlayer] enabled in
    soundPlayer?.setEnabled(enabled)
}

// Plan 6.5 Task 7: §14's `Elsewhere`. The authorization request sits next to
// `quietHours.requestAuthorizationIfNeeded()` above for the same reason — both
// are launch-time permissions — and, unlike Focus, this one is asked for even
// though `postsSystemNotification` ships off: the alert is the *channel*, and a
// user who later flips that switch should not have to relaunch to be asked. The
// call is a no-op in a bare binary; see `Notifier`'s own doc comment for the
// measured abort that guard prevents.
let notifier = Notifier()
notifier.requestAuthorizationIfNeeded()
// Task 5 shipped `AppModel.onStall` with nothing listening. This is the
// consumer: a stall has no `Cue` (§12 defines five and none is "stalled", and
// Plan 6.2's written decision 3 forbids inventing one), so a system
// notification is the whole alert. The wiring lives in `Notifier.postStalls`
// rather than as a closure here, because no test runs this file.
notifier.postStalls(from: model, preferences: preferences)

// Plan 6.4 Task 5: the gear in the drawer's footer is the *only* door to
// Settings — this app has no Dock icon and no menu bar, so there is no App menu
// to hang a `Settings…` item on and nothing in AppKit that would reopen the
// window for us. `SettingsWindowController` guarantees the single instance and
// raises the one that already exists, so this stays a plain forward with no
// state of its own. It shares the `preferences` store read above rather than
// building a second one, because a second store would be a second truth.
// `syncSoundSettings` and `playCue` are Plan 6.5 Task 7's other half of that
// same sharing rule: the Sound section previews through the *live* engine built
// above, so a pack chosen in Settings is audible on the very next `Play` and on
// the next real cue, rather than only after a relaunch. Both default to no-ops
// on this initialiser (fifteen test call sites rely on that) — which is exactly
// why omitting them here would be silent, and why they are named.
let settings = SettingsWindowController(
    store: preferences,
    syncSoundSettings: { [weak soundPlayer] in soundPlayer?.settings = $0 },
    playCue: { [weak soundPlayer] in soundPlayer?.play($0) })
controller.model.onOpenSettings = { settings.show() }

do {
    try model.start()
} catch {
    FileHandle.standardError.write(
        Data("vibecat: could not open the socket: \(error)\n".utf8))
    exit(1)
}

controller.refreshGeometry()
controller.present()

#if DEBUG
// Plan 6.4 Task 5's own hardware unknown — what activation does to
// `frontmostApplication` — which needs an unlocked screen and so could not be
// measured when the task was implemented. Gated exactly like the two probes
// above, and for the same reason; see `SettingsFocusProbe`'s doc comment for how
// to run it and how to read what it prints. Deliberately placed *after*
// `present()`, so the island is up and the probe drives the shipped gear closure
// rather than a window opened in isolation.
if CommandLine.arguments.contains("--settings-focus-probe") {
    SettingsFocusProbe.run(openSettings: { controller.model.onOpenSettings?() },
                           isOpen: { settings.isOpen })
}
#endif

app.run()
