# Notarization preparation

This app is currently distributed as a direct-download macOS ZIP. The current package is signed, but not notarized. Notarization is the next step for reducing Gatekeeper friction for public distribution.

Apple's current command-line path is `xcrun notarytool`. Do not use `altool`; Apple has deprecated it for notarization workflows.

## Prerequisites

- Active Apple Developer Program membership.
- A `Developer ID Application` certificate installed in the macOS login keychain.
- Xcode command line tools available.
- A notarization credential stored in Keychain, not committed to the repo.

## One-time credential setup

Use an app-specific password or App Store Connect API key. Store the credential in Keychain with `notarytool`.

App-specific password example:

```bash
xcrun notarytool store-credentials "api-voice-input-notary" \
  --apple-id "APPLE_ID_EMAIL" \
  --team-id "TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

App Store Connect API key example:

```bash
xcrun notarytool store-credentials "api-voice-input-notary" \
  --key "/secure/path/AuthKey_XXXXXXXXXX.p8" \
  --key-id "KEY_ID" \
  --issuer "ISSUER_ID"
```

Keep all IDs, passwords, and `.p8` files outside the repository.

## Release flow

1. Confirm tests pass.

```bash
swift test
./scripts/dev-cycle.sh
```

2. Package with a Developer ID Application certificate. For notarization, release signing should use a secure timestamp.

```bash
CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
  CODESIGN_TIMESTAMP=on \
  ./scripts/package-release.sh
```

`CODESIGN_TIMESTAMP=on` forces `codesign --timestamp`. If `CODESIGN_IDENTITY` starts with `Developer ID Application:`, `scripts/build-app.sh` also enables timestamping automatically.

3. Submit, staple, validate, and recreate the ZIP.

```bash
./scripts/notarize-release.sh
```

The script uses:

- `NOTARY_PROFILE=api-voice-input-notary` by default
- `APP_PATH=build/API音声ソフト.app` by default
- `dist/api-voice-input-<version>-<build>.zip` by default

Override when needed:

```bash
NOTARY_PROFILE="api-voice-input-notary" \
  APP_PATH="/path/to/API音声ソフト.app" \
  ./scripts/notarize-release.sh
```

The helper script performs these checks/actions:

- verifies the app bundle exists
- verifies the release ZIP exists
- verifies the app is signed by `Developer ID Application`
- submits the ZIP with `xcrun notarytool submit ... --wait`
- staples and validates the app bundle
- recreates the final public ZIP
- rewrites the `.zip.sha256`

4. Upload the final ZIP, `.sha256`, and release notes to GitHub Releases.

5. Update public links.

```bash
bash scripts/update-release-links.sh
```

6. Deploy the docs site and verify public links.

## Expected failure modes

- `The binary is not signed with a valid Developer ID certificate`: check `CODESIGN_IDENTITY` and Keychain certificate availability.
- `Team is not yet configured for notarization`: confirm Apple Developer Program status and agreements.
- Submission hangs or fails: fetch the notary log with `xcrun notarytool log <submission-id> --keychain-profile "api-voice-input-notary"`.
- Stapling fails: confirm the notary submission was accepted and that you are stapling the app bundle, not a stale unsigned build.

## Do not commit

- Apple ID email if private.
- Team ID if you do not want it public.
- App-specific passwords.
- App Store Connect `.p8` keys.
- Temporary keychains or exported certificates.
