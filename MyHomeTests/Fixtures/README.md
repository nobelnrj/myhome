# MyHomeTests/Fixtures — Bank Email Corpus (plan 07-04)

Anonymized real `.eml` alerts used to calibrate the HDFC and ICICI parsers (plan 07-05)
and the ingestion pipeline (plan 07-06). All committed files were scrubbed of PII; the
raw originals live in `_raw/` (git-ignored, local only).

> **Calibration caveat (volume):** Target was ≥50/bank. Actual corpus is **8 emails**
> (4 HDFC txn + 1 HDFC-credit + 2 ICICI-CC + 2 reject). This is enough to fingerprint
> every collected template **deterministically**, but **not** enough to statistically
> calibrate the 0.85 confidence threshold — that remains the carried Phase-7 blocker
> ("confidence threshold needs real-data calibration after first week", STATE.md).

---

## Confirmed senders

| Bank / source | From address (confirmed) | Display name | Notes |
|---|---|---|---|
| HDFC | `alerts@hdfcbank.bank.in` | `HDFC Bank InstaAlerts` | Envelope domain `comm.hdfcbank.bank.in`; SPF + DKIM pass, **DMARC `p=REJECT`** (spoof-resistant). gTLD is `.bank.in`. |
| ICICI | `credit_cards@icici.bank.in` | _(often none — bare `<credit_cards@icici.bank.in>`)_ | gTLD is `.bank.in`. |
| Amazon Pay (reject) | `no-reply@amazonpay.in` | `Amazon Pay India` | Not a bank alert sender → must be rejected. |

**Pre-filter rule for plan 05:** accept only `From` host == `hdfcbank.bank.in` (HDFC) or
`icici.bank.in` (ICICI). Everything else (incl. `amazonpay.in`) is rejected before body parsing.

## Confirmed subjects

| Type | Subject (confirmed) | Disambiguation note |
|---|---|---|
| HDFC UPI debit (spend) | `❗ You have done a UPI txn. Check details!` | Leading ❗ emoji, RFC2047 UTF-8 encoded-word in the header. |
| HDFC debit-card spend | `Rs.<amt> debited via Debit Card **<NNNN>` | Amount + masked card are **in the subject**. |
| HDFC UPI credit (P2P incoming) | `View: Account update for your HDFC Bank A/c` | ⚠️ **Same subject as refund** — must disambiguate in body. |
| HDFC refund / reversal | `View: Account update for your HDFC Bank A/c` | ⚠️ Identical subject to P2P credit. |
| ICICI CC spend | `Transaction alert for your ICICI Bank Credit Card` | |
| ICICI statement (reject) | `Amazon Pay ICICI Bank Credit Card Statement for the period …` | Carries a password-protected PDF; not a txn. |
| Amazon reminder (reject) | `Payment Reminder` | Promotional, non-bank sender. |

> **Subject is NOT sufficient for HDFC credit vs refund.** Both share
> `View: Account update for your HDFC Bank A/c`. Disambiguate on the body (see below).

## Confirmed body templates (the parse contract)

**HDFC UPI debit (spend)** — `hdfc_upi_debit_1.eml`
```
Rs.<amount> is debited from your account ending <NNNN> towards VPA <vpa> (<MERCHANT>) on <dd-mm-yy>.
UPI transaction reference no.: <ref>.
```
→ merchant = text inside `(...)` after the VPA. direction = debit.

**HDFC debit-card spend** — `hdfc_debit_card_1.eml`
```
Rs.<amount> is debited from your HDFC Bank Debit Card ending <NNNN> at <MERCHANT> on <dd Mon, yyyy> at <hh:mm:ss>.
```
→ merchant = text between ` at ` and ` on `. direction = debit.

**HDFC UPI credit — P2P incoming (NOT an expense)** — `hdfc_upi_credit_1.eml`
```
Rs.<amount> has been successfully credited to your HDFC Bank account ending in <NNNN>.
Transaction Details: a. Date: <dd-mm-yy> b. Sender: <NAME> (VPA: <vpa>) c. UPI Reference No.: <ref>
```
→ credited from a **person** ("Sender: <name>") → income/transfer → **skip, do not create an expense**.

**HDFC refund / reversal** — `hdfc_refund_1.eml`
```
Rs. <amount> is successfully credited to your account **<NNNN> by VPA <refund-vpa> <MERCHANT> on <dd-mm-yy>.
Your UPI transaction reference number is <ref>.
```
→ credited **by a refund VPA** (e.g. `gpayrefund-online@axisbank`) tied to a **merchant** →
`isReversal = true`. Distinguish from P2P credit: refund says "is successfully credited … **by VPA**"
(no "Sender:" line; VPA local-part contains `refund`), P2P says "**has been** successfully credited … Sender:".

