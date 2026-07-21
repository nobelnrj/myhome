// PantryIconClassifier.swift
// Phase 22: Pantry Icon Intelligence — the on-device classification seam (ICON-01).
//
// Follows MyHomeApp/Support/InsightService.swift, the working FoundationModels reference in this
// repo: availability switch, guided generation over a CLOSED @Generable type, a FRESH
// LanguageModelSession per call, and error routing left to the caller.
//
// Security (T-22-04): `SystemLanguageModel` is entirely on-device. There is no `URLSession` and no
// network entitlement anywhere in this feature, and nothing in this file persists anything — the
// only place a classification is remembered is `PantryIconCache` (device-local, unsynced).

import Foundation
import FoundationModels

// MARK: - PantryIconClassifying

/// The single testability seam for pantry icon classification.
///
/// `LanguageModelSession` is `final` — it cannot be subclassed or mocked — so every caller depends
/// on this protocol instead, exactly as Phase 16 hid generation behind `InsightGenerating`.
///
/// **Deliberately carries no `@available` gate.** It traffics only in the plain, ungated
/// `PantryCategory`, so 22-03's resolver and its tests compile and run on any OS the app supports
/// and never need an Apple-Intelligence device.
///
/// - Throws: `LanguageModelSession.GenerationError` on guardrail/context-window failure.
/// - Throws: `CancellationError` when the enclosing task is cancelled.
protocol PantryIconClassifying: Sendable {
    func classify(name: String) async throws -> PantryCategory
}

// MARK: - GeneratedPantryCategory (the @Generable twin — P22-D2)

/// The model-facing mirror of `PantryCategory`.
///
/// **Why a second enum.** `@Generable` cannot be applied conditionally, and it drags
/// `@available(iOS 26, *)` through every type that so much as mentions the annotated type. Gating
/// `PantryCategory` itself would gate the keyword-fallback path — the one path that must keep working
/// with Apple Intelligence switched off. So the guided-generation type is an iOS-26-only twin that
/// maps 1:1 back onto the plain enum.
///
/// **Cases and raw values must stay identical to `PantryCategory`.** The thing keeping the twins
/// honest is `PantryIconClassifierTests.generatedTwinMatchesPantryCategory` — adding a category to
/// one enum and forgetting the other is a test failure rather than a silently unreachable category.
@available(iOS 26, *)
@Generable(description: "The kind of household item a pantry entry refers to")
enum GeneratedPantryCategory: String, CaseIterable {
    case dairy = "dairy"
    case eggs = "eggs"
    case grainStaple = "grainStaple"
    case spice = "spice"
    case produce = "produce"
    case fruit = "fruit"
    case brew = "brew"
    case oilFat = "oilFat"
    case snackBakery = "snackBakery"
    case beverage = "beverage"
    case cleaning = "cleaning"
    case paperDisposable = "paperDisposable"
    case personalCare = "personalCare"
    case condiment = "condiment"
    case frozen = "frozen"
    case petSupplies = "petSupplies"
    case other = "other"

    /// The plain-enum equivalent. Non-nil for every case while the parity test passes.
    var asPantryCategory: PantryCategory? {
        PantryCategory(rawValue: rawValue)
    }
}

// MARK: - PantryIconPromptBuilder

/// Builds the (deliberately tiny) prompt for a single item-name classification.
///
/// **The item name is UNTRUSTED user free text** (AI-SPEC §5.3, T-22-03). It is treated strictly as
/// data to be classified, never as instructions. The defence is structural rather than textual: the
/// output type is a closed `@Generable` enum, so an injected "ignore previous instructions" cannot
/// produce anything except one of the 17 categories or an error. At worst an attacker changes which
/// of 17 icons is drawn on their own phone.
///
/// **Nothing but the name goes in** (T-22-04): no quantity, no unit, no other pantry row, no
/// financial context, no household data of any kind.
@available(iOS 26, *)
enum PantryIconPromptBuilder {

    /// Longest item-name fragment allowed into a prompt. A household item name is a few words; the
    /// cap exists so a pathological paste cannot dominate the context window.
    static let maxNameLength = 80

    /// System instructions injected into every `LanguageModelSession`.
    static let systemInstructions: String = """
        You classify a single household pantry item name into one of the given categories. \
        Pick the single best fit for the item as a household would shop for it. \
        If the name is empty, meaningless, or does not fit any other category, answer other.
        """

    /// Wraps the trimmed, truncated name in a minimal instruction.
    ///
    /// The name is the ONLY datum injected.
    static func buildPrompt(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = String(trimmed.prefix(maxNameLength))
        return "Classify this household pantry item name: \(safeName)"
    }
}

// MARK: - FoundationModelsPantryIconClassifier

/// Production implementation of `PantryIconClassifying`, backed by the on-device system model.
///
/// Creates a FRESH `LanguageModelSession` per call (Phase 16 Pitfall 3): no transcript carryover
/// between items, so classifying "milk" cannot colour the classification of the next row.
///
/// Does NOT catch `LanguageModelSession.GenerationError` — `.guardrailViolation` and
/// `.exceededContextWindowSize` propagate to the caller. The 22-03 resolver owns catch-and-fall-back
/// to the keyword table, mirroring how `InsightService` leaves error routing to its caller.
@available(iOS 26, *)
final class FoundationModelsPantryIconClassifier: PantryIconClassifying {

    func classify(name: String) async throws -> PantryCategory {
        // Fresh session per call — no transcript contamination between items.
        let session = LanguageModelSession(
            instructions: PantryIconPromptBuilder.systemInstructions
        )
        let prompt = PantryIconPromptBuilder.buildPrompt(for: name)
        let response = try await session.respond(
            to: prompt,
            generating: GeneratedPantryCategory.self
        )
        // `asPantryCategory` is non-nil while the parity test passes; `.other` is the structural
        // belt-and-braces so a future twin drift degrades to the neutral tile rather than crashing.
        return response.content.asPantryCategory ?? .other
    }
}

// MARK: - Availability Helper

/// Returns `true` only when the on-device model is usable for icon classification.
///
/// Same shape as `isInsightAvailable`: the inner switch is exhaustive over all three
/// `UnavailableReason` cases plus `@unknown default`, so a future SDK reason surfaces as a compile
/// warning rather than silently falling through a `default:`.
///
/// Every `false` branch means the same thing to the caller: fall back to the keyword table.
@available(iOS 26, *)
func isPantryIconClassificationAvailable(_ availability: SystemLanguageModel.Availability) -> Bool {
    switch availability {
    case .available:
        return true
    case .unavailable(let reason):
        switch reason {
        case .deviceNotEligible:
            return false
        case .appleIntelligenceNotEnabled:
            return false
        case .modelNotReady:
            return false
        @unknown default:
            return false
        }
    }
}
