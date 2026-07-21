// PantryIconResolverTests.swift
// Phase 22 Plan 03 — the non-blocking guarantee, in test form.
//
// The headline test is `synchronousPresentationNeverReachesTheModel`: it asserts the fake
// classifier's `callCount` is still 0 after a presentation lookup. That is a STRUCTURAL proof that
// the render path cannot reach inference — strictly stronger than timing a draw, which is what
// AI-SPEC §5.2 asks for ("list draws before classification completes").
//
// Every test builds its own resolver over an isolated `UserDefaults` suite. `PantryIconResolver.shared`
// is never touched: it wires the real App Group and the real on-device model.

import Testing
import Foundation
import SwiftUI
@testable import MyHome

@MainActor
struct PantryIconResolverTests {

    // MARK: - Fixtures

    /// A throwaway `UserDefaults` suite, so no test can see another's cache or the app group's.
    private func isolatedCache() -> PantryIconCache {
        let suite = "pantry-icon-resolver-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        return PantryIconCache(defaults: defaults)
    }

    private func makeResolver(
        classifier: PantryIconClassifying?,
        cache: PantryIconCache
    ) -> PantryIconResolver {
        PantryIconResolver(classifier: classifier, cache: cache)
    }

    // MARK: - ICON-03 / T-22-08: the render path cannot reach the model

    @Test("presentation() answers from the keyword table with the classifier never called (T-22-08)")
    func synchronousPresentationNeverReachesTheModel() {
        let fake = FakePantryIconClassifier()
        fake.result = .success(.paperDisposable)
        let resolver = makeResolver(classifier: fake, cache: isolatedCache())

        let tile = resolver.presentation(forName: "Milk")

        #expect(tile.symbol == PantryCategory.dairy.presentation.symbol)
        #expect(fake.callCount == 0)   // <- the non-blocking guarantee, structurally
    }

    @Test("An unknown name draws the neutral tile immediately on a cold cache")
    func unknownNameDrawsNeutralTileImmediately() {
        let fake = FakePantryIconClassifier()
        let resolver = makeResolver(classifier: fake, cache: isolatedCache())

        let tile = resolver.presentation(forName: "kitchen tissue")

        #expect(tile.symbol == PantryCategory.other.presentation.symbol)
        #expect(tile.symbol == "bag.fill")
        #expect(fake.callCount == 0)
    }

    // MARK: - Upgrade in place

