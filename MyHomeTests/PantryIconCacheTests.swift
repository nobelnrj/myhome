// PantryIconCacheTests.swift
// Phase 22 Plan 02, Task 1 — device-local pantry icon classification cache.
//
// Every test constructs its cache over its OWN UserDefaults suite name and tears the suite
// down afterwards. The LockSettingsTests precedent (a shared global UserDefaults key racing
// under Swift Testing parallelism) is exactly what this avoids: no two tests here ever touch
// the same suite, and none of them touches the real app group.
//
// Validation: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'
//             -parallel-testing-enabled NO -only-testing:MyHomeTests/PantryIconCacheTests

import Testing
import Foundation
@testable import MyHome

// MARK: - Suite Helper

/// Makes an isolated cache + a teardown closure that erases its backing suite.
///
/// Each caller passes a unique label so suites cannot bleed into one another even if the
/// runner is later switched back to parallel execution.
private func makeIsolatedCache(_ label: String) -> (cache: PantryIconCache, suiteName: String) {
    let suiteName = "test.pantryicon.\(label).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return (PantryIconCache(defaults: defaults), suiteName)
}

private func destroySuite(_ suiteName: String) {
    UserDefaults().removePersistentDomain(forName: suiteName)
}

// MARK: - PantryIconCacheTests

struct PantryIconCacheTests {

    // MARK: Normalisation

    @Test("A stored name is found again through the shared normalisation rule")
    func storeThenLookupIsNormalised() {
        let (cache, suite) = makeIsolatedCache("normalise")
        defer { destroySuite(suite) }

        cache.store(.dairy, forName: "  Milk  ")

        #expect(cache.category(forName: "milk") == .dairy)
        #expect(cache.category(forName: "MILK") == .dairy)
        #expect(cache.category(forName: " Milk ") == .dairy)
    }

    @Test("The cache key matches KitchenLogic's normalisation exactly")
    func keysAgreeWithKitchenLogic() {
        let (cache, suite) = makeIsolatedCache("agree")
        defer { destroySuite(suite) }

        cache.store(.grainStaple, forName: " Sona Masoori RICE ")
        let key = KitchenLogic.normalizedIconKey(forName: " Sona Masoori RICE ")

        #expect(key == "sona masoori rice")
        #expect(cache.category(forName: key) == .grainStaple)
    }

    // MARK: Misses

    @Test("An unknown name misses")
    func unknownNameReturnsNil() {
        let (cache, suite) = makeIsolatedCache("unknown")
        defer { destroySuite(suite) }

        #expect(cache.category(forName: "kitchen tissue") == nil)
    }

    @Test("Blank and nil names never hit and never occupy a slot")
    func blankNamesAreIgnored() {
        let (cache, suite) = makeIsolatedCache("blank")
        defer { destroySuite(suite) }

        cache.store(.dairy, forName: nil)
        cache.store(.dairy, forName: "")
        cache.store(.dairy, forName: "   ")

        #expect(cache.category(forName: nil) == nil)
        #expect(cache.category(forName: "") == nil)
        #expect(cache.category(forName: "   ") == nil)
        #expect(cache.count == 0)
    }

    // MARK: Tampered / stale persisted values (T-22-05)

    @Test("A persisted raw value that no longer names a category returns nil rather than crashing")
    func unrecognisedStoredRawValueReturnsNil() {
        let suiteName = "test.pantryicon.tampered.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { destroySuite(suiteName) }

        // Simulates a renamed category or a hand-edited defaults plist.
        defaults.set(["milk": "dairyProducts"], forKey: PantryIconCache.categoriesKey)
        defaults.set(["milk"], forKey: PantryIconCache.recencyKey)

        let cache = PantryIconCache(defaults: defaults)
        #expect(cache.category(forName: "milk") == nil)
    }

    // MARK: Cap + eviction (T-22-06)

    @Test("Storing 305 names leaves at most 300, evicting the 5 least recently stored")
    func capEvictsLeastRecentlyStored() {
        let (cache, suite) = makeIsolatedCache("cap")
        defer { destroySuite(suite) }

        for i in 0..<305 {
            cache.store(.other, forName: "item-\(i)")
        }

        #expect(cache.count <= PantryIconCache.maxEntries)
        #expect(cache.count == PantryIconCache.maxEntries)

        // The first five stored are the five gone.
        for i in 0..<5 {
            #expect(cache.category(forName: "item-\(i)") == nil)
        }
        // The sixth survives, as does the most recent.
        #expect(cache.category(forName: "item-5") == .other)
        #expect(cache.category(forName: "item-304") == .other)
    }

    @Test("Re-storing an existing name refreshes recency without growing the cache")
    func restoreRefreshesRecency() {
        let (cache, suite) = makeIsolatedCache("refresh")
        defer { destroySuite(suite) }

        for i in 0..<300 {
            cache.store(.other, forName: "item-\(i)")
        }
        #expect(cache.count == 300)

        // Touch the oldest entry — it becomes the newest, and the count is unchanged.
        cache.store(.dairy, forName: "item-0")
        #expect(cache.count == 300)
        #expect(cache.category(forName: "item-0") == .dairy)

        // One more distinct name now evicts item-1, NOT the just-refreshed item-0.
        cache.store(.spice, forName: "item-new")
        #expect(cache.count == 300)
        #expect(cache.category(forName: "item-0") == .dairy)
        #expect(cache.category(forName: "item-1") == nil)
        #expect(cache.category(forName: "item-new") == .spice)
    }

    @Test("Reading does not evict or reorder — rendering a row never writes")
    func readsDoNotMutate() {
        let (cache, suite) = makeIsolatedCache("readonly")
        defer { destroySuite(suite) }

        cache.store(.dairy, forName: "milk")
        cache.store(.eggs, forName: "eggs")
        let before = cache.count

        for _ in 0..<50 { _ = cache.category(forName: "milk") }

        #expect(cache.count == before)
        #expect(cache.category(forName: "eggs") == .eggs)
    }

    // MARK: Hygiene + persistence

    @Test("removeAll empties the cache")
    func removeAllEmpties() {
        let (cache, suite) = makeIsolatedCache("removeall")
        defer { destroySuite(suite) }

        cache.store(.dairy, forName: "milk")
        cache.store(.brew, forName: "filter coffee")
        #expect(cache.count == 2)

        cache.removeAll()

        #expect(cache.count == 0)
        #expect(cache.category(forName: "milk") == nil)
    }

    @Test("Two instances over the same defaults see each other's writes — persistence is real")
    func persistenceIsSharedAcrossInstances() {
        let suiteName = "test.pantryicon.shared.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { destroySuite(suiteName) }

        let writer = PantryIconCache(defaults: defaults)
        writer.store(.paperDisposable, forName: "Kitchen Tissue")

        let reader = PantryIconCache(defaults: defaults)
        #expect(reader.category(forName: "kitchen tissue") == .paperDisposable)
        #expect(reader.count == 1)
    }

    @Test("Every category round-trips through the persisted raw value")
    func allCategoriesRoundTrip() {
        let (cache, suite) = makeIsolatedCache("roundtrip")
        defer { destroySuite(suite) }

        for category in PantryCategory.allCases {
            cache.store(category, forName: "name-\(category.rawValue)")
        }
        for category in PantryCategory.allCases {
            #expect(cache.category(forName: "name-\(category.rawValue)") == category)
        }
    }
}
