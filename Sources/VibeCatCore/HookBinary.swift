import Foundation

/// Where `vibecat-hook` lives once it is installed, and how it gets there.
///
/// ## Why this type had to exist before a snippet could be installed for real
///
/// `HookSnippet.command(binaryPath:cli:socketPath:)` takes the path as a
/// parameter and its own doc comment says why: at the time it was written
/// **there was no installed location at all.** `Scripts/build-app.sh` copied
/// only the `vibecat` product into `VibeCat.app`, so the hook lived wherever
/// `swift build` had last put it — `.build/debug/vibecat-hook` or
/// `.build/release/vibecat-hook`, a path that moves with the build
/// configuration and sits inside a directory a person is entitled to delete.
/// A snippet pasted into another CLI's config file outlives every one of those
/// facts, so pointing it there is not an installation.
///
/// ## The two locations, and why there are two rather than one
///
/// - **`bundledURL`** — *next to the running executable.* One rule that is
///   correct for both shapes this project ships: inside a bundle it resolves
///   to `VibeCat.app/Contents/MacOS/vibecat-hook`, and for a bare
///   `swift run vibecat` it resolves to `.build/debug/vibecat-hook`, the
///   sibling `swift build` already produces. This is the **authoritative**
///   copy: `Scripts/build-app.sh` now builds and copies both products, so the
///   two are signed in the same `codesign` pass and cannot be out of step with
///   each other.
/// - **`installedURL`** — a fixed path, `~/Library/Application Support/VibeCat/
///   bin/vibecat-hook`, in the directory `SocketPath.resolve` already uses for
///   the socket. This is what a **snippet points at**, and it exists for one
///   reason the bundled copy cannot satisfy: a path written into another CLI's
///   config file has to survive the app being moved (Downloads → Applications),
///   renamed, or rebuilt in a different configuration. Only a path that is not
///   *inside* the app can do that.
///
/// `installIfNeeded()` mirrors the first onto the second at launch, so an app
/// update reaches every already-installed hook with nothing for the user to
/// re-paste. It compares size and modification date rather than reading a
/// multi-megabyte binary on every launch, and copies only on a difference.
///
/// ## Fail open (§2.3), at three separate levels
///
/// 1. Nothing here throws. A read-only container, a missing bundled copy, a
///    directory that cannot be created: every failure returns `nil` or `false`
///    and the app carries on. Installing a hook is not a launch requirement.
/// 2. `resolvedPath()` prefers the mirror but falls back to the bundled copy,
///    so a failed mirror still yields a path Settings can show and a person can
///    paste — just one that is fragile in the ways described above.
/// 3. Even a path that has gone stale cannot fail an agent's turn, because the
///    snippet `HookSnippet` generates wraps it in `[ -x … ] && … ; exit 0`.
///    That guard is the layer outside the Swift process, where the Swift
///    process's own unconditional `exit(0)` cannot reach.
public enum HookBinary {
    /// The product name, spelled once. `Package.swift`'s executable target and
    /// `Scripts/build-app.sh`'s `cp` both have to agree with this string, and
    /// `HookBinaryTests` asserts the built product is really named this rather
    /// than restating the literal.
    public static let name = "vibecat-hook"

    /// The copy shipped beside whatever executable is running — see the type's
    /// doc comment for why "beside me" is the one rule that covers both a
    /// signed bundle and a bare `swift run`.
    ///
    /// Takes the executable URL as a parameter (defaulted to the real one) so a
    /// test can point it at a fixture directory instead of the test runner's
    /// own bundle, which contains no `vibecat-hook` and never will.
    public static func bundledURL(
        executable: URL? = Bundle.main.executableURL
    ) -> URL? {
        executable?.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// The stable path a generated snippet points at. Deliberately a `bin`
    /// subdirectory rather than the support directory's root: the root already
    /// holds `vibecat.sock` and `custom-sources.json`, which are runtime state
    /// and user configuration respectively, and an executable is neither.
    public static func installedURL(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: "\(home)/Library/Application Support/VibeCat/bin/\(name)")
    }

    /// Copies `source` to `destination` when they differ, and reports the
    /// destination if a usable executable is there afterwards.
    ///
    /// "Differ" is size *and* modification date, not content: the hook is a
    /// multi-megabyte Mach-O and hashing it on every launch would be real work
    /// for a question a stat answers. The failure mode that leaves open — two
    /// different builds with identical size and mtime — requires a copy that
    /// preserves mtime, which `FileManager.copyItem` does, of a binary that
    /// happens to be byte-identical in length; and the consequence is a stale
    /// hook that still speaks the same wire protocol. Named rather than
    /// defended against, because the alternative costs a full read per launch.
    ///
    /// Returns `nil` on every failure. It never throws and it is never fatal:
    /// see the type's doc comment, point 1.
    @discardableResult
    public static func install(from source: URL?, to destination: URL) -> URL? {
        let fm = FileManager.default
        guard let source, fm.isExecutableFile(atPath: source.path) else {
            // No bundled copy to mirror. If a previous launch already put one
            // at `destination` it stays valid — a snippet pointing there keeps
            // working — so report it rather than reporting failure.
            return fm.isExecutableFile(atPath: destination.path) ? destination : nil
        }

        if !needsCopy(from: source, to: destination) { return destination }

        try? fm.createDirectory(at: destination.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        // Remove first: `copyItem` fails outright if anything is at the
        // destination, and an old hook must not be what stops a new one from
        // being installed.
        try? fm.removeItem(at: destination)
        try? fm.copyItem(at: source, to: destination)
        return fm.isExecutableFile(atPath: destination.path) ? destination : nil
    }

    /// Whether the mirror is missing or out of date. Internal rather than
    /// private so `HookBinaryTests` can pin the "identical file is not copied
    /// again" half without having to observe the absence of a write.
    static func needsCopy(from source: URL, to destination: URL) -> Bool {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: destination.path) else { return true }
        guard let a = try? fm.attributesOfItem(atPath: source.path),
              let b = try? fm.attributesOfItem(atPath: destination.path)
        else { return true }
        let sameSize = (a[.size] as? NSNumber) == (b[.size] as? NSNumber)
        let sameDate = (a[.modificationDate] as? Date) == (b[.modificationDate] as? Date)
        return !(sameSize && sameDate)
    }

    /// The launch-time call. One line in `VibeCatApp/main.swift`, with the
    /// whole of the behaviour here where a test can drive it — the same
    /// division `NotchController.init` and `Notifier.postStalls` already use,
    /// and for the same reason: no test runs `main.swift`, so anything written
    /// there is untested by construction.
    @discardableResult
    public static func installIfNeeded(home: String = NSHomeDirectory()) -> URL? {
        install(from: bundledURL(), to: installedURL(home: home))
    }

    /// The path to put in a snippet: the mirror if it is there, else the
    /// bundled copy, else nothing. Plan 6.7's Integrations page wants exactly
    /// this — a `nil` here is "not installed" and is the whole of the status it
    /// has to report.
    public static func resolvedPath(home: String = NSHomeDirectory(),
                                    executable: URL? = Bundle.main.executableURL) -> String? {
        let fm = FileManager.default
        let installed = installedURL(home: home)
        if fm.isExecutableFile(atPath: installed.path) { return installed.path }
        if let bundled = bundledURL(executable: executable),
           fm.isExecutableFile(atPath: bundled.path) { return bundled.path }
        return nil
    }
}
