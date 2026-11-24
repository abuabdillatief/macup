#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="macup"
BUNDLE_DIR="$ROOT_DIR/build/${APP_NAME}.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

echo "Building ${APP_NAME} (release)..."
cd "$ROOT_DIR"

BUILD_FLAGS=()
if [[ "${MACUP_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  BUILD_FLAGS+=(--disable-sandbox)
fi

swift build -c release "${BUILD_FLAGS[@]}"

BIN_PATH="$(swift build -c release "${BUILD_FLAGS[@]}" --show-bin-path)/${APP_NAME}"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "Error: compiled binary not found at $BIN_PATH" >&2
  exit 1
fi

rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR"
cp "$BIN_PATH" "$MACOS_DIR/${APP_NAME}"
chmod +x "$MACOS_DIR/${APP_NAME}"

cat > "$CONTENTS_DIR/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>macup</string>
    <key>CFBundleIdentifier</key>
    <string>com.macup.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>macup</string>
    <key>CFBundleDisplayName</key>
    <string>macup</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>macup uses Apple Events to open CLI commands in Terminal and optionally add Desktop spaces via Mission Control.</string>
</dict>
</plist>
EOF

echo "Ad-hoc signing ${BUNDLE_DIR}..."
codesign --force --deep --sign - "$BUNDLE_DIR"

echo "Done! App bundle created at:"
echo "  $BUNDLE_DIR"
echo "Run it with:"
echo "  open \"$BUNDLE_DIR\""
