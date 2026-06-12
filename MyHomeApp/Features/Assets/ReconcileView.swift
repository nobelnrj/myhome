import SwiftUI
import SwiftData

/// Whole-holding total-units overwrite screen (D-05).
///
/// Lets the user enter the authoritative total units from their latest statement,
/// which overwrites `Asset.units` (the running accrual estimate). Prior Contribution
/// rows are never deleted — they remain as history.
///
/// Mirrors `EditAssetView`: NavigationStack-in-sheet, validated save, Cancel/Confirm toolbar.
///
/// Threat mitigations:
/// - T-115-01: `parseReconciledUnits` returns nil for non-numeric/empty/<=0; Save disabled; `reconcile()` guards.
/// - T-115-02: `reconcile()` only sets `asset.units`; Contribution rows are never deleted/mutated.
/// - T-11-10: All display via plain `Text()` — never AttributedString(markdown:).
struct ReconcileView: View {

    var asset: Asset

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    // MARK: - Form State

    @State private var unitsText: String = ""

    // MARK: - Computed

    /// Parses and validates the text field input.
    /// Returns nil for empty, non-numeric, zero, or negative input (T-115-01).
    var reconciledUnits: Decimal? {
        ReconcileView.parseReconciledUnits(unitsText)
    }

    /// True only when the parsed units are non-nil and > 0 (Save gate — T-115-01).
    var isValid: Bool {
        reconciledUnits != nil
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Section 1 — Instruction
                Section {
                    Text("Enter the total units shown on your latest statement — this overwrites the running estimate.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                }

                // MARK: Section 2 — Units Input
                Section("Authoritative Units") {
                    // Current estimate for reference (T-11-10: plain Text)
                    if let current = asset.units {
                        HStack {
                            Text("Current estimate")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(formattedUnits(current))
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44)
                    }

                    HStack {
                        Text("Statement total units")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        TextField("0.0000", text: $unitsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.body)
                            .frame(minHeight: 44)
                    }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle("Reconcile Units")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm Units") {
                        reconcile()
                    }
                    .disabled(!isValid)
                    .tint(.accentColor)
                }
            }
            .onAppear {
                // Pre-fill with the current asset.units so the user edits the authoritative figure
                if let current = asset.units {
                    let formatter = NumberFormatter()
                    formatter.numberStyle = .decimal
                    formatter.maximumFractionDigits = 4
                    formatter.minimumFractionDigits = 0
                    formatter.usesGroupingSeparator = false
                    unitsText = formatter.string(from: current as NSDecimalNumber) ?? "\(current)"
                }
            }
        }
    }

    // MARK: - Reconcile

    private func reconcile() {
        guard let units = reconciledUnits, units > 0 else { return }
        do {
            asset.units = units                     // D-05: whole-holding total-units overwrite
            // Contribution log entries are NOT deleted — estimates stay as history (D-05, T-115-02)
            try context.save()                      // CR-01: explicit save
            dismiss()
        } catch {
            assertionFailure("Failed to reconcile: \(error)")
        }
    }

    // MARK: - Static helpers (unit-testable without a view instance)

    /// Parses a decimal string and returns the Decimal only when it is non-nil and > 0.
    /// Returns nil for empty string, non-numeric input, zero, or negative values (T-115-01).
    ///
    /// Extracted as a static func so it can be called directly from unit tests without
    /// constructing a view (mirrors `SIPSetupView.validate` and `SIPSetupView.nextInstallmentDate`).
    static func parseReconciledUnits(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Decimal(string: trimmed) else { return nil }
        guard value > 0 else { return nil }
        return value
    }

    // MARK: - Formatting helpers

    private func formattedUnits(_ units: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        return formatter.string(from: units as NSDecimalNumber) ?? "\(units)"
    }
}
