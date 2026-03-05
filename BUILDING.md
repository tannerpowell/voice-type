# Building VoiceType: Problems We Solved

VoiceType was built in a single session, from a working Python prototype to a native macOS menu bar app. The Swift/macOS platform threw a bunch of curveballs. Here's what we hit and how we fixed each one.

## 1. Invisible menu bar icon

**Problem**: The mic icon was nearly transparent in the menu bar. Barely visible.

**Cause**: Used SwiftUI's `.secondary` color, which renders almost invisible against the macOS menu bar.

**Fix**: Switched to `.primary` for idle state (renders as a normal menu bar icon), `.red` for recording, `.orange` for transcribing.

## 2. Settings window wouldn't open

**Problem**: Clicking "Settings..." in the menu bar dropdown did nothing. The window seemed to try to appear but never showed.

**Cause**: SwiftUI's `SettingsLink` and the `Settings` scene don't work reliably in `MenuBarExtra` apps, especially with `LSUIElement = true` (which hides the app from the Dock). This is a known SwiftUI bug with menu-bar-only apps.

**Fix**: Ditched `SettingsLink` and the `Settings` scene entirely. Created a plain `NSWindow` manually with `NSHostingView` wrapping the SwiftUI settings view. Called `NSApp.activate(ignoringOtherApps: true)` to bring it to front.

## 3. App didn't appear in macOS permission panels

**Problem**: VoiceType didn't show up in System Settings under Microphone, Accessibility, or Input Monitoring. No way to grant permissions.

**Cause**: Running via `swift run` produces a bare executable without a `CFBundleIdentifier`. macOS only shows bundled `.app` files with proper Info.plist metadata in its permission panels.

**Fix**: Created `bundle.sh` that wraps the compiled binary in a proper `.app` bundle with Info.plist (including `CFBundleIdentifier`, `LSUIElement`, `NSMicrophoneUsageDescription`), copies it to `/Applications`, and code-signs it.

## 4. Keychain password prompt on every launch

**Problem**: macOS popped up a Keychain password dialog every time VoiceType accessed the stored API key. No Touch ID option, just a password field.

**Cause**: The login keychain uses the older keychain format that doesn't support biometrics. Self-signed apps also trigger extra Keychain prompts because the code signature isn't trusted. Every rebuild changed the signature, invalidating the stored access.

**Fix**: Dropped Keychain entirely. Stored the API key in a plain file at `~/.config/voicetype/api-key` with `0600` permissions (owner-read-only). Simple, no prompts, no password dialogs. Also reads `GROQ_API_KEY` env var as fallback for compatibility with the original Python version.

## 5. Microphone permission not prompted

**Problem**: The app never asked for microphone access, and VoiceType didn't appear in the Microphone permission list.

**Cause**: `AVAudioEngine` doesn't automatically trigger the permission prompt in all contexts. The app needed to explicitly request access.

**Fix**: Added `AVCaptureDevice.requestAccess(for: .audio)` at app launch, which triggers the system permission dialog.

## 6. Recordings failed after the first one

**Problem**: First recording worked fine. Second and third recordings failed silently, or the hotkey stopped triggering.

**Cause**: Two issues stacked on top of each other:
1. macOS silently disables `CGEvent` taps if the callback takes too long (even briefly). The tap just stops firing with no error.
2. The app's state machine blocked new recordings while a previous transcription was still in flight. Status stuck on `.transcribing`, so `startRecording()` returned early.

**Fix**:
1. Added `tapDisabledByTimeout` detection in the event tap callback that re-enables the tap automatically.
2. Changed `startRecording()` to accept both `.idle` and `.transcribing` states, so you can start a new recording while the previous one is still being transcribed. The completion handler only resets to `.idle` if the status hasn't already moved to `.recording`.

## 7. "Failed to set input device" on subsequent recordings

**Problem**: After 2-4 successful recordings, the next one would fail with `OSStatus 1852797029` ("Failed to set input device"). The BOYA CM40 mic just refused to bind.

**Cause**: Creating a new `AVAudioEngine` instance each recording and calling `AudioUnitSetProperty` to set the input device works the first few times, then the audio unit enters a bad state. `AVAudioEngine`'s `inputNode` internally reuses a singleton audio unit, and repeatedly tearing it down and recreating it corrupts the device binding.

**Fix**: Switched to a persistent engine architecture. The `AVAudioEngine` is created once, the device is bound once, and the engine instance is reused across all recordings. Each recording just installs a tap, starts the engine, then removes the tap and stops. The device binding persists because the engine (and its audio unit) stays alive.

## 8. coreaudiod pegging CPU at 70%

**Problem**: After leaving VoiceType running, `coreaudiod` spiked to 70% CPU and the laptop got hot.

**Cause**: The audio engine wasn't fully releasing the hardware between recordings. `engine.stop()` without a proper tap removal left the audio pipeline in a half-open state, causing `coreaudiod` to spin.

**Fix**: Made `stopRecording()` airtight: remove the tap first, then stop the engine, then reset the converter. Added `engine.isRunning` checks to avoid redundant stop calls. The engine stays allocated (for device binding reuse) but is fully stopped between recordings.

## 9. Permissions reset on every rebuild

**Problem**: Every time we rebuilt the app, Accessibility and Input Monitoring permissions were revoked. Had to re-add VoiceType.app in System Settings each time.

**Cause**: Ad-hoc code signing (`codesign --sign -`) generates a new signature on every build. macOS ties permissions to the code signature, so a new signature means a new app identity.

**Fix**: Created a self-signed "VoiceType Dev" certificate in Keychain Access (self-signed root, code signing type, 10 year validity). Updated `bundle.sh` to sign with `codesign --sign "VoiceType Dev"` instead of ad-hoc. Now the signature is stable across rebuilds, and permissions persist.

## Timeline

All nine problems were discovered and fixed in about an hour. The Python prototype was maybe 100 lines. The Swift app is about 500 lines across 6 files. The ratio of "writing code" to "fighting the platform" was roughly 30/70, which feels about right for macOS development.
