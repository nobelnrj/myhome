import SwiftUI
import SwiftData

/// Sheet for creating or editing a holding (ASSET-01, ASSET-02, ASSET-04, D-01/D-02).
///
/// Mirrors `EditAccountView`: NavigationStack-in-sheet, nil=create, non-nil=edit.
/// Conditional scheme row (Section 2) appears only for mutual_fund class.
/// Validation guards (T-11-09): abs(units) < 1_000_000 + abs(costBasisPerUnit) < 1_000_000_000.
///
/// Threat mitigations:
/// - T-11-09: units and costBasisPerUnit bounds enforced in isValid and saveAsset.
/// - T-11-10: All names displayed via plain Text() — never AttributedString(markdown:).
/// - T-11-SC: No third-party packages used.
struct EditAssetView: View {

    var asset: Asset?  // nil = create, non-nil = edit

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AMFINavService.self) private var amfiNavService
    @Environment(NPSNavService.self) private var npsNavService

    // MARK: - Form State

    @State private var name: String = ""
    @State private var assetClassRaw: String = "mutual_fund"
    @State private var amfiSchemeCode: String? = nil
    @State private var npsSchemeCode: String? = nil
    @State private var units: Decimal = 0
    @State private var costBasisPerUnit: Decimal = 0
    @State private var currentNAV: Decimal = 0
    @State private var navAsOfDate: Date = Date()
    @State private var nameError: String? = nil
    @State private var showDeleteConfirmation = false

    // MARK: - Computed

    private var totalCost: Decimal { units * costBasisPerUnit }

    private var selectedSchemeName: String? {
        guard let code = amfiSchemeCode else { return nil }
        return amfiNavService.schemeList.first { $0.code == code }?.name
    }

    // MARK: - Validation (T-11-09)

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        units > 0 &&
        abs(units) < 1_000_000 &&
        abs(costBasisPerUnit) < 1_000_000_000
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Section 1 — Identity
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Holding name", text: $name)
                            .font(.body)
                            .frame(minHeight: 44)
                        if let error = nameError {
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(DesignTokens.negative)
                        }
                    }

                    Picker("Asset Class", selection: $assetClassRaw) {
                        Text("Mutual Fund").tag("mutual_fund")
                        Text("Stock").tag("stock")
                        Text("NPS").tag("nps")
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: Section 2 — MF Scheme (conditional)
                if assetClassRaw == "mutual_fund" {
                    Section("Scheme") {
                        NavigationLink(destination: AMFISchemePickerView(
                            selectedSchemeCode: $amfiSchemeCode,
                            amfiNavService: amfiNavService
                        )) {
                            HStack {
                                Text("Scheme")
                                    .font(.body)
                                    .foregroundStyle(DesignTokens.label)
                                Spacer()
                                if let name = selectedSchemeName {
                                    Text(name)  // T-11-10: plain Text — no AttributedString
                                        .font(.body)
                                        .foregroundStyle(DesignTokens.label2)
                                        .lineLimit(1)
                                } else {
                                    Text("Tap to choose a scheme")
                                        .font(.body)
                                        .foregroundStyle(DesignTokens.label2)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                    }
                }

                // MARK: Section 2b — NPS Scheme (conditional on nps class)
                if assetClassRaw == "nps" {
                    Section("NPS Scheme") {
                        NavigationLink(destination: NPSSchemePickerView(
                            selectedSchemeCode: $npsSchemeCode,
                            npsNavService: npsNavService
                        )) {
                            HStack {
                                Text("NPS Scheme")
                                    .font(.body)
                                    .foregroundStyle(DesignTokens.label)
                                Spacer()
                                if let code = npsSchemeCode {
                                    Text(code)  // T-11-10: plain Text — no AttributedString
                                        .font(.body)
                                        .foregroundStyle(DesignTokens.label2)
                                        .lineLimit(1)
                                } else {
                                    Text("Tap to choose a scheme")
                                        .font(.body)
                                        .foregroundStyle(DesignTokens.label2)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                    }
                }

                // MARK: Section 2c — SIP (edit mode only — SIP requires a persisted Asset.id)
                if asset != nil {
                    Section("SIP") {
                        NavigationLink("Configure SIP", destination: SIPSetupView(asset: asset!))
                            .frame(minHeight: 44)
                    }
                }

                // MARK: Section 3 — Units & Cost
                Section("Units & Cost") {
                    HStack {
                        Text("Units")
                            .font(.body)
                        Spacer()
                        TextField("0", value: $units, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.body)
                    }
                    .frame(minHeight: 44)

                    HStack {
                        Text("Cost per unit")
                            .font(.body)
                        Spacer()
                        TextField("0", value: $costBasisPerUnit, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.body)
                    }
                    .frame(minHeight: 44)

                    HStack {
                        Text("Total cost")
                            .font(.body)
                            .foregroundStyle(DesignTokens.label2)
                        Spacer()
                        Text(totalCost.formattedINRWhole())
                            .font(.body)
                            .foregroundStyle(DesignTokens.label2)
                    }
                }

                // MARK: Section 4 — Current NAV / Price
                Section {
                    HStack {
                        Text(assetClassRaw == "mutual_fund" ? "Current NAV (auto-fetched)" : "Current price")
                            .font(.body)
                        Spacer()
                        TextField("0", value: $currentNAV, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.body)
                    }
                    .frame(minHeight: 44)

                    DatePicker("As of", selection: $navAsOfDate, displayedComponents: [.date])
                        .font(.body)

                    if assetClassRaw == "mutual_fund" && amfiSchemeCode != nil {
                        Text("NAV auto-updates daily from AMFI")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.label2)
                    }
                }

                // MARK: Section 5 — Danger Zone (edit mode only)
                if asset != nil {
                    Section {
                        Button("Delete Holding") {
                            showDeleteConfirmation = true
                        }
                        .foregroundStyle(DesignTokens.negative)
                        .frame(minHeight: 44)
                    }
                }
            }
            .navigationTitle(asset == nil ? "New Holding" : "Edit Holding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Holding") {
                        saveAsset()
                    }
                    .disabled(!isValid)
                    .tint(DesignTokens.accentText)
                }
            }
            .onAppear {
                if let a = asset {
                    name = a.name ?? ""
                    assetClassRaw = a.assetClassRaw ?? "mutual_fund"
                    amfiSchemeCode = a.amfiSchemeCode
                    npsSchemeCode = a.npsSchemeCode
                    units = a.units ?? 0
                    costBasisPerUnit = a.costBasisPerUnit ?? 0
                    currentNAV = a.currentNAV ?? 0
                    navAsOfDate = a.navAsOfDate ?? Date()
                }
            }
        }
        .confirmationDialog(
            "Delete Holding?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Holding", role: .destructive) {
                if let a = asset {
                    context.delete(a)
                    try? context.save()  // CR-01
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This holding will be permanently removed. This cannot be undone.")
        }
    }

    // MARK: - Save

    private func saveAsset() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            nameError = "Holding name cannot be empty."
            return
        }
        // T-11-09 / WR-01: saveAsset is the single source of truth — re-assert every bound
        // here, including positivity, so a programmatic/refactored path can't persist a
        // zero/negative holding or a negative cost basis (which inverts gain/loss math).
        guard units > 0, abs(units) < 1_000_000 else {
            nameError = "Units must be greater than 0 and less than 1,000,000."
            return
        }
        guard costBasisPerUnit >= 0, abs(costBasisPerUnit) < 1_000_000_000 else {
            nameError = "Cost per unit must be between ₹0 and ₹1,00,00,00,000."
            return
        }

        do {
            let target: Asset
            if let existing = asset {
                target = existing
            } else {
                target = Asset()
                context.insert(target)
            }

            target.name = trimmed
            target.assetClassRaw = assetClassRaw
            // T-11-09: clear scheme code for non-MF assets
            target.amfiSchemeCode = assetClassRaw == "mutual_fund" ? amfiSchemeCode : nil
            // T-11-09: clear NPS scheme code when class is switched away from nps
            target.npsSchemeCode = assetClassRaw == "nps" ? npsSchemeCode : nil
            target.units = units
            target.costBasisPerUnit = costBasisPerUnit
            target.currentNAV = currentNAV > 0 ? currentNAV : nil
            target.navAsOfDate = currentNAV > 0 ? navAsOfDate : nil

            try context.save()  // CR-01: explicit save
            nameError = nil
            dismiss()
        } catch {
            assertionFailure("Failed to save asset: \(error)")
        }
    }
}