**ICICI CC spend** — `icici_cc_spend_1.eml`, `icici_cc_spend_2.eml`
```
Your ICICI Bank Credit Card XX<NNNN> has been used for a transaction of INR <amount> on <Mon dd, yyyy> at <hh:mm:ss>. Info: <MERCHANT>.
```
→ merchant = text after `Info:` up to the period. direction = debit.

### Formatting quirks the parser MUST tolerate
- **Amount prefix:** HDFC uses `Rs.` (no space) **and** `Rs. ` (with space, in the refund). ICICI uses `INR `.
- **Indian digit grouping:** ICICI amounts/limits group as `1,791.28` and lakh-style `2,57,941.00`.
- **Three date formats:** HDFC-UPI `dd-mm-yy` (`02-06-26`); HDFC-debit-card `dd Mon, yyyy` (`01 Jun, 2026`); ICICI `Mon dd, yyyy` (`Jun 02, 2026`).
- **Masked tails:** HDFC "ending <NNNN>" / "**<NNNN>"; ICICI "XX<NNNN>".

## Fixture inventory

| File | Bank | Type | Expected amount | Expected merchant | isReversal | canHandle |
|---|---|---|---|---|---|---|
| `hdfc_upi_debit_1.eml` | HDFC | UPI debit (spend) | 1500.00 | FRESHALICIOUS SUPER BAZAAR | false | ✅ true |
| `hdfc_debit_card_1.eml` | HDFC | Debit-card spend | 537.00 | Delightful Gourmet Pvt | false | ✅ true |
| `hdfc_upi_credit_1.eml` | HDFC | UPI credit (P2P in) | 2000.00 | _(sender, skip)_ | n/a — **skip, not an expense** | ✅ recognised, classified non-expense |
| `hdfc_refund_1.eml` | HDFC | Refund / reversal | 167.00 | Google India Digital Services Pvt Ltd | **true** | ✅ true |
| `icici_cc_spend_1.eml` | ICICI | CC spend | 833.00 | AMAZON PAY IN E COMMERCE | false | ✅ true |
| `icici_cc_spend_2.eml` | ICICI | CC spend | 1791.28 | BOOKMYSHOW COM | false | ✅ true |
| `icici_statement_reject_1.eml` | ICICI | Statement | — | — | — | ❌ false (reject) |
| `amazonpay_reminder_reject_1.eml` | Amazon Pay | Promo reminder | — | — | — | ❌ false (reject) |

## Confirmed vs RESEARCH `[ASSUMED]` (flags for plan 05)

- ✅ **Senders confirmed** — use `hdfcbank.bank.in` / `icici.bank.in` (gTLD `.bank.in`).
  If RESEARCH A1/A2 assumed `hdfcbank.net` / `icicibank.com`, **the real corpus contradicts it** — use the confirmed `.bank.in` hosts.
- ✅ **Merchant extraction confirmed** — three different strategies (HDFC-UPI parens, HDFC-card `at…on`, ICICI `Info:`). Single regex won't cover all; use per-template extraction.
- ⚠️ **Subject pre-filter insufficient for HDFC credit/refund** (shared subject) — body inspection required.
- ⚠️ **Confidence 0.85 NOT calibrated** (n=8). Carry as Phase-7 blocker; tune after a week of real data.

## Known gaps (deferred)

| Gap | Reason | Disposition |
|---|---|---|
| **HDFC credit-card spend** template | User holds no HDFC credit card | Future update; HDFC parser ships with debit-card + UPI + refund fingerprints only. |
| **ICICI UPI / debit / account** alerts | ICICI account barely used; strict/no alert mail | ICICI parser covers CC-spend + statement-reject only. |
| **OTP / promo** per bank | Not collected | `amazonpay_reminder_reject_1` + `icici_statement_reject_1` exercise the non-txn reject path instead. |
| **n>1 per template** (format variation) | Only 1 real sample per type | Add as real txns accumulate. |

## Anonymization (T-07-07)

Committed files are PII-scrubbed with **format-preserving** placeholders: personal name →
`ANANYA SHARMA …`, owner email → `customer@example.com`, owner VPA → `ananyasharma@okicici`,
account/card tails and 12-digit UPI refs → placeholder digits. **Merchant names and merchant/refund
VPAs are kept** (businesses, needed for realistic parsing). The two bulky non-transaction emails
(ICICI statement + Amazon reminder) are committed as **header-true, body-trimmed stubs** so no
PII-heavy body (or PDF attachment) is committed. Raw originals: `_raw/` (git-ignored).
