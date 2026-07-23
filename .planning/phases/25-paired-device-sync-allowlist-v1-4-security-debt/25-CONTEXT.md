# Phase 25: Paired-Device Sync Allowlist - Context

**Gathered:** 2026-07-23
**Status:** Ready for planning
**Source:** Direct decision capture (user sign-off via AskUserQuestion, this session)

<domain>
## Phase Boundary

Fixes #43 (SYNC-06): `MultipeerSyncTransport` currently trusts every peer on the LAN — it invites any discovered peer, accepts any invitation, and accepts any certificate. A seeded `-seedSampleData` simulator on the Mac mini's network became a rogue third peer and silently LWW-merged its SAMPLE pantry into a real phone's Kitchen (Kitchen is in sync scope; money data is excluded, so only Kitchen was hit).

This phase adds a **paired-devices allowlist** so auto-sync only ever connects to and merges with the two paired household phones. It delivers: (1) allowlist enforcement in the transport, (2) a code-confirmed pairing ceremony in Settings › Sync, (3) a guided one-time re-pair migration for the two already-syncing phones, and (4) tests.

**In scope:** allowlist store, transport gating, pairing UI + code derivation, migration, unpair, tests.
**Out of scope:** anything that stops a determined attacker who sniffs and spoofs the installID off the home LAN (would need a shared secret at pairing) — see Deferred. Also out of scope: changing the Phase 18 merge engine / LWW semantics, or widening/narrowing what data syncs.
</domain>

<decisions>
## Implementation Decisions (LOCKED — user sign-off 2026-07-23; do not re-litigate)

### Identity
- Peer identity = the persistent per-install `installID` (UUID) that already exists in `MultipeerSyncTransport` (`sync.installID` in UserDefaults.standard). NOT the MCPeerID display name — the display name derives from `UIDevice.current.name`, which the user can change (renaming the phone would break a name-based allowlist).
- The full `installID` must be exchanged over channels MC already provides: advertise it in `MCNearbyServiceAdvertiser` `discoveryInfo` (e.g. `["iid": installID]`) so the browser can gate BEFORE inviting; and send it as the invitation `context` so the advertiser can gate BEFORE accepting. Today both `discoveryInfo` and invite `context` are `nil`.

### Allowlist store
- A new local, **never-synced** `PairedDevicesStore`: a Codable set of `{installID, friendlyName, pairedAt}` persisted in UserDefaults. Sync settings are per-device and MUST NOT appear in any exported/synced `SyncSnapshot`.

### Pairing ceremony = code-confirmed
- Both phones enter an explicit pairing window (from Settings › Sync › "Pair New Device"). During the window they display the SAME 6-digit code, derived **deterministically from both installIDs** (e.g. a truncated hash of the two IDs sorted, so both sides compute the identical code with no extra exchange). Each user taps "Codes match" before trust is recorded on that device. A rogue peer produces a different code (or an unexpected device name) → the user declines.
- Chosen over windowed trust-on-first-use specifically because this is a security fix and TOFU has a rogue-in-window hole.

### Migration = guided one-time re-pair
- On upgrade from an unpaired build, sync is PAUSED with a clear "Pair your devices to resume sync" prompt (banner in Settings › Sync and/or the Sync screen). The user runs the code-confirmed pairing once and sync resumes.
- NO auto-adopt of the currently-connected peer (auto-adopt would re-open the trust hole at the migration moment — exactly the seeded-sim scenario).

### Enforcement behavior
- Normal mode: `foundPeer` invites ONLY if the peer's `iid` ∈ allowlist; `didReceiveInvitationFromPeer` accepts ONLY if the invite `context` iid ∈ allowlist. Every other peer is silently ignored (no session forms → no merge).
- Pairing mode: a time-boxed flag that relaxes the gate to allow the pairing handshake with an as-yet-untrusted peer, but trust is only persisted after mutual code confirmation.
- Unpairing removes the installID from the allowlist and stops future connections to it.

### Claude's Discretion (implementation details, for research/planning to decide)
- Exact 6-digit code derivation function (hash choice, truncation) — must be deterministic, order-independent across the two installIDs, and unit-testable as a pure function.
- Pairing-mode state machine shape and timeout; how discovery/invite is driven during pairing.
- Precise UI layout of the pairing sheet, code display, confirm buttons, paired-devices list, and the migration/paused banner — follow the existing neumorphic Sync screen patterns.
- Where the "unpaired → paused" gate lives in `SyncCoordinator` / `SyncStatusStore`.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Sync transport & trust (where the allowlist gates go)
- `MyHomeApp/Sync/MultipeerSyncTransport.swift` — the ONLY file touching MultipeerConnectivity. `foundPeer` (invites any peer), `advertiser didReceiveInvitationFromPeer` (accepts any invite), `didReceiveCertificate` (accepts any cert), `start()` (advertiser built with `discoveryInfo: nil`). These are the enforcement points.
- `MyHomeApp/Sync/SyncTransport.swift` — `SyncTransport` protocol, `SyncTransportEvent`, and `PeerInvitePolicy` (serviceType `myhome-sync`, `displayName(deviceName:installID:)` embedding a 6-char installID prefix, `shouldInvite` tie-break). Pure/testable.
- `MyHomeApp/Sync/SyncCoordinator.swift` — `@MainActor @Observable`; `handle(.connected)` → `pushLocalSnapshot()` (the silent auto-push the allowlist must gate); auto-retry/backoff; `syncNow()`.

### Sync UI & status
- `MyHomeApp/Features/Settings/SettingsView.swift` — Settings › Sync entry; `-openSync` debug hook; neumorphic patterns to match for the pairing UI.
- `MyHomeApp/Sync/SyncStatusStore.swift` — status/connected-peer surface the paused/pairing state should extend.

### Snapshot (must NOT carry the allowlist)
- `MyHomeApp/Sync/SyncSnapshot.swift`, `SnapshotExporter.swift`, `SnapshotImporter.swift` — verify the allowlist is never serialized here.

### Related memory / prior art
- Sync scope + auto-sync-on-connect hazard: the seeded-simulator incident that motivated #43.
- The `75f7d00` partial mitigation already skips `syncCoordinator.start()` in `-seedSampleData` builds — this phase must not regress that, and should supersede it as the general fix.
</canonical_refs>

<specifics>
## Specific Ideas

- Code derivation sketch: `code = SHA256(min(idA,idB) + "|" + max(idA,idB))` → take 6 decimal digits from the leading bytes. Both phones compute identically without exchanging the code.
- Keep the `SyncTransport` protocol seam intact so the allowlist logic stays unit-testable with the existing `FakeSyncTransport`; the allowlist check itself should be a pure function over `(peerIID, allowlist)` that tests can drive directly.
- Preserve the existing dual-connect tie-break (`PeerInvitePolicy.shouldInvite`) — the allowlist gate is ADDITIONAL to it, not a replacement.
</specifics>

<deferred>
## Deferred Ideas

- **Shared-secret / anti-spoofing pairing** (defeating a determined attacker who sniffs the broadcast installID and impersonates it on your home LAN). The installID allowlist fully stops the accidental rogue (seeded sim / other install) — the actual incident — but not active spoofing. A shared symmetric key exchanged at pairing + challenge/response would close it. Out of scope for a two-phone household unless research surfaces a cheap win.
- **Pairing more than two devices / device management UI beyond a simple list + unpair.**
</deferred>

---

*Phase: 25-paired-device-sync-allowlist-v1-4-security-debt*
*Context captured: 2026-07-23 via direct decision capture*
