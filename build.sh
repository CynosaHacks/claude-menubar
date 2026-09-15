#!/bin/bash
# Builds ClaudeStatus.app from main.swift using swiftc.
set -euo pipefail
cd "$(dirname "$0")"

APP="ClaudeStatus.app"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -o "$APP/Contents/MacOS/ClaudeStatus" main.swift

mkdir -p "$APP/Contents/Resources"
rm -rf "$APP/Contents/Resources/assets"
cp -R assets "$APP/Contents/Resources/assets"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ClaudeStatus</string>
    <key>CFBundleDisplayName</key>
    <string>ClaudeStatus</string>
    <key>CFBundleIdentifier</key>
    <string>com.reecedove.claudestatus</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeStatus</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Built $APP"
