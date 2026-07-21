// PantryIconResolver.swift
// Phase 22 Plan 03 — the async seam AI-SPEC §4.4 calls "the real work" of the phase.
//
// `KitchenLogic.icon(forName:)` is a synchronous pure function called during row rendering.
// Inference is async. This type bridges the two, and the bridge has one hard rule:
//
//   **`presentation` is synchronous and structurally cannot reach the classifier.**
//
// It is not `async`, it contains no `await`, and it holds no reference to the classifier in its
// call graph. A pantry row therefore draws a real tile the instant the list appears, on every
// device, with Apple Intelligence on, off, ineligible or still downloading. `classifyIfNeeded`
// runs separately, in a `.task` the row does not await, and upgrades the tile in place when it
// lands — no spinner, no placeholder, no layout shift (AI-SPEC §4.4).
//
// Pinned by `PantryIconResolverTests.synchronousPresentationNeverReachesTheModel`, which asserts
// the fake classifier's `callCount` is still 0 after a presentation lookup (T-22-08).

import SwiftUI
import FoundationModels

/// Resolves the icon tile for a pantry item name: instantly from cache-or-keywords, then better
/// from the on-device model.
///
/// **P22-D4 — lazy, not eager.** Classification is triggered on first *render* of a row, never on
/// item creation. Eager classification would miss every item that arrives by sync import or that
/// already sits in SchemaV11 on the device, and would put inference on the item-save path. Lazy
/// triggering also makes the non-blocking guarantee the default rather than something engineered.
///
/// **P22-D6 — one shared instance, read directly in `body`.** `@Observable` tracks any property
/// read during body evaluation, so no `@Environment` plumbing is needed; and one instance across
/// both the pantry list and the shopping list means a name appearing in both is classified once.
/// Tests construct their own instance with an injected fake classifier and an isolated cache.
///
/// **ICON-03.** Nothing here touches `PantryItem`, `SchemaV11` or any sync DTO. The only thing
/// persisted is the device-local `PantryIconCache`.
@MainActor
@Observable
final class PantryIconResolver {

    /// The app-wide instance both rows read.
    ///
    /// Availability is decided ONCE here, at construction — not per row and not per render.
    static let shared = PantryIconResolver(classifier: PantryIconResolver.makeSystemClassifier())

    /// `nil` means "no on-device model" — pre-iOS-26, ineligible device, Apple Intelligence off, or
    /// the model still downloading. Every one of those collapses to the same behaviour: the keyword
    /// tile, forever, with no inference attempted. Tests use `nil` to exercise that path without a
    /// device.
    @ObservationIgnored private let classifier: PantryIconClassifying?

    @ObservationIgnored private let cache: PantryIconCache

    /// Name key → category, mirroring the cache in memory so a scroll never re-reads `UserDefaults`.
    ///
    /// **`@ObservationIgnored` deliberately.** `presentation` memoises cache hits into this map, and
    /// `presentation` is called *during view body evaluation*. An observed mutation there would be a
    /// "modifying state during view update" write-back. The observed signal is `revision` instead,
    /// which only classification bumps — see below.
    @ObservationIgnored private var resolved: [String: PantryCategory] = [:]

    /// The one observed property. Read by `presentation` (so every row that draws a tile subscribes)
    /// and bumped only when a classification lands, which is exactly when a row must redraw.
    private var revision: Int = 0

    /// Keys currently being classified, for coalescing (T-22-07). Needs no lock: the class is
    /// `@MainActor`, so every touch happens on the main actor.
    @ObservationIgnored private var inFlight: Set<String> = []

    /// - Parameters:
    ///   - classifier: `nil` to model an unavailable on-device model.
    ///   - cache: injectable so tests run against an isolated `UserDefaults` suite.
    init(classifier: PantryIconClassifying?, cache: PantryIconCache = PantryIconCache()) {
        self.classifier = classifier
        self.cache = cache
    }

    /// Builds the production classifier, or `nil` when the on-device model cannot be used.
    ///
    /// Mirrors the shipped `#available(iOS 26, *)` + runtime-availability pattern from
    /// `AnalyticsView`/`InsightService`: the compile-time gate keeps the file building at the
    /// iOS 17 deployment target, the runtime check covers ineligible devices and disabled
    /// Apple Intelligence.
    private static func makeSystemClassifier() -> PantryIconClassifying? {
        if #available(iOS 26, *) {
            if isPantryIconClassificationAvailable(SystemLanguageModel.default.availability) {
                return FoundationModelsPantryIconClassifier()
            }
        }
        return nil
    }

    // MARK: - Synchronous presentation (the render path)

    /// The tile to draw for `rawName`, RIGHT NOW.
    ///
    /// Resolution order, per AI-SPEC §4.2:
    /// `in-memory` → `cache` → `KitchenLogic.keywordCategory` → `.other` (neutral `bag.fill`).
    ///
    /// Never `async`, never `await`, never calls the classifier, and never returns an empty tile.
    func presentation(forName rawName: String?) -> (symbol: String, color: Color) {
        _ = revision   // subscribe: a landed classification must redraw this row
        return category(forName: rawName).presentation
    }

    /// Convenience so the row call sites stay one line.
    func presentation(for item: PantryItem) -> (symbol: String, color: Color) {
        presentation(forName: item.name)
    }

    private func category(forName rawName: String?) -> PantryCategory {
        guard let key = KitchenLogic.normalizedIconKey(forName: rawName) else { return .other }
        if let known = resolved[key] { return known }
        if let cached = cache.category(forName: key) {
            resolved[key] = cached   // memoise; unobserved, so this is safe mid-body
            return cached
        }
        return KitchenLogic.keywordCategory(forName: key) ?? .other
    }

    // MARK: - Asynchronous upgrade

    /// Classifies `rawName` if it has not been classified before, then upgrades the tile in place.
    ///
    /// **Non-throwing by design**, so no call site needs a `try` and no view has an error to handle:
    /// a failed classification simply means the keyword tile stays (AI-SPEC §4.2). Every error is
    /// swallowed here — `GenerationError.guardrailViolation`, `.exceededContextWindowSize`,
    /// `CancellationError`, anything. `FoundationModelsPantryIconClassifier` deliberately does not
    /// catch; this is where catch-and-fall-back lives.
    ///
    /// Returns immediately (T-22-07: one inference per distinct name per device) when the name is
    /// blank, the model is unavailable, the key is already resolved or cached, or the key is
    /// already in flight — so recycling rows during a scroll costs nothing.
    func classifyIfNeeded(name rawName: String?) async {
        guard let key = KitchenLogic.normalizedIconKey(forName: rawName) else { return }
        guard let classifier else { return }          // model unavailable → keyword tile forever
        guard resolved[key] == nil else { return }
        if let cached = cache.category(forName: key) {
            resolved[key] = cached
            return
        }
        guard !inFlight.contains(key) else { return } // coalesce concurrent rows on one name

        inFlight.insert(key)
        defer { inFlight.remove(key) }

        do {
            // The normalised key is what goes to the model, matching what gets cached — so a cache
            // hit and a classification can never disagree about which name was asked about.
            let category = try await classifier.classify(name: key)
            guard !Task.isCancelled else { return }   // no partial write on a superseded row
            cache.store(category, forName: key)
            resolved[key] = category
            revision &+= 1                            // the observed mutation that redraws the row
        } catch {
            // Deliberately silent: the keyword-or-neutral tile is already on screen and stays.
        }
    }
}
