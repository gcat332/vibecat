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
#endif

// Shows the screen-recording prompt only when explicitly asked to, with
// `VIBECAT_REQUEST_SCREEN_RECORDING=1`. Without it the app never prompts: the
// permission buys the aura a better guess at what is behind the island, and
// asking for a whole-screen grant at launch to improve the colour of a glow
// would be wildly out of proportion. Design §15 does not list it, and Plan 6's
// Settings should be where this becomes a choice rather than an env var.
BackdropSampler.requestAccessIfAskedTo()

let model = AppModel(socketPath: SocketPath.default)
let controller = NotchController(model: model)

do {
    try model.start()
} catch {
    FileHandle.standardError.write(
        Data("vibecat: could not open the socket: \(error)\n".utf8))
    exit(1)
}

controller.refreshGeometry()
controller.present()

app.run()
