import AppKit
import VibeCatCore
import VibeCatUI

// No Dock icon, no menu bar of our own. The equivalent of LSUIElement for a
// target with no Info.plist.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

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
