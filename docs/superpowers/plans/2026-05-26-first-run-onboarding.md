# First-run Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a clear first-run setup guide entry point and align README/homepage setup copy.

**Architecture:** Keep the app windowless. Add a public setup-guide URL constant to `GroqAPIKeySetup`, expose it through a status-menu item, and update docs/homepage copy around a short first-run checklist.

**Tech Stack:** Swift 6, AppKit menubar app, Swift Testing/XCTest, static Vercel homepage.

---

### Task 1: Stable setup guide link

**Files:**
- Modify: `Sources/APIVoiceInputCore/GroqAPIKeySetup.swift`
- Modify: `Tests/APIVoiceInputCoreTests/GroqAPIKeySetupTests.swift`

- [ ] Add a failing test that expects `GroqAPIKeySetup.setupGuideURL.absoluteString == "https://api-voice-input.vercel.app/"`.
- [ ] Run `swift test --filter GroqAPIKeySetupTests` and confirm it fails because the constant does not exist.
- [ ] Add `public static let setupGuideURL = URL(string: "https://api-voice-input.vercel.app/")!`.
- [ ] Rerun the filtered test and confirm it passes.

### Task 2: Menubar setup guide item

**Files:**
- Modify: `Sources/APIVoiceInputApp/StatusMenuController.swift`
- Modify: `Sources/APIVoiceInputApp/AppDelegate.swift`

- [ ] Add an `openSetupGuide` closure to `StatusMenuController`.
- [ ] Add a menu item titled `初回セットアップを開く` near the Groq key items.
- [ ] Wire it in `AppDelegate` to `NSWorkspace.shared.open(GroqAPIKeySetup.setupGuideURL)`.
- [ ] Run `swift test` to verify the app still compiles.

### Task 3: Public copy alignment

**Files:**
- Modify: `README.md`
- Modify: `docs/index.html`

- [ ] Add a concise first-run checklist and mention the new menubar guide item.
- [ ] Keep `Fn → Fn` and `Fn → Enter` behavior unchanged.
- [ ] Run static grep checks for `初回セットアップを開く`, `3分セットアップ`, and `Fn → 話す → Fn`.
- [ ] Run `scripts/verify-release-scripts.sh`.
- [ ] Deploy `docs/` to Vercel production and curl-check the live page.
