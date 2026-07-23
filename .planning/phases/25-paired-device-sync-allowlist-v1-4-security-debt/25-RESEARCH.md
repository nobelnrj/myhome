# Phase 25: Paired-Device Sync Allowlist - Research

**Researched:** 2026-07-24
**Domain:** MultipeerConnectivity peer-authorization, deterministic pairing-code derivation (CryptoKit), Swift 6 concurrency in the sync transport
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **Identity = `installID` (UUID)**, NOT the MCPeerID display name (display name derives from `UIDevice.current.name`, which the user can change). The existing persistent per-install ID at `UserDefaults.standard["sync.installID"]`.
- **The full `installID` must be exchanged over channels MC already provides:** advertise it in `MCNearbyServiceAdvertiser` `discoveryInfo` (e.g. `["iid": installID]`) so the browser can gate BEFORE inviting; and send it as the invitation `context` so the advertiser can gate BEFORE accepting. Today both are `nil`.
- **Allowlist store = new local, never-synced `PairedDevicesStore`:** a Codable set of `{installID, friendlyName, pairedAt}` in UserDefaults. Sync settings are per-device and MUST NOT appear in any exported/synced `SyncSnapshot`.
- **Pairing ceremony = code-confirmed:** both phones enter an explicit pairing window and display the SAME 6-digit code derived **deterministically from both installIDs** (truncated hash of the two IDs sorted, so both compute identically with no extra exchange). Each user taps "Codes match" before trust is recorded on that device. Chosen over windowed trust-on-first-use because TOFU has a rogue-in-window hole.
- **Migration = guided one-time re-pair:** on upgrade from an unpaired build, sync is PAUSED with a clear "Pair your devices to resume sync" prompt. NO auto-adopt of the currently-connected peer.
- **Enforcement:** Normal mode — `foundPeer` invites ONLY if peer `iid` ∈ allowlist; `didReceiveInvitationFromPeer` accepts ONLY if invite `context` iid ∈ allowlist; every other peer silently ignored. Pairing mode — a time-boxed flag that relaxes the gate for the handshake, but trust is persisted ONLY after mutual code confirmation. Unpairing removes the installID and stops future connections.

### Claude's Discretion
- Exact 6-digit code derivation function (hash choice, truncation) — deterministic, order-independent, unit-testable pure function.
- Pairing-mode state machine shape and timeout; how discovery/invite is driven during pairing.
- Precise UI layout of the pairing sheet, code display, confirm buttons, paired-devices list, and migration/paused banner — follow existing neumorphic Sync-screen patterns.
- Where the "unpaired → paused" gate lives in `SyncCoordinator` / `SyncStatusStore`.

### Deferred Ideas (OUT OF SCOPE)
- **Shared-secret / anti-spoofing pairing** (defeating an attacker who sniffs the broadcast installID and impersonates it on the home LAN). The installID allowlist fully stops the *accidental* rogue (the actual incident) but not active spoofing. Note it, don't build it, unless a cheap win surfaces.
- **Pairing more than two devices / device-management UI beyond a simple list + unpair.**
- Changing the Phase 18 merge engine / LWW semantics, or widening/narrowing what data syncs.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SYNC-06 | Auto-sync only ever connects to / merges with the two paired household phones; any other peer advertising `myhome-sync` is ignored. Code-confirmed pairing ceremony, guided one-time re-pair migration, local-only allowlist, unpair. | Gate points identified in `MultipeerSyncTransport` (browse/accept); pure `PeerAllowlistPolicy` + `PairingCode` functions specified; pairing state machine + migration-pause design; `PairedDevicesStore` shape; test seam mapped to existing `FakeSyncTransport` + `SyncTransportTests` pure-policy pattern. |
</phase_requirements>

## Summary

This is a **security-hardening pass over the existing Phase 18–19 sync stack**, not a greenfield feature. The entire fix concentrates on four existing files plus a handful of new pure-value types. All the trust decisions live in one file — `MultipeerSyncTransport.swift` — which already isolates every MultipeerConnectivity (MC) touch behind the pure `SyncTransport` protocol. The repo's established discipline (pure, unit-tested policy types like `PeerInvitePolicy` in `SyncTransport.swift`; the MC-free `SyncCoordinator`; the `FakeSyncTransport` loopback seam) maps cleanly onto every locked decision.

Three trust gates must change from "accept everything" to "accept only allowlisted `iid`": the browser's `foundPeer` (before it invites), the advertiser's `didReceiveInvitationFromPeer` (before it accepts). Today both `discoveryInfo` and the invite `context` are `nil`; the fix populates them with the `installID` so each side can gate *before a session forms*. Because an empty allowlist then blocks every peer automatically, the "no paired device ⇒ nothing connects" success criterion falls out for free; the migration "pause" is a UX banner over that already-correct behavior.

The 6-digit code is a **pure CryptoKit SHA-256 derivation over the two sorted installIDs** — no key exchange, no network round-trip, both phones compute it identically. CryptoKit is already a proven dependency in this codebase (`Gmail/PKCE.swift`), so there is zero new dependency. The code's security value is *mutual-confirmation of intent*, not secrecy (both IDs are broadcast on the LAN) — which is exactly the accidental-rogue threat model the phase targets; active installID spoofing stays deferred.

