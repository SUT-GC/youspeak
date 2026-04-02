#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR/YouSpeak.xcodeproj"
ARCHIVE="$SCRIPT_DIR/build/YouSpeak.xcarchive"
EXPORT_DIR="$SCRIPT_DIR/build/export"
DMG="$SCRIPT_DIR/build/YouSpeak.dmg"

KEY_ID="A2JM79ZCZB"
ISSUER_ID="e150a256-b071-4390-8a5a-db12099c0b34"
KEY_PATH="/Users/bytedance/GC/apple/AuthKey_A2JM79ZCZB.p8"

mkdir -p "$SCRIPT_DIR/build"

echo "=== 1. Archive ==="
xcodebuild archive \
  -project "$PROJECT" \
  -scheme YouSpeak \
  -configuration Release \
  -archivePath "$ARCHIVE"

echo "=== 2. Export (Developer ID) ==="
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$SCRIPT_DIR/ExportOptions.plist"

APP="$EXPORT_DIR/YouSpeak.app"

echo "=== 3. 公证 ==="
ZIP="$SCRIPT_DIR/build/YouSpeak.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" \
  --key "$KEY_PATH" \
  --key-id "$KEY_ID" \
  --issuer "$ISSUER_ID" \
  --wait

echo "=== 4. 钉戳 ==="
xcrun stapler staple "$APP"

echo "=== 5. 打 DMG ==="
if ! command -v create-dmg &>/dev/null; then
  echo "安装 create-dmg..."
  brew install create-dmg
fi

create-dmg \
  --volname "YouSpeak" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "YouSpeak.app" 150 180 \
  --hide-extension "YouSpeak.app" \
  --app-drop-link 450 180 \
  "$DMG" \
  "$APP"

echo "=== 完成 ==="
echo "DMG: $DMG"
