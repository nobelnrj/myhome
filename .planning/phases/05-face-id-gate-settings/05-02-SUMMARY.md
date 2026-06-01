---
phase: 05-face-id-gate-settings
plan: "02"
subsystem: Security / Settings UI
tags: [face-id, lock-gate, settings, swiftui, privacy-blur, tdd]
dependency_graph:
  requires: ["05-01"]
  provides: ["UnlockView", "SettingsView", "RootView-gate-wiring", "LockSettingsTests"]
  affects: ["MyHomeApp/RootView.swift", "MyHomeApp/Features/Settings/", "MyHomeTests/LockSettingsTests.swift"]
tech_stack:
  added: []
  patterns:
    - "@Observable LockController owned via @State in RootView (never @StateObject)"
    - "Custom Binding for async auth-gated Toggle (D5-07a/b)"
    - "scenePhase .onChange two-argument iOS 17 form driving blur + grace-period re-lock"
    - ".blur(radius:) + .overlay { UnlockView } chained after TabView"
key_files:
  created:
    - MyHomeApp/Features/Settings/UnlockView.swift
    - MyHomeApp/Features/Settings/SettingsView.swift
    - MyHomeTests/LockSettingsTests.swift
  modified:
    - MyHomeApp/RootView.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "SettingsView toggle uses custom Binding (not $lockController.lockEnabled) to enforce async auth gate (D5-07a/b)"
  - "UnlockView uses @ViewBuilder appIconView helper to avoid Group type-inference issues in SwiftUI"
  - "UAT items captured as comment block in LockSettingsTests.swift (human_verify_mode=end-of-phase)"
metrics:
  duration: "~35 min"
  completed: "2026-06-02"
  tasks: 3
  files: 5
---

# Phase 05 Plan 02: Settings Tab + Lock Gate Wiring Summary

**One-liner:** Face ID gate wired into RootView (privacy blur + UnlockView overlay), Settings tab (tag 4) with auth-gated toggle, ManageCategoriesView sheet, Budgets deep-link, and About footer.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | UnlockView + SettingsView (Settings tab shell) | 85addf0 | UnlockView.swift, SettingsView.swift, project.pbxproj |
| 2 | RootView gate wiring + LockSettingsTests | df0b110 | RootView.swift, LockSettingsTests.swift, project.pbxproj |
| 3 | Full-suite green + UAT verification log | 7741ecd | LockSettingsTests.swift |

## What Was Built

### UnlockView.swift
Full-screen overlay shown when `lockController.isLocked && lockController.lockEnabled`. Contains:
- App icon (80×80 RoundedRectangle cornerRadius 18) via `@ViewBuilder appIconView` helper with UIImage fallback
- "MyHome" label (.title2 .semibold, `.accessibilityAddTraits(.isHeader)`)
- Error text (conditional on `authError != nil`, .subheadline .secondary)
- Unlock button (always visible — T-05-01, D5-02 manual retry path)
- No-passcode guidance (conditional on `authError == .noPasscode` — T-05-02, D5-05)
- `errorMessage(for:)` private func mapping all 4 LockAuthError cases to exact UI-SPEC copy

### SettingsView.swift
Settings tab (tag 4) with NavigationStack + List:
- Section("Security"): Face ID Lock Toggle via custom Binding calling auth-gated `enableLock()`/`disableLock()`
- Section("Data"): Manage Categories (sheet) + Budgets (tab 2 deep-link via `selectedTab = 2`)
- About section: "MyHome" + `Bundle.main.infoDictionary` version string
- No Gmail placeholder rows (D5-10)

### RootView.swift (modified)
- Added `@Environment(\.scenePhase)` and `@State private var lockController = LockController()`
- Settings tab (tag 4, `Label("Settings", systemImage: "gearshape")`)
- `.blur(radius: lockController.isBlurred ? 20 : 0)` + `.animation(.easeInOut(0.2))`
- `.overlay { if lockController.isLocked && lockController.lockEnabled { UnlockView(...).transition(.opacity) } }`
- `.onChange(of: scenePhase) { _, newPhase in ... }` (two-argument iOS 17 form)
- Auto-authenticate on `.active` when locked: `Task { await lockController.authenticate() }`
- Existing tabs 0–3 and `kOpenNoteNotification` deep-link preserved intact