**Primary recommendation:** Add two pure policy types to `SyncTransport.swift` (`PairingCode`, `PeerAllowlistPolicy`) and a `PairedDevicesStore` (UserDefaults-backed Codable). Wire `discoveryInfo`/`context` and gate the two MC callbacks in `MultipeerSyncTransport`. Drive pairing with a time-boxed flag on the transport that emits a *distinct* pairing-candidate event (not `.connected`) so `SyncCoordinator`'s auto-push can never fire at an untrusted peer. Surface pairing/paused state through `SyncStatusStore`/`SyncStatusView`. Keep all trust logic in pure functions unit-tested via the existing `SyncTransportTests` pattern; verify the MC wiring on-device.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Peer identity exchange (advertise/read `iid`) | Transport (`MultipeerSyncTransport`) | — | The ONLY MC-aware file; `discoveryInfo` + invite `context` are MC primitives. |
| Allowlist gate decision | Pure policy (`PeerAllowlistPolicy` in `SyncTransport.swift`) | Transport (calls it) | Antisymmetric to existing `PeerInvitePolicy`; must be unit-testable with no MC. |
| 6-digit code derivation | Pure policy (`PairingCode` in `SyncTransport.swift`) | Pairing UI (displays it) | Deterministic pure function — the discretion item explicitly wants this testable. |
| Allowlist persistence | `PairedDevicesStore` (UserDefaults) | Pairing UI, transport (reads set) | Local-only per-device state, sibling to `SyncStatusStore`'s `lastSyncedAt`. |
| Pairing-mode lifecycle / timeout | Transport flag + pairing UI/state | `SyncCoordinator` (stays clear of pairing) | The relax-the-gate flag must live where the gate lives (transport). |
| Auto-push suppression during pairing | Transport (distinct event) | `SyncCoordinator` (guard) | Prevents `handle(.connected) → pushLocalSnapshot()` at an untrusted peer. |
| Migration pause + re-pair banner | `SyncStatusStore` state + `SyncStatusView` | `MyHomeApp` (detection at launch) | Presentation of the already-correct "empty allowlist blocks all" behavior. |
| Own `installID` source of truth | New shared `InstallIdentity` (pure, UserDefaults) | Transport, pairing UI (both read it) | Currently `private` on the transport; pairing UI + code derivation need it. |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| MultipeerConnectivity | iOS 17 system framework | Peer discovery, invite, encrypted session | Already the sole transport; this phase only sets two currently-`nil` fields and gates two callbacks. `[VERIFIED: codebase]` |
| CryptoKit | iOS 13+ (system) | `SHA256` for deterministic code derivation | Already imported/used in `Gmail/PKCE.swift` + `PKCETests.swift` — proven available, no new dep. `[VERIFIED: codebase grep]` |
| Foundation (`UserDefaults`, `Codable`) | system | `PairedDevicesStore` persistence | Same mechanism `SyncStatusStore.lastSyncedAt` + `sync.installID` already use. `[VERIFIED: codebase]` |
| Swift Testing (`import Testing`) | Xcode 26.5 | Unit tests for pure policies + coordinator loopback | The repo's test framework (`@Test`, `@Suite(.serialized)`, `#expect`). `[VERIFIED: codebase]` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CryptoKit `SHA256` | `Hasher`/`hashValue` | `Hasher` is **per-process randomized** (seeded per launch) — NOT stable across the two devices or across relaunch. Would break the "both phones compute the identical code" requirement. Reject. `[VERIFIED: Swift stdlib docs]` |
| CryptoKit `SHA256` | Custom FNV/CRC | Reinventing a hash for no benefit; SHA-256 is already in-repo and collision-safe for a display code. Reject. |
| `installID` in `discoveryInfo` | A short random pairing token | Locked decision is `installID`; discoveryInfo has room (see limits below). |

**Installation:** No packages. `import CryptoKit` in the pure policy file; MultipeerConnectivity already imported in the transport.

**Version verification:** No third-party packages to verify — all system frameworks. iOS 17+ deployment target confirmed from CONTEXT/stack. CryptoKit availability confirmed by existing `Gmail/PKCE.swift` usage. `[VERIFIED: codebase grep]`

## Package Legitimacy Audit

**N/A — this phase installs zero external packages.** All dependencies are Apple system frameworks (MultipeerConnectivity, CryptoKit, Foundation, SwiftUI, Swift Testing) already linked by the app. No npm/PyPI/crates surface, no slopcheck run required.

## MultipeerConnectivity Mechanics (the load-bearing research)

### How to read a peer's `discoveryInfo` (browse-side gate)

`MCNearbyServiceBrowser`'s delegate already receives it:

```swift
// EXISTING signature in MultipeerSyncTransport.swift line 254
nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                         foundPeer peerID: MCPeerID,
                         withDiscoveryInfo info: [String: String]?) { ... }
```

- `info` is exactly the dictionary the *advertiser* passed to `MCNearbyServiceAdvertiser(peer:discoveryInfo:serviceType:)`. Today that init is called with `discoveryInfo: nil` (line 99–103), so `info` arrives `nil`. Set it to `["iid": installID]` in `start()` and the browser reads `info?["iid"]`. `[VERIFIED: codebase + Apple API]`
- **Delivery reliability:** `discoveryInfo` is advertised via a Bonjour **TXT record** and is delivered *with* `foundPeer` — it is the mechanism's purpose, not a best-effort side channel. There is no "sometimes the info is missing" case for a value the advertiser set; the only nil case is an advertiser that set nil (i.e., an old, un-updated build). Treat missing/`nil`/absent `iid` as **untrusted → do not invite**. `[CITED: Apple MultipeerConnectivity / RFC 6763 TXT records]`

### How to pass + read the invitation `context` (accept-side gate)

- **Send side (browser, when it decides to invite):** `invitePeer(peerBox.value, to: session, withContext: <installID as Data>, timeout: 15)` — today `withContext: nil` (line 272–277).
- **Receive side (advertiser):** the delegate already carries it:

```swift
// EXISTING signature line 223
nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                            didReceiveInvitationFromPeer peerID: MCPeerID,
                            withContext context: Data?,
                            invitationHandler: @escaping (Bool, MCSession?) -> Void) { ... }
```

Decode `context` (e.g. `String(data:encoding:.utf8)`) → gate on allowlist → call `invitationHandler(trusted, session)`. Decode **defensively**: `context` may be `nil` (old build), non-UTF8, or a non-UUID string → treat as untrusted, `invitationHandler(false, nil)`. Never force-unwrap. `[VERIFIED: codebase + Apple API]`

### Size budgets (both trivially satisfied by a 36-char UUID)

| Channel | Practical limit | Our payload |
|---------|-----------------|-------------|
| `discoveryInfo` (whole dict) | **~400 bytes** total to fit one BLE packet; each key=value ≤255 bytes UTF-8 | `iid=<36 chars>` ≈ 40 bytes; optional `name=<deviceName>` still well under budget |
| invite `context` (`Data`) | **~400 bytes** (small BLE payload) | UUID string = 36 bytes |

