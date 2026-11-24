#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="agentBar"
VERSION="${1:-0.2.0}"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
ZIP_PATH="$DIST_DIR/${APP_NAME}-v${VERSION}-macos.zip"
DMG_PATH="$DIST_DIR/${APP_NAME}-v${VERSION}-macos.dmg"
CHECKSUM_PATH="$DIST_DIR/SHA256SUMS.txt"

cd "$ROOT_DIR"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "==> 未发现 ${APP_BUNDLE}，先执行构建..."
  "$ROOT_DIR/scripts/build-app.sh"
fi

echo "==> 打包绿色压缩包：${ZIP_PATH}"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> 组装 DMG 安装镜像：${DMG_PATH}"
DMG_STAGE="/tmp/agentbar-dmg-stage-$$"
rm -rf "$DMG_STAGE" "$DMG_PATH"
mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

hdiutil create \
  -volname "${APP_NAME} v${VERSION}" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$DMG_STAGE"

echo "==> 生成 SHA256 校验文件：${CHECKSUM_PATH}"
(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$DMG_PATH")" "$(basename "$ZIP_PATH")" > "$CHECKSUM_PATH"
)

ls -lh "$DMG_PATH" "$ZIP_PATH" "$CHECKSUM_PATH"
cat "$CHECKSUM_PATH"
