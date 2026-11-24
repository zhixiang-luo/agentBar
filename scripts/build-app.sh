#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="agentBar"
BUNDLE_ID="com.agentbar.app"
VERSION="0.2.0"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/agentbar-clang-cache}"
export SWIFT_DRIVER_CACHE_PATH="${SWIFT_DRIVER_CACHE_PATH:-/tmp/agentbar-swift-cache}"

cd "$ROOT_DIR"

if [[ ! -f "$ROOT_DIR/assets/AppIcon.icns" ]] || [[ ! -f "$ROOT_DIR/assets/logo.png" ]]; then
  echo "==> 生成小猪应用图标..."
  "$ROOT_DIR/scripts/generate-icon.sh"
fi

echo "==> 编译 Release 二进制..."
swift build -c release --disable-sandbox --cache-path /tmp/agentbar-spm-cache

BIN_PATH="$(swift build -c release --disable-sandbox --cache-path /tmp/agentbar-spm-cache --show-bin-path)/${APP_NAME}"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "未找到编译产物：$BIN_PATH" >&2
  exit 1
fi

echo "==> 组装 ${APP_NAME}.app ..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
cp "$ROOT_DIR/assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/assets/logo.png" "$APP_BUNDLE/Contents/Resources/logo.png"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "==> 本地 Ad-hoc 签名..."
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "==> 打包完成：$APP_BUNDLE"
