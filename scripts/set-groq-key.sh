#!/usr/bin/env bash
set -euo pipefail

APP_PATH="$HOME/Applications/API音声ソフト.app"
BIN_PATH="$APP_PATH/Contents/MacOS/APIVoiceInputApp"
if [[ ! -x "$BIN_PATH" ]]; then
  APP_PATH="$(cd "$(dirname "$0")/.." && pwd)/build/API音声ソフト.app"
  BIN_PATH="$APP_PATH/Contents/MacOS/APIVoiceInputApp"
fi

KEY="$(osascript \
  -e 'display dialog "Groq API keyを入力してください" default answer "" with hidden answer buttons {"Cancel", "OK"} default button "OK"' \
  -e 'text returned of result')"

if [[ -z "$KEY" ]]; then
  echo "Groq API key is empty; nothing stored." >&2
  exit 1
fi

security delete-generic-password -s com.yoshiki.APIVoiceInput -a groq-api-key >/dev/null 2>&1 || true
security add-generic-password \
  -s com.yoshiki.APIVoiceInput \
  -a groq-api-key \
  -w "$KEY" \
  -T "$BIN_PATH" \
  -T "$APP_PATH"
echo "Groq API key stored in macOS Keychain and trusted for: $APP_PATH"
