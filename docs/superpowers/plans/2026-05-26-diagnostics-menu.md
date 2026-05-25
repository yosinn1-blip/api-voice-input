# Diagnostics Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a menubar diagnostic dialog that summarizes setup blockers and points to the local debug log.

**Architecture:** Keep the formatter in `APIVoiceInputCore` as a pure value object, and keep macOS permission reads plus Finder/browser actions in `APIVoiceInputApp`.

**Tech Stack:** Swift 6, Swift Package Manager, Swift Testing, AppKit, AVFoundation, ApplicationServices.

---

### Task 1: Core diagnostic status formatter

**Files:**
- Create: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputCore/DiagnosticStatus.swift`
- Create: `/Users/yoshiki/api音声ソフト/Tests/APIVoiceInputCoreTests/DiagnosticStatusTests.swift`

- [ ] Write failing Swift Testing tests for ready and blocked diagnostic snapshots.
- [ ] Run `swift test --filter DiagnosticStatusTests` and confirm the type is missing.
- [ ] Add `DiagnosticStatus`, `DiagnosticSnapshot`, and `DiagnosticMicrophonePermission` to format a checklist message and choose `ready` vs `needsAttention`.
- [ ] Rerun `swift test --filter DiagnosticStatusTests` and confirm the tests pass.

### Task 2: Menubar wiring

**Files:**
- Modify: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/StatusMenuController.swift`
- Modify: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/AppDelegate.swift`
- Modify: `/Users/yoshiki/api音声ソフト/Sources/APIVoiceInputApp/DebugLog.swift`

- [ ] Add a `showDiagnostics` closure to `StatusMenuController`.
- [ ] Add a menu item titled `診断を表示` near setup/troubleshooting actions.
- [ ] Build a `DiagnosticSnapshot` in `AppDelegate` from API key state, Accessibility trust, microphone authorization, and debug log existence.
- [ ] Show an `NSAlert` with the formatted diagnostic message.
- [ ] Handle alert buttons: reveal the log/folder, open setup guide, or dismiss.

### Task 3: Verification and release safety checks

**Files:**
- All changed files.

- [ ] Run `swift test`.
- [ ] Run `scripts/verify-release-scripts.sh`.
- [ ] Run `scripts/package-release.sh` to ensure app packaging still works.
- [ ] Inspect `git status --short`.
- [ ] Commit and push the implementation.
- [ ] Record the checkpoint in Obsidian.
