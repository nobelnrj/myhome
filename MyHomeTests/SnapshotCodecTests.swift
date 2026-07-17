import Testing
import Foundation
@testable import MyHome

// Requirements: SYNC-02 — snapshot codec byte-fidelity, version refusal, Decimal-as-string.
// Validation: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/SnapshotCodecTests

/// SnapshotCodecTests — pure value tests for `SnapshotCodec` and `SyncDecimal`.
///
/// No container, no @MainActor, no device — SyncSnapshot is a pure Codable value type.
/// These lock down the two money/merge invariants at the byte level:
///   - money crosses JSON as a String, never a JSON number (SYNC success criterion 4)
///   - canonical encoding is byte-deterministic (required by the LWW tiebreak)
///   - a mismatched schemaVersion is refused BEFORE any entity decode
struct SnapshotCodecTests {

    // MARK: - Fixture

    /// A fully-populated snapshot: at least one element in every DTO array, one DeletionDTO,
    /// realistic field values including a Data? reminder blob — so encode/decode exercises
    /// every DTO shape.
    static func makeFixture() -> SyncSnapshot {
        let reminderBlob = Data([0x01, 0x02, 0x03, 0xFF])
        let d0 = Date(timeIntervalSince1970: 1_700_000_000)   // whole-second — stable under ms encoding
        let d1 = Date(timeIntervalSince1970: 1_700_000_123)

        return SyncSnapshot(
            exportedAt: d0,
            deviceName: "iPhone-Test",
            categories: [
                CategoryDTO(id: UUID(), syncID: UUID(), updatedAt: d0, name: "Groceries",
                            symbolName: "cart", sortOrder: 3,
                            monthlyBudget: SyncDecimal.string(from: Decimal(string: "5000")!),
                            currencyCode: "INR", createdAt: d0)
            ],
            expenses: [
                ExpenseDTO(id: UUID(), syncID: UUID(), updatedAt: d1,
                           amount: SyncDecimal.string(from: Decimal(string: "1234.56")!),
                           currencyCode: "INR", date: d1, note: "coffee", createdAt: d1,
                           categorySyncIDs: [UUID()], rawEmailBody: nil, parserID: "HDFC",
                           parserVersion: "1", sourceLabel: "HDFC CC", gmailMessageID: "m1",
                           ingestionStateRaw: "autoSaved", parseConfidence: 0.87,
                           sourceAccount: "a@b.com", accountID: UUID(), isTransfer: false,
                           transferPairID: nil)
            ],
            notes: [
                NoteDTO(id: UUID(), syncID: UUID(), updatedAt: d0, title: "Shopping",
                        isPinned: true, createdAt: d0, modifiedAt: d0, reminderEnabled: true,
                        reminderDate: d1, reminderIsAllDay: false,
                        reminderRecurrenceData: reminderBlob, reminderEndRuleData: nil,
                        reminderLeadMinutes: 15, isDailyRoutine: true,
                        routineLastResetDate: d0, routineDailyReminderTime: d1)
            ],
            noteBlocks: [
                NoteBlockDTO(id: UUID(), syncID: UUID(), updatedAt: d0, kindRaw: "checkbox",
                             text: "milk", isChecked: false, order: 0, noteSyncID: UUID(),
                             reminderEnabled: false, reminderDate: nil, reminderIsAllDay: false,
                             reminderRecurrenceData: nil, reminderEndRuleData: reminderBlob,
                             reminderLeadMinutes: 0)
            ],
            accounts: [
                AccountDTO(id: UUID(), syncID: UUID(), updatedAt: d0, name: "HDFC",
                           typeRaw: "savings", symbolName: "banknote", colorHex: "#FF3B30",
                           last4: "1234",
                           balanceBaseline: SyncDecimal.string(from: Decimal(string: "100000.50")!),
                           balanceAsOfDate: d0, isArchived: false, sortOrder: 1,
                           sourceLabel: nil, createdAt: d0)
            ],
            assets: [
                AssetDTO(id: UUID(), syncID: UUID(), updatedAt: d0, name: "Nifty50",
                         assetClassRaw: "mutual_fund",
                         units: SyncDecimal.string(from: Decimal(string: "12.3456")!),
                         costBasisPerUnit: SyncDecimal.string(from: Decimal(string: "98.76")!),
                         currentNAV: SyncDecimal.string(from: Decimal(string: "105.4321")!),
                         navAsOfDate: d0, createdAt: d0, amfiSchemeCode: "120503",
                         npsSchemeCode: nil)
            ],
            netWorthSnapshots: [
                NetWorthSnapshotDTO(id: UUID(), syncID: UUID(), updatedAt: d0, date: d0,
                                    totalNetWorth: SyncDecimal.string(from: Decimal(string: "500000")!),
                                    mfValue: SyncDecimal.string(from: Decimal(string: "300000")!),
                                    stockValue: SyncDecimal.string(from: Decimal(string: "100000")!),
                                    npsValue: SyncDecimal.string(from: Decimal(string: "50000")!),
                                    cashValue: SyncDecimal.string(from: Decimal(string: "50000")!),
                                    createdAt: d0)
            ],
            sips: [
                SIPDTO(id: UUID(), syncID: UUID(), updatedAt: d0, assetID: UUID(),
                       dayOfMonth: 5, amount: SyncDecimal.string(from: Decimal(string: "10000")!),
                       startDate: d0, isActive: true, lastAccruedDate: d0,
                       reminderNotificationID: "n1", createdAt: d0, npsAllocationE: 0,
                       npsAllocationC: 0, npsAllocationG: 0, npsAssetE: nil, npsAssetC: nil,
                       npsAssetG: nil)
            ],
            sipAmountChanges: [
                SIPAmountChangeDTO(id: UUID(), syncID: UUID(), updatedAt: d0, sipID: UUID(),
                                   effectiveFrom: d0,
                                   amount: SyncDecimal.string(from: Decimal(string: "12000")!),
                                   createdAt: d0)
            ],
            contributions: [
                ContributionDTO(id: UUID(), syncID: UUID(), updatedAt: d0, assetID: UUID(),
                                sipID: UUID(), date: d0,
                                amount: SyncDecimal.string(from: Decimal(string: "10000")!),
                                navUsed: SyncDecimal.string(from: Decimal(string: "100.25")!),
                                navDate: d0,
                                unitsAdded: SyncDecimal.string(from: Decimal(string: "99.7506")!),
                                isEstimate: true, createdAt: d0)
            ],
            routineCompletions: [
                RoutineCompletionDTO(id: UUID(), syncID: UUID(), updatedAt: d0, noteID: UUID(),
                                     dayKey: d0, completedAt: d0, createdAt: d0)
            ],
            deletions: [
                DeletionDTO(entitySyncID: UUID(), entityKindRaw: SyncEntityKind.expense.rawValue,
                            deletedAt: d1)
            ]
        )
    }

