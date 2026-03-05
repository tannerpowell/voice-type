import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKey: String = ""
    @State private var selectedDeviceName: String = ""
    @State private var devices: [(UInt32, String)] = []
    @State private var saved = false

    var body: some View {
        Form {
            Section("Groq API Key") {
                SecureField("gsk_...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                Button("Save API Key") {
                    GroqTranscriber.saveAPIKey(apiKey)
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        saved = false
                    }
                }
                .disabled(apiKey.isEmpty)

                if saved {
                    Text("Saved to Keychain")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            Section("Input Device") {
                Picker("Microphone", selection: $selectedDeviceName) {
                    Text("System Default").tag("")
                    ForEach(devices, id: \.0) { device in
                        Text(device.1).tag(device.1)
                    }
                }
                .onChange(of: selectedDeviceName) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "selectedInputDevice")
                }
            }

            Section("Permissions") {
                Text("This app requires:")
                    .font(.caption)
                VStack(alignment: .leading, spacing: 4) {
                    Label("Microphone access", systemImage: "mic")
                    Label("Accessibility (for typing text)", systemImage: "keyboard")
                    Label("Input Monitoring (for global hotkey)", systemImage: "eye")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("Open Privacy & Security Settings") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!
                    )
                }
                .font(.caption)
            }

            Section("Usage") {
                Text("Hold Ctrl+Shift to record. Release to transcribe and type into the focused field.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 380)
        .onAppear {
            if let existing = GroqTranscriber.loadAPIKey() {
                apiKey = existing
            }
            devices = AudioRecorder.availableInputDevices().map { (UInt32($0.0), $0.1) }
            selectedDeviceName = UserDefaults.standard.string(forKey: "selectedInputDevice") ?? ""
        }
    }
}
