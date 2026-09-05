#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/app/FluxRelay.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.png"
ICONSET_DIR="$ROOT_DIR/.build/AppIcon.iconset"
ENGINE_SRC="$ROOT_DIR/Resources/engine"
ENGINE_BINARY="$ENGINE_SRC/aria2c"
ENGINE_MANIFEST="$ENGINE_SRC/aria2-build.json"
EXPECTED_ARIA2_VERSION="1.37.0-git.9e72735"

if [ "$(uname -m)" != "arm64" ]; then
  echo "FluxRelay is built for Apple Silicon (arm64) only." >&2
  exit 1
fi

if [ ! -x "$ENGINE_BINARY" ]; then
  echo "Missing arm64 aria2 engine. Run Scripts/build-aria2-arm64.sh --install first." >&2
  exit 1
fi

if [ ! -f "$ENGINE_MANIFEST" ]; then
  echo "Missing aria2 build manifest: $ENGINE_MANIFEST" >&2
  exit 1
fi

if [ "$(xcrun lipo -archs "$ENGINE_BINARY")" != "arm64" ]; then
  echo "The bundled aria2 engine must contain only the arm64 architecture." >&2
  exit 1
fi

if ! "$ENGINE_BINARY" --version | grep -F "aria2 version $EXPECTED_ARIA2_VERSION" >/dev/null; then
  echo "The bundled aria2 version does not match $EXPECTED_ARIA2_VERSION." >&2
  exit 1
fi

if ! "$ENGINE_BINARY" --max-connection-per-server=64 --split=64 --version >/dev/null; then
  echo "The bundled aria2 engine is missing Motrix's 64-connection compatibility patch." >&2
  exit 1
fi

if otool -L "$ENGINE_BINARY" | tail -n +2 | grep -vE '^[[:space:]]+(/System/Library/|/usr/lib/)' >/dev/null; then
  echo "The bundled aria2 engine has a non-system dynamic dependency." >&2
  otool -L "$ENGINE_BINARY" >&2
  exit 1
fi

cd "$ROOT_DIR"
env CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-cache" xcrun swift build -c release --arch arm64 --product FluxRelay

if [ "$(xcrun lipo -archs "$ROOT_DIR/.build/release/FluxRelay")" != "arm64" ]; then
  echo "The FluxRelay executable must contain only the arm64 architecture." >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR/engine"
cp "$ROOT_DIR/.build/release/FluxRelay" "$MACOS_DIR/FluxRelay"
cp "$ENGINE_BINARY" "$RESOURCES_DIR/engine/aria2c"
cp "$ENGINE_SRC/aria2.conf" "$RESOURCES_DIR/engine/aria2.conf"
cp "$ENGINE_MANIFEST" "$RESOURCES_DIR/engine/aria2-build.json"
cp -R "$ROOT_DIR/Resources/Localization/." "$RESOURCES_DIR/"
chmod +x "$RESOURCES_DIR/engine/aria2c"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>FluxRelay</string>
  <key>CFBundleIdentifier</key>
  <string>dev.codex.motrix-native</string>
  <key>CFBundleName</key>
  <string>FluxRelay</string>
  <key>CFBundleDisplayName</key>
  <string>FluxRelay</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh-Hans</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>0.3.0</string>
  <key>CFBundleVersion</key>
  <string>3</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSArchitecturePriority</key>
  <array>
    <string>arm64</string>
  </array>
  <key>LSRequiresNativeExecution</key>
  <true/>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
