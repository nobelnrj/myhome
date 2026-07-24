import Foundation
import Testing
@testable import MyHome

/// SYNC-04 — unit tests for the transport seam's pure logic: envelope wire format,
/// the invite tie-break, and MCPeerID display-name bounds. No MultipeerConnectivity
/// and no device required — real two-device discovery is a later human-verify concern.
@Suite struct SyncTransportTests {

    // MARK: - SyncEnvelope round-trip

    @Test func snapshotRequestRoundTrips() throws {
        let data = try SyncEnvelope.encode(.snapshotRequest)
        let decoded = try SyncEnvelope.decode(data)
        #expect(decoded == .snapshotRequest)
    }

    @Test func snapshotPayloadRoundTripsBytesExactly() throws {
        // Arbitrary non-trivial payload (stands in for SnapshotExporter bytes).
        let payload = Data((0..<512).map { UInt8($0 & 0xFF) })
        let data = try SyncEnvelope.encode(.snapshot(payload))
        let decoded = try SyncEnvelope.decode(data)
        #expect(decoded == .snapshot(payload))
        if case .snapshot(let out) = decoded {
            #expect(out == payload)
        } else {
            Issue.record("decoded envelope was not .snapshot")
        }
    }

    @Test func emptySnapshotPayloadRoundTrips() throws {
        let data = try SyncEnvelope.encode(.snapshot(Data()))
        let decoded = try SyncEnvelope.decode(data)
        #expect(decoded == .snapshot(Data()))
    }

    // MARK: - SyncEnvelope garbage rejection

