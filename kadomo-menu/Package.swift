// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KadomoMenu",
    platforms: [.macOS(.v14)],
    targets: [
        // Search, ranking, config, themes, and the keyboard state machine.
        // No AppKit, so it is testable headless and portable to other frontends.
        .target(name: "KadomoMenuCore"),
        // The resident AppKit launcher. The same binary is the `kadomo-menu` CLI.
        .executableTarget(
            name: "KadomoMenu",
            dependencies: ["KadomoMenuCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "KadomoMenuCoreTests", dependencies: ["KadomoMenuCore"]),
    ]
)
