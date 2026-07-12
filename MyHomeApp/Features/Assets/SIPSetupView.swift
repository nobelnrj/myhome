import SwiftUI
import SwiftData

/// Sheet for creating or editing a SIP (Systematic Investment Plan) definition for a holding.
///
/// Mirrors `EditAssetView`: NavigationStack-in-sheet, form fields, validation, save.
///
/// Features:
/// - Amount (Decimal), day-of-month (1...31), isActive Toggle (D-04)
/// - For NPS assets: three allocation % fields (E/C/G summing to 100, D-01) + strategy pickers
/// - Create: inserts a SIP + initial SIPAmountChange
/// - Edit: updates existing SIP; appends a NEW SIPAmountChange only when amount changed (D-07)
/// - Amount-change history is never rewritten — only new rows appended (D-07)
///
/// Threat mitigations:
/// - T-114-01: isValid enforced at Save button + saveSIP guard
/// - T-114-02: amount change appends a new SIPAmountChange effective next-installment (D-07)
/// - T-114-03: all displayed values via plain Text() — never AttributedString(markdown:)
struct SIPSetupView: View {

    var asset: Asset

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    // MARK: - Form state

    @State private var amount: Decimal = 0
    @State private var dayOfMonth: Int = 5
    @State private var isActive: Bool = true
    @State private var startDate: Date = Date()

    // NPS allocation fields (D-01)
    @State private var npsAllocationE: Int = 0
    @State private var npsAllocationC: Int = 0
    @State private var npsAllocationG: Int = 0

    // NPS strategy asset IDs (nil = not linked)
    @State private var npsAssetE: UUID? = nil
    @State private var npsAssetC: UUID? = nil
    @State private var npsAssetG: UUID? = nil

    // NPS asset picker — all NPS holdings available for strategy linking
    @Query(filter: #Predicate<Asset> { $0.assetClassRaw == "nps" }) private var npsAssets: [Asset]

    // Load existing active SIP for this asset (if any)
    @State private var activeSIP: SIP? = nil
    @State private var originalAmount: Decimal = 0

    // MARK: - Computed

    private var isNPS: Bool { asset.assetClassRaw == "nps" }

    /// T-114-01: amount > 0, dayOfMonth 1...31, nps allocation sums to 100 (D-01)
    var isValid: Bool {
        Self.validate(
            amount: amount,
            dayOfMonth: dayOfMonth,
            isNPS: isNPS,
            npsAllocationE: npsAllocationE,
            npsAllocationC: npsAllocationC,
            npsAllocationG: npsAllocationG
        )
    }

    /// Static pure validator — extracted for unit testing (SIPSetupValidationTests).
    /// T-114-01: amount > 0; dayOfMonth in 1...31; nps allocation E+C+G == 100 (each >= 0).
    static func validate(
        amount: Decimal,
        dayOfMonth: Int,
        isNPS: Bool,
        npsAllocationE: Int,
        npsAllocationC: Int,
        npsAllocationG: Int
    ) -> Bool {
        guard amount > 0 else { return false }
        guard dayOfMonth >= 1 && dayOfMonth <= 31 else { return false }
        if isNPS {
            guard npsAllocationE >= 0, npsAllocationC >= 0, npsAllocationG >= 0 else { return false }
            guard npsAllocationE + npsAllocationC + npsAllocationG == 100 else { return false }
        }
        return true
    }

    // MARK: - Next installment date (D-07, pure function — tested directly)

    /// Returns the first installment date on `dayOfMonth` that is strictly after `reference`.
    ///
    /// Uses IST Gregorian calendar; clamps dayOfMonth to the actual last day of each month
    /// (e.g. dayOfMonth 31 in February → Feb 28/29). Analogous to `elapsedInstallmentDates`
    /// in SIPAccrualService; the EDIT amount-change path sets `effectiveFrom` from this func.
    ///
    /// - Parameters:
    ///   - dayOfMonth: Desired installment day (1–31; clamped per month)
    ///   - reference: Exclusive lower bound — returned date must be strictly after this
    ///   - calendar: IST Gregorian calendar (caller supplies for testability)
    /// - Returns: The first installment date strictly after `reference`
    static func nextInstallmentDate(dayOfMonth: Int, after reference: Date, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month], from: reference)
        guard var year = comps.year, var month = comps.month else {
            // Fallback: return reference + 1 month (should never happen with a valid calendar)
            return calendar.date(byAdding: .month, value: 1, to: reference) ?? reference
        }

        // Safety: iterate at most 24 months to find the next installment date
        for _ in 0..<24 {
            let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
            let range = calendar.range(of: .day, in: .month, for: firstOfMonth)!
            let clampedDay = min(dayOfMonth, range.upperBound - 1)

            var candidateComps = DateComponents()
            candidateComps.year = year
            candidateComps.month = month
            candidateComps.day = clampedDay
            candidateComps.hour = 0
            candidateComps.minute = 0
            candidateComps.second = 0

            if let candidate = calendar.date(from: candidateComps), candidate > reference {
                return candidate
            }

            // Advance to next month
            month += 1
            if month > 12 {
                month = 1
                year += 1
            }
        }

        // Should never be reached; return reference + 1 month as last resort
        return calendar.date(byAdding: .month, value: 1, to: reference) ?? reference
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Section 1 — Core SIP fields
                Section("SIP Details") {
                    HStack {
                        Text("Monthly Amount")
                            .font(.body)
                        Spacer()
                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.body)
                    }
                    .frame(minHeight: 44)

