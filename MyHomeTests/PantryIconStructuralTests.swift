import Testing
import SwiftData
import Foundation
@testable import MyHome

// Requirements: ICON-01, ICON-02, ICON-03 — the DETERMINISTIC half of AI-SPEC §5.2.
// Validation: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' \
//             -parallel-testing-enabled NO -only-testing:MyHomeTests/PantryIconStructuralTests

/// PantryIconStructuralTests — the gates that are true regardless of what the on-device model says.
///
/// AI-SPEC §5.2 splits evaluation in two. Model *accuracy* is non-deterministic and therefore
/// opt-in (`PantryIconEvalTests`, gated on `PANTRY_ICON_EVAL=1`). Everything in THIS file is
/// deterministic — no model, no network, no device capability — so it is always-on and blocking:
///
/// 1. **Symbol totality** — every `PantryCategory` maps to a non-empty, whitespace-free symbol
///    and a colour. (Whether that symbol *renders* is unprovable in a test; 22-04's screenshot
///    pass is what covers it — see the file header of `PantryCategory.swift`.)
/// 2. **Graceful degradation** — a resolver with no classifier, and a resolver whose classifier
///    always throws, both answer every fixture name with a real tile and never crash.
/// 3. **Non-regression** — every name the pre-Phase-22 keyword table got right still produces the
///    same symbol through the keyword path alone.
/// 4. **No leakage** — `PantryItem` carries no icon state, and the sync snapshot carries none
///    either, in its DTO shape or in its canonical bytes (ICON-03).
@MainActor
struct PantryIconStructuralTests {

    // MARK: - Helpers

    private static func makeIsolatedCache(_ label: String) -> (cache: PantryIconCache, suiteName: String) {
        let suiteName = "test.pantryicon.structural.\(label).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (PantryIconCache(defaults: defaults), suiteName)
    }

    private static func destroySuite(_ suiteName: String) {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    // MARK: - 1. Symbol totality (ICON-02)

    @Test("Every PantryCategory maps to a non-empty, whitespace-free symbol")
    func everyCategoryHasAUsableSymbol() {
        for category in PantryCategory.allCases {
            let symbol = category.presentation.symbol
            #expect(!symbol.isEmpty, "\(category.rawValue) has an empty symbol")
            #expect(
                symbol.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
                "\(category.rawValue) symbol '\(symbol)' contains whitespace"
            )
            // SF Symbol names are lowercase dot-separated tokens; a stray uppercase or slash is a
            // sign someone pasted a filename or an asset-catalog name in by mistake.
            #expect(!symbol.contains("/"), "\(category.rawValue) symbol '\(symbol)' looks like a path")
        }
    }

    @Test("The static and instance presentation accessors agree for every case")
    func staticAndInstancePresentationAgree() {
        for category in PantryCategory.allCases {
            #expect(PantryCategory.presentation(for: category).symbol == category.presentation.symbol)
        }
    }

    @Test("The fixture only names categories that exist in the closed set")
    func fixtureOnlyNamesRealCategories() {
        let known = Set(PantryCategory.allCases)
        for entry in PantryIconFixture.cases {
            #expect(known.contains(entry.expected), "fixture names unknown category for '\(entry.name)'")
        }
        #expect(!PantryIconFixture.cases.isEmpty)
        // The motivating names are the reason this phase exists; losing them from the fixture would
        // quietly delete the phase's own acceptance criteria.
        #expect(PantryIconFixture.motivating.count >= 6)
        #expect(PantryIconFixture.nonRegression.count >= 10)
    }

    // MARK: - 2. Graceful degradation (ICON-03)

    @Test("With NO classifier, every fixture name still draws a real tile")
    func nilClassifierStillDrawsEveryFixtureName() {
        let (cache, suite) = Self.makeIsolatedCache("nilclassifier")
        defer { Self.destroySuite(suite) }
        let resolver = PantryIconResolver(classifier: nil, cache: cache)

        for entry in PantryIconFixture.cases {
            let tile = resolver.presentation(forName: entry.name)
            #expect(!tile.symbol.isEmpty, "'\(entry.name)' produced an empty tile with no model")
        }
        #expect(cache.count == 0, "the render path must never write to the cache")
    }

