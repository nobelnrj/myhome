---
phase: 01-foundation-manual-expense-spine
plan: 01
subsystem: xcode-project-bootstrap
tags: [xcode, swift-testing, privacy-manifest, identifiers, concurrency]
dependency_graph:
  requires: []
  provides:
    - xcode-project (MyHome.xcodeproj)
    - app-target (MyHome / com.reojacob.myhome)
    - test-target (MyHomeTests with Swift Testing)
    - privacy-manifest (PrivacyInfo.xcprivacy)
    - nyquist-wave-0-stubs
  affects:
    - all downstream plans (02-04) depend on this project skeleton
tech_stack:
  added:
    - Swift 6.0 (SWIFT_VERSION = 6.0, Xcode 26 toolchain)
    - SwiftUI (iOS 17.0 minimum)
    - Swift Testing (bundled, @Test / #expect / Issue.record)
    - SWIFT_STRICT_CONCURRENCY = complete (set from day one per RESEARCH Open Question 2)
  patterns:
    - @main App struct with NavigationStack placeholder root view
    - Swift Testing @MainActor struct with @Test stubs (no XCTest base class)
    - PrivacyInfo.xcprivacy in Copy Bundle Resources phase (FND-04)
key_files:
  created:
    - MyHome.xcodeproj/project.pbxproj
    - MyHome.xcodeproj/xcshareddata/xcschemes/MyHome.xcscheme
    - MyHomeApp/MyHomeApp.swift
    - MyHomeApp/RootView.swift
    - MyHomeApp/MyHome.entitlements
    - MyHomeApp/Info.plist
    - MyHomeApp/Resources/Assets.xcassets/
    - MyHomeApp/Resources/PrivacyInfo.xcprivacy
    - MyHomeApp/Features/Expenses/ (empty dir, populated plan 03)
    - MyHomeApp/Persistence/Schema/ (empty dir, populated plan 02)
    - MyHomeApp/Persistence/Models/ (empty dir, populated plan 02)
    - MyHomeTests/ExpenseModelTests.swift
    - MyHomeTests/MigrationTests.swift
    - README.md
  modified: []
decisions:
  - "Used @testable import MyHome (not MyHomeApp) — product module name is MyHome per TARGET_NAME"
  - "PrivacyInfo excluded from Task 1 build phase, added atomically in Task 2 with the file"
  - "ENABLE_PREVIEWS = YES retained so Xcode previews work in later plans; disabled for CLI builds"
  - "objectVersion = 56 (Xcode 14 compatibility version) — sufficient for all Phase 1 features"
metrics:
  duration: 27 min
  completed_date: "2026-05-29"
  tasks_completed: 2
  tasks_total: 2
  files_created: 14
  files_modified: 2
---

# Phase 01 Plan 01: Xcode Project Bootstrap Summary

Greenfield Xcode project bootstrapped with all locked one-way-door identifiers, strict Swift 6 concurrency, the PrivacyInfo.xcprivacy required-reason manifest, and the 5-test Nyquist Wave 0 red-stub harness.

## What Was Built

**Task 1 — Bootstrap Xcode project with locked identifiers and strict concurrency** (commit 990c446)

Created the Xcode project from scratch as text files (no Xcode GUI available):
- `project.pbxproj` with two targets: `MyHome` (app) and `MyHomeTests` (unit test)
- Locked identifiers: `PRODUCT_BUNDLE_IDENTIFIER = com.reojacob.myhome`, `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `SWIFT_VERSION = 6.0`
- `SWIFT_STRICT_CONCURRENCY = complete` on project and both targets (set from day one per Open Question 2 resolution)
- App Group entitlement `group.com.reojacob.myhome` in `MyHome.entitlements`
- CloudKit container `iCloud.com.reojacob.myhome` documented as comment/placeholder (CloudKit off in v1)
- `MyHomeApp.swift` — `@main` App stub rendering `RootView`
- `RootView.swift` — `NavigationStack` placeholder (real list arrives plan 03)
- Folder layout: `Features/Expenses/`, `Persistence/Schema/`, `Persistence/Models/`, `Resources/`
- `README.md` documenting `@Observable`-only rule, Decimal money, UTC dates, App Group fallback note
- Shared scheme `MyHome.xcscheme` with build + test actions
- `xcodebuild build` → **BUILD SUCCEEDED**

**Task 2 — PrivacyInfo.xcprivacy and Swift Testing target (Nyquist Wave 0)** (commit b2efedd)

- `PrivacyInfo.xcprivacy` with `NSPrivacyTracking: false`, `CA92.1` (UserDefaults), `C617.1` (FileTimestamp) — satisfies FND-04 and threat T-01-02 (mitigate)
- Added to Copy Bundle Resources phase in `project.pbxproj`
- `MyHomeTests/ExpenseModelTests.swift` — 4 `@MainActor @Test` stubs:
  - `expenseCRUD` — #expect(Bool(false), "stub — implemented in plan 02")
  - `expenseUpdate` — #expect(Bool(false), "stub — implemented in plan 02")
  - `currencyFormatting` — #expect(Bool(false), "stub — implemented in plan 02")
  - `expensePropertiesAreCloudKitReady` — #expect(Bool(false), "stub — implemented in plan 02")
- `MyHomeTests/MigrationTests.swift` — `v1StoreMigratesCleanly` stub using `Issue.record("seed store not yet created — plan 04")`
- All 5 stubs compile and run RED (TEST FAILED — expected, Nyquist Wave 0 baseline)

## Verification Evidence

```
xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'
→ BUILD SUCCEEDED

xcodebuild test -scheme MyHome -only-testing:MyHomeTests -destination '...'
→ TEST FAILED (5 red stubs as required)
  ExpenseModelTests/expenseCRUD() FAILED
  ExpenseModelTests/expenseUpdate() FAILED
  ExpenseModelTests/currencyFormatting() FAILED
  ExpenseModelTests/expensePropertiesAreCloudKitReady() FAILED
  MigrationTests/v1StoreMigratesCleanly() FAILED

grep PRODUCT_BUNDLE_IDENTIFIER → com.reojacob.myhome ✓
grep IPHONEOS_DEPLOYMENT_TARGET → 17.0 ✓
grep SWIFT_STRICT_CONCURRENCY → complete ✓
grep group.com.reojacob.myhome → MyHome.entitlements ✓
grep @StateObject|@ObservedObject|@Published MyHomeApp/ → zero results ✓
grep NSPrivacyTracking PrivacyInfo.xcprivacy → file found ✓
grep CA92.1|C617.1 PrivacyInfo.xcprivacy → both found ✓
grep -c @Test ExpenseModelTests.swift → 4 ✓
grep v1StoreMigratesCleanly MigrationTests.swift → found ✓
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Module name is MyHome, not MyHomeApp**

- **Found during:** Task 2 — test compilation
- **Issue:** Test files used `@testable import MyHomeApp` but the module name is `MyHome` (from `PRODUCT_NAME = $(TARGET_NAME)` where target is named `MyHome`). Build failed with "unable to resolve module dependency: MyHomeApp".
- **Fix:** Changed `@testable import MyHomeApp` → `@testable import MyHome` in both test files.
- **Files modified:** `MyHomeTests/ExpenseModelTests.swift`, `MyHomeTests/MigrationTests.swift`
- **Commit:** b2efedd (included in Task 2 commit)

**2. [Rule 3 - Blocking] PrivacyInfo excluded from Task 1 build phase**

- **Found during:** Task 1 build — PrivacyInfo.xcprivacy referenced in Resources phase but file not yet created
- **Issue:** Task 1 pre-included PrivacyInfo in the build phase before the file existed (Task 2 creates the file), causing "couldn't be opened because there is no such file" error.
- **Fix:** Removed PrivacyInfo from the Resources build phase in Task 1 pbxproj. Task 2 added it back atomically alongside creating the file.
- **Files modified:** `MyHome.xcodeproj/project.pbxproj`

## Known Stubs

All stubs are intentional and documented:

| Stub | File | Reason |
|------|------|--------|
| `expenseCRUD` | `MyHomeTests/ExpenseModelTests.swift` | Expense @Model not yet created (plan 02) |
| `expenseUpdate` | `MyHomeTests/ExpenseModelTests.swift` | Expense @Model not yet created (plan 02) |
| `currencyFormatting` | `MyHomeTests/ExpenseModelTests.swift` | Decimal.formattedINR() extension not yet created (plan 02) |
| `expensePropertiesAreCloudKitReady` | `MyHomeTests/ExpenseModelTests.swift` | Expense @Model not yet created (plan 02) |
| `v1StoreMigratesCleanly` | `MyHomeTests/MigrationTests.swift` | Seed store requires plan 04 |
| `RootView` placeholder | `MyHomeApp/RootView.swift` | ExpenseListView arrives in plan 03 |
| `Features/Expenses/` empty | folder | Populated in plan 03 |
| `Persistence/Schema/` empty | folder | Populated in plan 02 |
| `Persistence/Models/` empty | folder | Populated in plan 02 |

These stubs are the correct state at this plan stage (Nyquist Wave 0 baseline). They will be filled in plans 02-04.

## Threat Surface Scan

No new threat surface beyond what is declared in the plan's threat model:
- `PrivacyInfo.xcprivacy` correctly mitigates T-01-02 (App Store rejection via ITMS-91053)
- SwiftData store URL is NOT set yet (plan 02) — T-01-01 (store Data Protection) is unaffected at this stage
- Zero third-party packages installed — T-01-SC not applicable

## Self-Check: PASSED

Files exist:
- MyHome.xcodeproj/project.pbxproj ✓
- MyHome.xcodeproj/xcshareddata/xcschemes/MyHome.xcscheme ✓
- MyHomeApp/MyHomeApp.swift ✓
- MyHomeApp/RootView.swift ✓
- MyHomeApp/MyHome.entitlements ✓
- MyHomeApp/Resources/PrivacyInfo.xcprivacy ✓
- MyHomeTests/ExpenseModelTests.swift ✓
- MyHomeTests/MigrationTests.swift ✓
- README.md ✓

Commits exist:
- 990c446 feat(01-01): bootstrap Xcode project ✓
- b2efedd feat(01-01): add PrivacyInfo.xcprivacy and Swift Testing stubs ✓
