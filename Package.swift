// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DockGone",
    platforms: [.macOS("26.0")],   // NSGlassEffectView
    targets: [
        .executableTarget(
            name: "DockGone",
            path: "Sources/DockGone",
            linkerSettings: [.linkedFramework("Carbon")]
        )
    ]
)
