---
phase: 07-bank-parsers-ingestion-pipeline
plan: 04
type: execute
wave: 2
status: complete
completed: 2026-06-02
requirements: [ING-06, ING-07, ING-08, ING-09]
---

# 07-04 Summary — Bank email corpus (human-action gate)

## Outcome

Human corpus-collection gate satisfied with a **real but small** corpus (8 anonymized
`.eml` fixtures). Confirmed senders/subjects/body templates recorded for plan 05; PII
scrubbed (T-07-07 mitigated). Two real gaps logged as deferred.

## What was collected (vs ≥50/bank target)

| Bank | cc-spend | upi/debit | refund/reversal | credit (non-expense) | reject | total |
|---|---|---|---|---|---|---|
| HDFC | — (no HDFC CC held) | 2 (UPI + debit-card) | 1 | 1 (P2P incoming) | — | 4 |
| ICICI | 2 | — (no alert mail) | — | — | 1 statement | 3 |
| Amazon Pay | — | — | — | — | 1 reminder | 1 |

Total **8**. Real-but-short → every collected template is deterministically
fingerprintable, but the **0.85 confidence threshold stays uncalibrated** (carried
Phase-7 blocker, tune after a week of real data).

## Confirmed (replaces RESEARCH `[ASSUMED]`)

- **Senders:** HDFC `alerts@hdfcbank.bank.in` (DMARC p=REJECT), ICICI `credit_cards@icici.bank.in` — gTLD `.bank.in`. Pre-filter accepts only these hosts.
- **Subjects + body templates** for all 6 transaction types documented in `MyHomeTests/Fixtures/README.md`.
- **Key finding:** HDFC P2P-credit and refund share the subject `View: Account update for your HDFC Bank A/c` → plan 05 MUST disambiguate on body (refund = "credited … by VPA <refund-vpa> <merchant>", no "Sender:" line), not subject.
- **3 merchant-extraction strategies** (HDFC-UPI parens / HDFC-card `at…on` / ICICI `Info:`) and **3 date formats** — per-template parsing required.

## Files

- `MyHomeTests/Fixtures/README.md` — confirmed senders/subjects/templates + fixture inventory + gaps.
- `MyHomeTests/Fixtures/*.eml` — 8 scrubbed fixtures (6 real txn/credit + 2 header-true reject stubs).
- `MyHomeTests/Fixtures/_raw/` — raw originals, **git-ignored** (PII, local only).
- `.gitignore` — added `_raw/` rule.

## Anonymization (T-07-07)

Format-preserving placeholders for name/email/VPA/card-tails/UPI-refs; merchant names &
refund VPAs kept for parser realism. Bulky statement (945 KB + PDF) and Amazon reminder
committed as header-true, body-trimmed stubs — no PII-heavy body committed. PII sweep of
committed set: clean.

## Deferred (logged in README)

- **HDFC credit-card spend** template — user holds no HDFC CC → future update.
- **ICICI UPI/debit/account** alerts — account barely used / no alert mail → ICICI parser is CC-spend + statement-reject only.
- **n>1 per template** — single sample per type; add as real txns accumulate.

## Handoff to plan 05

Parsers should be written to the confirmed templates as canonical fingerprints, ship
HDFC = {UPI-debit, debit-card, refund, P2P-credit-skip} and ICICI = {CC-spend, statement-reject},
implement reversal detection (validated only by `hdfc_refund_1`), and leave the 0.85
threshold as a tunable constant pending real-usage calibration.
