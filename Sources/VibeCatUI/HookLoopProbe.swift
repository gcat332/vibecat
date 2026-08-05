#if DEBUG
import AppKit
import SwiftUI
import VibeCatCore

/// **Plan 7's own claim, measured on hardware instead of argued: "VibeCat works
/// with a CLI nobody wrote code for."**
///
/// Everything Tasks 1–5 built is reachable from a unit test. What is not is the
/// join: a *real* second CLI running a *generated* hook snippet, invoking a
/// *real* `vibecat-hook`, over a *real* socket, into the running app's own
/// `AppModel`, resolving a *real* icon path out of the user's own
/// `custom-sources.json`, and drawing it in the *real* `SessionRow`. Every one
/// of those is a separate process boundary or a separate file on disk, and no
/// test in this suite crosses more than two of them.
///
/// So this probe is the instrument for the whole chain at once, and it reports
/// three things a test cannot:
///
/// 1. **What arrived** — for each session the app now holds: the `cli` the wire
///    carried, the state, and the icon path `AppModel`'s registry resolved for
///    it. A `nil` here is the exact defect this task existed to close (a
///    mechanism complete and populated by nothing), so it is printed rather
///    than inferred.
/// 2. **Whether that path is a real image**, through the same
///    `SourceIcon.loadValidImage` the view uses — not a `FileManager` existence
///    check, which would pass for a directory or a corrupt download.
/// 3. **Whether the row actually drew it**, in pixels: the icon's own dominant
///    colour, sampled from the file, counted inside a render of the real
///    `SessionListFace`. `CLIMark`'s geometric fallback draws in the state
///    accent, so a count near zero means the fallback ran and the brand icon
///    did not — the same "assert a colour only the thing under test can emit"
///    rule the golden tests use, applied outside the test process.
///
/// **Why `NSHostingView` and not `ImageRenderer`.** `SessionListFace` contains a
/// `ScrollView`, and `ImageRenderer` paints a `ScrollView`'s content fully
/// transparent — measured in `Tests/VibeCatUITests/Raster.swift`, 165 opaque
/// pixels for a bare `Text` against 0 for the identical `Text` inside one. This
/// is the same route `rasteriseHosted` takes for the same reason.
///
/// Gated on `DEBUG` **and** an explicit `--hook-loop-probe`, exactly like
/// `KeyDownProbe` and `BadgeCPUProbe`: an ordinary launch, and any release
/// build, never takes this path.
///
/// ## How to run it
///
/// ```
/// Scripts/build-app.sh
/// open .build/VibeCat.app --args --hook-loop-probe
/// # then, from any CLI's hook, or by hand:
/// .build/debug/vibecat-hook codex   < a-real-payload.json
/// ```
///
/// **It writes its report to a file as well as stdout, and that is not a
/// convenience.** `open` passes `--args` but no environment, and its child's
/// stdout is not the terminal's — so for the one launch shape that matters
/// (`open`, the signed bundle, TCC attributing to the app itself) neither an env
/// var nor a pipe is available. Measured while running this task: launching
/// `VibeCat.app/Contents/MacOS/vibecat` directly from a shell instead
/// **SIGABRTs**, `TCC` namespace, "must contain an NSFocusStatusUsageDescription
/// key" — even though `Info.plist` does contain it, because a shell-launched
/// bundle makes the *shell* the responsible process and TCC reads that process's
/// plist. That is precisely the hazard `Scripts/build-app.sh`'s footer warns
/// about, here with a crash report attached. So the file defaults are what make
/// this probe usable at all; the env vars below only override them.
public enum HookLoopProbe {
    /// Where the render goes. Overridable so a second run does not overwrite the
    /// first.
    public static let pngPathKey = "VIBECAT_PROBE_PNG"
    /// Where the text report goes. Same reasoning.
    public static let reportPathKey = "VIBECAT_PROBE_REPORT"
    /// How long to wait for events before reporting.
    public static let secondsKey = "VIBECAT_PROBE_SECONDS"

    /// The support directory `SocketPath.resolve` and `JSONFileCustomSourceStore`
    /// already use — nowhere new, and reachable from an `open`-launched bundle
    /// with no environment at all.
    static func defaultPath(_ file: String, home: String = NSHomeDirectory()) -> String {
        "\(home)/Library/Application Support/VibeCat/\(file)"
    }

    /// Accumulated so the whole report can be written in one go at the end;
    /// `print` still happens line by line for a foreground run.
    @MainActor private static var transcript: [String] = []

    @MainActor private static func say(_ line: String) {
        transcript.append(line)
        print(line)
        fflush(stdout)
    }

    /// Chains onto `model.onChange` rather than replacing it, so the island
    /// keeps redrawing while the probe watches — this measures the shipped app,
    /// not a headless stand-in for it.
    @MainActor
    public static func run(model: AppModel) {
        let env = ProcessInfo.processInfo.environment
        let seconds = env[secondsKey].flatMap(Double.init) ?? 30
        let png = env[pngPathKey] ?? defaultPath("hook-loop-probe.png")
        let reportPath = env[reportPathKey] ?? defaultPath("hook-loop-probe.txt")

        say("hook-loop-probe: listening \(seconds)s → \(reportPath), \(png)")

        let previous = model.onChange
        model.onChange = { [weak model] in
            previous?()
            guard let model else { return }
            say("hook-loop-probe: onChange, \(model.store.sessions.count) session(s)")
        }

        let t = Timer(timeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated {
                report(model: model, png: png)
                try? transcript.joined(separator: "\n").appending("\n")
                    .write(toFile: reportPath, atomically: true, encoding: .utf8)
                exit(0)
            }
        }
        RunLoop.main.add(t, forMode: .common)
    }