                    Stepper("Day of Month: \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
                        .font(.body)
                        .frame(minHeight: 44)

                    DatePicker("Start Date", selection: $startDate, displayedComponents: [.date])
                        .font(.body)

                    Toggle("Active", isOn: $isActive)
                        .font(.body)
                        .frame(minHeight: 44)
                }

                // MARK: Section 2 — NPS Allocation (conditional)
                if isNPS {
                    Section {
                        HStack {
                            Text("Equity (E) %")
                                .font(.body)
                            Spacer()
                            TextField("0", value: $npsAllocationE, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(.body)
                        }
                        .frame(minHeight: 44)

                        HStack {
                            Text("Corporate Debt (C) %")
                                .font(.body)
                            Spacer()
                            TextField("0", value: $npsAllocationC, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(.body)
                        }
                        .frame(minHeight: 44)

                        HStack {
                            Text("Government Securities (G) %")
                                .font(.body)
                            Spacer()
                            TextField("0", value: $npsAllocationG, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(.body)
                        }
                        .frame(minHeight: 44)

                        let allocationSum = npsAllocationE + npsAllocationC + npsAllocationG
                        let sumColor: Color = allocationSum == 100 ? DesignTokens.label2 : DesignTokens.negative
                        Text("Total: \(allocationSum)% (must total 100%)")
                            .font(.caption)
                            .foregroundStyle(sumColor)
                    } header: {
                        Text("NPS Allocation")
                    }

                    // MARK: Section 3 — NPS Strategy Holdings
                    Section("NPS Strategy Holdings") {
                        Picker("Equity Holding", selection: $npsAssetE) {
                            Text("None").tag(UUID?.none)
                            ForEach(npsAssets) { a in
                                Text(a.name ?? a.id.uuidString)  // T-114-03: plain Text
                                    .tag(UUID?.some(a.id))
                            }
                        }
                        .frame(minHeight: 44)

                        Picker("Corp. Debt Holding", selection: $npsAssetC) {
                            Text("None").tag(UUID?.none)
                            ForEach(npsAssets) { a in
                                Text(a.name ?? a.id.uuidString)  // T-114-03: plain Text
                                    .tag(UUID?.some(a.id))
                            }
                        }
                        .frame(minHeight: 44)

                        Picker("Gov. Securities Holding", selection: $npsAssetG) {
                            Text("None").tag(UUID?.none)
                            ForEach(npsAssets) { a in
                                Text(a.name ?? a.id.uuidString)  // T-114-03: plain Text
                                    .tag(UUID?.some(a.id))
                            }
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            .navigationTitle(activeSIP == nil ? "New SIP" : "Edit SIP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save SIP") {
                        saveSIP()
                    }
                    .disabled(!isValid)
                    .tint(DesignTokens.accentText)
                }
            }
            .onAppear {
                loadExistingSIP()
            }
        }
    }

    // MARK: - Load existing SIP

    private func loadExistingSIP() {
        let assetID = asset.id
        let descriptor = FetchDescriptor<SIP>(
            predicate: #Predicate<SIP> { $0.assetID == assetID && $0.isActive == true }
        )
        if let sip = try? context.fetch(descriptor).first {
            activeSIP = sip
            amount = sip.amount
            originalAmount = sip.amount
            dayOfMonth = sip.dayOfMonth
            isActive = sip.isActive
            startDate = sip.startDate
            npsAllocationE = sip.npsAllocationE
            npsAllocationC = sip.npsAllocationC
            npsAllocationG = sip.npsAllocationG
            npsAssetE = sip.npsAssetE
            npsAssetC = sip.npsAssetC
            npsAssetG = sip.npsAssetG
        }
    }

    // MARK: - Save

    private func saveSIP() {
        guard isValid else { return }

        do {
            let target: SIP
            let isCreating = activeSIP == nil

            if let existing = activeSIP {
                target = existing
            } else {
                target = SIP()
                context.insert(target)
            }

            target.assetID = asset.id
            target.dayOfMonth = dayOfMonth
            target.amount = amount
            target.isActive = isActive
            target.startDate = startDate

            if isNPS {
                target.npsAllocationE = npsAllocationE
                target.npsAllocationC = npsAllocationC
                target.npsAllocationG = npsAllocationG
                target.npsAssetE = npsAssetE
                target.npsAssetC = npsAssetC
                target.npsAssetG = npsAssetG
            } else {
                // Clear NPS fields for non-NPS SIPs
                target.npsAllocationE = 0
                target.npsAllocationC = 0
                target.npsAllocationG = 0
                target.npsAssetE = nil
                target.npsAssetC = nil
                target.npsAssetG = nil
            }

            if isCreating {
                // CREATE: append initial SIPAmountChange with effectiveFrom = startDate
                let initialChange = SIPAmountChange(
                    sipID: target.id,
                    effectiveFrom: startDate,
                    amount: amount
                )
                context.insert(initialChange)
            } else if amount != originalAmount {
                // EDIT with changed amount: append a NEW SIPAmountChange effective next installment (D-07)
                // Never rewrite past changes — next-installment-only rule
                var istCal = Calendar(identifier: .gregorian)
                istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
                let nextDate = Self.nextInstallmentDate(
                    dayOfMonth: dayOfMonth,
                    after: Date(),
                    calendar: istCal
                )
                let amountChange = SIPAmountChange(
                    sipID: target.id,
                    effectiveFrom: nextDate,
                    amount: amount
                )
                context.insert(amountChange)
            }

            try context.save()  // CR-01: explicit save
            dismiss()
        } catch {
            assertionFailure("Failed to save SIP: \(error)")
        }
    }
}
