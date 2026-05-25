# Homepage deployment

The public homepage is served at:

- https://api-voice-input.vercel.app/

The source for the homepage is:

- `docs/index.html`

## When to deploy

Deploy after changing any of these files:

- `docs/index.html`
- `README.md` direct release links, when the homepage should match them
- release asset URLs in GitHub Releases

## Manual deployment

This project has previously been deployed with the Vercel CLI from the repository root:

```bash
npx --yes vercel@latest deploy docs --prod --yes --project api-voice-input
```

Expected production alias:

```text
https://api-voice-input.vercel.app/
```

## Post-deploy checks

```bash
curl -L https://api-voice-input.vercel.app/ | grep -E '初回につまずいたら|whisper-large-v3|SHA256|Release notes'
```

Also verify manually that the top section includes:

- `最新版をダウンロード`
- `最新版Release`
- `SHA256`
- `Release notes`

## Release link update flow

After uploading a new GitHub Release asset:

```bash
bash scripts/update-release-links.sh
```

Then deploy `docs/` again with Vercel and verify the public page.

## Notes

- Do not put Vercel tokens or credentials in repository files.
- If the Vercel CLI asks for login, use the existing authenticated local setup when available.
- If a token is needed, store it outside the repo, preferably in Keychain or the CI secret store.
