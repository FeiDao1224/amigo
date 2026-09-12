#!/bin/bash
# 打包 Amigo.app（含图标）。用法: swift build -c release && tools/package-app.sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Amigo.app"
BIN="$ROOT/.build/release/Amigo"
[ -f "$BIN" ] || { echo "先 swift build -c release"; exit 1; }
# 版本号唯一来源：Sources/AmigoCore/App/AppInfo.swift
VERSION="$(sed -n 's/.*static let version = "\([0-9][0-9.]*\)".*/\1/p' "$ROOT/Sources/AmigoCore/App/AppInfo.swift")"
[ -n "$VERSION" ] || { echo "读不到 AppInfo.version"; exit 1; }
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
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>Amigo</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <!-- amigo:// 导入链接；没有这段 AppDelegate 的 application(_:open:) 永远收不到回调 -->
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>com.amigo.app.import</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>CFBundleURLSchemes</key><array><string>amigo</string></array>
  </dict></array>
</dict></plist>
PLIST
# 自签(ad-hoc)：不需要 Apple 账号，避免"已损坏"
codesign --force --deep --sign - "$APP" 2>/dev/null && echo "已自签 (ad-hoc)"
echo "打包完成: $APP (v$VERSION)"
echo "分发提示：对方首次打开若被拦，右键→打开；或终端执行  xattr -cr '<路径>/Amigo.app'  再打开。"
