---
phase: 07-bank-parsers-ingestion-pipeline
plan: 05
type: tdd
wave: 3
status: complete
completed: 2026-06-03
requirements: [ING-06, ING-07, ING-08, ING-09]
subsystem: ingestion
tags: [bank-parser, hdfc, icici, gmail-fetch, tdd]

dependency_graph:
  requires: ["07-01", "07-03", "07-04"]
  provides: ["HDFCParser", "ICICIParser", "SystemGmailFetch"]
  affects: ["GmailSyncController", "IngestionPipeline"]

tech_stack:
  added: []
  patterns:
    - "Two-stage bank parser: canHandle pre-filter + fingerprint-match + value-extract"
    - "QP decode on Unicode scalars (not grapheme clusters) to handle CRLF soft line breaks"
    - "HTML-only email body extraction via targeted tag stripping (no MIME library)"
    - "NSRegularExpression + Decimal for money amounts (never Double — Pitfall 17)"
    - "URLSession GET + Bearer token + pagination for Gmail REST"

key_files:
  created:
    - MyHomeApp/Features/Ingestion/HDFCParser.swift
    - MyHomeApp/Features/Ingestion/ICICIParser.swift
    - MyHomeTests/Resources/Fixtures/hdfc_upi_debit_1.eml
    - MyHomeTests/Resources/Fixtures/hdfc_debit_card_1.eml
    - MyHomeTests/Resources/Fixtures/hdfc_refund_1.eml
    - MyHomeTests/Resources/Fixtures/hdfc_upi_credit_1.eml
    - MyHomeTests/Resources/Fixtures/icici_cc_spend_1.eml
    - MyHomeTests/Resources/Fixtures/icici_cc_spend_2.eml
    - MyHomeTests/Resources/Fixtures/icici_statement_reject_1.eml
    - MyHomeTests/Resources/Fixtures/amazonpay_reminder_reject_1.eml
  modified:
    - MyHomeApp/Gmail/GmailFetchPort.swift
    - MyHomeTests/HDFCParserTests.swift
    - MyHomeTests/ICICIParserTests.swift
    - MyHome.xcodeproj/project.pbxproj

decisions:
  - "HDFC/ICICI emails are HTML-only (no text/plain part) — body extracted from HTML via QP-decode + tag strip"
  - "QP decoder operates on Unicode scalars not Swift Characters to avoid CRLF grapheme-cluster collapse"
  - "Fixtures live in MyHomeTests/Resources/Fixtures/ (project bundle reference path, not MyHomeTests/Fixtures/)"
  - "HDFC P2P-credit disambiguated from refund on body: has-been vs is-successfully + Sender: line presence"
  - "listMessageIDs capped at 3 pages (Pitfall 7) to prevent runaway Gmail API pagination"

metrics:
  duration_minutes: 95
  completed_date: "2026-06-03"
  tasks: 2
  files_created: 12
  files_modified: 3
---

# Phase 07 Plan 05: HDFC/ICICI Parsers + SystemGmailFetch Summary

## One-liner

HDFC and ICICI bank email parsers calibrated to the real 07-04 corpus via two-stage HTML+QP extraction, with SystemGmailFetch real Gmail REST pagination.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | HDFCParser + ICICIParser GREEN against real corpus (RED → GREEN → REFACTOR) | 3fac4d0 |
| 2 | SystemGmailFetch real Gmail REST implementation | 89c035a |

## What Was Built

### Task 1: HDFCParser + ICICIParser

**HDFCParser** (`struct HDFCParser: BankEmailParser`, parserID `hdfc-v1`):
- `canHandle`: accepts `@hdfcbank.bank.in` sender + non-blocked subject; rejects OTP/promo/verification/statement
- Templates: UPI-debit, debit-card, refund (3 templates); P2P-credit → nil (skip, not an expense)
- Body extraction: QP-decode (scalar-level CRLF handling) + HTML tag strip
- Amount: NSRegularExpression on `Rs.{amount}` patterns, `Decimal(string:)` — never Double
- Reversal: refund template always sets `isReversal=true`, `amount=-abs(amount)`
- HDFC P2P-credit disambiguated from refund via `"by VPA"` (refund) vs `"Sender:"` (P2P)
- MerchantNormalizer.normalize() called at parse time

