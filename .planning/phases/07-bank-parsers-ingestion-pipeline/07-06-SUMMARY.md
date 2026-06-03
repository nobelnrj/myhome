---
phase: 07-bank-parsers-ingestion-pipeline
plan: 06
type: execute
wave: 4
status: complete
completed: 2026-06-03
requirements: [ING-04, ING-12, ING-13, ING-14]
subsystem: ingestion
tags: [gmail-sync, ingestion-pipeline, review-inbox, bgtask, live-verified]

dependency_graph:
  requires: ["07-02", "07-03", "07-05"]
  provides: ["GmailSyncController.sync pipeline", "Review Inbox UI", "BGAppRefreshTask"]
  affects: ["ExpenseListView", "ExpenseRow", "RootView", "MyHomeApp"]

tech_stack:
  added: []
  patterns:
    - "Full foreground ingestion pipeline: getProfile→list→skip-dismissed→skip-ingested→getRaw→parse→score→dedup→triage→persist"
    - "Triage by confidence threshold (0.85): autoSaved / needsReview / possibleDuplicate"
    - "Idempotent re-sync via gmailMessageID guard (ING-14)"
    - "Best-effort BGAppRefreshTask with reschedule-inside-handler + fresh ModelContainer + MainActor hop"
    - "Review Inbox section + tab badge driven by ingestionStateRaw query"

key_files:
  created:
    - MyHomeApp/Features/Expenses/ReviewInboxRow.swift
  modified:
    - MyHomeApp/Features/Gmail/GmailSyncController.swift
    - MyHomeApp/Features/Expenses/ExpenseListView.swift
    - MyHomeApp/Features/Expenses/ExpenseRow.swift
    - MyHomeApp/Features/Ingestion/DismissedMessageStore.swift
    - MyHomeApp/Features/Ingestion/HDFCParser.swift
    - MyHomeApp/RootView.swift
    - MyHomeApp/MyHomeApp.swift
    - MyHomeApp/Info.plist
    - MyHomeTests/IngestionPipelineTests.swift
    - MyHomeTests/GmailSyncControllerTests.swift
    - MyHome.xcodeproj/project.pbxproj

decisions:
  - "Auto-save threshold kept at 0.85 as a named constant (autoSaveThreshold) — tunable pending calibration"
  - "First-sync backfill widened from 30d to 120d (~4 months) so the initial sync captures meaningful spend history (live-verification finding)"
  - "Re-sync idempotency enforced by a gmailMessageID Set guard, separate from DedupChecker (which matches amount+merchant+date across other expenses)"
  - "Merchant→category auto-categorisation resolves the parser's categoryHint to a seeded Category by name; unknown merchants stay Uncategorized (D7-09)"
  - "From header normalized to a bare address (unwrap 'Display <addr>') and trailing CRLF stripped so parser host-suffix matching works on real Gmail RAW emails"
  - "Added HDFCParser.parseUPIInstaAlert for the newer 'has been debited from account ... to VPA' InstaAlert format absent from the 07-04 sample corpus"

metrics:
  completed_date: "2026-06-03"
  tasks: 4
  files_created: 1
  files_modified: 11
---

# Phase 07 Plan 06: End-to-End Ingestion Pipeline + Review Inbox + BGAppRefreshTask Summary

## One-liner

Wired the full zero-touch Gmail ingestion pipeline (parse → score → dedup → triage → persist), the Review Inbox triage surface with a tab badge, the auto marker + source label, and a best-effort BGAppRefreshTask — then calibrated it against the real inbox during live verification.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | GmailSyncController full pipeline + connectedEmail (UAT-6-05) | 2a627a5 |
| 2 | Review Inbox UI + tab badge + auto marker + source label | 2a627a5 |
| 3 | BGAppRefreshTask registration + Info.plist keys | 2a627a5 |
| 4 | Live human-verify checkpoint (simulator + real Google account) | live this session + f0ac84d |

## What Was Built