`[MEDIUM: multiple community sources + openradar rdar://15116709 — "if discoveryInfo is too large nothing works and no warnings"]`. **Pitfall:** an oversized `discoveryInfo` silently breaks discovery with no error. Keep it to `iid` (+ optionally a short `name`); do NOT stuff a full snapshot or long device string in there.

### Timing / ordering — can `context` be trusted before the encrypted session forms?

Order of events for a connection:
1. Advertiser broadcasts `discoveryInfo` (TXT).
2. Browser `foundPeer(withDiscoveryInfo:)` — **gate #1 here, pre-invite.** No session yet.
3. Browser `invitePeer(withContext:)`.
4. Advertiser `didReceiveInvitationFromPeer(withContext:)` — **gate #2 here, pre-accept.** No session yet.
5. Advertiser calls `invitationHandler(true, session)` → handshake begins.
6. `session(didReceiveCertificate:)` fires on both sides during the TLS-style handshake.
7. `session(peer:didChange: .connected)` → the link is live → `SyncCoordinator` pushes.

Both gates (#2, #4) execute **before** the encrypted session exists. That is the whole point of using `discoveryInfo`/`context`: you decide whether to form a session at all, so an un-allowlisted peer never reaches step 5. `[VERIFIED: MC callback ordering, codebase]`

**Trust caveat (drives the deferred item):** `discoveryInfo` and `context` are sent *before* encryption and are **not authenticated** — anyone on the LAN can read the broadcast `installID` and could replay it in their own `context`. So the allowlist stops any peer that doesn't *know* an allowlisted `iid` (every accidental rogue: a seeded sim, a neighbor's install — each has its own random UUID), but not an attacker who sniffs and spoofs a known `iid`. This is precisely the CONTEXT threat boundary. No cheap authenticated-channel win exists here without the deferred shared secret.

### `.required` encryption + `didReceiveCertificate` interaction

- The session is built with `encryptionPreference: .required` (line 94) — the link refuses to form unencrypted. Good, keep it.
- `didReceiveCertificate` (line 208) currently accepts all. The presented certificate is a **per-session self-signed peer cert; it is NOT bound to the `installID`.** Gating there adds *no* installID assurance — it cannot distinguish a trusted peer from a spoofer. **Recommendation: leave `didReceiveCertificate` accepting.** The real identity gate is at steps #2/#4. Document this so a reviewer doesn't "harden" the cert callback under the false belief it authenticates identity. `[VERIFIED: MC security model]`

## Deterministic 6-Digit Pairing Code

### Recommended pure function (add to `SyncTransport.swift`, sibling of `PeerInvitePolicy`)

```swift
import CryptoKit

/// Deterministic, order-independent 6-digit confirmation code from two installIDs.
/// Both phones compute the identical value with NO extra exchange (both IDs are
/// already known: one from discoveryInfo, one local). Pure + unit-testable.
public enum PairingCode {
    public static func sixDigit(_ idA: String, _ idB: String) -> String {
        let lo = min(idA, idB)          // order-independence: sort the two IDs
        let hi = max(idA, idB)
        let input = Data("\(lo)|\(hi)".utf8)
        let digest = SHA256.hash(data: input)          // stable across devices/relaunch
        let b = Array(digest)                           // 32 bytes
        let n = (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16)
              | (UInt32(b[2]) << 8)  |  UInt32(b[3])
        return String(format: "%06u", n % 1_000_000)    // always 6 digits, zero-padded
    }
}
```

- **Order-independent:** `min`/`max` on the two ID strings means `sixDigit(a,b) == sixDigit(b,a)`. `[VERIFIED: reasoning]`
- **Cross-device stable:** SHA-256 is deterministic. Do **NOT** use Swift's `Hasher`/`hashValue` — it is seeded with a per-process random value and differs per launch and per device. `[VERIFIED: Swift stdlib — Hasher is randomly seeded]`
- **Zero-padding:** `%06u` guarantees a fixed 6-glyph display (e.g. `004217`), which matters for a "do these match?" visual compare.

### Entropy / collision considerations (2-device setting)

- 6 digits = 10⁶ ≈ 20 bits. This is **not** a brute-force secret — it never defends against guessing (an active attacker who knows both IDs computes the exact code anyway; that's the deferred threat). Its job is: when three devices are in pairing mode at once, phone A talking to rogue-C shows `code(A,C)` while real phone B shows `code(A,B)` — these differ with probability ≈ `1 − 10⁻⁶`, so the humans see mismatched numbers and decline. **Accidental collision** (a rogue's code coincidentally equals the intended one) is ~1-in-a-million — acceptable for a two-phone household, and even then the *device name* shown alongside would look wrong. `[VERIFIED: reasoning; matches CONTEXT threat scope]`
- Recommend displaying the code **grouped** (`042 178`) and next to the peer's `friendlyName`, so the human has two independent signals.

## `installID` — make it a shared source of truth

Today `installID` is `private var` on `MultipeerSyncTransport` (lines 47–57), reading `UserDefaults.standard["sync.installID"]`. The pairing UI and `PairingCode` both need *this device's own* `installID`, and tests need to inject one.

**Recommendation:** extract a tiny pure type reused by the transport, keeping the **exact same UserDefaults key** so the existing per-install ID survives the upgrade (migration correctness depends on stable IDs — a new key would orphan the two already-paired-in-practice phones):

```swift
public enum InstallIdentity {
    static let key = "sync.installID"   // UNCHANGED — do not rotate on upgrade
    public static func current(_ defaults: UserDefaults = .standard) -> String {
        if let e = defaults.string(forKey: key) { return e }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: key)
        return fresh
    }
}
```

`[VERIFIED: codebase — key must stay "sync.installID"]`

## PairedDevicesStore (local-only allowlist)

### Persistence shape

