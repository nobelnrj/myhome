import Foundation

/// Pure helper for mapping a parsed sourceLabel (from a bank email) to an Account UUID.
///
/// Design (D-05, STAB-02):
/// - Operates on plain `[Account]` values — no @Model refs held.
/// - All outputs are `UUID` scalars — safe to capture before an `await` suspension.
/// - Excludes archived accounts (T-09-09 / Pitfall 6).
///
/// Usage in GmailSyncController.syncAccount (pre-loop capture pattern):
/// ```swift
/// let accounts = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
/// let accountIDsByLabel = AccountAttributionHelper.buildAccountIDsByLabel(from: accounts)
/// // … inside per-message loop:
/// if let label = parsed.rawSourceLabel {
///     expense.accountID = AccountAttributionHelper.accountID(forSourceLabel: label, in: accountIDsByLabel)
/// }
/// ```
enum AccountAttributionHelper {

    /// Builds a `[String: UUID]` lookup keyed by `sourceLabel` and lowercased `name`
    /// for every non-archived account.
    ///
    /// Precedence (highest first):
    /// 1. `sourceLabel` (exact, case-sensitive) — bank-supplied key set during migration.
    /// 2. `name.lowercased()` — fallback for manually-named accounts.
    ///
    /// Archived accounts are excluded (T-09-09).
    static func buildAccountIDsByLabel(from accounts: [Account]) -> [String: UUID] {
        var map: [String: UUID] = [:]
        for account in accounts where !account.isArchived {
            // Index by lowercased name as the baseline fallback
            if let name = account.name {
                map[name.lowercased()] = account.id
            }
            // sourceLabel overrides name for the same key (higher-priority exact match)
            if let label = account.sourceLabel {
                map[label] = account.id
            }
        }
        return map
    }

    /// Resolves `sourceLabel` to an account UUID using the pre-built map.
    ///
    /// Tries exact match first, then lowercased fallback.
    /// Returns `nil` when no active account matches (expense stays Unassigned, D-05).
    static func accountID(forSourceLabel label: String, in map: [String: UUID]) -> UUID? {
        map[label] ?? map[label.lowercased()]
    }
}
