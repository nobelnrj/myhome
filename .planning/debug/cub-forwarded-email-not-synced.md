---
status: resolved
trigger: "CUB forwarded transaction-alert email in the user's Gmail inbox does not appear in the expenses list after a Gmail sync. Forwarded from mebhuvanya001@gmail.com; original sender cubalert@cityunionbank.org."
created: 2026-06-05
updated: 2026-06-05
resolution_type: expected_behavior
---

# Debug Session: cub-forwarded-email-not-synced

## Symptoms

- **Expected behavior:** After Gmail sync, the CUB transaction-alert email (already present in the inbox, forwarded) should be parsed and appear in the expenses list.
- **Actual behavior:** The email does not appear in expenses after sync. No expense row is created.
- **Error messages:** None reported — silent no-show.
- **Timeline:** First test of the newly added CUBParser (added 2026-06-05). Never worked for this forwarded sample.
- **Reproduction:** A CUB alert forwarded from mebhuvanya001@gmail.com (top-level `From: Bhuvanya Sridhar <mebhuvanya001@gmail.com>`, `Subject: Fwd: CUB Transaction Alert`) sits in the inbox; original CUB sender `cubalert@cityunionbank.org` appears only inside the forwarded body. A sync is run; no expense is created.

## Relevant code

- `MyHomeApp/Features/Gmail/GmailSyncController.swift`
  - `bankSenderFilter` (line 149): `"from:(hdfcbank.bank.in OR icici.bank.in OR cityunionbank.org)"` — server-side Gmail query.
  - sync loop (lines 488-499): fetch raw message → `sender = emailAddress(from: extractHeader("From", ...))` → `parsers.first(where: canHandle)` → `parser.parse`.
  - `extractHeader` (749), `emailAddress` (771): read the FIRST top-level `From:` header line only.
- `MyHomeApp/Features/Ingestion/CUBParser.swift`
  - `canHandle(sender:subject:)` (48-63): requires sender host to end with `@cityunionbank.org` / `.cityunionbank.org`; blocks OTP/promo/statement subjects.
  - `parse` (67): fingerprint on body literals ("debited with INR", "towards", "Avl Bal").

## Evidence

- timestamp: 2026-06-05 — **Fixture corpus confirms two distinct forms.** The only committed CUB fixture `MyHomeTests/Resources/Fixtures/cub_savings_debit_1.eml` is the DIRECT form: top-level `From: CITYUNIONBANK <cubalert@cityunionbank.org>`, `Subject: CUB Transaction Alert`. The user's failing sample is the FORWARDED form: top-level `From: Bhuvanya Sridhar <mebhuvanya001@gmail.com>`, `Subject: Fwd: CUB Transaction Alert`, with `cubalert@cityunionbank.org` only inside the quoted body.

- timestamp: 2026-06-05 — **STAGE 1 (server-side query) drops the forwarded message.** `bankSenderFilter` = `from:(... OR cityunionbank.org)`. Gmail's `from:` operator matches the top-level `From` header only. For the forwarded message that header is `mebhuvanya001@gmail.com`, which does not match any OR term → Gmail never returns the message ID → it is never fetched. This is the FIRST and decisive drop point. (Cannot exercise the live API locally, but the filter string is a static literal and Gmail `from:` semantics are well-defined; the drop is deterministic.)

- timestamp: 2026-06-05 — **STAGE 2 (canHandle) would ALSO drop it, if it ever reached there.** `extractHeader("From", from:)` (line 749) iterates lines and returns the first whose prefix is `From:`. In the forwarded raw email the first such line is the forwarder's: `Bhuvanya Sridhar <mebhuvanya001@gmail.com>`. `emailAddress(from:)` (line 771) extracts `mebhuvanya001@gmail.com`. `CUBParser.canHandle` (line 51) requires `hasSuffix("@cityunionbank.org")` or `.cityunionbank.org` → `gmail.com` fails both → returns false → `parsers.first(where:)` finds no parser → `continue` (line 497). Independent confirmation that even a fetched forwarded message is rejected before parse.

- timestamp: 2026-06-05 — **STAGE 3 (subject block) is NOT the cause.** Subject `Fwd: CUB Transaction Alert` lowercased = `fwd: cub transaction alert`. Checked against `blockedSubjectKeywords` (otp, one time password, verification code, verify, promotional, offer, statement) — no substring match. Subject filtering is innocent; the message dies upstream on sender host regardless.

- timestamp: 2026-06-05 — **STAGES 4-5 (parse / dedup / dismissal) are unreachable.** They sit after the `canHandle` guard (lines 499-502). Since Stage 1 and Stage 2 both drop the message, parse/dedup/dismissal are never invoked and are not contributors.

- timestamp: 2026-06-05 — **DIRECT form is correctly handled (control).** For `cub_savings_debit_1.eml`, top-level `From:` is `CITYUNIONBANK <cubalert@cityunionbank.org>` → extracted address `cubalert@cityunionbank.org` → `hasSuffix("@cityunionbank.org")` true → canHandle passes → parse runs. The pipeline works for the user's confirmed real workflow. (Note: leading `Delivered-To:`/`Return-Path:` lines do not match prefix `From:`, so the real From line is selected correctly.)

## Resolution

- **root_cause:** The forwarded CUB email is dropped at the server-side Gmail query stage (`bankSenderFilter`, GmailSyncController.swift line 149): Gmail's `from:` operator matches only the top-level `From` header, which on a forwarded message is the forwarder (`mebhuvanya001@gmail.com`), not `cityunionbank.org` — so the message is never fetched. As a secondary barrier, even if fetched, `extractHeader("From")` + `CUBParser.canHandle` (line 51) reject the forwarder's host before parse. Both barriers are by-design sender authentication, not defects.

- **fix:** NOT APPLIED — none required for the intended workflow. The user has confirmed their real production flow is DIRECT bank emails from `cubalert@cityunionbank.org`, which the pipeline handles correctly (verified via `cub_savings_debit_1.eml`). The forwarded message was an unrepresentative test sample. This is **expected behavior**, not a bug: forwarding deliberately replaces the authenticated top-level sender, and matching on it is a security feature (T-07-09 — rejects non-bank senders). Supporting forwarded alerts would require (a) broadening the Gmail query and (b) extracting the embedded original sender from the quoted body — both of which weaken sender authentication and are only warranted if the user explicitly wants a forwarding workflow. Recommend no change unless that requirement is confirmed.

- **classification:** EXPECTED BEHAVIOR for an unrepresentative test input. The DIRECT-email workflow (the user's actual use case) is functioning correctly.
