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

DEFAULT_IDENTITY="Whispur Compact Local Code Signing"
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  if /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$DEFAULT_IDENTITY\""; then
    SIGN_IDENTITY="$DEFAULT_IDENTITY"
  else
    SIGN_IDENTITY="-"
  fi
fi

/usr/bin/codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$APP_DIR"
echo "codesigned with: $SIGN_IDENTITY" >&2
echo "$APP_DIR"
