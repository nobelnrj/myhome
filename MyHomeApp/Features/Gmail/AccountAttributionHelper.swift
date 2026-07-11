import Foundation

/// Pure helper for mapping a parsed sourceLabel (from a bank email) to an Account UUID.
///
/// Design (D-05, STAB-02):
/// - Operates on plain `[Account]` values — no @Model refs held.
/// - All outputs are `UUID` scalars — safe to capture before an `await` suspension.
/// - Excludes archived accounts (T-09-09 / Pitfall 6).
///
/// Account aliasing (D-MERGE-01):
/// One real-world balance can be reached through several ingestion identities — e.g. a
/// savings account *and* its debit card, or the same account masked as `••843` in one email
/// and `••6843` in another. To roll these into one balance without a schema migration, an
/// Account's `sourceLabel` may hold MULTIPLE aliases separated by `\n`. Every alias resolves
/// to the same account id, so future emails from any identity attribute to one account.
/// `AccountMerger` writes these multi-line sourceLabels; this helper reads them.
///
/// Usage in GmailSyncController.syncAccount (pre-loop capture pattern):
/// ```swift
/// let accounts = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
/// let accountIDsByLabel = AccountAttributionHelper.buildAccountIDsByLabel(from: accounts)
/// // … inside per-message loop:
/// if let label = parsed.rawSourceLabel {
///     expense.accountID = AccountAttributionHelper.accountID(forSourceLabel: label, in: accountIDsByLabel)
///         ?? AccountAttributionHelper.accountIDBySuffix(forSourceLabel: label, accounts: accounts)
/// }
/// ```
enum AccountAttributionHelper {

    /// Delimiter separating aliases packed into a single `Account.sourceLabel`.
    static let aliasSeparator = "\n"

    // MARK: - Alias plumbing (D-MERGE-01)

    /// The list of distinct, non-empty aliases packed into an account's `sourceLabel`.
    ///
    /// A single-identity account returns a one-element list; a merged account returns all
    /// its absorbed identities. Order is first-seen. Returns `[]` when `sourceLabel` is nil.
    static func aliases(of account: Account) -> [String] {
        aliases(fromSourceLabel: account.sourceLabel)
    }

    /// Splits a raw `sourceLabel` string into its alias list (trimmed, de-duplicated, order-stable).
    static func aliases(fromSourceLabel sourceLabel: String?) -> [String] {
        guard let sourceLabel else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for piece in sourceLabel.components(separatedBy: aliasSeparator) {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted { result.append(trimmed) }
        }
        return result
    }

    /// Packs an alias list back into a single `sourceLabel` string (de-duplicated, order-stable).
    /// Returns `nil` when the resulting list is empty so the field stays nil for label-less accounts.
    static func sourceLabel(fromAliases aliases: [String]) -> String? {
        var seen = Set<String>()
        var result: [String] = []
        for alias in aliases {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted { result.append(trimmed) }
        }
        return result.isEmpty ? nil : result.joined(separator: aliasSeparator)
    }

    // MARK: - Label → accountID map

