#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${API_VOICE_LOG:-$HOME/Library/Application Support/APIVoiceInput/debug.log}"
LINES="${API_VOICE_DIAG_LINES:-140}"

if [[ ! -f "$LOG_FILE" ]]; then
  echo "diagnosis=log-missing"
  echo "detail=$LOG_FILE がありません"
  exit 1
fi

RECENT="$(/usr/bin/tail -n "$LINES" "$LOG_FILE")"

echo "log=$LOG_FILE"

DIAG_OUTPUT="$(printf '%s\n' "$RECENT" | /usr/bin/python3 -c '
import sys

events = [
    ("ok-paste-command-sent", "貼り付けコマンド送信まで到達しています", "paste command sent"),
    ("accessibility-not-trusted", "文字起こしは成功していますが、アクセシビリティ未許可のため自動貼り付けできていません", "paste skipped because Accessibility is not trusted"),
    ("missing-groq-api-key", "Groq APIキーが見つかっていません", "process failed missing Groq API key"),
    ("empty-audio-skipped", "無音または短すぎる録音としてAPI送信前に破棄されています", "process canceled empty audio before transcription"),
    ("silence-hallucination-suppressed", "無音由来と思われる定型誤認識を破棄しています", "process canceled common silence hallucination"),
    ("processing-error", "処理中エラーがあります。下の直近ログを確認してください", "process failed error="),
    ("recording-started", "録音開始までは到達しています。停止後の処理ログを待ってください", "startRecording ok"),
    ("accessibility-prompted", "アプリ起動時にアクセシビリティ許可が必要な状態です", "accessibility not trusted"),
    ("app-launched", "アプリは起動しています。まだ録音処理ログはありません", "app launched"),
]

lines = sys.stdin.read().splitlines()
latest = None
for index, line in enumerate(lines):
    for diagnosis, detail, pattern in events:
        if pattern in line:
            latest = (index, diagnosis, detail)

if latest:
    _, diagnosis, detail = latest
else:
    diagnosis = "unknown"
    detail = "既知パターンに一致しません"

print(f"diagnosis={diagnosis}")
print(f"detail={detail}")
')"
echo "$DIAG_OUTPUT"

echo "--- recent log ---"
echo "$RECENT"
