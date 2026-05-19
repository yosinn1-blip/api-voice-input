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

Expected artifacts:

```text
dist/API音声ソフト-<version>.zip
dist/API音声ソフト-<version>.zip.sha256
dist/API音声ソフト-<version>-release-notes.txt
```

## Manual smoke test

- [ ] Fresh install launches
- [ ] Menu shows Groq key setup items
- [ ] Key setup dialog uses a secure field
- [ ] `Fn → speak → Enter` works after key setup
- [ ] Browser media control does not run unless explicitly enabled

## Public link

Only after the ZIP is uploaded to a stable public URL:

- [ ] Update `/Users/yoshiki/dev/zenn-content/articles/ai-voice-input-self-built.md`
- [ ] Add app link and setup note
- [ ] Verify public link opens
- [ ] Commit and push Zenn article repo

## Notarization note

The current MVP packaging script signs the app but does not notarize it. For broader public distribution, notarization with an Apple Developer account should be added.