    /// Builds a `[String: UUID]` lookup keyed by each `sourceLabel` alias and lowercased `name`
    /// for every non-archived account.
    ///
    /// Precedence (highest first):
    /// 1. Each `sourceLabel` alias (exact, case-sensitive) — bank-supplied keys.
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
            // Each sourceLabel alias overrides name for the same key (higher-priority exact match)
            for alias in aliases(of: account) {
                map[alias] = account.id
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

    // MARK: - Suffix matching (D-MERGE-02: ••843 vs ••6843)

    /// Splits a bank label into a non-digit prefix and its trailing digit run, e.g.
    /// `"ICICI CC ••5005"` → `(prefix: "icici cc", digits: "5005")`.
    ///
    /// The prefix is lowercased and stripped of the masking marker (`•`, `*`, `x`, `X`) and
    /// surrounding whitespace so it can be compared across emails. Returns `nil` when the label
    /// has no trailing digits (nothing to suffix-match on).
    static func labelIdentity(_ label: String) -> (prefix: String, digits: String)? {
        // Peel trailing digits off the end.
        var digits = ""
        var idx = label.endIndex
        while idx > label.startIndex {
            let prev = label.index(before: idx)
            let ch = label[prev]
            if ch.isNumber { digits.insert(ch, at: digits.startIndex); idx = prev } else { break }
        }
        guard !digits.isEmpty else { return nil }

        let rawPrefix = String(label[label.startIndex..<idx])
        // Drop masking glyphs and collapse whitespace so "ICICI ••" == "icici xx".
        let cleaned = rawPrefix
            .lowercased()
            .replacingOccurrences(of: "•", with: " ")
            .replacingOccurrences(of: "*", with: " ")
            .replacingOccurrences(of: "x", with: " ")
        let prefix = cleaned.split { $0 == " " || $0 == "\t" }.joined(separator: " ")
        return (prefix, digits)
    }

    /// Minimum overlap length for two masked account numbers to be considered the same account.
    /// `843` (last-3) vs `6843` (last-4) overlap on 3 digits; a 2-digit tail like `••45` is too
    /// weak to safely merge, so require at least 3.
    static let minSuffixOverlap = 3

    /// Two masked numbers refer to the same account when the same institution reports them and
    /// one is a suffix of the other with at least `minSuffixOverlap` shared trailing digits.
    static func digitsMatchBySuffix(_ a: String, _ b: String) -> Bool {
        guard a != b else { return true }
        let shorter = a.count <= b.count ? a : b
        let longer = a.count <= b.count ? b : a
        guard shorter.count >= minSuffixOverlap else { return false }
        return longer.hasSuffix(shorter)
    }

    /// A plain-value entry for suffix matching: one per non-archived account alias that carries a
    /// digit tail. Holds no `@Model` ref, so it is safe to capture before an `await` (STAB-02).
    struct SuffixIndexEntry: Equatable {
        let prefix: String
        let digits: String
        let id: UUID
    }

    /// Builds the value-typed suffix index from accounts, for use across an await boundary.
    static func buildSuffixIndex(from accounts: [Account]) -> [SuffixIndexEntry] {
        var index: [SuffixIndexEntry] = []
        for account in accounts where !account.isArchived {
            for alias in aliases(of: account) {
                guard let identity = labelIdentity(alias) else { continue }
                index.append(SuffixIndexEntry(prefix: identity.prefix, digits: identity.digits, id: account.id))
            }
        }
        return index
    }

    /// Resolves a label that failed exact/alias matching against a pre-built suffix index.
    ///
    /// Requires an identical institution prefix AND a suffix digit overlap, so it never merges a
    /// savings account with its debit card (different prefixes) — those go through `AccountMerger`.
    /// Returns `nil` when no account matches.
    static func accountIDBySuffix(forSourceLabel label: String, in index: [SuffixIndexEntry]) -> UUID? {
        guard let target = labelIdentity(label) else { return nil }
        for entry in index where entry.prefix == target.prefix && digitsMatchBySuffix(entry.digits, target.digits) {
            return entry.id
        }
        return nil
    }

    /// Resolves a label that failed exact/alias matching by comparing its institution prefix and
    /// masked digits against existing non-archived accounts (D-MERGE-02). This collapses the
    /// `••843` / `••6843` masking-variance duplicates at ingestion time without a manual merge.
    ///
    /// Convenience wrapper over the index-based resolver for synchronous callers that hold `[Account]`.
    static func accountIDBySuffix(forSourceLabel label: String, accounts: [Account]) -> UUID? {
        accountIDBySuffix(forSourceLabel: label, in: buildSuffixIndex(from: accounts))
    }

    // MARK: - unmatchedSourceLabels (07-07 auto-create)

    /// Returns the distinct, non-empty expense `sourceLabel`s that do not resolve to any existing
    /// account (07-07) — neither by exact/alias match nor by suffix match (D-MERGE-02). These are
    /// the labels a fresh device should auto-create accounts for so that per-account balances and
    /// transfer detection work without manual tagging.
    ///
    /// Two labels that suffix-match each other (e.g. `••843` and `••6843`) collapse to a single
    /// entry so auto-create spawns one account, not two.
    ///
    /// Order is first-seen (deterministic) so callers create accounts in a stable order.
    static func unmatchedSourceLabels(in expenses: [Expense], accounts: [Account]) -> [String] {
        let map = buildAccountIDsByLabel(from: accounts)
        var seen = Set<String>()
        // Identities of labels already chosen this pass, so intra-batch suffix dupes collapse.
        var chosen: [(prefix: String, digits: String)] = []
        var result: [String] = []
        for expense in expenses {
            guard let label = expense.sourceLabel, !label.isEmpty else { continue }
            if accountID(forSourceLabel: label, in: map) != nil { continue }
            if accountIDBySuffix(forSourceLabel: label, accounts: accounts) != nil { continue }

            // Collapse duplicates within this batch: exact-string, then suffix.
            if !seen.insert(label).inserted { continue }
            if let identity = labelIdentity(label),
               chosen.contains(where: { $0.prefix == identity.prefix && digitsMatchBySuffix($0.digits, identity.digits) }) {
                continue
            }
            if let identity = labelIdentity(label) { chosen.append(identity) }
            result.append(label)
        }
        return result
    }
}
