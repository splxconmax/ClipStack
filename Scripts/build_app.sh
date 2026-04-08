#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/ClipStack.app"
PRODUCT_NAME="ClipStack"
PLIST_PATH="$APP_DIR/Contents/Info.plist"
ICON_SCRIPT="$ROOT_DIR/Scripts/generate_app_icon.swift"
CONFIGURATION="release"

mkdir -p "$BUILD_DIR/clang-module-cache" \
  "$BUILD_DIR/swift-module-cache" \
  "$ROOT_DIR/.swiftpm/cache" \
  "$ROOT_DIR/.swiftpm/config" \
  "$ROOT_DIR/.swiftpm/security" \
  "$ROOT_DIR/Assets"

export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/swift-module-cache"

if ! swift build \
  --package-path "$ROOT_DIR" \
  --scratch-path "$BUILD_DIR" \
  --cache-path "$ROOT_DIR/.swiftpm/cache" \
  --config-path "$ROOT_DIR/.swiftpm/config" \
  --security-path "$ROOT_DIR/.swiftpm/security" \
  --disable-sandbox \
  -c release \
  --product "$PRODUCT_NAME"
then
  CONFIGURATION="debug"
  swift build \
    --package-path "$ROOT_DIR" \
    --scratch-path "$BUILD_DIR" \
    --cache-path "$ROOT_DIR/.swiftpm/cache" \
    --config-path "$ROOT_DIR/.swiftpm/config" \
    --security-path "$ROOT_DIR/.swiftpm/security" \
    --disable-sandbox \
    -c debug \
    --product "$PRODUCT_NAME"
fi

EXECUTABLE_PATH="$BUILD_DIR/$CONFIGURATION/$PRODUCT_NAME"
if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  EXECUTABLE_PATH="$BUILD_DIR/arm64-apple-macosx/$CONFIGURATION/$PRODUCT_NAME"
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/$PRODUCT_NAME"

if [[ -f "$ICON_SCRIPT" ]]; then
  ICON_WORK_DIR="$(mktemp -d "$BUILD_DIR/app-icon.XXXXXX")"
  trap 'rm -rf "$ICON_WORK_DIR"' EXIT
  ICON_PREVIEW="$ICON_WORK_DIR/AppIcon.png"
  ICON_RESOURCE="$ICON_WORK_DIR/app_icon.rsrc"
  BUNDLE_ICON_FILE="$APP_DIR"/$'Icon\r'

  swiftc -module-cache-path "$BUILD_DIR/swift-module-cache" "$ICON_SCRIPT" -o "$ICON_WORK_DIR/icon-generator"
  "$ICON_WORK_DIR/icon-generator" "$ICON_PREVIEW"
  sips -i "$ICON_PREVIEW" >/dev/null
  DeRez -only icns "$ICON_PREVIEW" > "$ICON_RESOURCE"
  Rez -append "$ICON_RESOURCE" -o "$BUNDLE_ICON_FILE"
  SetFile -a C "$APP_DIR"
  SetFile -a V "$BUNDLE_ICON_FILE"
fi

/bin/cat > "$PLIST_PATH" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>ClipStack</string>
  <key>CFBundleIdentifier</key>
  <string>com.codex.ClipStack</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>ClipStack</string>
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
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

echo "Built $APP_DIR ($CONFIGURATION)"
