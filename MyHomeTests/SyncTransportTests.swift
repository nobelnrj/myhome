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
}