### LockSettingsTests.swift
4 Swift Testing (@Test/#expect) tests:
- `enableLockSetsFlagOnAuthSuccess` — spy evaluate=(true,nil) → lockEnabled==true
- `enableLockBlockedOnAuthFailure` — spy evaluate=(false, LAError(.userCancel)) → lockEnabled stays false
- `disableLockClearsFlagOnAuthSuccess` — precondition lockEnabled=true, auth success → lockEnabled==false
- `lockEnabledPersistsToDefaults` — fresh LockController sees persisted value (App Group round-trip)
- UAT items 1-7 captured as comment block for end-of-phase manual sign-off

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] UnlockView app icon Group type inference error**
- **Found during:** Task 1 build
- **Issue:** `Group { if/else ... }.accessibilityHidden(true)` caused Swift type inference failure ("generic parameter 'R' could not be inferred") in SwiftUI view builder context
- **Fix:** Extracted icon logic into `@ViewBuilder private var appIconView: some View` helper property, applied `.accessibilityHidden(true)` at the call site
- **Files modified:** `MyHomeApp/Features/Settings/UnlockView.swift`
- **Commit:** 85addf0

**2. [Rule 1 - Bug] `.foregroundStyle(.accent)` not valid SwiftUI API**
- **Found during:** Task 1 build
- **Issue:** `.foregroundStyle(.accent)` is not a valid SwiftUI `ShapeStyle` member; correct form is `Color.accentColor`
- **Fix:** Changed to `.foregroundStyle(Color.accentColor)`
- **Files modified:** `MyHomeApp/Features/Settings/UnlockView.swift`
- **Commit:** 85addf0

**3. [Rule 1 - Bug] Xcode project UUID collision for Settings files**
- **Found during:** Task 1 project file edit
- **Issue:** Plan 05-01 already claimed F501/F502/A501/A502 for BiometricAuthPort, SpyBiometricAuth, etc. The initial script used the same IDs for Settings files, causing "Build input files cannot be found" with wrong paths
- **Fix:** Used unique IDs F601/F602/A601/A602 for UnlockView.swift and SettingsView.swift; F603/A603 for LockSettingsTests.swift
- **Files modified:** `MyHome.xcodeproj/project.pbxproj`
- **Commit:** 85addf0

## Known Stubs

None — all views have real data sources wired. UnlockView receives live LockController. SettingsView reads live Bundle version string. ManageCategoriesView is self-contained with SwiftData.

## Threat Surface Scan

No new trust boundaries introduced beyond those in the plan's threat model:
- T-05-01 (UnlockView always-visible Unlock button): mitigated — button always rendered
- T-05-02 (no-passcode guidance): mitigated — escape path shown when authError == .noPasscode
- T-05-03 (Settings toggle tamper): mitigated — custom Binding + auth-gated enable/disable; covered by LockSettingsTests
- T-05-04 (privacy blur): mitigated — blur on both .inactive and .background; verified by UAT-3

## UAT Items (end-of-phase manual sign-off required)

| # | Description | Requirement |
|---|-------------|-------------|
| UAT-1 | Enable Face ID Lock in Settings → auth prompt appears; on success toggle stays ON | SEC-01, D5-07a |
| UAT-2 | Kill + relaunch with lock enabled → UnlockView shows, auto-auth fires, Unlock button visible | D5-01, D5-02 |
| UAT-3 | Background + app switcher → content blurred, no financial data legible | D5-02, T-05-04 |
| UAT-4 | "Manage Categories" sheet opens, add/rename/delete persists | SET-02 |
| UAT-5 | "Budgets" row switches to Budgets tab (tag 2) | SET-03, D5-08 |
| UAT-6 | Disable lock → auth prompt first, toggle goes OFF only on success | D5-07b |
| UAT-7 | No-passcode device → guidance text shown, no lockout | D5-05, T-05-02 |

## Self-Check: PASSED

Files verified:
- FOUND: MyHomeApp/Features/Settings/UnlockView.swift
- FOUND: MyHomeApp/Features/Settings/SettingsView.swift
- FOUND: MyHomeTests/LockSettingsTests.swift
- RootView.swift modified with tag(4), scenePhase, blur, overlay

Commits verified:
- 85addf0: feat(05-02): add UnlockView and SettingsView
- df0b110: feat(05-02): wire LockController into RootView + add LockSettingsTests
- 7741ecd: test(05-02): full suite green + UAT verification log

Tests: ** TEST SUCCEEDED ** (full suite, iPhone 17 simulator)