```swift
public struct PairedDevice: Codable, Equatable, Sendable {
    public var installID: String
    public var friendlyName: String
    public var pairedAt: Date
}

@MainActor @Observable
final class PairedDevicesStore {
    private static let key = "sync.pairedDevices"        // UserDefaults.standard
    private(set) var devices: [PairedDevice] = []        // decode on init
    func isPaired(_ iid: String) -> Bool { devices.contains { $0.installID == iid } }
    func add(_ d: PairedDevice) { /* upsert by installID, persist */ }
    func remove(installID: String) { /* filter, persist */ }
    var allowlist: Set<String> { Set(devices.map(\.installID)) }
}
```

- Mirror `SyncStatusStore`: `@MainActor @Observable`, `UserDefaults.standard`, JSON-encode the array under one key. `[VERIFIED: codebase pattern]`
- Expose an `allowlist: Set<String>` so the transport gate and `PeerAllowlistPolicy` take a plain `Set` (pure, injectable).

### The "never enters SyncSnapshot" guarantee

- `SyncSnapshot` (Codable in `SyncSnapshot.swift`) has a **fixed, explicit field list** — one array per SwiftData `@Model` DTO, plus `deletions`. `PairedDevice` is **not** a `@Model` and is **not** a field of `SyncSnapshot`, so it *structurally cannot* be serialized by `SnapshotCodec.encode`. `SnapshotExporter` only fetches SwiftData entities; it never reads UserDefaults. `[VERIFIED: SyncSnapshot.swift + SnapshotExporter.swift]`
- **Belt-and-suspenders test (SC-5):** build a snapshot on a store that has paired devices persisted, encode via `SnapshotCodec.encode`, assert the bytes contain neither any paired `installID` nor any `friendlyName` string (same technique the existing `expensesNeverCrossTheWire` test uses at `SyncCoordinatorTests.swift:428`).

## Enforcement — the gate (pure policy + two transport call sites)

### Pure policy (add to `SyncTransport.swift`)

```swift
public enum PeerAllowlistPolicy {
    /// Whether to form/accept a session with a peer of the given installID.
    /// Normal mode: only allowlisted peers. Pairing mode: any peer (handshake only —
    /// trust is persisted separately, after mutual code confirmation).
    public static func shouldConnect(peerIID: String?,
                                     allowlist: Set<String>,
                                     pairingMode: Bool) -> Bool {
        guard let peerIID, !peerIID.isEmpty else { return false }  // missing iid = untrusted
        return pairingMode || allowlist.contains(peerIID)
    }
}
```

`[VERIFIED: reasoning; antisymmetric-policy precedent = PeerInvitePolicy]`

### Wiring in `MultipeerSyncTransport`

1. `start()`: build advertiser with `discoveryInfo: ["iid": InstallIdentity.current()]` (+ optional `"name"`).
2. `browser(foundPeer:withDiscoveryInfo:)`: after the existing `shouldInvite` tie-break, **also** require `PeerAllowlistPolicy.shouldConnect(peerIID: info?["iid"], allowlist:, pairingMode:)`. Only then `invitePeer(..., withContext: <installID Data>, ...)`. The allowlist gate is **ADDITIONAL to** `shouldInvite`, not a replacement (locked decision).
3. `advertiser(didReceiveInvitationFromPeer:withContext:)`: decode `context` → `PeerAllowlistPolicy.shouldConnect(...)` → `invitationHandler(passed, passed ? session : nil)`.
4. The transport holds two injected/settable inputs: the current `allowlist: Set<String>` (from `PairedDevicesStore`) and a `pairingMode: Bool` flag. Because MC callbacks are `nonisolated` and hop to `@MainActor`, read these on the MainActor hop (they already do for `session`/`myDisplayName`).

## Pairing-Mode State Machine

### Shape

- A **time-boxed flag** (recommend 2 minutes) settable on the transport: `beginPairing()` / `endPairing()`. While set, `pairingMode == true` relaxes the gate.
- **Critical: do NOT let a pairing handshake trigger the auto-push.** `SyncCoordinator.handle(.connected) → pushLocalSnapshot()` would ship this phone's Kitchen to the as-yet-untrusted candidate — the exact hole we're closing, re-opened during the window.
  - **Recommended design (clean separation):** in pairing mode the transport, on reaching a live session with an *un-allowlisted* candidate, emits a **new** event `SyncTransportEvent.pairingCandidate(peerName: String, peerIID: String)` **instead of** `.connected`. `SyncCoordinator` ignores it (no push). The pairing UI receives the candidate, computes `PairingCode.sixDigit(ownIID, peerIID)`, displays it. On the user's "Codes match" tap → `PairedDevicesStore.add(...)` → `endPairing()`. The normal reconnect loop then brings up a genuine, trusted `.connected` and the usual push runs — now safely, to a trusted peer.
  - **Alternative (defense-in-depth):** thread `peerIID` onto `.connected` and guard `pushLocalSnapshot` on `allowlist.contains(connectedPeerIID)`. More invasive to the coordinator; the distinct-event approach keeps the coordinator's contract unchanged. Prefer the distinct event; the guard can be added as a second layer if desired.
- **Timeout:** a `Task.sleep`-based cancel (same idiom as `SyncCoordinator.scheduleRetry`) that flips `pairingMode` off and tears down any candidate session if no confirmation arrives.

### Composition with existing machinery

- **`PeerInvitePolicy.shouldInvite` tie-break is preserved** — still decides which side sends the invite so exactly one session forms (no dual-connect race). The allowlist gate runs *in addition*, after the tie-break passes.
- **`SyncCoordinator` auto-retry/backoff** is untouched; it keeps calling `transport.stop()/start()`. Pairing mode is orthogonal transport state.
- During pairing, only **one** candidate should be driven to the code step at a time (the `shouldInvite` tie-break already yields a single inviter per pair; if multiple candidates appear, surface them one at a time or show the first — a two-phone household rarely hits this).

## Migration — unpaired-build upgrade

### The gate is automatic; the banner explains it

Once the allowlist gate ships, an **empty allowlist blocks every peer** — so a freshly-upgraded phone with no paired devices simply won't sync. That already satisfies "sync is paused." The remaining work is **detecting the upgrade case to show the right copy** and not silently look broken.

