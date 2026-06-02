---
phase: 07
slug: bank-parsers-ingestion-pipeline
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-02
---

# Phase 07 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Swift) |
| **Config file** | none — MyHome.xcodeproj scheme `MyHome` |
| **Quick run command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests` |
| **Full suite command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |
| **Estimated runtime** | ~TBD seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command (scoped `-only-testing`)
- **After every plan wave:** Run full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** TBD seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | ING-XX | T-07-01 / — | (to be filled by planner) | unit | `(command)` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Test fixtures for HDFC/ICICI parser corpus (`.eml` anonymized samples)
- [ ] Shared spy/double: `SpyGmailFetch` mirroring `SpyGmailAuth`
- [ ] Pure-logic test targets for ConfidenceScorer, DedupChecker, MerchantNormalizer

*If none: "Existing infrastructure covers all phase requirements."*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| BGAppRefreshTask fires overnight | ING-04 | Simulator cannot represent real BG scheduling | Install on real device, leave unplugged overnight, confirm ingestion ran |
| Real bank-email parse accuracy | ING-06/07 | Requires 50+ real anonymized HDFC/ICICI emails | Run corpus through parsers, confirm confidence calibration |

*If none: "All phase behaviors have automated verification."*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < TBDs
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
