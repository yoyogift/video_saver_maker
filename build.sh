#!/bin/bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SOURCE_DIR")"
APP="$PROJECT_DIR/Video Saver Maker.app"
TEMPLATE="$APP/Contents/Resources/VideoTemplate.saver"
mkdir -p "$APP/Contents/MacOS" "$TEMPLATE/Contents/MacOS" "$TEMPLATE/Contents/Resources"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -O2 -bundle \
  -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 \
  -framework ScreenSaver -framework AppKit -framework AVFoundation -framework QuartzCore \
  "$SOURCE_DIR/VideoScreenSaver.m" -o "$TEMPLATE/Contents/MacOS/VideoSaver"
cat > "$TEMPLATE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VideoSaver</string>
<key>CFBundleIdentifier</key><string>local.videosavermaker.template</string>
<key>CFBundleName</key><string>Video Saver</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSPrincipalClass</key><string>VSMVideoScreenSaver_0000000000000000</string>
</dict></plist>
PLIST
codesign --force --sign - --timestamp=none "$TEMPLATE"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -O2 \
  -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 \
  -framework Cocoa -framework AVFoundation -framework UniformTypeIdentifiers \
  "$SOURCE_DIR/App.m" "$SOURCE_DIR/SaverExporter.m" -o "$APP/Contents/MacOS/VideoSaverMaker"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VideoSaverMaker</string>
<key>CFBundleIdentifier</key><string>local.videosavermaker.app</string>
<key>CFBundleName</key><string>Video Saver Maker</string>
<key>CFBundleDisplayName</key><string>Video Saver Maker</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>Video Saver Maker — local video screensaver builder.</string>
</dict></plist>
PLIST
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built: %s\n' "$APP"
