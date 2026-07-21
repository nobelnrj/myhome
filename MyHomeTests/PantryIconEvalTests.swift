import Testing
import Foundation
import FoundationModels
@testable import MyHome

// Requirements: ICON-01 — the NON-DETERMINISTIC half of AI-SPEC §5.2.
//
// OPT-IN. This suite does not run on a routine invocation. To run it:
//
//   PANTRY_ICON_EVAL=1 xcodebuild test -scheme MyHome \
//     -destination 'platform=iOS Simulator,name=iPhone 17' \
//     -parallel-testing-enabled NO \
//     -only-testing:MyHomeTests/PantryIconEvalTests
//
// (xcodebuild forwards the process environment to the test runner, so exporting the variable on
// the command line is enough.)

/// PantryIconEvalTests — measures how well the real on-device model classifies this household's
/// vocabulary, against the committed `PantryIconFixture`.
///
/// **Why this is opt-in and the structural gates are not.** The model is non-deterministic: the
/// same name can classify differently across runs, and Apple Intelligence may be unavailable,
/// ineligible or mid-download on any given machine. Making that a blocking gate would mean a
/// single flaky classification reddens an unrelated change — the exact failure mode AI-SPEC §5.2
/// tells us to avoid. The deterministic guarantees (symbol totality, graceful degradation, no
/// leakage) live in `PantryIconStructuralTests` and ARE always-on and blocking.
///
/// Thresholds (AI-SPEC §5.2):
/// - ≥ 90% exact-category accuracy across the whole fixture.
/// - **100%** on `PantryIconFixture.nonRegression` — a name the old keyword table got right must
///   never regress.
///
/// On failure the full name → expected → actual table is printed, so a miss is diagnosable
/// without a rerun (a rerun would produce different misses anyway).
@Suite(
    "Pantry icon model accuracy (opt-in)",
    .enabled(if: ProcessInfo.processInfo.environment["PANTRY_ICON_EVAL"] == "1")
)
struct PantryIconEvalTests {

    /// One classified fixture row.
    private struct Outcome {
        let name: String
        let expected: PantryCategory
        let actual: PantryCategory?   // nil = the call threw
    }

    private static func makeClassifier() -> PantryIconClassifying? {
        if #available(iOS 26, *) {
            if isPantryIconClassificationAvailable(SystemLanguageModel.default.availability) {
                return FoundationModelsPantryIconClassifier()
            }
        }
        return nil
    }

    private static func classify(
        _ entries: [(name: String, expected: PantryCategory)],
        with classifier: PantryIconClassifying
    ) async -> [Outcome] {
        var outcomes: [Outcome] = []
        for entry in entries {
            // The resolver sends the NORMALISED key to the model; mirror that here so the eval
            // measures the string the app actually classifies.
            let key = KitchenLogic.normalizedIconKey(forName: entry.name)
            guard let key else {
                // A blank name never reaches the model in production — the resolver short-circuits
                // it — so the accepted answer is the neutral tile, scored as a hit by construction.
                outcomes.append(Outcome(name: entry.name, expected: entry.expected, actual: entry.expected))
                continue
            }
            let actual = try? await classifier.classify(name: key)
            outcomes.append(Outcome(name: entry.name, expected: entry.expected, actual: actual))
        }
        return outcomes
    }

    private static func report(_ outcomes: [Outcome], label: String) -> String {
        var lines = ["", "=== \(label) ===", "name | expected | actual"]
        for o in outcomes where o.actual != o.expected {
            lines.append("MISS  \(o.name) | \(o.expected.rawValue) | \(o.actual?.rawValue ?? "<threw>")")
        }
        let hits = outcomes.filter { $0.actual == $0.expected }.count
        lines.append("hits \(hits)/\(outcomes.count)")
        return lines.joined(separator: "\n")
    }

    @Test("Overall fixture accuracy is at least 90%")
    func overallAccuracyMeetsThreshold() async throws {
        guard let classifier = Self.makeClassifier() else {
            Issue.record("Skipped: the on-device model is unavailable on this machine. Enable Apple Intelligence and rerun.")
            return
        }

        let outcomes = await Self.classify(PantryIconFixture.cases, with: classifier)
        let hits = outcomes.filter { $0.actual == $0.expected }.count
        let accuracy = Double(hits) / Double(outcomes.count)

        print(Self.report(outcomes, label: "Pantry icon eval — full fixture"))
        print(String(format: "accuracy = %.1f%%", accuracy * 100))

        #expect(accuracy >= 0.90, "accuracy \(accuracy) below the 0.90 threshold")
    }

    @Test("The non-regression set is classified perfectly")
    func nonRegressionAccuracyIsPerfect() async throws {
        guard let classifier = Self.makeClassifier() else {
            Issue.record("Skipped: the on-device model is unavailable on this machine. Enable Apple Intelligence and rerun.")
            return
        }

        let outcomes = await Self.classify(PantryIconFixture.nonRegression, with: classifier)
        let hits = outcomes.filter { $0.actual == $0.expected }.count

        print(Self.report(outcomes, label: "Pantry icon eval — non-regression"))

        #expect(hits == outcomes.count, "a name the keyword table got right regressed under the model")
    }

    @Test("The motivating names all leave the neutral bag behind")
    func motivatingNamesGetAMeaningfulCategory() async throws {
        guard let classifier = Self.makeClassifier() else {
            Issue.record("Skipped: the on-device model is unavailable on this machine. Enable Apple Intelligence and rerun.")
            return
        }

        let outcomes = await Self.classify(PantryIconFixture.motivating, with: classifier)
        print(Self.report(outcomes, label: "Pantry icon eval — motivating names"))

        // The bar here is looser than exact-match on purpose: the phase exists because these names
        // fell through to `bag.fill`. Anything other than `.other` is progress; the exact-category
        // score for them is already counted in the overall accuracy test.
        for o in outcomes {
            #expect(o.actual != nil && o.actual != .other, "'\(o.name)' still lands on the neutral bag")
        }
    }
}
