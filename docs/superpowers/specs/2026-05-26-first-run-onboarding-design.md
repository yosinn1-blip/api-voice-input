# First-run onboarding polish design

## Goal
Make the first three minutes clearer for a new AI Voice Input user without changing the core recording workflow.

## Current state
The app already has release links, a Vercel homepage, README setup steps, a Groq key onboarding dialog, and status-menu items for Groq key setup and Accessibility settings. The remaining friction is that a user who launches the menubar app can miss the web setup guide and may not know the expected smoke test: click an input field, press `Fn`, speak, then press `Fn` or `Enter`.

## Design
Add one low-risk entry point in the menubar: `初回セットアップを開く`. It opens the public setup page at `https://api-voice-input.vercel.app/`. Keep the app windowless and key-only; do not add a new wizard, account system, or paid API fallback.

Update the README and homepage to frame setup as a short checklist:

1. Open the app and find `🎙` in the menubar.
2. Allow microphone and Accessibility.
3. Get and save a Groq API key.
4. Run a first smoke test in an AI chat input field.

## Error handling
If the web page cannot open, macOS handles the failure through the default browser mechanism. The existing Groq key status and Accessibility settings menu items remain the troubleshooting path.

## Testing
Add a core test for the setup guide URL so the app and docs have a stable public guide target. Run `swift test`, release script verification, static grep checks for the new setup copy, and Vercel deploy after homepage changes.
