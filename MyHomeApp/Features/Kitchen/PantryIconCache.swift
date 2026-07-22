import Foundation

/// Remembers which `PantryCategory` an item name was classified as, **on this device only**.
///
/// **ICON-03 — this cache is the ONLY place a classification is persisted.** `PantryItem` gains no
/// `symbolName`/`colorHex` field, `SchemaV11` does not change, and no sync DTO mentions icons. Icons
/// stay *derived*. The accepted consequence: two phones may briefly disagree about a tile until each
/// classifies the name locally. That is harmless and self-correcting — and it is a far better trade
/// than a schema bump plus a divergent, migrating, synced field for a cosmetic feature.
///
/// **Storage: App-Group `UserDefaults`** (`group.com.reojacob.myhome`), mirroring
/// `DismissedMessageStore`. Note that an App Group is *same-device* storage shared with extensions —
/// it is not cross-device sync. Deliberately NOT a SwiftData model: a SwiftData entity is exactly the
/// synced, migrating state ICON-03 forbids (P22-D3).
///
/// Two plain plist-safe values are written, no `Codable` and no archiver, matching the discipline of
/// the existing stores:
///   - `pantry_icon_categories`: `[String: String]` — normalised name → `PantryCategory.rawValue`
///   - `pantry_icon_recency`:    `[String]`         — the same keys, ordered oldest-first
///
/// **Capped at 300 entries** with least-recently-*stored* eviction (T-22-06). A household pantry is
/// tens of items, so the cap only ever bites on typo churn; it exists so a long-lived install cannot
/// grow `UserDefaults` without bound.
///
/// `defaults` is injectable so tests run against an isolated suite instead of stamping on the real
/// app group.
/// `@unchecked Sendable`: `UserDefaults` is not formally `Sendable` but is documented as
/// thread-safe, and the only stored property is an immutable reference to one. The struct holds no
/// mutable state of its own — every read and write goes straight through `defaults`.
struct PantryIconCache: @unchecked Sendable {

    /// Maximum number of remembered names. Exceeding it evicts from the oldest end of `recencyKey`.
    static let maxEntries = 300

    /// `internal` so tests can seed a deliberately-tampered persisted value (T-22-05).
    static let categoriesKey = "pantry_icon_categories"
    static let recencyKey = "pantry_icon_recency"

    let defaults: UserDefaults

    /// - Parameter defaults: defaults to the App Group suite, exactly as `DismissedMessageStore` does.
    init(defaults: UserDefaults = UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard) {
        self.defaults = defaults
    }

    // MARK: - Reads

    /// The remembered category for `name`, or `nil` when the name was never classified.
    ///
    /// Reading does NOT touch recency. Row rendering calls this on every draw, and a read that wrote
    /// back to `UserDefaults` would turn scrolling a pantry list into a stream of disk writes.
    ///
    /// **T-22-05:** the persisted string goes through `PantryCategory(rawValue:)`, so a renamed
    /// category or a hand-edited defaults plist yields `nil` — the caller then falls back to the
    /// keyword table. There is no force-unwrap and no crash path here.
    func category(forName name: String?) -> PantryCategory? {
        guard let key = KitchenLogic.normalizedIconKey(forName: name) else { return nil }
        guard let raw = categories()[key] else { return nil }
        return PantryCategory(rawValue: raw)
    }

    /// Number of remembered names. Exists for tests and for the cap assertions.
    var count: Int {
        categories().count
    }

    // MARK: - Writes

    /// Remembers `category` for `name`, refreshing the name's recency and enforcing the cap.
    ///
    /// A blank or `nil` name is a no-op, so an unnamed row can never occupy a cache slot.
    /// Re-storing an existing name moves it to the newest end without growing the entry count.
    func store(_ category: PantryCategory, forName name: String?) {
        guard let key = KitchenLogic.normalizedIconKey(forName: name) else { return }

        var map = categories()
        var recency = self.recency()

        map[key] = category.rawValue
        recency.removeAll { $0 == key }
        recency.append(key)

        // Evict from the oldest end until the map is back inside the cap (T-22-06).
        while map.count > Self.maxEntries, let oldest = recency.first {
            recency.removeFirst()
            map.removeValue(forKey: oldest)
        }

        defaults.set(map, forKey: Self.categoriesKey)
        defaults.set(recency, forKey: Self.recencyKey)
    }

    /// Forgets every remembered classification. Used for test hygiene and as a reset hook.
    func removeAll() {
        defaults.removeObject(forKey: Self.categoriesKey)
        defaults.removeObject(forKey: Self.recencyKey)
    }

    // MARK: - Internal

    private func categories() -> [String: String] {
        (defaults.dictionary(forKey: Self.categoriesKey) as? [String: String]) ?? [:]
    }

    private func recency() -> [String] {
        defaults.stringArray(forKey: Self.recencyKey) ?? []
    }
}
