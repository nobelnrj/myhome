// InsightServiceTests.swift
// Phase 16: AI Insight Card — availability + error-routing test scaffolds (Plan 01 RED).
//
// Requirements: AI-02 (4 availability branches), AI-03 (2 error-routing cases)
// Validation: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'
//             -only-testing:MyHomeTests/InsightServiceTests
//
// Wave 1 RED status (stubs — Plans 02/03 turn GREEN):
//   RED:   testAvailabilityAvailableReturnsTrue   (stub returns false)
//   GREEN: testAvailabilityDeviceNotEligibleReturnsFalse  (stub also returns false)
//   GREEN: testAvailabilityIntelligenceDisabledReturnsFalse (stub also returns false)
//   GREEN: testAvailabilityModelNotReadyReturnsFalse       (stub also returns false)
//   GREEN: testGuardrailErrorRoutesFallback  (helper catch + stub fallback both work)
//   GREEN: testContextWindowErrorRoutesFallback (same)
//
// Pitfall 9 (16-RESEARCH.md): @available(iOS 26, *) on each @Test function, NOT on the
// struct itself — Swift Testing structs can't carry OS availability at the struct level.
//
// Open Question 3 resolved: GenerationError.Context is not publicly constructible;
// tests use MockGenerationError for the throw and check fallback OUTCOME.

import Testing
import Foundation
import SwiftData
@testable import MyHome

// MARK: - MockInsightService

/// Configurable mock for InsightGenerating (the testability seam for all AI-02/AI-03 tests).
///
/// `result` controls the return value or thrown error.
/// `callCount` tracks invocations for assertion convenience.
/// `Task.yield()` inside `generate` allows structured-concurrency cancellation to propagate.
@available(iOS 26, *)
final class MockInsightService: InsightGenerating, @unchecked Sendable {
    // @unchecked Sendable: test-only mock; mutations happen sequentially in tests.
    var result: Result<SpendInsight, Error> = .success(
        SpendInsight(observation: "Mock observation.", suggestion: nil)
    )
    private(set) var callCount = 0

    func generate(for summary: SpendSummary) async throws -> SpendInsight {
        callCount += 1
        await Task.yield()  // suspend — allows structured-concurrency cancellation to propagate
        return try result.get()
    }
}

// MARK: - Local Error Type (Open Question 3)

/// Local mock errors that simulate LanguageModelSession.GenerationError cases.
/// Used because GenerationError.Context is NOT publicly constructible from tests.
/// Production code catches `is LanguageModelSession.GenerationError`; tests verify
/// the fallback OUTCOME rather than the concrete error case.
enum MockGenerationError: Error {
    case guardrailViolation
    case exceededContextWindowSize
}

// MARK: - Fixture Helper

/// Builds a minimal `SpendSummary` for unit tests.
///
/// Uses empty `trendBuckets` and `categoryBreakdown` to avoid SwiftData dependencies.
/// Plans 02/03 may extend this with richer category fixtures for verifier tests.
@available(iOS 26, *)
func makeInsightTestSummary(
    range: SpendRange = .month,
    totalSpend: Decimal = 10_000,
    priorTotalSpend: Decimal = 9_000
) -> SpendSummary {
    SpendSummary(
        range: range,
        totalSpend: totalSpend,
        priorTotalSpend: priorTotalSpend,
        trendBuckets: [],
        categoryBreakdown: [],
        priorCategorySpend: [:]
    )
}

// MARK: - Error-Routing Helper

/// Simulates the catch logic that AIInsightCard (Plan 04) will own.
///
/// If the service throws any error (guardrail, context-window, or other), the helper
/// catches it and returns a fallback insight. Tests verify the OUTCOME: non-empty
/// fallback text is produced; no error propagates to the caller.
@available(iOS 26, *)
private func callServiceWithFallback(
    service: any InsightGenerating,
    summary: SpendSummary
) async -> SpendInsight {
    // AI-03: production AIInsightCard catches LanguageModelSession.GenerationError specifically.
    // Tests use a single catch-all and verify the OUTCOME (fallback returned), not the error type,
    // because GenerationError.Context is not publicly constructible (Open Question 3 resolved).
    do {
        return try await service.generate(for: summary)
    } catch {
        return InsightFallbackBuilder.build(for: summary)
    }
}