- **Detection at launch (`MyHomeApp.onAppear`):** if `PairedDevicesStore` is empty AND `SyncStatusStore.lastSyncedAt != nil` (this phone *has* synced before, under the trust-any regime) → set a "needs re-pair" state. A fresh install (empty allowlist, `lastSyncedAt == nil`) shows the ordinary "pair your devices" bootstrap copy instead. Persist a one-shot `sync.pairingMigrationShown` flag so the banner is informative, not nagging.
- **No auto-adopt:** never seed the allowlist from the currently-connected peer — that's the seeded-sim hole at the migration moment (locked decision). The user must run the code-confirmed ceremony once.

### Where the paused gate/state lives

- Add a state to the presentation layer, e.g. `PeerSyncStatus` gains no new case *required* (empty allowlist naturally sits at `.idle`/`.connecting` and never connects), but for clear UX add a boolean on `SyncStatusStore` such as `needsPairing` / `isPaused`, surfaced by `SyncStatusPresentation` into a banner string + CTA in `SyncStatusView` (and optionally a row badge in `SettingsView`'s Sync entry). Keep `SyncStatusPresentation` pure (it already is — a testable mapper) so the banner copy is unit-tested without a view. `[VERIFIED: SyncStatusView.swift / SyncStatusPresentation]`

## Recommended Project Structure (delta only)

```
MyHomeApp/Sync/
├── SyncTransport.swift          # ADD: PairingCode, PeerAllowlistPolicy, InstallIdentity (pure)
│                                #      + SyncTransportEvent.pairingCandidate(peerName:peerIID:)
├── MultipeerSyncTransport.swift # EDIT: discoveryInfo=["iid":…], gate foundPeer + didReceiveInvitation,
│                                #       pass invite context, pairingMode flag + begin/endPairing
├── PairedDevicesStore.swift     # NEW: @Observable UserDefaults allowlist (local-only)
├── SyncCoordinator.swift        # (ideally untouched; ignores .pairingCandidate)
└── SyncStatusStore.swift        # EDIT: needsPairing/isPaused surface

MyHomeApp/Features/Settings/
├── SyncStatusView.swift         # EDIT: paused/re-pair banner + "Pair New Device" entry
├── PairDeviceView.swift         # NEW: pairing sheet — code display, "Codes match" confirm,
│                                #      paired-devices list + unpair (neumorphic patterns)
└── SettingsView.swift           # EDIT (optional): badge the Sync row when needsPairing

MyHomeTests/
├── SyncTransportTests.swift     # ADD: PairingCode determinism/order-independence,
│                                #      PeerAllowlistPolicy gating, InstallIdentity
├── PairedDevicesStoreTests.swift# NEW: round-trip, add/remove, allowlist set
└── SyncCoordinatorTests.swift   # ADD: .pairingCandidate → no push; empty allowlist → paused
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cross-device stable hash for the code | Custom hash / `hashValue` | `CryptoKit.SHA256` | `Hasher` is per-process randomized → different code each launch/device. SHA-256 is deterministic + already in-repo. |
| Peer identity channel | A bespoke pre-session message protocol | MC `discoveryInfo` + invite `context` | They exist precisely to carry pre-session metadata and gate before a session forms. |
| Dual-connect avoidance | New tie-break | Existing `PeerInvitePolicy.shouldInvite` | Already solved and unit-tested; allowlist is additive. |
| Snapshot exclusion of the allowlist | Manual field-stripping | Nothing — it's not a `@Model`/snapshot field | Structurally cannot be serialized; just assert it in a test. |
| Loopback test harness | New two-device test rig | Existing `FakeSyncTransport.linkedPair()` | Already proves change-propagation, echo-suppression, LWW without devices. |

**Key insight:** every trust decision reduces to a **pure function over `(peerIID, allowlist, pairingMode)`** plus a **pure code derivation** — both testable with zero MC. The MC file only *wires* those functions to two callbacks and two currently-`nil` fields.

## Runtime State Inventory

> Included because the phase persists new local state and has a migration step.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `sync.installID` (UserDefaults.standard, per-install UUID) already exists and is **stable across upgrade** — the allowlist keys on it. New: `sync.pairedDevices` (Codable allowlist). `sync.lastSyncedAt` (existing) used to detect "synced before" for migration. | Reuse `sync.installID` key unchanged; add `sync.pairedDevices`; read `sync.lastSyncedAt` for migration detection. |
| Live service config | The two real phones are currently paired *by behavior only* (trust-any) — there is NO stored allowlist on either device yet. After upgrade both have an EMPTY allowlist → both must run the ceremony once. There is nothing to export/migrate from a service. | Guided one-time re-pair (no auto-adopt). |
| OS-registered state | None — MC advertises/browses live; nothing registered with the OS persists a peer. Bonjour service `myhome-sync` is ephemeral. | None. |
| Secrets/env vars | None. `installID` is a non-secret random UUID (broadcast on the LAN by design). No key material, no entitlement change (free-provisioning intact; MC + Local Network already configured). | None — verified no new entitlement needed. |
| Build artifacts | None. Pure Swift additions; the existing `-seedSampleData` sync-skip guard (`MyHomeApp.swift:74–81`) stays and is **superseded in spirit**: once the allowlist ships, a seeded sim has its own random `installID` ∉ allowlist and can't connect regardless — but keep the DEBUG skip as a second layer (do not regress it). | Keep the `-seedSampleData` skip; note allowlist now provides the general fix. |

**Nothing found in OS-registered / secrets / build-artifact categories** — verified by grep over `MyHomeApp/` and the entitlements-free MC setup.

## Common Pitfalls

### Pitfall 1: Auto-push to an untrusted peer during the pairing window
**What goes wrong:** relaxing the gate for pairing lets a session form; `SyncCoordinator.handle(.connected)` immediately calls `pushLocalSnapshot()`, shipping Kitchen data to a not-yet-confirmed (possibly rogue) candidate.
**Why it happens:** the coordinator treats any `.connected` as trusted.
**How to avoid:** emit `.pairingCandidate` (not `.connected`) for un-allowlisted candidates; only after "Codes match" + `endPairing()` does a real trusted `.connected` fire. (Optional second layer: guard `pushLocalSnapshot` on `allowlist.contains(peerIID)`.)
**Warning signs:** a test where a candidate connects in pairing mode and `sentEnvelopes` contains a `.snapshot`.

### Pitfall 2: Oversized `discoveryInfo` silently kills discovery
**What goes wrong:** stuffing extra fields into `discoveryInfo` pushes it past the BLE packet budget; discovery stops with **no error** (openradar rdar://15116709).
**How to avoid:** keep it to `["iid": …]` (+ short `name`); stay well under ~400 bytes total / 255 bytes per pair.
**Warning signs:** peers stop being found after adding a field to `discoveryInfo`.

### Pitfall 3: Using `Hasher`/`hashValue` for the code
**What goes wrong:** the two phones show different 6-digit codes and can never confirm.
**Why:** `Hasher` is seeded with a per-process random value.
**How to avoid:** `CryptoKit.SHA256` over the sorted IDs. Unit-test a fixed input → fixed output vector.

### Pitfall 4: Rotating / regenerating `installID`
**What goes wrong:** changing the UserDefaults key or clearing it on upgrade orphans the two devices — every future pairing breaks and the allowlist keys on a value that changed.
**How to avoid:** reuse `sync.installID` verbatim; never regenerate on upgrade.

### Pitfall 5: Trusting the certificate callback as identity
**What goes wrong:** a reviewer "hardens" `didReceiveCertificate` believing it authenticates the peer; it doesn't (per-session self-signed cert, unbound to `installID`).
**How to avoid:** gate at `foundPeer`/`didReceiveInvitation`; document that the cert callback is not an identity gate.

### Pitfall 6: Forgetting the `pbxproj` file refs for new Swift files
**What goes wrong (repo-specific):** `PairedDevicesStore.swift`, `PairDeviceView.swift`, `PairedDevicesStoreTests.swift` won't compile — the project has **no synchronized groups**; each new file needs 4 manual `project.pbxproj` edits (see MEMORY: "Xcode explicit file refs"). Surfaces only at the post-merge build gate.
**How to avoid:** add explicit pbxproj file refs for every new `.swift` in the same task that creates it.

## Code Examples

### Gate the browser (foundPeer) — additive to the existing tie-break
```swift
// In MultipeerSyncTransport.browser(_:foundPeer:withDiscoveryInfo:), inside the @MainActor hop:
guard let session = self.session else { return }
let peerIID = info?["iid"]                                   // NEW
guard PeerAllowlistPolicy.shouldConnect(peerIID: peerIID,   // NEW additive gate
                                        allowlist: self.allowlist,
                                        pairingMode: self.pairingMode) else { return }
if PeerInvitePolicy.shouldInvite(localDisplayName: self.myDisplayName,
                                 remoteDisplayName: remoteName) {
    browserBox.value.invitePeer(peerBox.value, to: session,
                                withContext: Data(InstallIdentity.current().utf8), // NEW
                                timeout: 15)
}
```

### Gate the advertiser (accept) — defensive context decode
```swift
// In advertiser(_:didReceiveInvitationFromPeer:withContext:), on the @MainActor hop:
let peerIID = context.flatMap { String(data: $0, encoding: .utf8) }   // may be nil
let ok = PeerAllowlistPolicy.shouldConnect(peerIID: peerIID,
                                           allowlist: self.allowlist,
                                           pairingMode: self.pairingMode)
box.value(ok, ok ? self.session : nil)   // reject → (false, nil), no session forms
```

### Pure code-derivation test (fits SyncTransportTests.swift pattern)
```swift
@Test func pairingCodeIsOrderIndependentAndDeterministic() {
    let a = "11111111-1111-1111-1111-111111111111"
    let b = "22222222-2222-2222-2222-222222222222"
    #expect(PairingCode.sixDigit(a, b) == PairingCode.sixDigit(b, a))   // order-independent
    #expect(PairingCode.sixDigit(a, b).count == 6)                       // always 6 glyphs
    #expect(PairingCode.sixDigit(a, b).allSatisfy(\.isNumber))
}
```

## State of the Art

| Old Approach (current code) | Current Approach (this phase) | Impact |
|-----------------------------|-------------------------------|--------|
| Trust any peer: `discoveryInfo: nil`, invite any, accept any invite/cert | Gate on `installID` via `discoveryInfo`/`context` before session forms | Accidental rogue (seeded sim / other install) can never merge |
| Pairing = implicit (first peer on `myhome-sync`) | Explicit code-confirmed ceremony | Closes the trust-on-first-use rogue-in-window hole |
| `-seedSampleData` sync-skip is the only guard (partial, `75f7d00`) | Allowlist is the general fix; DEBUG skip kept as a second layer | Robust beyond dev builds |

**Deprecated/outdated:** nothing removed; `didReceiveCertificate` stays accept-all *by design* (documented as non-identity).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `discoveryInfo` / invite `context` budget ≈ 400 bytes (BLE-packet-bound) | MC Mechanics | LOW — our payload (~40 bytes) is an order of magnitude under any plausible limit; even a 255-byte-per-pair cap is satisfied. Sourced from multiple community reports + openradar, not a single Apple doc line. |
| A2 | `discoveryInfo` is always delivered with `foundPeer` when the advertiser set it | MC Mechanics | LOW — this is the documented mechanism; if a peer sends nil we already treat it as untrusted, which is the safe failure. |
| A3 | 2-minute pairing timeout | Pairing state machine | LOW — pure UX tuning; adjust freely, no correctness impact. |

**No `[ASSUMED]` package or compliance claims** — all dependencies are system frameworks verified present in the codebase.

## Open Questions

1. **Friendly name source for the paired list.**
   - What we know: `UIDevice.current.name` on iOS 16+ returns a generic "iPhone" without the (unavailable on free-provisioning) device-name entitlement; the existing `PeerInvitePolicy.displayName` already sanitizes whatever it returns.
   - What's unclear: whether both phones will show a distinguishable friendly name or two "iPhone" entries.
   - Recommendation: put a short `"name"` in `discoveryInfo` alongside `iid`, fall back to the `#installIDprefix` suffix (already in the display name) so the list is never ambiguous. Not a blocker.

2. **Multiple simultaneous pairing candidates.**
   - What we know: the `shouldInvite` tie-break yields one inviter per pair; a two-phone household rarely has ≥3 devices in pairing mode.
   - Recommendation: surface the first candidate; if a second appears, the mismatched code already protects the user. Don't build multi-candidate UI (deferred: >2 devices).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| MultipeerConnectivity | transport gating | ✓ (already linked) | iOS 17 SDK | — |
| CryptoKit | `PairingCode` SHA-256 | ✓ (used in `Gmail/PKCE.swift`) | iOS 13+ | — |
| Local Network permission | MC discovery | ✓ (already configured/handled) | — | existing error-path copy |
| Xcode / iPhone 17 sim | build + on-device MC-wiring verification | ✓ | Xcode 26.5, iPhone 17 (per MEMORY) | — |

**Missing dependencies:** none. No new entitlement, no paid capability — free-provisioning intact.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (`import Testing`, `@Test`, `#expect`, `@Suite(.serialized)`) |
| Config file | none — Xcode test target `MyHomeTests` |
| Quick run command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/SyncTransportTests` |
| Full suite command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |

### Success Criteria → Test Map
| SC | Behavior | Test Type | Automated Command | File Exists? |
|----|----------|-----------|-------------------|-------------|
| SC-1 | Empty allowlist ⇒ transport neither invites nor accepts (unpaired peer never forms a session) | unit (pure) | `PeerAllowlistPolicy.shouldConnect(peerIID:"x", allowlist:[], pairingMode:false) == false`; and coordinator test: candidate in normal mode → no `.connected`, no `.snapshot` in `sentEnvelopes` | ❌ Wave 0 (add to `SyncTransportTests` + `SyncCoordinatorTests`) |
| SC-2 | Code-confirmed pairing adds a peer on both phones; only mutually-confirmed peers trusted | unit (pure) + integration | `PairingCode` determinism/order-independence; `PairedDevicesStore.add` upsert; pairing-mode `.pairingCandidate` emitted, `add` on confirm | ❌ Wave 0 (`PairedDevicesStoreTests` NEW; `SyncTransportTests`) |
| SC-3 | After pairing, auto-sync connects + merges as before (no LWW/engine regression) | integration (loopback) | existing `SyncCoordinatorTests` change-propagation/LWW tests still green with allowlisted peers | ✅ (existing suite must stay green) |
| SC-4 | Upgrade from unpaired build ⇒ sync paused + re-pair prompt; resumes only after pairing | unit (pure mapper) | `SyncStatusPresentation` banner copy when `needsPairing`; migration-detection given (empty allowlist ∧ lastSyncedAt≠nil) | ❌ Wave 0 (extend `SyncStatusPresentationTests`) |
| SC-5 | Allowlist never appears in any exported/synced snapshot | unit | build snapshot with paired devices present → `SnapshotCodec.encode` bytes contain no installID/friendlyName (mirror `expensesNeverCrossTheWire`) | ❌ Wave 0 (add to `SyncCoordinatorTests` or a snapshot test) |
| SC-6 | Unpairing removes the installID + stops future connections | unit (pure) | `PairedDevicesStore.remove` → `isPaired == false`; `PeerAllowlistPolicy.shouldConnect` false for the removed id | ❌ Wave 0 (`PairedDevicesStoreTests`) |

### Sampling Rate
- **Per task commit:** `-only-testing:MyHomeTests/SyncTransportTests` (pure policies, <30s)
- **Per wave merge:** full `MyHomeTests` suite (proves no Phase 18/19 sync regression — SC-3)
- **Phase gate:** full suite green + on-device 3-device manual check (real phone + real phone + seeded sim on LAN: sim never connects; two phones pair via matching code) before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `MyHomeTests/PairedDevicesStoreTests.swift` — round-trip, add/upsert, remove, `allowlist` set (SC-2, SC-6)
- [ ] `MyHomeTests/SyncTransportTests.swift` additions — `PairingCode` (determinism, order-independence, 6-digit), `PeerAllowlistPolicy.shouldConnect` matrix (empty/trusted/pairing), `InstallIdentity` (SC-1, SC-2)
- [ ] `MyHomeTests/SyncCoordinatorTests.swift` additions — `.pairingCandidate` ⇒ no push; snapshot-excludes-allowlist (SC-1, SC-5)
- [ ] `MyHomeTests/SyncStatusPresentationTests.swift` additions — paused/needs-pairing banner copy (SC-4)
- [ ] `FakeSyncTransport` extension — add `simulatePairingCandidate(peerName:peerIID:)` so coordinator no-push is drivable (the MC discoveryInfo/context *wiring* itself stays on-device manual — the fake covers the coordinator contract, not MC internals)
- [ ] pbxproj file refs for every new `.swift` (repo footgun — see Pitfall 6)

*Note: the raw MC callback wiring (reading `discoveryInfo`, passing `context`, calling the pure gate) is integration code inside `MultipeerSyncTransport` and is NOT reachable through `FakeSyncTransport`. Keep the decision logic in the pure `PeerAllowlistPolicy`/`PairingCode` (fully unit-tested) and verify the wiring on-device (3-device scenario above).*

## Security Domain

### Applicable ASVS Categories (Level 1)
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V1 Architecture | yes | Trust boundary is the two MC gate callbacks; identity = `installID`; documented that cert callback is not an identity gate |
| V2 Authentication | partial | Peer "authentication" = allowlist membership + human code-confirm. Explicitly NOT resistant to active installID spoofing (deferred shared-secret) |
| V4 Access Control | yes | Un-allowlisted peer denied session formation (default-deny; empty allowlist blocks all) |
| V5 Input Validation | yes | `discoveryInfo["iid"]` and invite `context` are UNTRUSTED LAN input — decode defensively, never force-unwrap, missing/malformed ⇒ deny (no crash) |
| V6 Cryptography | yes | `CryptoKit.SHA256` for the code (used for deterministic derivation/confirmation, NOT for secrecy). No hand-rolled crypto |

### Known Threat Patterns
| Pattern | STRIDE | Standard Mitigation | Status |
|---------|--------|---------------------|--------|
| Accidental rogue peer (seeded sim / other install) merges data | Spoofing / Tampering | installID allowlist + code-confirmed pairing (rogue has its own random UUID ∉ allowlist; its code won't match) | **Fixed by this phase** |
| Malformed/oversized `discoveryInfo` or `context` crashes or breaks discovery | Denial of Service / Tampering | Defensive decode (deny on nil/non-UTF8/non-UUID); keep `discoveryInfo` tiny | **Fixed** |
| Auto-push leaks Kitchen to untrusted candidate during pairing | Information Disclosure | `.pairingCandidate` event (no push) until trust persisted | **Fixed** |
| Active attacker sniffs broadcast installID and spoofs it in `context` | Spoofing | Shared-secret + challenge/response at pairing | **DEFERRED** (out of scope per CONTEXT; no cheap authenticated-channel win found — pre-session `discoveryInfo`/`context` are unauthenticated by design) |

`security_block_on: high` — no HIGH-severity finding is introduced by this phase; the one residual (active spoofing) is a pre-existing, explicitly-accepted MEDIUM for a two-phone household.

## Sources

### Primary (HIGH confidence)
- Codebase — `MyHomeApp/Sync/{MultipeerSyncTransport,SyncTransport,SyncCoordinator,SyncStatusStore,SyncSnapshot,SnapshotExporter}.swift`, `MyHomeApp/MyHomeApp.swift`, `MyHomeApp/Features/Settings/{SyncStatusView,SettingsView}.swift`, `MyHomeTests/{SyncCoordinatorTests,SyncTransportTests}.swift` — exact trust points, seams, patterns.
- Codebase — `MyHomeApp/Gmail/PKCE.swift`, `MyHomeTests/PKCETests.swift` — CryptoKit availability precedent.
- `.planning/phases/25-…/25-CONTEXT.md`, `.planning/ROADMAP.md` — locked decisions.

### Secondary (MEDIUM confidence)
- Apple MultipeerConnectivity API surface (`MCNearbyServiceAdvertiser` init, `MCNearbyServiceBrowser.invitePeer(_:to:withContext:timeout:)`, delegate signatures) — [developer.apple.com/documentation/multipeerconnectivity](https://developer.apple.com/documentation/multipeerconnectivity/mcnearbyserviceadvertiser)
- `discoveryInfo` / `context` size limits (~400 bytes, 255-byte pairs, TXT/RFC 6763) — community + openradar [rdar://15116709](https://www.openradar.appspot.com/15116709), corroborated across multiple MC tutorials.
- Swift stdlib `Hasher` is per-process randomly seeded (why not to use it for the code) — Swift standard library documentation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all system frameworks, CryptoKit precedent in-repo.
- Architecture (gate points, pure-policy placement, pairing event): HIGH — read directly from the canonical files; mirrors existing `PeerInvitePolicy`/`FakeSyncTransport` patterns.
- MC size limits / delivery: MEDIUM — corroborated across sources but not a single authoritative Apple doc line; our payload is far under any cited bound, so risk is negligible.
- Pitfalls: HIGH — derived from the actual code paths (auto-push, `-seedSampleData` guard, pbxproj footgun from MEMORY).

**Research date:** 2026-07-24
**Valid until:** 2026-08-23 (stable — system frameworks + local codebase; re-verify only if the sync stack is refactored)

## RESEARCH COMPLETE

**Phase:** 25 - Paired-Device Sync Allowlist
**Confidence:** HIGH

### Key Findings
- All trust changes concentrate in `MultipeerSyncTransport.swift` (two gate callbacks + two currently-`nil` fields: `discoveryInfo` and invite `context`); both gates run **before** any session forms, so an un-allowlisted peer never reaches the encrypted link.
- Every trust decision reduces to a **pure, unit-testable function**: `PeerAllowlistPolicy.shouldConnect(peerIID:allowlist:pairingMode:)` and `PairingCode.sixDigit(_:_:)` (CryptoKit SHA-256 over sorted IDs — deterministic and cross-device stable; `Hasher` would NOT be). Both belong in `SyncTransport.swift` next to `PeerInvitePolicy`, tested via the existing `SyncTransportTests` pattern.
- The critical hidden hole: during the pairing window a relaxed gate lets a session form, and `SyncCoordinator.handle(.connected)` would auto-push Kitchen data to an untrusted candidate. Fix: emit a distinct `.pairingCandidate` event (not `.connected`) so no push fires until trust is persisted.
- Migration needs no explicit "pause switch" — an empty allowlist blocks all peers automatically; the work is detecting the upgrade case (empty allowlist ∧ `lastSyncedAt≠nil`) to show a re-pair banner, with NO auto-adopt.
- `PairedDevicesStore` (UserDefaults Codable) structurally cannot enter `SyncSnapshot` (not a `@Model`); assert it with a bytes-don't-contain test mirroring `expensesNeverCrossTheWire`. Reuse the existing `sync.installID` key unchanged (migration correctness). Remember the repo pbxproj file-ref footgun for every new `.swift`.

### File Created
`.planning/phases/25-paired-device-sync-allowlist-v1-4-security-debt/25-RESEARCH.md`

### Confidence Assessment
| Area | Level | Reason |
|------|-------|--------|
| Standard Stack | HIGH | System frameworks only; CryptoKit precedent in-repo |
| Architecture | HIGH | Read from canonical files; mirrors existing patterns |
| Pitfalls | HIGH | Derived from actual code paths + MEMORY footguns |
| MC size limits | MEDIUM | Multi-source, payload far under any bound |

### Open Questions
- Friendly-name source (device name may be generic "iPhone" on free-provisioning) — mitigate by adding a short `name` to `discoveryInfo`; not a blocker.
- Multiple simultaneous pairing candidates — mismatched code already protects; don't build multi-candidate UI (>2 devices deferred).

### Ready for Planning
Research complete. Planner can create PLAN.md files against the gate points, pure policies, pairing state machine, migration, store, and the 6-criteria validation map above.
