#!/bin/bash
# 打包 Amigo.app（含图标）。用法: swift build -c release && tools/package-app.sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Amigo.app"
BIN="$ROOT/.build/release/Amigo"
[ -f "$BIN" ] || { echo "先 swift build -c release"; exit 1; }
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Amigo"
cp "$ROOT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R "$ROOT/Assets/pets" "$APP/Contents/Resources/pets"   # 内置默认形象 + 动作帧（新用户不空白、开箱即动）
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Amigo</string>
  <key>CFBundleDisplayName</key><string>Amigo</string>
  <key>CFBundleIdentifier</key><string>com.amigo.app</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleExecutable</key><string>Amigo</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# 自签(ad-hoc)：不需要 Apple 账号，避免"已损坏"
codesign --force --deep --sign - "$APP" 2>/dev/null && echo "已自签 (ad-hoc)"
echo "打包完成: $APP"
echo "分发提示：对方首次打开若被拦，右键→打开；或终端执行  xattr -cr '<路径>/Amigo.app'  再打开。"
