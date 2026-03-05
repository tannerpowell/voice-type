# VoiceType

A native macOS menu bar app that turns your voice into text. Hold a hotkey, speak, release, and your words appear in whatever text field has focus.

No Electron. No subscription. No cloud account. Just a $0 API key, a USB mic, and software that feels like it cost $200.

## How it works

1. You hold **Ctrl+Shift**
2. VoiceType records from your microphone
3. You release the keys
4. Audio goes to Groq's Whisper API (fast, free tier available)
5. Transcribed text is typed into the focused field via native macOS keystroke injection

The whole cycle takes about 1 second. It works in any app: your browser, your editor, Slack, Notes, Terminal.

## What you need

- A Mac running macOS 14 (Sonoma) or later
- A microphone (built-in works, USB mic like the BOYA CM40 works better)
- A [Groq API key](https://console.groq.com/keys) (free to create, generous free tier)

## Setup

### 1. Get a Groq API key

Head to [console.groq.com/keys](https://console.groq.com/keys), sign up, and create an API key. It takes about 30 seconds. Groq runs Whisper Large V3 on custom hardware, so transcription is fast and the free tier handles casual use easily.

### 2. Build VoiceType

```bash
git clone https://github.com/tannerpowell/voice-type.git
cd voice-type/VoiceType
```

First build (one time):

```bash
swift build -c release
```

### 3. Create a code signing certificate

macOS requires a signed app bundle for microphone, accessibility, and input monitoring permissions. You only do this once.

Open **Keychain Access** (Spotlight > "Keychain Access"), then:

1. Menu: **Keychain Access > Certificate Assistant > Create a Certificate...**
2. Name: `VoiceType Dev`
3. Identity Type: **Self Signed Root**
4. Certificate Type: **Code Signing**
5. Check **Let me override defaults**
6. Validity: `3650` days (10 years)
7. Key Size: 2048 bits, RSA
8. **Key Usage Extension**: check Signature only
9. **Basic Constraints**: skip (leave unchecked)
10. **Subject Alternate Name**: uncheck it
11. Keychain: **login**
12. Click Create

Then trust it for code signing:

1. Double-click the **VoiceType Dev** certificate in Keychain Access
2. Expand **Trust**
3. Set **Code Signing** to **Always Trust**
4. Close (enter your password when prompted)

### 4. Bundle and install

```bash
chmod +x bundle.sh
./bundle.sh
```

This builds a release binary, wraps it in a `.app` bundle, signs it with your certificate, and copies it to `/Applications`.

### 5. Grant permissions

Launch VoiceType:

```bash
open /Applications/VoiceType.app
```

A mic icon appears in your menu bar. Click it, open **Settings**, and paste your Groq API key.

Then grant three permissions in **System Settings > Privacy & Security**:

| Permission | Why | How |
|---|---|---|
| **Microphone** | Record your voice | Prompted automatically on first recording |
| **Input Monitoring** | Detect Ctrl+Shift globally | Add VoiceType.app manually via the + button |
| **Accessibility** | Type text into focused fields | Add VoiceType.app manually via the + button |

You may need to quit and relaunch after granting permissions.

### 6. Use it

- **Hold Ctrl+Shift** to record (menu bar icon turns red)
- **Release** to transcribe (icon turns orange briefly)
- Text appears in whatever field has focus

That's it. Works in every app on your Mac.

## Menu bar states

| Icon | Color | Meaning |
|------|-------|---------|
| Mic | Default | Idle, ready to record |
| Mic (filled) | Red | Recording |
| Ellipsis | Orange | Transcribing |

Click the menu bar icon for status, last transcription, settings, and quit.

## Configuration

**API key**: stored at `~/.config/voicetype/api-key` (file permissions `0600`). Also reads the `GROQ_API_KEY` environment variable as a fallback.

**Microphone**: selectable in Settings. Defaults to system input device.

## Rebuilding

After making changes:

```bash
cd VoiceType
./bundle.sh
```

Because the app is signed with a stable certificate, your permissions survive rebuilds. No need to re-grant accessibility or input monitoring each time.

## Architecture

```
VoiceType/
  Package.swift              # Swift Package Manager, macOS 14+
  Sources/
    VoiceTypeApp.swift       # App entry, MenuBarExtra, state machine
    AudioRecorder.swift      # AVAudioEngine capture, device selection, WAV encoding
    GroqTranscriber.swift    # Multipart POST to Groq Whisper API
    KeyboardInjector.swift   # CGEvent-based keystroke injection
    HotkeyManager.swift      # Global Ctrl+Shift hotkey via CGEvent tap
    SettingsView.swift       # SwiftUI settings window
  bundle.sh                  # Build, bundle, sign, install
  AppIcon.icns               # App icon
```

Six source files. No dependencies. No Xcode project needed (though it opens in Xcode fine).

## Credits

Built with Claude Code. Whisper transcription by [Groq](https://groq.com).

## License

MIT
