import Testing
import Foundation
@testable import MyHome

/// Wave-0 scaffold for NPSNavService parser + IST gate tests (filled in by plan 11.1-03).
///
/// Behaviors this suite must cover (per VALIDATION.md Per-Task Verification Map):
///   - NPS NAV history parse: DD-MM-YYYY date format, JSON Number nav field
///   - npsnav.in /api/latest-min response shape: [[code, nav], ...] array-of-pairs
///   - IST daily gate: shouldFetch returns false for same-day fetch, true for yesterday
///   - Nearest-prior-date fallback for holidays/weekends (no entry → prior published date)
///   - NPSScheme struct: code, name, nav fields
///   - Silent-fail on invalid JSON (returns empty array, no throw)
///
/// All tests in this file run offline using committed fixtures under MyHomeTests/Fixtures/nps/.
@Suite("NPSNavServiceTests")
struct NPSNavServiceTests {

    @Test("placeholder — Wave-0 scaffold; plan 11.1-03 fills in parser + IST gate tests")
    func placeholder() {}
}