    @Test func garbageBytesThrowNeverCrash() {
        let garbage = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0x42, 0x7B, 0x7D])
        #expect(throws: (any Error).self) {
            _ = try SyncEnvelope.decode(garbage)
        }
    }

    @Test func emptyDataThrows() {
        #expect(throws: (any Error).self) {
            _ = try SyncEnvelope.decode(Data())
        }
    }

    @Test func wrongShapeJSONThrows() {
        // Valid JSON, wrong shape (missing/unknown kind) → must throw, not default.
        let json = Data(#"{"kind":"bogus"}"#.utf8)
        #expect(throws: (any Error).self) {
            _ = try SyncEnvelope.decode(json)
        }
    }

    // MARK: - PeerInvitePolicy.shouldInvite antisymmetry

    @Test func shouldInviteIsAntisymmetricForDistinctNames() {
        let a = "Alpha#aaa111"
        let b = "Bravo#bbb222"
        let aInvitesB = PeerInvitePolicy.shouldInvite(localDisplayName: a, remoteDisplayName: b)
        let bInvitesA = PeerInvitePolicy.shouldInvite(localDisplayName: b, remoteDisplayName: a)
        // Exactly one side invites.
        #expect(aInvitesB != bInvitesA)
    }

    @Test func shouldInviteIsFalseBothWaysForEqualNames() {
        let name = "Same#abc123"
        #expect(PeerInvitePolicy.shouldInvite(localDisplayName: name, remoteDisplayName: name) == false)
    }

    @Test func shouldInviteFollowsStrictOrdering() {
        #expect(PeerInvitePolicy.shouldInvite(localDisplayName: "A", remoteDisplayName: "B") == true)
        #expect(PeerInvitePolicy.shouldInvite(localDisplayName: "B", remoteDisplayName: "A") == false)
    }

    // MARK: - PeerInvitePolicy.displayName bounds

    @Test func displayNameContainsSuffixAndIsBounded() {
        let name = PeerInvitePolicy.displayName(deviceName: "Reo's iPhone", installID: "ABCDEF0123456789")
        #expect(name.isEmpty == false)
        #expect(name.contains("#"))
        #expect(name.contains("ABCDEF")) // first 6 of install ID
        #expect(name.utf8.count <= 63)
    }

    @Test func displayNameSurvivesEmojiAndLongNames() {
        let crazy = String(repeating: "🏠家Home! ", count: 40) // long + emoji + CJK + punctuation
        let name = PeerInvitePolicy.displayName(deviceName: crazy, installID: "ZZZZ9999")
        #expect(name.isEmpty == false)
        #expect(name.utf8.count <= 63)
        #expect(name.contains("#"))
        // Emoji/punctuation must be sanitized out; only alphanumerics + spaces + '#' remain.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " #"))
        for scalar in name.unicodeScalars {
            #expect(allowed.contains(scalar), "unexpected scalar \(scalar) in \(name)")
        }
    }

    @Test func displayNameFallsBackWhenSanitationEmpties() {
        // A name consisting only of emoji/punctuation sanitizes to empty → fallback.
        let name = PeerInvitePolicy.displayName(deviceName: "🎉🎊✨!!!", installID: "FALLBK00")
        #expect(name.isEmpty == false)
        #expect(name.hasPrefix("MyHome#"))
        #expect(name.utf8.count <= 63)
    }

    @Test func displayNamesAreDistinctForSameDeviceDifferentInstall() {
        let a = PeerInvitePolicy.displayName(deviceName: "iPhone", installID: "111111aaa")
        let b = PeerInvitePolicy.displayName(deviceName: "iPhone", installID: "222222bbb")
        #expect(a != b)
    }

    // MARK: - serviceType constraints

    @Test func serviceTypeMeetsMCConstraints() {
        let s = PeerInvitePolicy.serviceType
        #expect(s.utf8.count <= 15)
        #expect(s.isEmpty == false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        for scalar in s.unicodeScalars {
            #expect(allowed.contains(scalar))
        }
    }

    // MARK: - PairingCode (SYNC-06)

    @Test func pairingCodeIsOrderIndependent() {
        let a = "11111111-1111-1111-1111-111111111111"
        let b = "22222222-2222-2222-2222-222222222222"
        // Both phones must derive the identical code regardless of which ID is "theirs".
        #expect(PairingCode.sixDigit(a, b) == PairingCode.sixDigit(b, a))
    }

    @Test func pairingCodeIsAlwaysSixDecimalDigits() {
        let a = "11111111-1111-1111-1111-111111111111"
        let b = "22222222-2222-2222-2222-222222222222"
        let code = PairingCode.sixDigit(a, b)
        #expect(code.count == 6)
        let allDigits = code.allSatisfy { $0.isNumber }
        #expect(allDigits)
    }

    @Test func pairingCodeMatchesGoldenVector() {
        // Locked constant computed once from the SHA-256 derivation (proves cross-run,
        // cross-device determinism — a per-process Hasher would NOT reproduce this).
        let a = "11111111-1111-1111-1111-111111111111"
        let b = "22222222-2222-2222-2222-222222222222"
        #expect(PairingCode.sixDigit(a, b) == "773804")
    }

    @Test func pairingCodeZeroPadsShortValues() {
        // Whatever the inputs, the display is always a fixed 6-glyph string.
        let code = PairingCode.sixDigit("a", "b")
        #expect(code.count == 6)
        let allDigits = code.allSatisfy { $0.isNumber }
        #expect(allDigits)
    }

    // MARK: - PeerAllowlistPolicy.shouldConnect (SYNC-06)

    @Test func shouldConnectDeniesNilPeerIID() {
        #expect(PeerAllowlistPolicy.shouldConnect(peerIID: nil, allowlist: ["x"], pairingMode: false) == false)
    }

    @Test func shouldConnectDeniesEmptyPeerIID() {
        #expect(PeerAllowlistPolicy.shouldConnect(peerIID: "", allowlist: ["x"], pairingMode: false) == false)
    }

    @Test func shouldConnectDeniesEmptyAllowlistInNormalMode() {
        #expect(PeerAllowlistPolicy.shouldConnect(peerIID: "x", allowlist: [], pairingMode: false) == false)
    }

    @Test func shouldConnectAllowsAllowlistedPeerInNormalMode() {
        #expect(PeerAllowlistPolicy.shouldConnect(peerIID: "x", allowlist: ["x"], pairingMode: false) == true)
    }

    @Test func shouldConnectDeniesNonMemberInNormalMode() {
        #expect(PeerAllowlistPolicy.shouldConnect(peerIID: "y", allowlist: ["x"], pairingMode: false) == false)
    }

    @Test func shouldConnectRelaxesGateInPairingMode() {
        // Pairing relaxes the gate so the handshake can proceed with an untrusted peer.
        #expect(PeerAllowlistPolicy.shouldConnect(peerIID: "x", allowlist: [], pairingMode: true) == true)
    }

    @Test func shouldConnectStillDeniesMissingIIDEvenInPairingMode() {
        // A peer that advertises NO id is untrusted regardless of pairing mode.
        #expect(PeerAllowlistPolicy.shouldConnect(peerIID: nil, allowlist: [], pairingMode: true) == false)
    }

    // MARK: - PeerAllowlistPolicy.decodeIID (SYNC-06 — untrusted invite-context decode, V5)

    @Test func decodeIIDReturnsNilForNilData() {
        // An old build sends no invite context ⇒ untrusted, never crash.
        #expect(PeerAllowlistPolicy.decodeIID(nil) == nil)
    }

    @Test func decodeIIDReturnsTheStringForAValidUUIDPayload() {
        let uuid = "11111111-2222-3333-4444-555555555555"
        #expect(PeerAllowlistPolicy.decodeIID(Data(uuid.utf8)) == uuid)
    }

    @Test func decodeIIDTrimsWhitespaceAndRejectsEmpty() {
        #expect(PeerAllowlistPolicy.decodeIID(Data("  padded-id  ".utf8)) == "padded-id")
        #expect(PeerAllowlistPolicy.decodeIID(Data("   ".utf8)) == nil)   // whitespace-only ⇒ nil
        #expect(PeerAllowlistPolicy.decodeIID(Data()) == nil)            // empty ⇒ nil
    }

    @Test func decodeIIDRejectsNonUTF8Garbage() {
        // Hostile invalid-UTF8 bytes must decode to nil, never crash.
        let garbage = Data([0xFF, 0xFE, 0xFD, 0xC0, 0x80])
        #expect(PeerAllowlistPolicy.decodeIID(garbage) == nil)
    }

    @Test func decodeIIDRejectsOversizedInput() {
        // > 64 bytes is not one of ours ⇒ untrusted (also mirrors tiny-discoveryInfo discipline).
        let oversized = Data(String(repeating: "A", count: 65).utf8)
        #expect(PeerAllowlistPolicy.decodeIID(oversized) == nil)
        // A 36-char UUID (well under the cap) still passes.
        let uuid = "abcdef01-2345-6789-abcd-ef0123456789"
        #expect(uuid.utf8.count == 36)
        #expect(PeerAllowlistPolicy.decodeIID(Data(uuid.utf8)) == uuid)
    }

    // MARK: - InstallIdentity (SYNC-06)

    @Test func installIdentityReturnsExistingValue() {
        let defaults = UserDefaults(suiteName: "InstallIdentityTests.existing")!
        defaults.removePersistentDomain(forName: "InstallIdentityTests.existing")
        defaults.set("preexisting-id", forKey: InstallIdentity.key)
        #expect(InstallIdentity.current(defaults) == "preexisting-id")
    }

    @Test func installIdentityMintsAndPersistsWhenAbsent() {
        let defaults = UserDefaults(suiteName: "InstallIdentityTests.mint")!
        defaults.removePersistentDomain(forName: "InstallIdentityTests.mint")
        let minted = InstallIdentity.current(defaults)
        #expect(minted.isEmpty == false)
        // Persisted: a second read returns the SAME value (does not re-mint).
        #expect(InstallIdentity.current(defaults) == minted)
        #expect(defaults.string(forKey: InstallIdentity.key) == minted)
    }
}
