import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @State private var store = CaptureStore()
    @State private var showImporter = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    recordButton
                    importButton
                } footer: {
                    Text("Audio is transcribed on your device. Only the text transcript is sent to your backend.")
                }

                if store.items.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No captures yet",
                            systemImage: "waveform",
                            description: Text("Record a meeting or note, or import an audio file. Scribe will find events and reminders in it.")
                        )
                    }
                } else {
                    Section("Captures") {
                        ForEach(store.items) { item in
                            NavigationLink {
                                ReviewView(item: item) { await store.retry(item) }
                            } label: {
                                CaptureRow(item: item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Scribe")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    Task { await store.importAudio(from: url) }
                }
            }
            .alert(
                "Permission needed",
                isPresented: Binding(
                    get: { store.permissionMessage != nil },
                    set: { if !$0 { store.permissionMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { store.permissionMessage = nil }
            } message: {
                Text(store.permissionMessage ?? "")
            }
        }
    }

    private var recordButton: some View {
        Button {
            Task { await store.toggleRecording() }
        } label: {
            Label(
                store.isRecording ? "Stop recording" : "Record",
                systemImage: store.isRecording ? "stop.circle.fill" : "mic.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(store.isRecording ? .red : .accentColor)
        }
    }

    private var importButton: some View {
        Button {
            showImporter = true
        } label: {
            Label("Import an audio file", systemImage: "square.and.arrow.down")
        }
        .disabled(store.isRecording)
    }
}

private struct CaptureRow: View {
    let item: CapturedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.body)
            HStack(spacing: 6) {
                if item.status.isWorking {
                    ProgressView().controlSize(.mini)
                }
                Text(item.status == .ready ? readyLabel : item.status.label)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
        }
    }

    private var readyLabel: String {
        item.actionableCount == 0
            ? "Nothing actionable found"
            : "\(item.actionableCount) item(s) to review"
    }

    private var statusColor: Color {
        switch item.status {
        case .failed: return .red
        case .ready: return item.actionableCount == 0 ? .secondary : .green
        default: return .secondary
        }
    }
}
