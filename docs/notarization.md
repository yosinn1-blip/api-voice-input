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

2. Package the signed app.

```bash
./scripts/package-release.sh
```

3. Submit the ZIP to Apple's notary service.

```bash
xcrun notarytool submit "dist/api-voice-input-<version>-<build>.zip" \
  --keychain-profile "api-voice-input-notary" \
  --wait
```

4. If accepted, staple the ticket to the app bundle before the final public ZIP is created.

```bash
xcrun stapler staple "path/to/API音声ソフト.app"
xcrun stapler validate "path/to/API音声ソフト.app"
spctl --assess --type execute --verbose=4 "path/to/API音声ソフト.app"
```

5. Re-create the public ZIP from the stapled app bundle.

```bash
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --keepParent --norsrc \
  "path/to/API音声ソフト.app" \
  "dist/api-voice-input-<version>-<build>.zip"
/usr/bin/shasum -a 256 "dist/api-voice-input-<version>-<build>.zip" \
  > "dist/api-voice-input-<version>-<build>.zip.sha256"
```

6. Upload the final ZIP, `.sha256`, and release notes to GitHub Releases.

7. Update public links.

```bash
bash scripts/update-release-links.sh
```

8. Deploy the docs site and verify public links.

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
