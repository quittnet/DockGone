// swift-tools-version: 5.9
import PackageDescription

// Stagehand is a SwiftPM executable so it builds with `swift build` and opens
// directly in Xcode (File ▸ Open ▸ this folder). `install.sh` wraps the built
// binary into a proper .app bundle (Info.plist + ad-hoc signature) so that the
// Accessibility grant and the SMAppService login item have a stable identity.
let package = Package(
    name: "Stagehand",
    platforms: [.macOS(.v13)],   // MenuBarExtra, SMAppService, async openApplication
    targets: [
        .executableTarget(
            name: "Stagehand",
            path: "Sources/Stagehand",
            // Carbon's RegisterEventHotKey is the only way an .accessory app
            // (which never becomes key) can receive system-wide hotkeys.
            linkerSettings: [.linkedFramework("Carbon")]
        )
    ]
)
