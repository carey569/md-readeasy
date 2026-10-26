#!/usr/bin/env bash
# 编译并组装 build/ReadEasy.app；传 --install 时再安装到 /Applications 并注册到 LaunchServices。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP="$ROOT/build/ReadEasy.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/ReadEasy"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ReadEasy"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/web Resources/zh-Hans.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "已构建 $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST=/Applications/ReadEasy.app
  osascript -e 'tell application id "io.github.ruichen31.ReadEasy" to quit' >/dev/null 2>&1 || true
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  # 删掉构建目录里的副本并注销，否则「打开方式」里会出现两个 ReadEasy
  "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
  rm -rf "$APP"
  # 注册文档类型，让 Finder 右键「打开方式」里出现 ReadEasy
  "$LSREGISTER" -f -R -trusted "$DEST"
  echo "已安装到 $DEST"
fi
