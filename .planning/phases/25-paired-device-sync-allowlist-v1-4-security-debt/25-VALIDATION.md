---
phase: 25
slug: paired-device-sync-allowlist-v1-4-security-debt
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-24
---

# Phase 25 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Derived from the
> "## Validation Architecture" section of 25-RESEARCH.md (maps all 6 success criteria).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`@Suite`/`@Test`) + XCTest, via `xcodebuild test` |
| **Config file** | MyHome.xcodeproj (scheme `MyHome`) |
| **Quick run command** | `xcodebuild test -project MyHome.xcodeproj -scheme MyHome -destination 'platform=iOS Simulator,id=560D9A16-6007-45DB-A996-DFBA222A0F87' -derivedDataPath /tmp/mh-dd -only-testing:MyHomeTests/SyncTransportTests -only-testing:MyHomeTests/PairingCodeTests -only-testing:MyHomeTests/PeerAllowlistTests` |
| **Full suite command** | `xcodebuild test -project MyHome.xcodeproj -scheme MyHome -destination 'platform=iOS Simulator,id=560D9A16-6007-45DB-A996-DFBA222A0F87' -derivedDataPath /tmp/mh-dd` |
| **Estimated runtime** | quick ~30s · full ~2-3 min |

---

## Sampling Rate

- **After every task commit:** run the quick command for the touched suite.
- **After every plan wave:** run the full suite.
- **Before `/gsd-verify-work`:** full suite green + on-device two-phone pairing sign-off (the one unavoidable manual gate — MC pairing can't be exercised in a single simulator).
- **Max feedback latency:** ~30s (quick), ~3 min (full).

---

## Per-Task Verification Map

> Populated by the planner alongside PLAN.md. Each success criterion below MUST map to at
> least one automated check (pure-function unit test preferred; transport-seam integration
> test via FakeSyncTransport where a session is required).

| Success Criterion | Requirement | Threat Ref | Verification approach | Test Type |
|-------------------|-------------|------------|-----------------------|-----------|
| SC-1 unpaired ⇒ no invite/accept/merge | SYNC-06 | T-25-01 | `PeerAllowlistPolicy.shouldConnect` returns false for empty allowlist; FakeSyncTransport: unknown peer forms no session | unit + integration |
| SC-2 code-confirmed pairing adds peer both sides | SYNC-06 | T-25-02 | `PairingCode.sixDigit` deterministic + order-independent; pairing state machine persists only after mutual confirm | unit |
| SC-3 paired peer merges as before (no LWW regression) | SYNC-06 | — | existing sync round-trip tests stay green with a paired allowlist | integration |
| SC-4 upgrade ⇒ sync paused + re-pair prompt, no auto-adopt | SYNC-06 | T-25-03 | empty allowlist ∧ lastSyncedAt≠nil ⇒ paused state; no installID auto-added | unit |
| SC-5 allowlist never in exported/synced snapshot | SYNC-06 | T-25-04 | bytes-don't-contain test mirroring `expensesNeverCrossTheWire` | unit |
| SC-6 unpair removes + stops future connects | SYNC-06 | T-25-02 | store removal ⇒ `shouldConnect` false for that iid | unit |

*Status: ⬜ pending until planner writes the task-level map.*

---

## Wave 0 Requirements

- [ ] Allowlist / code / gating tests EXTEND the existing `MyHomeTests/SyncTransportTests.swift` (the plans chose this over new stub files — same proven pattern as `PeerInvitePolicy` tests). No separate `PairingCodeTests`/`PeerAllowlistTests` files are created.
- [ ] Every new `.swift` file (`PairedDevicesStore.swift`, the pairing view) needs the 4 manual `project.pbxproj` edits — an explicit sub-step with a `grep -c … == 4` acceptance check lives in 25-01 Task 2 and 25-03 Task 2 (no synchronized groups in this project).

> Note: this doc's frontmatter (`nyquist_compliant`, `wave_0_complete`, sign-off) is finalized during/after 25-01 execution, once the tests referenced by each plan's `<automated>` command exist and pass.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real two-phone code-confirmed pairing + rogue-peer rejection | SYNC-06 | MultipeerConnectivity pairing needs two real devices on a LAN; a single simulator can't form the session | On both phones: Settings › Sync › Pair New Device → confirm matching 6-digit code → verify sync resumes; then confirm an unpaired peer (seeded sim) never connects. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 180s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
