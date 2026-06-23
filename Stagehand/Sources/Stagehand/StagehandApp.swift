import SwiftUI

/// Window identifiers used with `openWindow`.
enum AppWindow {
    static let main = "main"
}

/// The app. SwiftUI owns the lifecycle: a `Window` scene for the Dock app window
/// and a `MenuBarExtra` for the menu-bar item. SwiftUI also supplies the standard
/// App / Edit / Window menus automatically — so text fields get Cut/Copy/Paste
/// and there's no hand-built menu bar to go wrong.
@main
struct StagehandApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared
    @StateObject private var store = ProfileStore.shared

    var body: some Scene {
        Window("Stagehand", id: AppWindow.main) {
            RootView()
                .environmentObject(model)
                .environmentObject(store)
        }
        .defaultSize(width: 820, height: 560)

        MenuBarExtra("Stagehand", systemImage: "macwindow.on.rectangle") {
            MenuBarContent()
                .environmentObject(model)
                .environmentObject(store)
        }
        .menuBarExtraStyle(.menu)
    }
}
