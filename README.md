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

## Developing with an LLM

This project was built entirely with Claude Code in a single session. If you want to extend it, paste this prompt to get your LLM up to speed:

<details>
<summary>Click to expand LLM bootstrap prompt</summary>

```
You're working on VoiceType, a native macOS menu bar app (Swift, SwiftUI, SPM).
The user holds Ctrl+Shift to record from their mic, releases to transcribe via
Groq Whisper API, and the text is typed into the focused field via CGEvent
keystroke injection.

PROJECT STRUCTURE:
- Package.swift: SPM manifest, macOS 14+, no external dependencies
- Sources/VoiceTypeApp.swift: @main App with MenuBarExtra, AppState class
  coordinates recording/transcription/typing lifecycle
- Sources/AudioRecorder.swift: AVAudioEngine capture with CoreAudio device
  selection, 16kHz mono PCM, WAV encoding
- Sources/GroqTranscriber.swift: multipart POST to Groq Whisper API, API key
  stored at ~/.config/voicetype/api-key (plain file, 0600 permissions)
- Sources/KeyboardInjector.swift: CGEvent Unicode keystroke injection
- Sources/HotkeyManager.swift: global Ctrl+Shift detection via CGEvent tap
  on flagsChanged events
- Sources/SettingsView.swift: SwiftUI settings in a manually-created NSWindow
  (not Settings scene, which is broken for MenuBarExtra apps)
- bundle.sh: builds release, creates .app bundle, signs with "VoiceType Dev"
  certificate, copies to /Applications

KEY ARCHITECTURE DECISIONS (learned the hard way):
1. AVAudioEngine is persistent (created once, reused). Creating a new engine per
   recording corrupts the audio unit device binding after 2-4 cycles (OSStatus
   1852797029). The engine stays alive; each recording just toggles tap + start/stop.
2. CGEvent taps get silently disabled by macOS on timeout. The callback checks for
   tapDisabledByTimeout and re-enables the tap automatically.
3. SettingsLink and the Settings scene don't work in MenuBarExtra + LSUIElement apps.
   Settings window is a plain NSWindow with NSHostingView.
4. API key is a dotfile, not Keychain. Keychain causes password prompts on every
   launch for self-signed apps, and the login keychain doesn't support Touch ID.
5. App must be a signed .app bundle (not bare executable) to appear in macOS
   permission panels. bundle.sh handles this.
6. Code signing uses a self-signed "VoiceType Dev" certificate so permissions
   survive rebuilds. Ad-hoc signing resets permissions every time.
7. stopRecording() must: remove tap, stop engine, reset converter (in that order).
   Skipping any step causes coreaudiod to spin at 70% CPU.

PERMISSIONS REQUIRED:
- Microphone (requested via AVCaptureDevice.requestAccess at launch)
- Input Monitoring (for CGEvent tap global hotkey)
- Accessibility (for CGEvent keystroke injection)

BUILD & TEST:
- swift build (debug) or ./bundle.sh (release + install to /Applications)
- Run from terminal for logs: /Applications/VoiceType.app/Contents/MacOS/VoiceType
- All log lines prefixed with [VoiceType]

GROQ API:
- Endpoint: POST https://api.groq.com/openai/v1/audio/transcriptions
- Model: whisper-large-v3
- Multipart form: file (WAV), model, language (en), prompt (punctuation hint)
- Reads API key from GROQ_API_KEY env var or ~/.config/voicetype/api-key
```

</details>

See [BUILDING.md](BUILDING.md) for the 9 platform issues we hit and how we solved them.

## Credits

Built with [Claude Code](https://claude.ai/code). Whisper transcription by [Groq](https://groq.com).

## License

MIT
