#!/bin/bash
set -euo pipefail

APP_NAME="VoiceType"
BUNDLE_DIR=".build/${APP_NAME}.app"
CONTENTS="${BUNDLE_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

# Build release
swift build -c release 2>&1

# Clean old bundle
rm -rf "${BUNDLE_DIR}"

# Create structure
mkdir -p "${MACOS}" "${RESOURCES}"

# Copy binary
cp ".build/release/${APP_NAME}" "${MACOS}/${APP_NAME}"

# Copy icon
cp "AppIcon.icns" "${RESOURCES}/AppIcon.icns"

# Create Info.plist
cat > "${CONTENTS}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.voicetype.app</string>
    <key>CFBundleName</key>
    <string>VoiceType</string>
    <key>CFBundleExecutable</key>
    <string>VoiceType</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoiceType needs microphone access to record your voice for transcription.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign
codesign --force --sign "VoiceType Dev" "${BUNDLE_DIR}"

# Install to /Applications
rm -rf /Applications/VoiceType.app
cp -R "${BUNDLE_DIR}" /Applications/VoiceType.app

echo ""
echo "Built: ${BUNDLE_DIR}"
echo "Installed: /Applications/VoiceType.app"
echo "Run:   open /Applications/VoiceType.app"