    // MARK: - Decimal survives as a string (byte-level)

    @Test("Decimal money encodes as a JSON string, never a JSON number")
    func decimalEncodesAsString() throws {
        let snap = Self.makeFixture()
        let data = try SnapshotCodec.encode(snap)
        let json = String(decoding: data, as: UTF8.self)

        #expect(json.contains("\"amount\":\"1234.56\""),
                "money must cross the wire as a quoted string")
        #expect(!json.contains("\"amount\":1234.56"),
                "money must NEVER appear as a bare JSON number (Double drift gate)")
    }

    @Test("SyncDecimal round-trips every representative money value")
    func syncDecimalRoundTrip() {
        let values: [Decimal] = [
            Decimal(string: "0")!,
            Decimal(string: "0.01")!,
            Decimal(string: "1234.56")!,
            Decimal(string: "-14000")!,
            Decimal(string: "99999999.9999")!
        ]
        for d in values {
            let s = SyncDecimal.string(from: d)
            #expect(SyncDecimal.decimal(from: s) == d,
                    "round-trip failed for \(s)")
        }
    }

    // MARK: - Canonical determinism

    @Test("encode -> decode -> encode is byte-identical")
    func canonicalDeterminism() throws {
        let snap = Self.makeFixture()
        let data1 = try SnapshotCodec.encode(snap)
        let decoded = try SnapshotCodec.decode(data1)
        let data2 = try SnapshotCodec.encode(decoded)
        #expect(data1 == data2, "canonical encoding must be byte-stable across round-trip")
        #expect(decoded == snap, "decoded snapshot must equal the original value")
    }

    // MARK: - Version refusal

    @Test("decode refuses a schemaVersion-9 snapshot before decoding entities")
    func versionMismatchRefused() throws {
        let snap = Self.makeFixture()
        let data = try SnapshotCodec.encode(snap)
        var json = String(decoding: data, as: UTF8.self)
        json = json.replacingOccurrences(of: "\"schemaVersion\":10", with: "\"schemaVersion\":9")
        let tampered = Data(json.utf8)

        #expect(throws: SyncError.schemaVersionMismatch(found: 9, expected: 10)) {
            _ = try SnapshotCodec.decode(tampered)
        }
    }

    @Test("decode of garbage bytes throws malformedSnapshot")
    func garbageThrowsMalformed() {
        let garbage = Data("not json at all }{".utf8)
        #expect {
            _ = try SnapshotCodec.decode(garbage)
        } throws: { error in
            guard case SyncError.malformedSnapshot = error else { return false }
            return true
        }
    }

    @Test("decode of truncated valid JSON throws malformedSnapshot")
    func truncatedThrowsMalformed() throws {
        let data = try SnapshotCodec.encode(Self.makeFixture())
        let truncated = data.prefix(data.count / 2)
        #expect {
            _ = try SnapshotCodec.decode(Data(truncated))
        } throws: { error in
            guard case SyncError.malformedSnapshot = error else { return false }
            return true
        }
    }
}
