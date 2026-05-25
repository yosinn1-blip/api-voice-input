#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

printf '== release script verifier ==\n'
printf 'root=%s\n' "$ROOT"

printf '== required files ==\n'
required_files=(
  "Info.plist"
  "README.md"
  "docs/index.html"
  "docs/notarization.md"
  "scripts/build-app.sh"
  "scripts/package-release.sh"
  "scripts/update-release-links.sh"
  "scripts/notarize-release.sh"
)
for path in "${required_files[@]}"; do
  if [[ ! -f "$path" ]]; then
    echo "ERROR: missing required file: $path" >&2
    exit 1
  fi
  printf 'ok %s\n' "$path"
done

printf '== shell syntax ==\n'
/bin/bash -n scripts/*.sh

printf '== release metadata ==\n'
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)"
ARTIFACT_BASE="api-voice-input-${VERSION}-${BUILD}"
printf 'version=%s\n' "$VERSION"
printf 'build=%s\n' "$BUILD"
printf 'artifact_base=%s\n' "$ARTIFACT_BASE"

printf '== static release-link checks ==\n'
if ! /usr/bin/grep -Fq "api-voice-input-${VERSION}-${BUILD}.zip" README.md; then
  echo "WARN: README.md does not reference current artifact name: api-voice-input-${VERSION}-${BUILD}.zip" >&2
fi
if ! /usr/bin/grep -Fq "api-voice-input-${VERSION}-${BUILD}.zip" docs/index.html; then
  echo "WARN: docs/index.html does not reference current artifact name: api-voice-input-${VERSION}-${BUILD}.zip" >&2
fi
/usr/bin/grep -Fq "api-voice-input-${VERSION}-${BUILD}.zip.sha256" README.md
/usr/bin/grep -Fq "api-voice-input-${VERSION}-${BUILD}-release-notes.txt" README.md
/usr/bin/grep -Fq "api-voice-input-${VERSION}-${BUILD}.zip.sha256" docs/index.html
/usr/bin/grep -Fq "api-voice-input-${VERSION}-${BUILD}-release-notes.txt" docs/index.html
/usr/bin/grep -Fq 'class="subactions"' docs/index.html

printf '== notarization script checks ==\n'
/usr/bin/grep -Fq 'xcrun notarytool submit' scripts/notarize-release.sh
/usr/bin/grep -Fq 'xcrun stapler staple' scripts/notarize-release.sh
/usr/bin/grep -Fq 'spctl --assess' scripts/notarize-release.sh
/usr/bin/grep -Fq 'Authority=Developer ID Application' scripts/notarize-release.sh

printf '== build signing checks ==\n'
/usr/bin/grep -Fq 'CODESIGN_TIMESTAMP' scripts/build-app.sh
/usr/bin/grep -Fq 'Developer ID Application:' scripts/build-app.sh
/usr/bin/grep -Fq -- '--timestamp' scripts/build-app.sh

printf 'release script verifier passed\n'
