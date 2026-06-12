import Testing
import Foundation
@testable import MyHome

/// Wave-0 scaffold for SIPAccrualService accrual math tests (filled in by plan 11.1-02).
///
/// Behaviors this suite must cover (per VALIDATION.md Per-Task Verification Map):
///   - MF historical NAV parse: DD-MM-YYYY date format, JSON String nav field (mfapi.in shape)
///   - Exact-date NAV lookup + nearest-prior fallback (holidays / weekends / future dates)
///   - SIP elapsed-installment date computation (IST): day-of-month clamping (Feb), month walk
///   - units = amount ÷ NAV (Decimal, no Double drift, round-down to 4dp)
///   - NPS allocation split across E/C/G (sum-to-100, remainder to largest slice)
///   - Amount-change history: applies from next installment only (D-07)
///   - isActive toggle stops future accrual (D-04)
///
/// All tests in this file run offline using committed fixtures under MyHomeTests/Fixtures/mf/.
@Suite("SIPAccrualServiceTests")
struct SIPAccrualServiceTests {

    @Test("placeholder — Wave-0 scaffold; plan 11.1-02 fills in accrual math tests")
    func placeholder() {}
}