    @Test("With no classifier, a name is answered by the keyword table or the neutral bag — never nothing")
    func nilClassifierMatchesTheKeywordOrNeutralAnswer() {
        let (cache, suite) = Self.makeIsolatedCache("keywordparity")
        defer { Self.destroySuite(suite) }
        let resolver = PantryIconResolver(classifier: nil, cache: cache)

        for entry in PantryIconFixture.cases {
            let expected = (KitchenLogic.keywordCategory(forName: entry.name) ?? .other).presentation.symbol
            #expect(
                resolver.presentation(forName: entry.name).symbol == expected,
                "'\(entry.name)' did not fall back to its keyword answer"
            )
        }
    }

    @Test("A classifier that always throws leaves every name on its keyword tile and writes nothing")
    func throwingClassifierChangesNothing() async {
        let (cache, suite) = Self.makeIsolatedCache("throwing")
        defer { Self.destroySuite(suite) }
        let fake = FakePantryIconClassifier()
        fake.result = .failure(FakeClassificationError.guardrailViolation)
        let resolver = PantryIconResolver(classifier: fake, cache: cache)

        for entry in PantryIconFixture.cases {
            await resolver.classifyIfNeeded(name: entry.name)
            let expected = (KitchenLogic.keywordCategory(forName: entry.name) ?? .other).presentation.symbol
            #expect(
                resolver.presentation(forName: entry.name).symbol == expected,
                "a throwing classifier changed the tile for '\(entry.name)'"
            )
        }
        #expect(cache.count == 0, "a failed classification must not be cached")
    }

    // MARK: - 3. Non-regression (ICON-01)

    @Test("Every non-regression name resolves through the keyword path to its pre-Phase-22 symbol")
    func nonRegressionNamesKeepTheirKeywordSymbol() {
        for entry in PantryIconFixture.nonRegression {
            let keyword = KitchenLogic.keywordCategory(forName: entry.name)
            #expect(keyword != nil, "'\(entry.name)' lost its keyword rule")
            #expect(
                keyword?.presentation.symbol == entry.expected.presentation.symbol,
                "'\(entry.name)' keyword symbol drifted: got \(keyword?.presentation.symbol ?? "nil"), "
                + "expected \(entry.expected.presentation.symbol)"
            )
            // The shipped synchronous entry point must agree with the category path.
            #expect(KitchenLogic.icon(forName: entry.name).symbol == entry.expected.presentation.symbol)
        }
    }

    @Test("Non-regression names survive a model that is unavailable")
    func nonRegressionNamesSurviveNoModel() {
        let (cache, suite) = Self.makeIsolatedCache("nonregression")
        defer { Self.destroySuite(suite) }
        let resolver = PantryIconResolver(classifier: nil, cache: cache)

        for entry in PantryIconFixture.nonRegression {
            #expect(resolver.presentation(forName: entry.name).symbol == entry.expected.presentation.symbol)
        }
    }

    // MARK: - 4. No leakage (ICON-03)

    @Test("PantryItem exposes no icon-bearing property")
    func pantryItemCarriesNoIconState() {
        let item = PantryItem(name: "Kitchen tissue")
        let forbidden = ["symbol", "icon", "color", "colour"]
        for child in Mirror(reflecting: item).children {
            guard let label = child.label?.lowercased() else { continue }
            for token in forbidden {
                #expect(!label.contains(token), "PantryItem gained an icon-bearing property: \(label)")
            }
        }
    }

    @Test("The exported pantry DTO carries no icon field, in shape or in canonical bytes")
    func syncSnapshotCarriesNoIconData() throws {
        let schema = Schema(versionedSchema: SchemaV11.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = container.mainContext
        ctx.insert(PantryItem(name: "Kitchen tissue", quantity: 1, unit: "pack"))
        try ctx.save()

        let snapshot = try SnapshotExporter.makeSnapshot(context: ctx, deviceName: "A")
        #expect(snapshot.pantryItems.count == 1)

        let forbidden = ["symbol", "icon", "color", "colour"]
        for dto in snapshot.pantryItems {
            for child in Mirror(reflecting: dto).children {
                guard let label = child.label?.lowercased() else { continue }
                for token in forbidden {
                    #expect(!label.contains(token), "PantryItemDTO gained an icon field: \(label)")
                }
            }
        }

        // Byte-level backstop: even a hand-rolled `encode(to:)` could not sneak a key past this.
        let data = try SnapshotCodec.encode(snapshot)
        let json = String(decoding: data, as: UTF8.self).lowercased()
        for token in forbidden {
            #expect(!json.contains("\"\(token)"), "canonical snapshot bytes contain a '\(token)' key")
        }
        // And no symbol string from the presentation table leaked into the payload either.
        for category in PantryCategory.allCases {
            #expect(
                !json.contains(category.presentation.symbol.lowercased()),
                "snapshot bytes contain the symbol for \(category.rawValue)"
            )
        }
    }

    @Test("The icon cache lives outside the model layer — classifying writes nothing to the store")
    func classificationDoesNotTouchTheModelStore() async throws {
        let schema = Schema(versionedSchema: SchemaV11.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = container.mainContext
        let item = PantryItem(name: "Kitchen tissue")
        ctx.insert(item)
        try ctx.save()
        let updatedAtBefore = item.updatedAt

        let (cache, suite) = Self.makeIsolatedCache("nomodelwrite")
        defer { Self.destroySuite(suite) }
        let fake = FakePantryIconClassifier()
        fake.result = .success(.paperDisposable)
        let resolver = PantryIconResolver(classifier: fake, cache: cache)
        await resolver.classifyIfNeeded(name: item.name)

        #expect(cache.category(forName: "kitchen tissue") == .paperDisposable)
        #expect(item.updatedAt == updatedAtBefore, "classification bumped the LWW clock — it would sync")
        #expect(!ctx.hasChanges, "classification made the model context dirty")
    }
}
