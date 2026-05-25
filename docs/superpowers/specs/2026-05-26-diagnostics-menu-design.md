# Diagnostics Menu Design

Date: 2026-05-26
Status: Approved by user shorthand (`おk`) after the recommended next step was proposed.

## Goal

Make AI Voice Input easier to troubleshoot from the menubar when the user presses `Fn` and nothing useful appears.

## Current state

The app already has menu items for first-run setup, Groq API key creation, Groq API key entry, API key status, and Accessibility settings. It also writes a local debug log at `~/Library/Application Support/APIVoiceInput/debug.log`, and there is a shell script that can diagnose recent log patterns. The missing piece is an in-app, non-terminal status check that points the user to the likely blocker.

## Design

Add a low-risk status menu item titled `診断を表示`. Selecting it opens a small `NSAlert` with a checklist-style diagnostic summary:

- Groq API key: configured or missing.
- Accessibility permission: allowed or not allowed.
- Microphone permission: allowed, not decided yet, denied/restricted, or unknown.
- Debug log: show the local log path and whether it currently exists.

The alert includes these actions:

1. `ログをFinderで表示` — reveal the debug log if it exists, otherwise reveal/create the Application Support folder.
2. `セットアップを開く` — open the public setup page.
3. `OK` — dismiss.

Keep this feature local-only. Do not read, upload, or print API keys. Do not add telemetry. Do not add a new window or long-running background process.

## Architecture

Add a testable `DiagnosticStatus` value in `APIVoiceInputCore`. It receives plain values from the app layer and formats the user-facing diagnostic message. The AppKit layer remains responsible for reading macOS state (`AXIsProcessTrusted`, `AVCaptureDevice.authorizationStatus`) and opening Finder/browser actions.

This keeps permission APIs out of core tests while preserving a stable, tested message builder.

## Testing

Use TDD for the core status formatter:

- A fully configured snapshot reports that the app is ready.
- A missing key, missing Accessibility permission, denied microphone permission, and missing log produce concrete next actions.

Then compile the app through `swift test`, run release-script verification, and build/package once to catch AppKit wiring errors.
