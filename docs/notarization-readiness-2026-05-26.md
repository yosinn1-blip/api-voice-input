# AI Voice Input notarization readiness — 2026-05-26

## Current state

- App release: v0.1.5 build 6.
- `xcrun notarytool` is installed and available.
- Release helper scripts are present and `scripts/verify-release-scripts.sh` passes.
- Current signing identity detected locally: `Whispur Compact Local Code Signing`.
- No `Developer ID Application` code signing identity was detected in the current keychain search.

## Blocker

Notarization cannot be completed yet because the app must be signed with a valid `Developer ID Application` certificate before `scripts/notarize-release.sh` will submit it.

## Safe next steps

1. Install or create an Apple Developer `Developer ID Application` certificate.
2. Store a notary credential in Keychain under `api-voice-input-notary` using `xcrun notarytool store-credentials`.
3. Rebuild with Developer ID signing and timestamping:

```bash
CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
  CODESIGN_TIMESTAMP=on \
  ./scripts/package-release.sh
```

4. Run `./scripts/notarize-release.sh`.
5. Replace the GitHub Release ZIP/SHA after validation.

## Verified commands

- `scripts/verify-release-scripts.sh` passed.
- `xcrun notarytool --help` exited 0.
- `security find-identity -v -p codesigning` showed no Developer ID Application identity.
