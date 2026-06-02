# MyHomeTests/Fixtures

This directory contains anonymized `.eml` corpus files used to test the HDFC and ICICI bank email parsers.

## Corpus Gate

The `.eml` files are collected and added by the **human corpus-collection checkpoint** in **plan 04** before parser calibration begins in **plan 05**. This directory intentionally ships empty in plan 01.

**Do not add synthetic or AI-generated `.eml` files.** Parsers must be calibrated against real bank email alerts; synthetic emails do not exercise real-world formatting variation (HTML entities, line endings, multi-part MIME, encoding variants).

## Expected Naming Convention

### HDFC

| Filename Pattern | Description |
|---|---|
| `hdfc_cc_spend_N.eml` | Credit card spend alert (N = 1, 2, 3, …) |
| `hdfc_upi_debit_N.eml` | UPI/NEFT debit alert |
| `hdfc_refund_N.eml` | Refund / reversal (expect `isReversal = true`, negative amount) |
| `hdfc_otp_N.eml` | OTP email (rejection fixture — `canHandle` must return `false`) |
| `hdfc_promo_N.eml` | Promotional email (rejection fixture) |
| `hdfc_statement_N.eml` | Account statement email (rejection fixture) |

### ICICI

| Filename Pattern | Description |
|---|---|
| `icici_cc_spend_N.eml` | Credit card spend alert |
| `icici_upi_debit_N.eml` | UPI/NEFT debit alert |
| `icici_refund_N.eml` | Refund / reversal |
| `icici_otp_N.eml` | OTP email (rejection fixture) |
| `icici_promo_N.eml` | Promotional email (rejection fixture) |
| `icici_statement_N.eml` | Account statement email (rejection fixture) |

## Anonymization Requirements

Before adding corpus files:
1. Replace real card numbers with `••1234` (last 4 digits only).
2. Replace real merchant amounts with plausible but non-personal values.
3. Remove personal names, addresses, and account balances.
4. Replace real timestamps with anonymized dates (keep the format, change the value).
5. Do NOT include Gmail Message-ID headers that could identify the sender's account.

## Volume Target

Aim for **50+ real emails per bank** (HDFC + ICICI) before calibrating the parsers in plan 05. The confidence threshold (0.85) is calibrated against this corpus.

## Bundle Resource Registration

The `Fixtures` folder is registered as a bundle resource of the `MyHomeTests` target in `project.pbxproj`. Files added to this directory are automatically included in the test bundle and loaded via:

```swift
Bundle(for: type(of: SpyGmailFetch())).url(forResource:withExtension:subdirectory:)
```
