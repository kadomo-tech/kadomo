// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KadomoMenu",
    platforms: [.macOS(.v14)],
    targets: [
        // Search, ranking, config, themes, and the keyboard state machine.
        // No AppKit, so it is testable headless and portable to other frontends.
        .target(name: "KadomoMenuCore"),
        // The optional Omarchy theme integration: palette parsing, the adapter
        // to Kadomo's appearance contract, storage, Git, and catalogs. It may use
        // Core; Core never uses it. Leave it out and the app builds without it.
        .target(name: "KadomoOmarchy", dependencies: ["KadomoMenuCore"]),
        // The resident AppKit launcher. The same binary is the `kadomo-menu` CLI.
        .executableTarget(
            name: "KadomoMenu",
            dependencies: ["KadomoMenuCore", "KadomoOmarchy"],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "KadomoSocketTests", dependencies: ["KadomoMenu"]),
        .testTarget(name: "KadomoMenuCoreTests", dependencies: ["KadomoMenuCore"]),
        .testTarget(name: "KadomoOmarchyTests", dependencies: ["KadomoOmarchy", "KadomoMenuCore"]),
    ]
)