### Task 1: GmailSyncController pipeline (commit 2a627a5)
- `sync()` runs the full pipeline: `getProfile`→`connectedEmail` (UAT-6-05), `listMessageIDs` (bank-sender + time-window query), then per message: skip dismissed → skip already-ingested → `getRawMessage` → pick parser via `canHandle` → `parse` → `ConfidenceScorer.score` → `DedupChecker.findDuplicate` → triage → persist `Expense` with SchemaV4 ingestion fields.
- Triage: `possibleDuplicate` if a dedup hit, else `autoSaved` if confidence ≥ 0.85, else `needsReview`.
- Phase 6 proactive token-refresh block and `.error`/`.tokenExpired` handling preserved (06-SECURITY intact).

### Task 2: Review Inbox UI (commit 2a627a5)
- `ReviewInboxRow.swift` — triage row showing parsed fields + source label, with swipe Accept (clears `ingestionStateRaw`) and Discard (records dismissed message ID + deletes), tap-to-edit, and a possible-duplicate side-by-side line.
- `ExpenseListView` — "Needs Review" section above the main list, driven by an `ingestionStateRaw != autoSaved` query; exposes the review count to `RootView` for the Expenses-tab `.badge`.
- `ExpenseRow` — envelope "auto" marker for `autoSaved` expenses + source label when present.

### Task 3: BGAppRefreshTask (commit 2a627a5)
- `Info.plist`: `BGTaskSchedulerPermittedIdentifiers` (`com.reojacob.myhome.emailrefresh`) + `UIBackgroundModes` (`fetch`).
- `MyHomeApp`: `.backgroundTask(.appRefresh(...))` handler that reschedules first, hops to `MainActor`, builds a fresh `ModelContainer`/context, and runs `sync()`; `scheduleBackgroundRefresh()` submitted on `.background` scene phase. "Sync now" remains the reliable path.

### Task 4: Live verification + real-corpus calibration (this session + commit f0ac84d)
Verified against the live Google account on the simulator. Real-inbox findings were fixed during verification:
- **First-sync window too narrow** — widened backfill 30d → 120d so the initial sync pulls ~4 months of history.
- **Re-sync re-inserted the same emails** — added a `gmailMessageID` Set guard for idempotent re-sync (ING-14).
- **Auto-categorisation missing** — resolve the parser's `categoryHint` to a seeded `Category` by name (D7-09/D7-12).
- **HDFC UPI alerts dropped** — real `From` headers arrive as `Display Name <addr>` with trailing CRLF; added bare-address normalization + CRLF trimming so host-suffix matching works. Added `parseUPIInstaAlert` for the newer HDFC "has been debited from account … to VPA" format that was absent from the 07-04 sample corpus.

A separate follow-up (commit 855b69b) grouped the expense list by month with per-month totals and added a category filter — a UI polish on top of the now-populated list, not part of the 07-06 plan scope.

## Deviations from Plan

### Bookkeeping anomaly (resolved)
The Task 1–3 code was committed (2a627a5) and the Task 4 human-verify checkpoint was completed live, but the `07-06-SUMMARY.md` and STATE/ROADMAP updates were never written — leaving the plan looking incomplete on disk. Resolved via `/gsd-execute-phase 7`'s safe-resume gate: closed out manually (no re-execution) after confirming the production commit + live verification.

### Temp diagnostics removed
Live verification used scaffolding in `GmailSyncController` (os.Logger pipeline traces, a forced full-backfill `if true` override, parse-fail `.eml` dumps to Documents). All removed before close-out; the watermark-based incremental-sync query was restored. The real fixes above were kept (commit f0ac84d).

## Verification

- `xcodebuild build` — BUILD SUCCEEDED (iPhone 17 simulator)
- `xcodebuild test` — TEST SUCCEEDED (full suite, including IngestionPipelineTests + GmailSyncControllerTests)
- Live: connected-email shown after Sync, real bank emails ingested + auto-categorised, Review Inbox triage + badge functional, idempotent re-sync confirmed.
- BGAppRefreshTask registered; LLDB simulate-trigger / real-device overnight run is best-effort per plan (Sync now is the reliable path).

## Self-Check: PASSED
