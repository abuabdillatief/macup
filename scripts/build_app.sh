#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="macup"
BUNDLE_DIR="$ROOT_DIR/build/${APP_NAME}.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_PNG="$ROOT_DIR/Resources/AppIcon.png"

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
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/${APP_NAME}"
chmod +x "$MACOS_DIR/${APP_NAME}"

ICON_PLIST_ENTRY=""
if [[ -f "$ICON_PNG" ]]; then
  echo "Generating AppIcon.icns from $ICON_PNG..."
  ICONSET_DIR="$ROOT_DIR/build/AppIcon.iconset"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png"      >/dev/null
  sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png"   >/dev/null
  sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png"      >/dev/null
  sips -z 64 64     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png"   >/dev/null
  sips -z 128 128   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png"    >/dev/null
  sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png"    >/dev/null
  sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png"    >/dev/null
  sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
  python3 - "$ICONSET_DIR" "$RESOURCES_DIR/AppIcon.icns" <<'PY'
import os, struct, sys

iconset_dir, out_path = sys.argv[1], sys.argv[2]
mapping = [
    (b"icp4", "icon_16x16.png"),
    (b"ic11", "icon_16x16@2x.png"),
    (b"icp5", "icon_32x32.png"),
    (b"ic12", "icon_32x32@2x.png"),
    (b"ic07", "icon_128x128.png"),
    (b"ic13", "icon_128x128@2x.png"),
    (b"ic08", "icon_256x256.png"),
    (b"ic14", "icon_256x256@2x.png"),
    (b"ic09", "icon_512x512.png"),
    (b"ic10", "icon_512x512@2x.png"),
]
chunks = []
for ostype, filename in mapping:
    with open(os.path.join(iconset_dir, filename), "rb") as f:
        data = f.read()
    chunks.append(ostype + struct.pack(">I", len(data) + 8) + data)
body = b"".join(chunks)
with open(out_path, "wb") as f:
    f.write(b"icns" + struct.pack(">I", len(body) + 8) + body)
PY
  rm -rf "$ICONSET_DIR"
  ICON_PLIST_ENTRY=$'    <key>CFBundleIconFile</key>\n    <string>AppIcon</string>'
fi

BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
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
    <string>0.2.0</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
${ICON_PLIST_ENTRY}
    <key>NSAppleEventsUsageDescription</key>
    <string>macup uses Apple Events to open CLI commands in Terminal and optionally add Desktop spaces via Mission Control.</string>
</dict>
</plist>
EOF

SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
echo "Signing ${BUNDLE_DIR} with identity '${SIGN_IDENTITY}'..."
codesign --force --deep --sign "$SIGN_IDENTITY" "$BUNDLE_DIR"
touch "$BUNDLE_DIR"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$BUNDLE_DIR" >/dev/null 2>&1 || true

echo "Done! App bundle created at:"
echo "  $BUNDLE_DIR"
echo "Run it with:"
echo "  open \"$BUNDLE_DIR\""
