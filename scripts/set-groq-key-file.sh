#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/APIVoiceInput"
SECRETS="$APP_SUPPORT/secrets.env"
mkdir -p "$APP_SUPPORT"
chmod 700 "$APP_SUPPORT"
KEY="$(osascript \
  -e 'display dialog "Groq API keyを入力してください" default answer "" with hidden answer buttons {"Cancel", "OK"} default button "OK"' \
  -e 'text returned of result')"
if [[ -z "$KEY" ]]; then
  echo "Groq API key is empty; nothing stored." >&2
  exit 1
fi
umask 077
printf 'GROQ_API_KEY=%s\n' "$KEY" > "$SECRETS"
chmod 600 "$SECRETS"
echo "Groq API key stored at: $SECRETS"
