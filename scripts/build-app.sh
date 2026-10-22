#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release -Xswiftc -file-prefix-map -Xswiftc "$PWD=." -Xswiftc -debug-prefix-map -Xswiftc "$PWD=."
APP="$PWD/dist/Terminal+.app"
for previous in "Terminal Tiles.app" "Codex Tiles.app"; do
    if [ -d "$PWD/dist/$previous" ] && [ ! -e "$APP" ]; then
        mv "$PWD/dist/$previous" "$APP"
    fi
done
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN_DIR="$(swift build -c release --show-bin-path)"
cp "$BIN_DIR/CodexTiles" "$APP/Contents/MacOS/CodexTiles.next"
/usr/bin/strip -S "$APP/Contents/MacOS/CodexTiles.next"
mv -f "$APP/Contents/MacOS/CodexTiles.next" "$APP/Contents/MacOS/CodexTiles"
mkdir -p "$APP/Contents/Resources/Licenses"
for dependency in SwiftTerm swift-png h; do
    cp -f ".build/checkouts/$dependency/LICENSE" "$APP/Contents/Resources/Licenses/$dependency.txt"
    if [ -f ".build/checkouts/$dependency/NOTICE" ]; then
        cp -f ".build/checkouts/$dependency/NOTICE" "$APP/Contents/Resources/Licenses/$dependency-NOTICE.txt"
    fi
done
cp LICENSE "$APP/Contents/Resources/Licenses/TerminalPlus.txt"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.codextiles.app</string>
<key>CFBundleName</key><string>Terminal+</string>
<key>CFBundleDisplayName</key><string>Terminal+</string>
<key>CFBundleExecutable</key><string>CodexTiles</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.8.0</string>
<key>CFBundleVersion</key><string>10</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built: $APP"
