// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibeCat",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VibeCatCore", targets: ["VibeCatCore"]),
        .library(name: "VibeCatTransport", targets: ["VibeCatTransport"]),
        .executable(name: "vibecat-hook", targets: ["VibeCatHook"]),
        .library(name: "VibeCatUI", targets: ["VibeCatUI"]),
        .executable(name: "vibecat", targets: ["VibeCatApp"]),
    ],
    targets: [
        // The source icons are a `.copy`, not a `.process`: they are already
        // 256x256 PNGs and asset-catalogue processing would rewrite them into a
        // form only Xcode reads. `.copy` keeps a plain file a plain file, which is
        // what `SourceIcon`'s path-based loader wants.
        .target(name: "VibeCatCore", resources: [.copy("Resources/Icons")]),
        .target(name: "VibeCatTransport", dependencies: ["VibeCatCore"]),
        // The hook's logic lives in a library so tests can import it. An
        // executable target with a main.swift cannot be @testable imported
        // reliably, so the executable is kept to nothing but wiring.
        .target(name: "VibeCatHookKit", dependencies: ["VibeCatCore", "VibeCatTransport"]),
        // main.swift imports all three directly, so all three are declared —
        // a transitive dependency is not guaranteed to be importable.
        .executableTarget(name: "VibeCatHook",
                          dependencies: ["VibeCatHookKit", "VibeCatCore", "VibeCatTransport"]),
        // The UI logic lives in a library for the same reason the hook's does:
        // an executable target with a main.swift cannot be @testable imported.
        .target(name: "VibeCatUI", dependencies: ["VibeCatCore", "VibeCatTransport"]),
        // Info.plist is the app *bundle's*, assembled by Scripts/build-app.sh —
        // it is not a resource of the executable target and SwiftPM should not
        // try to process or copy it.
        .executableTarget(name: "VibeCatApp",
                          dependencies: ["VibeCatUI", "VibeCatCore", "VibeCatTransport"],
                          exclude: ["Info.plist"]),
        .testTarget(name: "VibeCatCoreTests", dependencies: ["VibeCatCore"]),
        // VibeCatUI is needed directly (not merely importable through some
        // other target) so PipelineTests can drive the real AppModel — "the
        // island answers it" — over a real socket, the end-to-end test Task 8
        // adds beside the existing hook round-trip.
        .testTarget(name: "VibeCatTransportTests",
                    dependencies: ["VibeCatTransport", "VibeCatCore", "VibeCatHookKit", "VibeCatUI"]),
        // VibeCatTransport is needed directly (not just transitively through
        // VibeCatUI) so AppModelTests can reference
        // SocketClient.defaultAnswerDeadline — the one place the fallback
        // deadline value lives — rather than hardcoding a second copy of 20
        // that could silently drift from it.
        .testTarget(name: "VibeCatUITests", dependencies: ["VibeCatUI", "VibeCatCore", "VibeCatTransport"]),
    ]
)
