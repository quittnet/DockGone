import SwiftUI

/// Preferences: global snap shortcuts, the Moom-style automation triggers,
/// launch-at-login, and Accessibility status.
struct SettingsSheet: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var store: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var arrangeShortcuts = Prefs.arrangeShortcutsEnabled
    @State private var displayProfile: UUID? = Prefs.displayChangeProfileID
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var showSpaces = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Window Snapping") {
                    Toggle("Global snap shortcuts (⌃⌥ keys)", isOn: $arrangeShortcuts)
                        .onChange(of: arrangeShortcuts) { newValue in
                            Prefs.arrangeShortcutsEnabled = newValue
                            model.applyArrangeShortcuts()
                        }
                    Text("⌃⌥ + arrows = halves · U/I/J/K = quarters · D/F/G = thirds · ↩ maximize · C center · ⌃⌥⌘→ next display")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Automation") {
                    Picker("Restore on display change", selection: $displayProfile) {
                        Text("Off").tag(UUID?.none)
                        ForEach(store.profiles) { profile in
                            Text(profile.name).tag(UUID?.some(profile.id))
                        }
                    }
                    .onChange(of: displayProfile) { Prefs.displayChangeProfileID = $0 }
                }

                Section("Startup") {
                    Toggle("Launch Stagehand at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            do { try LoginItem.setEnabled(newValue) }
                            catch { launchAtLogin = LoginItem.isEnabled }   // revert on failure
                        }
                    Text("To auto-restore a layout at login, turn on “Open at startup” on each "
                        + "profile (in its detail view). Flagged profiles restore in order when "
                        + "Stagehand launches at login.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Mission Control") {
                    Button("Name Desktops…") { showSpaces = true }
                    Text("Experimental: name Mission Control desktops (Spaces) via private "
                        + "macOS APIs. May require relaunching the Dock and can break on macOS updates.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Permissions") {
                    HStack {
                        Text("Accessibility")
                        Spacer()
                        if model.isTrusted {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Enable…") {
                                AccessibilityManager.triggerSystemPrompt()
                                AccessibilityManager.openSystemSettings()
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 480, height: 460)
        .onAppear { model.refreshTrust() }
        .sheet(isPresented: $showSpaces) { SpacesView() }
    }
}
