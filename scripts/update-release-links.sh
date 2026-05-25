#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/Info.plist")"
TAG="${RELEASE_TAG:-v${VERSION}}"
ARTIFACT_BASE="api-voice-input-${VERSION}-${BUILD}"
REPO_URL="https://github.com/yosinn1-blip/api-voice-input"
RELEASE_BASE="${REPO_URL}/releases/download/${TAG}/${ARTIFACT_BASE}"

export ROOT VERSION BUILD TAG ARTIFACT_BASE REPO_URL RELEASE_BASE

/usr/bin/python3 <<'PY'
from pathlib import Path
import os
import re
import sys

root = Path(os.environ["ROOT"])
version = os.environ["VERSION"]
tag = os.environ["TAG"]
repo_url = os.environ["REPO_URL"]
release_base = os.environ["RELEASE_BASE"]
zip_url = f"{release_base}.zip"
sha_url = f"{release_base}.zip.sha256"
notes_url = f"{release_base}-release-notes.txt"
latest_url = f"{repo_url}/releases/latest"

readme_path = root / "README.md"
docs_path = root / "docs" / "index.html"

readme = readme_path.read_text(encoding="utf-8")
readme_replacement = (
    "最新版はGitHub Releasesからダウンロードできます。\n\n"
    f"- 最新Release: {latest_url}\n"
    f"- {tag} ZIP: {zip_url}\n"
    f"- SHA256: {sha_url}\n"
    f"- Release notes: {notes_url}\n\n"
    "このアプリはメニューバー常駐型です。"
)
readme_pattern = re.compile(
    r"最新版はGitHub Releasesからダウンロードできます。\n\n"
    r"(?:- .*\n)+\n"
    r"このアプリはメニューバー常駐型です。"
)
readme_updated, readme_count = readme_pattern.subn(readme_replacement, readme, count=1)
if readme_count != 1:
    print("ERROR: README.md download block was not updated", file=sys.stderr)
    sys.exit(1)
readme_path.write_text(readme_updated, encoding="utf-8")

docs = docs_path.read_text(encoding="utf-8")
release_asset_url = r"https://github\.com/yosinn1-blip/api-voice-input/releases/download/v[0-9]+(?:\.[0-9]+)*/api-voice-input-[0-9]+(?:\.[0-9]+)*-[0-9]+"

docs_updated, zip_count = re.subn(f"{release_asset_url}\\.zip", zip_url, docs, count=1)
if zip_count != 1:
    print("ERROR: docs/index.html download URL was not updated", file=sys.stderr)
    sys.exit(1)

docs_updated, latest_count = re.subn(
    r"https://github\.com/yosinn1-blip/api-voice-input/releases/latest",
    latest_url,
    docs_updated,
)

docs_updated, sha_count = re.subn(f"{release_asset_url}\\.zip\\.sha256", sha_url, docs_updated)
docs_updated, notes_count = re.subn(f"{release_asset_url}-release-notes\\.txt", notes_url, docs_updated)

# Older homepage versions did not include subaction links; add them below the main action buttons.
if sha_count == 0 and notes_count == 0:
    subactions = (
        '      <div class="subactions" aria-label="ダウンロード補助リンク">\n'
        f'        <a href="{latest_url}">最新版Release</a>\n'
        '        <span>·</span>\n'
        f'        <a href="{sha_url}">SHA256</a>\n'
        '        <span>·</span>\n'
        f'        <a href="{notes_url}">Release notes</a>\n'
        '      </div>\n'
    )
    marker = '      </div>\n      <div class="pill-demo"'
    replacement = f'      </div>\n{subactions}      <div class="pill-demo"'
    docs_updated, subactions_count = docs_updated.replace(marker, replacement, 1), docs_updated.count(marker)
    if subactions_count < 1:
        print("ERROR: docs/index.html subaction insertion point was not found", file=sys.stderr)
        sys.exit(1)

if '.subactions {' not in docs_updated:
    css_marker = '    .button.primary { background: var(--accent); color: var(--accentText); border-color: transparent; }\n'
    css_addition = (
        css_marker
        '    .subactions { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 10px; font-size: 14px; color: var(--muted); }\n'
        '    .subactions a { color: inherit; text-underline-offset: 3px; }\n'
    )
    if css_marker not in docs_updated:
        print("ERROR: docs/index.html CSS insertion point was not found", file=sys.stderr)
        sys.exit(1)
    docs_updated = docs_updated.replace(css_marker, css_addition, 1)

docs_updated, footer_count = re.subn(
    r"AI Voice Input v[0-9]+(?:\.[0-9]+)*",
    f"AI Voice Input v{version}",
    docs_updated,
    count=1,
)
if footer_count != 1:
    print("ERROR: docs/index.html footer version was not updated", file=sys.stderr)
    sys.exit(1)

docs_path.write_text(docs_updated, encoding="utf-8")

print(f"README.md -> {tag}")
print(f"docs/index.html -> {zip_url}")
print(f"docs/index.html sha256 -> {sha_url}")
print(f"docs/index.html release notes -> {notes_url}")
PY

printf 'release_tag=%s\n' "$TAG"
printf 'zip_url=%s.zip\n' "$RELEASE_BASE"
printf 'sha256_url=%s.zip.sha256\n' "$RELEASE_BASE"
printf 'release_notes_url=%s-release-notes.txt\n' "$RELEASE_BASE"
