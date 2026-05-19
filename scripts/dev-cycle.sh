#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="${API_VOICE_LOG:-$HOME/Library/Application Support/APIVoiceInput/debug.log}"
RUN_TESTS="${API_VOICE_RUN_TESTS:-1}"
TAIL_LINES="${API_VOICE_TAIL_LINES:-40}"
OPEN_TEXTEDIT="${API_VOICE_OPEN_TEXTEDIT:-0}"

cd "$ROOT"

echo "== API音声ソフト dev cycle =="
echo "root=$ROOT"
MARKER="=== dev-cycle $(/bin/date -u +%Y-%m-%dT%H:%M:%SZ) ==="
mkdir -p "$(/usr/bin/dirname "$LOG_FILE")"
echo "$MARKER" >> "$LOG_FILE"

echo "== shell syntax =="
/bin/bash -n scripts/build-app.sh scripts/install-app.sh scripts/diagnose-last-run.sh "$0"

if [[ "$RUN_TESTS" != "0" ]]; then
  echo "== swift test =="
  swift test
else
  echo "== swift test skipped =="
fi

echo "== install fixed-signed app =="
APP_PATH="$(scripts/install-app.sh | tail -n 1)"
echo "app=$APP_PATH"

echo "== signature =="
SIGNATURE_INFO="$(/usr/bin/codesign -dv --verbose=4 "$APP_PATH" 2>&1 || true)"
echo "$SIGNATURE_INFO" | /usr/bin/grep -E 'Identifier=|Authority=|Signature=|TeamIdentifier=' || true
if /usr/bin/grep -Fq "Signature=adhoc" <<<"$SIGNATURE_INFO"; then
  echo "ERROR: installed app is ad-hoc signed; Accessibility trust may reset" >&2
  exit 1
fi

echo "== wait for app launch =="
for _ in {1..30}; do
  if /usr/bin/pgrep -x APIVoiceInputApp >/dev/null 2>&1; then
    break
  fi
  /bin/sleep 0.2
done

if ! /usr/bin/pgrep -x APIVoiceInputApp >/dev/null 2>&1; then
  echo "ERROR: APIVoiceInputApp is not running" >&2
  exit 1
fi
APP_PID="$(/usr/bin/pgrep -x APIVoiceInputApp | /usr/bin/head -n 1)"
/bin/ps -p "$APP_PID" -o pid=,command=

/bin/sleep 1.0

echo "== latest health =="
if [[ -f "$LOG_FILE" ]]; then
  RECENT_LOG="$(/usr/bin/awk -v marker="$MARKER" 'seen { print } index($0, marker) { seen=1 }' "$LOG_FILE" | /usr/bin/tail -n "$TAIL_LINES")"
  if [[ -z "$RECENT_LOG" ]]; then
    RECENT_LOG="$(/usr/bin/tail -n "$TAIL_LINES" "$LOG_FILE")"
  fi
  echo "$RECENT_LOG"
  if /usr/bin/grep -Fq "accessibility not trusted" <<<"$RECENT_LOG"; then
    echo "WARN: Accessibility is not trusted. Opening settings." >&2
    /usr/bin/open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
  fi
else
  echo "WARN: log file not found: $LOG_FILE" >&2
fi

if [[ "$OPEN_TEXTEDIT" == "1" ]]; then
  echo "== open TextEdit scratch =="
  /usr/bin/open -a TextEdit
fi

echo "== ready =="
echo "次は対象アプリで Fn を押して実入力テストしてください。失敗したら scripts/diagnose-last-run.sh で原因を分類できます。"
