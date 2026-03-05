import AppKit
import AVFoundation
import CoreAudio
import SwiftUI

@main
struct VoiceTypeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.menuBarIcon)
                .symbolRenderingMode(.multicolor)
        }
    }
}

@MainActor
class AppState: ObservableObject {
    enum Status {
        case idle
        case recording
        case transcribing
    }

    @Published var status: Status = .idle
    @Published var lastTranscription: String = ""
    @Published var errorMessage: String?

    let audioRecorder = AudioRecorder()
    let transcriber = GroqTranscriber()
    let hotkeyManager = HotkeyManager()
    private var settingsWindow: NSWindow?

    var menuBarIcon: String {
        switch status {
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .transcribing: return "ellipsis.circle"
        }
    }

    var menuBarIconColor: Color {
        switch status {
        case .idle: return .primary
        case .recording: return .red
        case .transcribing: return .orange
        }
    }

    init() {
        hotkeyManager.onRecordStart = { [weak self] in
            Task { @MainActor in
                self?.startRecording()
            }
        }
        hotkeyManager.onRecordStop = { [weak self] in
            Task { @MainActor in
                self?.stopRecordingAndTranscribe()
            }
        }
        hotkeyManager.start()
        requestMicPermission()
    }

    private func requestMicPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if !granted {
                    Task { @MainActor in
                        self.errorMessage = "Microphone permission denied"
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = "Microphone permission denied. Enable in System Settings > Privacy > Microphone."
        case .authorized:
            break
        @unknown default:
            break
        }
    }

    func showSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .environmentObject(self)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceType Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    func startRecording() {
        print("[VoiceType] startRecording called, status=\(status)")
        // Allow recording even if previous transcription is still in flight
        guard status == .idle || status == .transcribing else {
            print("[VoiceType] blocked: status is \(status)")
            return
        }
        errorMessage = nil
        do {
            var deviceID: AudioDeviceID?
            if let savedDevice = UserDefaults.standard.string(forKey: "selectedInputDevice"), !savedDevice.isEmpty {
                deviceID = AudioRecorder.findDevice(matching: savedDevice)
                print("[VoiceType] using device: \(savedDevice) -> ID: \(String(describing: deviceID))")
            }
            try audioRecorder.startRecording(deviceID: deviceID)
            status = .recording
            print("[VoiceType] recording started")
        } catch {
            print("[VoiceType] recording error: \(error)")
            errorMessage = "Recording failed: \(error.localizedDescription)"
        }
    }

    func stopRecordingAndTranscribe() {
        print("[VoiceType] stopRecording called, status=\(status)")
        guard status == .recording else {
            print("[VoiceType] not recording, ignoring stop")
            return
        }
        let wavData = audioRecorder.stopRecording()
        status = .transcribing
        print("[VoiceType] got WAV data: \(wavData?.count ?? 0) bytes")

        guard let wavData, !wavData.isEmpty else {
            status = .idle
            errorMessage = "No audio captured"
            print("[VoiceType] no audio captured")
            return
        }

        let apiKey = GroqTranscriber.loadAPIKey()
        guard let apiKey, !apiKey.isEmpty else {
            status = .idle
            errorMessage = "No API key configured. Open Settings to add your Groq API key."
            print("[VoiceType] no API key")
            return
        }
        print("[VoiceType] sending to Groq...")

        Task {
            do {
                let text = try await transcriber.transcribe(wavData: wavData, apiKey: apiKey)
                print("[VoiceType] transcription: \(text)")
                if !text.isEmpty {
                    lastTranscription = text
                    try? await Task.sleep(for: .milliseconds(50))
                    KeyboardInjector.typeText(text)
                }
                if status == .transcribing { status = .idle }
            } catch {
                print("[VoiceType] transcription error: \(error)")
                errorMessage = "Transcription error: \(error.localizedDescription)"
                if status == .transcribing { status = .idle }
            }
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading) {
            switch appState.status {
            case .idle:
                Text("Ready (hold Ctrl+Shift to record)")
            case .recording:
                Text("Recording...")
                    .foregroundStyle(.red)
            case .transcribing:
                Text("Transcribing...")
                    .foregroundStyle(.orange)
            }

            if let error = appState.errorMessage {
                Divider()
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if !appState.lastTranscription.isEmpty {
                Divider()
                Text("Last: \(appState.lastTranscription)")
                    .font(.caption)
                    .lineLimit(3)
            }

            Divider()

            Button("Settings...") {
                appState.showSettings()
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(4)
    }
}
