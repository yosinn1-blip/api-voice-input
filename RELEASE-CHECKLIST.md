# Release Checklist

## Before packaging

- [ ] `swift test` passes
- [ ] `./scripts/dev-cycle.sh` passes
- [ ] No API keys, auth tokens, or personal secrets are committed
- [ ] `README.md` setup steps are current
- [ ] `PRIVACY.md` accurately describes network/data behavior
- [ ] `録音開始時にYouTubeを一時停止` is off by default

## Package

Run:

```bash
./scripts/package-release.sh
```

The packaging script reads `CFBundleShortVersionString` and `CFBundleVersion` from `Info.plist` and writes artifacts as `api-voice-input-<version>-<build>`.

For `CFBundleShortVersionString=0.1.3` and `CFBundleVersion=4`, expected artifacts are:

```text
dist/api-voice-input-0.1.3-4.zip
dist/api-voice-input-0.1.3-4.zip.sha256
dist/api-voice-input-0.1.3-4-release-notes.txt
```

## Manual smoke test

- [ ] Fresh install launches
- [ ] Menu shows Groq key setup items
- [ ] Key setup dialog uses a secure field
- [ ] `Fn → speak → Enter` works after key setup
- [ ] Browser media control does not run unless explicitly enabled

## Public link

Only after the ZIP is uploaded to a stable public URL:

- [ ] Verify the GitHub Release download link opens
- [ ] Verify the `.zip.sha256` link opens
- [ ] Verify the release notes link opens
- [ ] Update `README.md` direct download links if the version or filename changed
- [ ] Update `docs/index.html` download URL if the version or filename changed
- [ ] Verify https://api-voice-input.vercel.app/ returns 200
- [ ] Update `/Users/yoshiki/dev/zenn-content/articles/ai-voice-input-self-built.md`
- [ ] Add app link and setup note
- [ ] Verify public link opens
- [ ] Commit and push Zenn article repo

## Notarization note

The current MVP packaging script signs the app but does not notarize it. For broader public distribution, notarization with an Apple Developer account should be added.