**ICICIParser** (`struct ICICIParser: BankEmailParser`, parserID `icici-v1`):
- `canHandle`: accepts `@icici.bank.in` sender + non-blocked subject; rejects statement/OTP/promo
- Templates: CC-spend (one template — corpus-limited per plan 07-04 gaps)
- Body extraction: HTML tag strip (ICICI emails are 7bit, no QP needed)
- Amount: NSRegularExpression on `INR {amount} on` pattern, Indian comma handling
- Merchant: extracted from `Info: {MERCHANT}.` pattern

**Test coverage** — HDFCParserTests + ICICIParserTests (26 tests):
- canHandle: accept + reject for all edge cases (OTP, promo, verification, statement, wrong sender)
- parse: all fixture files (6 real transactions + 2 reject stubs), fingerprint-fail nil case
- Reversal detection, score ranges, normalizedMerchant population

### Task 2: SystemGmailFetch

Three Gmail REST v1 endpoints implemented:
- `getProfile`: GET `/profile` → `GmailProfile`
- `listMessageIDs`: GET `/messages?q=&maxResults=` with `nextPageToken` loop (max 3 pages)
- `getRawMessage`: GET `/messages/{id}?format=RAW` + base64url decode (`-`→`+`, `_`→`/`, pad, `Data(base64Encoded:)`)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] HDFC emails are HTML-only — no text/plain part**
- **Found during:** Task 1 (reading fixtures)
- **Issue:** Plan assumed text/plain part exists; real HDFC emails (confirmed corpus) are multipart/alternative with text/html only (quoted-printable)
- **Fix:** Body extraction decodes quoted-printable then strips HTML tags; finds `<html` start, works on the HTML body
- **Files modified:** HDFCParser.swift (extractVisibleText, decodeQuotedPrintable, stripHTMLTags)
- **Commit:** 3fac4d0

**2. [Rule 1 - Bug] Swift CRLF grapheme cluster collapses =\r\n in QP decoder**
- **Found during:** Task 1 (QP decoder not handling CRLF soft line breaks)
- **Issue:** Swift `Character` treats `\r\n` as a single grapheme cluster; checking `char == "\r"` when char is `\r\n` returns false. All HDFC emails use `=\r\n` QP soft line breaks, causing fingerprint misses.
- **Fix:** QP decoder rewrote to operate on `unicodeScalars` array with integer index, checking U+000D and U+000A separately
- **Files modified:** HDFCParser.swift (decodeQuotedPrintable)
- **Commit:** 3fac4d0

**3. [Rule 1 - Bug] Fixtures in wrong directory for test bundle**
- **Found during:** Task 1 (fixture-loading tests failing with FixtureError.notFound)
- **Issue:** Project file reference F711FIX points to `MyHomeTests/Resources/Fixtures/` (inside the `Resources` group), but the `.eml` files were placed in `MyHomeTests/Fixtures/` by plan 07-04
- **Fix:** Copied `.eml` files to `MyHomeTests/Resources/Fixtures/` (the path the bundle reference resolves to)
- **Files modified:** 8 `.eml` files added to MyHomeTests/Resources/Fixtures/
- **Commit:** 3fac4d0

## TDD Gate Compliance

- RED gate: Test stubs rewritten with real fixture data + actual parser references → compiled with `cannot find 'HDFCParser' in scope` errors (confirmed RED)
- GREEN gate: Both parsers implemented; all 26 tests pass (`** TEST SUCCEEDED **`)
- REFACTOR: No structural changes needed after GREEN

## Threat Surface Scan

No new threat surface beyond the plan's `<threat_model>`. All three T-07-08/09/10 mitigations are implemented:
- T-07-08: Parser treats body as plain String; no eval, no HTML rendering, no script execution
- T-07-09: canHandle pre-filter rejects non-bank senders before body retention
- T-07-10: All Gmail calls over HTTPS via URLSession.shared; token never logged; in-memory only

## Self-Check: PASSED
