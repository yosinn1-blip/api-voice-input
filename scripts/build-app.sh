#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/build/API音声ソフト.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

cd "$ROOT"
swift build -c debug --product APIVoiceInputApp
BIN_DIR="$(swift build -c debug --show-bin-path)"
rm -rf "$APP_DIR"
mkdir -p "$MACOS"
cp "$BIN_DIR/APIVoiceInputApp" "$MACOS/APIVoiceInputApp"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
chmod +x "$MACOS/APIVoiceInputApp"
/usr/bin/codesign --force --sign - "$APP_DIR"
echo "$APP_DIR"