    @Test("After classification the tile upgrades and the category is persisted in the cache")
    func classificationUpgradesTheTileAndWritesTheCache() async {
        let fake = FakePantryIconClassifier()
        fake.result = .success(.paperDisposable)
        let cache = isolatedCache()
        let resolver = makeResolver(classifier: fake, cache: cache)

        #expect(resolver.presentation(forName: "kitchen tissue").symbol == "bag.fill")

        await resolver.classifyIfNeeded(name: "kitchen tissue")

        #expect(resolver.presentation(forName: "kitchen tissue").symbol
                == PantryCategory.paperDisposable.presentation.symbol)
        #expect(cache.category(forName: "kitchen tissue") == .paperDisposable)
        #expect(fake.callCount == 1)
    }

    @Test("A pre-warmed cache is honoured synchronously and short-circuits classification (T-22-07)")
    func cacheHitShortCircuits() async {
        let fake = FakePantryIconClassifier()
        let cache = isolatedCache()
        cache.store(.paperDisposable, forName: "kitchen tissue")
        let resolver = makeResolver(classifier: fake, cache: cache)

        #expect(resolver.presentation(forName: "kitchen tissue").symbol
                == PantryCategory.paperDisposable.presentation.symbol)

        await resolver.classifyIfNeeded(name: "kitchen tissue")

        #expect(fake.callCount == 0)
    }

    @Test("A second classifyIfNeeded for an already-resolved name does not re-run inference")
    func alreadyResolvedNameIsNotReclassified() async {
        let fake = FakePantryIconClassifier()
        fake.result = .success(.cleaning)
        let resolver = makeResolver(classifier: fake, cache: isolatedCache())

        await resolver.classifyIfNeeded(name: "fabric softener")
        await resolver.classifyIfNeeded(name: "fabric softener")
        await resolver.classifyIfNeeded(name: "  Fabric Softener  ")   // same normalised key

        #expect(fake.callCount == 1)
    }

    // MARK: - Coalescing (T-22-07)

    @Test("Ten concurrent classifications of one name collapse to a single inference")
    func concurrentCallsCoalesceToOneInference() async {
        let fake = FakePantryIconClassifier()
        fake.result = .success(.paperDisposable)
        let resolver = makeResolver(classifier: fake, cache: isolatedCache())

        var tasks: [Task<Void, Never>] = []
        for _ in 0..<10 {
            tasks.append(Task { await resolver.classifyIfNeeded(name: "kitchen tissue") })
        }
        for task in tasks { await task.value }

        #expect(fake.callCount == 1)
        #expect(resolver.presentation(forName: "kitchen tissue").symbol
                == PantryCategory.paperDisposable.presentation.symbol)
    }

    // MARK: - Degradation

    @Test("A throwing classifier leaves the keyword tile, writes nothing, and does not propagate")
    func throwingClassifierFallsBackAndWritesNothing() async {
        let fake = FakePantryIconClassifier()
        fake.result = .failure(FakeClassificationError.guardrailViolation)
        let cache = isolatedCache()
        let resolver = makeResolver(classifier: fake, cache: cache)

        await resolver.classifyIfNeeded(name: "kitchen tissue")   // no `try` — non-throwing by design

        #expect(resolver.presentation(forName: "kitchen tissue").symbol == "bag.fill")
        #expect(cache.category(forName: "kitchen tissue") == nil)
        #expect(cache.count == 0)
    }

    @Test("A keyword-known name keeps its keyword tile when classification throws")
    func throwingClassifierKeepsKeywordTile() async {
        let fake = FakePantryIconClassifier()
        fake.result = .failure(FakeClassificationError.guardrailViolation)
        let resolver = makeResolver(classifier: fake, cache: isolatedCache())

        await resolver.classifyIfNeeded(name: "milk")

        #expect(resolver.presentation(forName: "milk").symbol
                == PantryCategory.dairy.presentation.symbol)
    }

    @Test("Model unavailable (nil classifier) makes classification a no-op and keeps the keyword tile")
    func modelUnavailableDegradesToKeywordTable() async {
        let cache = isolatedCache()
        let resolver = makeResolver(classifier: nil, cache: cache)

        await resolver.classifyIfNeeded(name: "kitchen tissue")

        #expect(resolver.presentation(forName: "milk").symbol
                == PantryCategory.dairy.presentation.symbol)
        #expect(resolver.presentation(forName: "kitchen tissue").symbol == "bag.fill")
        #expect(cache.count == 0)
    }

    // MARK: - Blank names

    @Test("Blank, whitespace-only and nil names never classify and always draw the neutral tile",
          arguments: [String?.none, "", "   ", "\n\t"])
    func blankNamesNeverClassify(name: String?) async {
        let fake = FakePantryIconClassifier()
        fake.result = .success(.paperDisposable)
        let cache = isolatedCache()
        let resolver = makeResolver(classifier: fake, cache: cache)

        #expect(resolver.presentation(forName: name).symbol == "bag.fill")

        await resolver.classifyIfNeeded(name: name)

        #expect(fake.callCount == 0)
        #expect(cache.count == 0)
    }

    // MARK: - Cancellation

    @Test("A cancelled classification writes no partial result")
    func cancellationWritesNothing() async {
        let fake = FakePantryIconClassifier()
        fake.result = .success(.paperDisposable)
        let cache = isolatedCache()
        let resolver = makeResolver(classifier: fake, cache: cache)

        let task = Task { await resolver.classifyIfNeeded(name: "kitchen tissue") }
        task.cancel()
        await task.value

        #expect(cache.category(forName: "kitchen tissue") == nil)
        #expect(resolver.presentation(forName: "kitchen tissue").symbol == "bag.fill")
    }

    // MARK: - Normalisation parity

    @Test("Case and padding variants share one classification (one inference per distinct name)")
    func normalisationIsSharedWithTheCache() async {
        let fake = FakePantryIconClassifier()
        fake.result = .success(.paperDisposable)
        let cache = isolatedCache()
        let resolver = makeResolver(classifier: fake, cache: cache)

        await resolver.classifyIfNeeded(name: "Kitchen Tissue")

        #expect(fake.callCount == 1)
        #expect(resolver.presentation(forName: "  kitchen tissue ").symbol
                == PantryCategory.paperDisposable.presentation.symbol)
        #expect(cache.count == 1)
    }
}
