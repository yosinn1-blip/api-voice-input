#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT/dist"
APP_NAME="API音声ソフト.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/Info.plist")"
ARTIFACT_BASE="api-voice-input-${VERSION}-${BUILD}"
ZIP_PATH="$DIST_DIR/${ARTIFACT_BASE}.zip"
NOTES_PATH="$DIST_DIR/${ARTIFACT_BASE}-release-notes.txt"

cd "$ROOT"

printf '== release package ==\n'
printf 'root=%s\n' "$ROOT"
printf 'version=%s build=%s\n' "$VERSION" "$BUILD"

printf '== shell syntax ==\n'
/bin/bash -n scripts/build-app.sh scripts/install-app.sh scripts/diagnose-last-run.sh "$0"

printf '== swift test ==\n'
swift test

printf '== build release app ==\n'
BUILT_APP="$(API_VOICE_BUILD_CONFIGURATION=release scripts/build-app.sh | tail -n 1)"
printf 'app=%s\n' "$BUILT_APP"

printf '== verify signature ==\n'
/usr/bin/codesign --verify --deep --strict --verbose=2 "$BUILT_APP"
SIGNATURE_INFO="$(/usr/bin/codesign -dv --verbose=4 "$BUILT_APP" 2>&1 || true)"
echo "$SIGNATURE_INFO" | /usr/bin/grep -E 'Identifier=|Authority=|Signature=|TeamIdentifier=' || true

if /usr/bin/grep -Fq 'Signature=adhoc' <<<"$SIGNATURE_INFO"; then
  cat >&2 <<'EOM'
ERROR: refusing to package an ad-hoc signed app for public distribution.
Set CODESIGN_IDENTITY to a stable local or Developer ID signing identity.
EOM
  exit 1
fi

printf '== create dist zip ==\n'
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH" "$ZIP_PATH.sha256" "$NOTES_PATH"
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --keepParent --norsrc "$BUILT_APP" "$ZIP_PATH"
/usr/bin/shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

cat > "$NOTES_PATH" <<EON
API音声ソフト ${VERSION} (${BUILD})

AIに話しかけるためのMac音声入力アプリです。

Setup:
1. ZIPを展開してAPI音声ソフト.appを開く
2. マイク権限とアクセシビリティ権限を許可
3. メニューバーの🎙から「無料のGroq APIキーを取得」
4. Groq APIキーを作成して「Groq APIキーを設定…」に貼り付け

Changes:
- 長文入力時は、貼り付け後の自動Enter送信を少し遅らせます。
- YouTube一時停止のMediaRemote成功判定を厳しくし、失敗時はフォールバックへ進むようにしました。

Notes:
- アプリ独自アカウントは不要です。
- Groq APIキーはmacOS Keychainに保存されます。
- 録音音声は文字起こしのためGroq APIへ送信されます。
- YouTube一時停止オプションは初期状態ではオフです。
- このZIPはnotarize済みではありません。必要に応じて右クリック→開くを使ってください。
EON

printf 'zip=%s\n' "$ZIP_PATH"
printf 'sha256=%s\n' "$ZIP_PATH.sha256"
printf 'release_notes=%s\n' "$NOTES_PATH"
