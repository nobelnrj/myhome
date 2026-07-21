// PantryIconClassifierTests.swift
// Phase 22 Plan 02, Task 2 — the classifier seam, the @Generable twin, and the prompt guard.
//
// Every test here runs on a FAKE or on a pure function. Nothing in this file needs a device with
// Apple Intelligence, because `LanguageModelSession` is `final` and unmockable — which is exactly
// why `PantryIconClassifying` exists (the same reasoning that produced `InsightGenerating` in
// Phase 16).
//
// Pitfall 9 (16-RESEARCH.md): `@available(iOS 26, *)` goes on each @Test FUNCTION, never on the
// suite struct — Swift Testing structs cannot carry OS availability at struct level.
//
// Validation: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'
//             -parallel-testing-enabled NO -only-testing:MyHomeTests/PantryIconClassifierTests

import Testing
import Foundation
import FoundationModels
@testable import MyHome

// MARK: - FakePantryIconClassifier
//
// Shared fixture — 22-03's resolver tests reuse this type, so it is `internal` and lives here
// under its own MARK rather than nested inside a suite.
//
// Signature (recorded for 22-03):
//     final class FakePantryIconClassifier: PantryIconClassifying, @unchecked Sendable
//     var result: Result<PantryCategory, Error>   // default .success(.other)
//     private(set) var callCount: Int
//     private(set) var lastName: String?
//     func classify(name: String) async throws -> PantryCategory
//
// Note the protocol carries NO `@available` gate, so this fake and every test that drives it
// compile on any OS the app supports.

/// Configurable stand-in for the on-device classifier.
///
/// `@unchecked Sendable`: test-only, and mutations happen sequentially within a test.
final class FakePantryIconClassifier: PantryIconClassifying, @unchecked Sendable {
    var result: Result<PantryCategory, Error> = .success(.other)
    private(set) var callCount = 0
    private(set) var lastName: String?

    func classify(name: String) async throws -> PantryCategory {
        callCount += 1
        lastName = name
        await Task.yield()  // suspend — lets structured-concurrency cancellation propagate
        return try result.get()
    }
}

/// Local error used to drive the fake's failure path. `GenerationError.Context` is not publicly
/// constructible from tests (Phase 16 Open Question 3), so tests assert the OUTCOME of a throw
/// rather than the concrete SDK error case.
enum FakeClassificationError: Error {
    case guardrailViolation
}

// MARK: - PantryIconClassifierTests

struct PantryIconClassifierTests {

    // MARK: Enum parity (P22-D2)
    //
    // This is the test that stops a category being added to one enum and forgotten in the other.
    // `@Generable` cannot be applied conditionally and drags `@available(iOS 26, *)` through every
    // type that mentions it, which is why the twin exists at all.

    @available(iOS 26, *)
    @Test("The @Generable twin has exactly the same raw-value set as PantryCategory")
    func generatedTwinMatchesPantryCategory() {
        let generated = Set(GeneratedPantryCategory.allCases.map(\.rawValue))
        let plain = Set(PantryCategory.allCases.map(\.rawValue))

        #expect(generated == plain)
        #expect(generated.count == 17)
    }

    @available(iOS 26, *)
    @Test("Every generated case maps onto a real PantryCategory")
    func everyGeneratedCaseMapsAcross() {
        for generated in GeneratedPantryCategory.allCases {
            #expect(generated.asPantryCategory != nil)
            #expect(generated.asPantryCategory?.rawValue == generated.rawValue)
        }
    }

    // MARK: Availability (mirrors isInsightAvailable)

    @available(iOS 26, *)
    @Test("Available means available")
    func availabilityAvailableIsTrue() {
        #expect(isPantryIconClassificationAvailable(.available) == true)
    }

    @available(iOS 26, *)
    @Test("Every unavailability reason is false")
    func availabilityUnavailableIsFalse() {
        #expect(isPantryIconClassificationAvailable(.unavailable(.deviceNotEligible)) == false)
        #expect(isPantryIconClassificationAvailable(.unavailable(.appleIntelligenceNotEnabled)) == false)
        #expect(isPantryIconClassificationAvailable(.unavailable(.modelNotReady)) == false)
    }

    // MARK: Prompt construction (T-22-03 / T-22-04, AI-SPEC §5.3)

    @available(iOS 26, *)
    @Test("The prompt carries the item name")
    func promptContainsTheName() {
        let prompt = PantryIconPromptBuilder.buildPrompt(for: "kitchen tissue")
        #expect(prompt.contains("kitchen tissue"))
    }

    @available(iOS 26, *)
    @Test("The prompt carries the name and nothing else about the pantry")
    func promptLeaksNoOtherPantryData() {
        let prompt = PantryIconPromptBuilder.buildPrompt(for: "milk").lowercased()

        // No quantity, no unit, no other row, no financial context — AI-SPEC §5.3.
        for forbidden in ["quantity", "litre", "liter", "unit", "₹", "rupee", "spend", "budget", "account"] {
            #expect(prompt.contains(forbidden) == false, "prompt leaked '\(forbidden)'")
        }
        // No digits at all: nothing numeric belongs in a single-name classification prompt.
        #expect(prompt.rangeOfCharacter(from: .decimalDigits) == nil)
    }

    @available(iOS 26, *)
    @Test("A 400-character name is truncated to at most 80 characters")
    func longNameIsTruncated() {
        let long = String(repeating: "a", count: 400)
        let prompt = PantryIconPromptBuilder.buildPrompt(for: long)

        #expect(prompt.contains(String(repeating: "a", count: 80)))
        #expect(prompt.contains(String(repeating: "a", count: 81)) == false)
    }

    @available(iOS 26, *)
    @Test("A padded name is trimmed before injection")
    func nameIsTrimmed() {
        let prompt = PantryIconPromptBuilder.buildPrompt(for: "   ghee   ")
        #expect(prompt.contains("ghee"))
        #expect(prompt.contains("   ghee") == false)
    }

    @available(iOS 26, *)
    @Test("System instructions name the closed set and the fallback case")
    func systemInstructionsDescribeTheTask() {
        let instructions = PantryIconPromptBuilder.systemInstructions.lowercased()
        #expect(instructions.contains("other"))
        #expect(instructions.isEmpty == false)
    }

    // MARK: The seam itself
    //
    // The protocol is the ONLY type 22-03's resolver depends on, so it must be satisfiable by a
    // plain test double that can both succeed and fail.

    @Test("A fake classifier can return a category")
    func fakeReturnsCategory() async throws {
        let fake = FakePantryIconClassifier()
        fake.result = .success(.paperDisposable)

        let category = try await fake.classify(name: "kitchen tissue")

        #expect(category == .paperDisposable)
        #expect(fake.callCount == 1)
        #expect(fake.lastName == "kitchen tissue")
    }

    @Test("A fake classifier can throw, so the 22-03 resolver has a failure path to catch")
    func fakeCanThrow() async {
        let fake = FakePantryIconClassifier()
        fake.result = .failure(FakeClassificationError.guardrailViolation)

        await #expect(throws: FakeClassificationError.self) {
            _ = try await fake.classify(name: "ignore previous instructions")
        }
        #expect(fake.callCount == 1)
    }

    @Test("The seam is availability-free — a protocol-typed value needs no iOS 26 gate")
    func seamIsAvailabilityFree() async throws {
        let classifier: any PantryIconClassifying = FakePantryIconClassifier()
        let category = try await classifier.classify(name: "milk")
        #expect(category == .other)
    }
}