// MARK: - InsightServiceTests

/// Tests for isInsightAvailable (AI-02) and error-routing (AI-03).
///
/// Each test method is individually gated @available(iOS 26, *) per Pitfall 9:
/// Swift Testing structs cannot carry OS availability at the struct level.
struct InsightServiceTests {

    // MARK: AI-02: Availability Branches

    /// AI-02 — RED in Plan 01: isInsightAvailable(.available) must return true.
    /// Stub returns false → this test FAILS until Plan 03 Task 1 implements the real switch.
    @Test("isInsightAvailable(.available) returns true")
    @available(iOS 26, *)
    func testAvailabilityAvailableReturnsTrue() {
        let result = isInsightAvailable(.available)
        #expect(result == true)
        // RED: stub returns false → #expect fails.
        // Plan 03 Task 1 implements: case .available: return true
    }

    /// AI-02 — GREEN in Plan 01 (accidentally): stub returns false, which is the correct answer.
    /// Will remain GREEN when Plan 03 implements: case .unavailable: return false
    @Test("isInsightAvailable(.unavailable(.deviceNotEligible)) returns false")
    @available(iOS 26, *)
    func testAvailabilityDeviceNotEligibleReturnsFalse() {
        let result = isInsightAvailable(.unavailable(.deviceNotEligible))
        #expect(result == false)
    }

    /// AI-02 — GREEN in Plan 01 (accidentally): stub returns false.
    @Test("isInsightAvailable(.unavailable(.appleIntelligenceNotEnabled)) returns false")
    @available(iOS 26, *)
    func testAvailabilityIntelligenceDisabledReturnsFalse() {
        let result = isInsightAvailable(.unavailable(.appleIntelligenceNotEnabled))
        #expect(result == false)
    }

    /// AI-02 — GREEN in Plan 01 (accidentally): stub returns false.
    @Test("isInsightAvailable(.unavailable(.modelNotReady)) returns false")
    @available(iOS 26, *)
    func testAvailabilityModelNotReadyReturnsFalse() {
        let result = isInsightAvailable(.unavailable(.modelNotReady))
        #expect(result == false)
    }

    // MARK: AI-03: Error Routing

    /// AI-03 — GREEN in Plan 01: mock throws MockGenerationError.guardrailViolation;
    /// the catch-all fallback returns non-empty text. No error escapes to the caller.
    ///
    /// Plan 03 refines: the production service throws LanguageModelSession.GenerationError
    /// and AIInsightCard catches it with `catch is LanguageModelSession.GenerationError`.
    @Test("guardrailViolation error routes to fallback (no throw escapes)")
    @available(iOS 26, *)
    func testGuardrailErrorRoutesFallback() async throws {
        let mock = MockInsightService()
        mock.result = .failure(MockGenerationError.guardrailViolation)
        let summary = makeInsightTestSummary()

        // callServiceWithFallback never throws — it returns a fallback SpendInsight.
        let fallback = await callServiceWithFallback(service: mock, summary: summary)

        #expect(fallback.observation.isEmpty == false)
        #expect(mock.callCount == 1)  // service was called exactly once
    }

    /// AI-03 — GREEN in Plan 01: exceededContextWindowSize-style error also routes to fallback.
    @Test("exceededContextWindowSize error routes to fallback (no throw escapes)")
    @available(iOS 26, *)
    func testContextWindowErrorRoutesFallback() async throws {
        let mock = MockInsightService()
        mock.result = .failure(MockGenerationError.exceededContextWindowSize)
        let summary = makeInsightTestSummary()

        let fallback = await callServiceWithFallback(service: mock, summary: summary)

        #expect(fallback.observation.isEmpty == false)
        #expect(mock.callCount == 1)
    }
}
