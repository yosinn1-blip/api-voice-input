#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${API_VOICE_INSTALL_DIR:-$HOME/Applications}"
APP_NAME="API音声ソフト.app"
APP_PATH="$INSTALL_DIR/$APP_NAME"

mkdir -p "$INSTALL_DIR"

BUILT_APP="$("$ROOT/scripts/build-app.sh" | tail -n 1)"

if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$BUILT_APP"; then
  echo "Built app failed codesign verification: $BUILT_APP" >&2
  exit 1
fi

SIGNATURE_INFO="$(/usr/bin/codesign -dv --verbose=4 "$BUILT_APP" 2>&1 || true)"
if /usr/bin/grep -Fq "Signature=adhoc" <<<"$SIGNATURE_INFO"; then
  cat >&2 <<'EOF'
Refusing to install an ad-hoc signed app.

Reason:
  Ad-hoc signatures make macOS Accessibility trust unstable after rebuilds.

Fix:
  Set CODESIGN_IDENTITY to a stable local signing identity, or create one.
EOF
  exit 1
fi

/usr/bin/pkill -x APIVoiceInputApp 2>/dev/null || true
/bin/sleep 0.5

/usr/bin/ditto "$BUILT_APP" "$APP_PATH"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
/usr/bin/open "$APP_PATH"

echo "$APP_PATH"
