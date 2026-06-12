import SwiftUI

struct SettingsView: View {
    @AppStorage(backendURLDefaultsKey) private var backendURL = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://your-backend.example.com", text: $backendURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Backend URL")
                } footer: {
                    Text("Scribe sends transcripts here to extract events and reminders. Deploy scribe/backend and paste its base URL.")
                }

                Section("Privacy") {
                    Label(
                        "Audio is transcribed on your device. Only the text transcript is sent to your backend — raw audio never leaves the phone.",
                        systemImage: "lock.shield"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("Good to know") {
                    Text("iOS does not allow apps to record regular phone calls or read your WhatsApp/Messages. Scribe works on audio you record or import in the app. Recording other people may require their consent depending on where you live.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
