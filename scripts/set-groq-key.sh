#!/usr/bin/env bash
set -euo pipefail

KEY="$(osascript \
  -e 'display dialog "Groq API keyを入力してください" default answer "" with hidden answer buttons {"Cancel", "OK"} default button "OK"' \
  -e 'text returned of result')"

if [[ -z "$KEY" ]]; then
  echo "Groq API key is empty; nothing stored." >&2
  exit 1
fi

security add-generic-password -U -s com.yoshiki.APIVoiceInput -a groq-api-key -w "$KEY"
echo "Groq API key stored in macOS Keychain for com.yoshiki.APIVoiceInput/groq-api-key."