    @MainActor
    private static func report(model: AppModel, png: String) {
        let sessions = model.store.mostUrgentFirst
        say("hook-loop-probe: ---- report ----")
        say("hook-loop-probe: sessions=\(sessions.count)")
        // **Through `SourceIcon.loadValidImage`, never `NSImage(contentsOfFile:)`
        // directly.** A first version of this probe re-read the file itself to
        // sample its dominant colour, and that unguarded read is what hung the
        // main thread on the run *after* `SourceIconLoader` had already fixed the
        // product's own path — the probe reproduced the very defect it was
        // reporting on. Everything here now goes through the bounded loader, and
        // the colour is derived from the image it hands back rather than from a
        // second read of the same path. Nothing downstream needs the image itself:
        // the pixel evidence below is two renders differing in one input, not a
        // colour match, so `loadsAsImage` above is all this loop has to report.
        for s in sessions {
            let image = s.icon.flatMap { SourceIcon.loadValidImage(atPath: $0) }
            say("hook-loop-probe:   cli=\(s.cli) state=\(s.state) project=\(s.project)")
            say("hook-loop-probe:     activity=\(s.activity?.sentence ?? "-") / \(s.activity?.command ?? "-")")
            say("hook-loop-probe:     model=\(s.model ?? "-")")
            say("hook-loop-probe:     icon=\(s.icon ?? "<nil>") loadsAsImage=\(image != nil)")
        }

        guard !sessions.isEmpty else {
            say("hook-loop-probe: nothing arrived — no render written")
            return
        }


        let size = CGSize(width: 388, height: 420)
        guard let rep = render(sessions, size: size) else {
            say("hook-loop-probe: could not build a bitmap rep")
            return
        }
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: png))
            say("hook-loop-probe: wrote \(png) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
        }

        // **Two renders differing in exactly one input**, which is this repo's own
        // rule for a colour assertion and is what the first version of this block
        // got wrong. That version sampled the icon file's "dominant colour",
        // quantised it to 8 levels a channel, and counted matches within a
        // tolerance in the render — and reported **0** for a run whose render
        // provably contained 311 pixels of `#5C74FF`, Codex's own brand indigo. The
        // arithmetic, not the product, was wrong; a probe that can report zero for
        // a correct render is worse than no probe. So: render the same sessions
        // with every icon stripped and count the pixels that differ. No colour
        // constant, no tolerance, no quantisation.
        let control = sessions.map { s -> Session in var c = s; c.icon = nil; return c }
        guard let controlRep = render(control, size: size) else { return }
        say("hook-loop-probe: pixels differing from the same list rendered with icon=nil: "
            + "\(differingPixels(rep, controlRep))")
        say("hook-loop-probe:   (zero means CLIMark's geometric fallback drew for both — "
            + "Session.icon did not reach the row)")
        say("hook-loop-probe: most common opaque colours in the mark's corner:")
        for line in topColours(in: rep, side: 120, limit: 4) {
            say("hook-loop-probe:   \(line)")
        }
    }

    /// The list, through `NSHostingView`. See the type's doc comment for why not
    /// `ImageRenderer`: `SessionListFace` contains a `ScrollView`, whose content
    /// `ImageRenderer` paints fully transparent.
    @MainActor
    private static func render(_ sessions: [Session], size: CGSize) -> NSBitmapImageRep? {
        let view = SessionListFace(sessions: sessions).frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep.converting(to: .sRGB, renderingIntent: .default) ?? rep
    }

    private static func differingPixels(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Int {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return -1 }
        var n = 0
        for y in 0..<a.pixelsHigh {
            for x in 0..<a.pixelsWide {
                guard let pa = a.colorAt(x: x, y: y), let pb = b.colorAt(x: x, y: y) else { continue }
                if abs(pa.redComponent - pb.redComponent) > 0.02
                    || abs(pa.greenComponent - pb.greenComponent) > 0.02
                    || abs(pa.blueComponent - pb.blueComponent) > 0.02 { n += 1 }
            }
        }
        return n
    }

    /// The leading `side`×`side` device pixels, where the mark sits. Printed so a
    /// person can see *which* colours drew rather than only that something did —
    /// the state accent and the brand hue should both be present and different,
    /// which is §4.3's split-by-context ruling visible in one line.
    private static func topColours(in rep: NSBitmapImageRep, side: Int, limit: Int) -> [String] {
        var tally: [String: Int] = [:]
        for y in 0..<min(side, rep.pixelsHigh) {
            for x in 0..<min(side, rep.pixelsWide) {
                guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 else { continue }
                tally[String(format: "#%02X%02X%02X", Int(c.redComponent * 255),
                             Int(c.greenComponent * 255), Int(c.blueComponent * 255)),
                      default: 0] += 1
            }
        }
        return tally.sorted { $0.value > $1.value }.prefix(limit).map { "\($0.key) ×\($0.value)" }
    }

}
#endif
