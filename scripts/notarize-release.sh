#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT/dist"
APP_PATH="${APP_PATH:-$ROOT/build/API音声ソフト.app}"
NOTARY_PROFILE="${NOTARY_PROFILE:-api-voice-input-notary}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/Info.plist")"
ARTIFACT_BASE="api-voice-input-${VERSION}-${BUILD}"
ZIP_PATH="$DIST_DIR/${ARTIFACT_BASE}.zip"
SHA_PATH="$ZIP_PATH.sha256"

cd "$ROOT"

printf '== notarize release ==\n'
printf 'app=%s\n' "$APP_PATH"
printf 'zip=%s\n' "$ZIP_PATH"
printf 'notary_profile=%s\n' "$NOTARY_PROFILE"

if [[ ! -d "$APP_PATH" ]]; then
  cat >&2 <<EOF
ERROR: app bundle not found: $APP_PATH
Run ./scripts/package-release.sh first, or pass APP_PATH=/path/to/API音声ソフト.app.
EOF
  exit 1
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  cat >&2 <<EOF
ERROR: release ZIP not found: $ZIP_PATH
Run ./scripts/package-release.sh first.
EOF
  exit 1
fi

printf '== verify Developer ID signature ==\n'
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNATURE_INFO="$(/usr/bin/codesign -dv --verbose=4 "$APP_PATH" 2>&1 || true)"
echo "$SIGNATURE_INFO" | /usr/bin/grep -E 'Identifier=|Authority=|Signature=|TeamIdentifier=' || true

if ! /usr/bin/grep -Fq 'Authority=Developer ID Application' <<<"$SIGNATURE_INFO"; then
  cat >&2 <<'EOF'
ERROR: app is not signed with a Developer ID Application certificate.
Set CODESIGN_IDENTITY="Developer ID Application: ..." and rebuild with ./scripts/package-release.sh.
EOF
  exit 1
fi

printf '== submit to Apple notary service ==\n'
xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

printf '== staple ticket ==\n'
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

printf '== recreate notarized ZIP ==\n'
rm -f "$ZIP_PATH" "$SHA_PATH"
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --keepParent --norsrc "$APP_PATH" "$ZIP_PATH"
(
  cd "$DIST_DIR"
  /usr/bin/shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$SHA_PATH")"
)

printf 'notarized_zip=%s\n' "$ZIP_PATH"
printf 'sha256=%s\n' "$SHA_PATH"
