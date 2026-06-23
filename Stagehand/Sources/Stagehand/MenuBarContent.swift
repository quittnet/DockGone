import SwiftUI
import AppKit

/// Contents of the `MenuBarExtra` dropdown. Declarative — no NSMenu rebuilding.
struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: ProfileStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Restore a saved profile.
        if store.profiles.isEmpty {
            Text("No saved profiles")
        } else {
            Section("Restore Layout") {
                ForEach(store.profiles) { profile in
                    Button(profile.name) { model.restore(profile) }
                        .disabled(model.isRestoring)
                }
            }
        }

        Divider()

        Button("Save Current Layout…") { model.saveCurrentLayout() }
            .disabled(model.isRestoring)
        Button("Create Layout…") {
            openWindow(id: AppWindow.main)
            model.showComposer = true
        }
        Button("Open Stagehand Window") { openWindow(id: AppWindow.main) }

        Divider()

        Menu("Arrange Window") {
            ForEach(WindowArranger.Action.allCases, id: \.self) { action in
                Button(action.title) { model.arrange(action) }
            }
        }

        Button("Name Desktops…") {
            openWindow(id: AppWindow.main)
            model.showSpaces = true
        }

        if !model.lastWarnings.isEmpty {
            Divider()
            Section("Last Restore") {
                ForEach(model.lastWarnings, id: \.self) { warning in
                    Text("⚠︎ \(warning)")
                }
            }
        }

        Divider()

        if !model.isTrusted {
            Button("Enable Accessibility…") {
                AccessibilityManager.triggerSystemPrompt()
                AccessibilityManager.openSystemSettings()
            }
        }
        Button("Settings…") {
            openWindow(id: AppWindow.main)
            model.showSettings = true
        }

        Divider()

        Button("Quit Stagehand") { NSApplication.shared.terminate(nil) }
    }
}
