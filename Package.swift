// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibeCat",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VibeCatCore", targets: ["VibeCatCore"]),
        .library(name: "VibeCatTransport", targets: ["VibeCatTransport"]),
        .executable(name: "vibecat-hook", targets: ["VibeCatHook"]),
    ],
    targets: [
        .target(name: "VibeCatCore"),
        .target(name: "VibeCatTransport", dependencies: ["VibeCatCore"]),
        // The hook's logic lives in a library so tests can import it. An
        // executable target with a main.swift cannot be @testable imported
        // reliably, so the executable is kept to nothing but wiring.
        .target(name: "VibeCatHookKit", dependencies: ["VibeCatCore", "VibeCatTransport"]),
        // main.swift imports all three directly, so all three are declared —
        // a transitive dependency is not guaranteed to be importable.
        .executableTarget(name: "VibeCatHook",
                          dependencies: ["VibeCatHookKit", "VibeCatCore", "VibeCatTransport"]),
        .testTarget(name: "VibeCatCoreTests", dependencies: ["VibeCatCore"]),
        .testTarget(name: "VibeCatTransportTests",
                    dependencies: ["VibeCatTransport", "VibeCatCore", "VibeCatHookKit"]),
    ]
)
