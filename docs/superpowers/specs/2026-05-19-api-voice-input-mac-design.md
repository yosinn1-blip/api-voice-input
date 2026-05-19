# API音声ソフト Mac MVP Design

Date: 2026-05-19
Status: Draft for user review

## Goal

Build a personal macOS voice input app that prioritizes speed, AI cleanup, free-tier operation, and user-controlled UI/interaction.

The app should not try to build a speech model. It should own the Mac experience: recording, overlay, hotkeys, paste behavior, profiles, and provider routing. Speech-to-text and cleanup are provided by swappable APIs or optional local fallbacks.

## Non-goals for the MVP

- No custom speech recognition model training.
- No paid API auto-upgrade or paid fallback by default.
- No autonomous background usage that can spend money.
- No complex history/search UI in the first version.
- No browser extension in the first version unless needed later for YouTube precision control.

## Recommended stack

Use Swift / SwiftUI for the app.

Reasons:

- macOS menu bar apps, global shortcuts, overlays, microphone permissions, clipboard, and Accessibility flows are native concerns.
- Prior app-body patching of existing Electron apps caused signature and Accessibility risk, so the new app should avoid modifying third-party app bundles.
- API calls and cleanup prompts are simple enough to implement directly in Swift at MVP scale.

## Architecture

The app is split into small components so later features can be added without rewriting the core.

### AppShell

Owns menu bar lifecycle, settings window, app startup, and permission prompts.

### HotkeyController

Registers the global recording shortcut. The first version should support one configurable shortcut. Later versions can support profile-specific shortcuts.

### RecordingController

Starts and stops microphone capture, writes a temporary audio file, and reports recording state.

The MVP can use file-based transcription rather than realtime streaming. This keeps the first version simpler while still allowing fast cloud STT providers.

### OverlayController

Shows a small lower-screen overlay during recording and processing.

Initial states:

- idle: hidden
- recording: minimal waveform or pulsing pill
- transcribing: subtle loading state
- cleaning: subtle loading state
- pasted: short success flash
- failed: small error with clipboard fallback note

The overlay should be intentionally minimal: dark translucent pill, low visual weight, no large panels.

### TranscriptionProvider

A protocol/interface for STT engines.

Initial providers:

- Groq Whisper, because it is fast and has a usable free tier.
- Manual/local fallback slot, even if not fully implemented in MVP.

Later providers can include Deepgram, ElevenLabs, OpenAI, Gemini, or local Whisper without changing recording/UI code.

### CleanupProvider

A protocol/interface for AI cleanup.

Initial providers:

- Gemini free tier, if available and acceptable for cleanup.
- Groq lightweight LLM, if available within free-tier limits.
- none, for raw transcript paste.

Cleanup must be profile-driven, not hardcoded.

### ProfileManager

Stores language and behavior profiles.

MVP starts with one `default` profile, but the data model must support multiple profiles from the beginning.

A profile contains:

- display name
- STT language hint
- transcription provider
- cleanup provider
- cleanup prompt
- punctuation/style preference
- paste mode
- send Enter after paste: true/false

This directly supports later “よく使う言語を登録” without redesign.

### PasteController

Pastes the final text into the current foreground app.

MVP behavior:

- Save current clipboard.
- Put final text on clipboard.
- Send paste command.
- Optionally send Enter depending on profile.
- Restore clipboard when safe, or leave final text if paste failed.

Failure rule: never lose the generated text. If paste fails, leave it in clipboard and show a small overlay error.

### AutomationHooks

A small lifecycle hook system.

Initial events:

- `onRecordingWillStart`
- `onRecordingDidStop`
- `onTranscriptionDidFinish`
- `onPasteDidFinish`
- `onFailure`

The MVP may not expose hook UI, but the internal hook points should exist.

This enables later features such as pausing YouTube during dictation.

## Later feature: YouTube pause/resume

This is feasible after the MVP.

Implementation levels:

1. Media-key mode
   - On recording start, send global media pause.
   - On finish, send global media play.
   - Simple but may affect Spotify, Apple Music, or other media apps.

2. Browser-tab mode
   - Detect Chrome/Safari YouTube tabs and pause only those tabs.
   - More precise but requires browser automation permissions and per-browser handling.

3. Chrome-extension mode
   - A small companion extension reports YouTube playback state and accepts pause/resume commands.
   - Most reliable for YouTube, but more implementation work.

Recommended later path: start with browser-tab mode if YouTube control becomes important. Keep media-key mode as an optional quick toggle only.

## Later feature: language/profile registration

This should be easy if `ProfileManager` exists from the start.

Examples:

- Japanese casual note
- Japanese polished message
- English email
- Code/comment input
- ChatGPT prompt mode
- Obsidian memo mode

Each profile can later get its own hotkey, cleanup prompt, provider, and paste behavior.

## Free-tier strategy

The app should assume that free providers can fail or rate-limit.

Rules:

- Never silently switch to a paid provider.
- Show provider/rate-limit failure clearly in the overlay or menu.
- Keep text/audio failure artifacts locally only as needed for retry.
- Let the user choose provider order manually.
- Store API keys in Keychain, not files.

## Privacy and secrets

- API keys are stored in macOS Keychain.
- Temporary audio files are deleted after success by default.
- A debug mode may preserve audio/transcript artifacts, but it must be opt-in.
- No secrets are written to logs, docs, git, or Obsidian.

## MVP user flow

1. User presses the configured hotkey.
2. Overlay appears at the bottom in recording state.
3. User speaks.
4. User presses the hotkey again or Enter, depending on configured behavior.
5. App sends audio to the selected STT provider.
6. App optionally sends transcript to cleanup provider.
7. App pastes final text into the foreground app.
8. Overlay briefly confirms success or shows a recoverable failure.

## Testing and verification

Automated checks:

- Provider protocol unit tests with mocked API responses.
- Profile encode/decode tests.
- Cleanup prompt tests for empty/long/Japanese/English input.
- PasteController tests where possible with mocked clipboard.

Manual verification:

- TextEdit paste.
- ChatGPT/browser text field paste.
- Obsidian paste.
- VS Code paste.
- Failure case: no network/API error leaves text in clipboard or shows clear retry path.
- Free-tier/rate-limit response is displayed and does not trigger paid fallback.

## First implementation slice

The first build should only prove the core loop:

- menu bar app
- one hotkey
- microphone recording to temp file
- minimal bottom overlay
- one STT provider
- one cleanup provider or cleanup disabled
- paste into foreground app
- one default profile saved locally
- Keychain-backed API key storage

Everything else should wait until the loop feels good.
