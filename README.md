# My Home

Personal household-ops iOS app. Expense tracker + note keeper for a two-person household.

## Project-Wide Rules

### Observable / State
- Use `@Observable` macro for all view models and shared state. **Never** `@StateObject`, `@ObservedObject`, or `@Published`.
- View state that is local to one view uses `@State`.
- SwiftData models use `@Bindable` for editing.

### Money
- Store all amounts as `Decimal`. **Never** `Double` (floating-point drift on sums).
- Display with `Locale(identifier: "en_IN")` for Indian Rupee lakh grouping (₹1,00,000.00).
- `currencyCode: String` is present on all monetary models for future multi-currency support.

### Dates
- Store as `Date` (always UTC in Swift). **Never** store as a String or date-only type.
- Format for display only: use `DateFormatter` with `timeZone = .current`.

### SwiftData / CloudKit Readiness
- Every `@Model` property must be **optional** or carry a **default value**. No bare required fields.
- **No `@Attribute(.unique)`** anywhere. Enforce uniqueness via lookup-before-insert in application code.
- Every relationship must be `optional` with `inverse:` declared and `deleteRule: .nullify`.
- A reflection test (`expensePropertiesAreCloudKitReady`) enforces these rules automatically.

### App Group Fallback Note
The production store URL uses the App Group container:
`group.com.reojacob.myhome → MyHome.store`

On a free Apple Developer account, App Group entitlement provisioning may fail.
If it does, the `ModelContainer+App.swift` factory falls back to `.applicationSupportDirectory`.
**Do NOT change the bundle/group IDs** — the fallback is purely a URL choice.
When the paid account is active, migrate the store file from Application Support to the App Group
container and update the factory. Document that migration in the relevant phase's PLAN.md.

## Locked Identifiers (D-09 — never change)

| ID | Value |
|----|-------|
| Bundle ID | `com.reojacob.myhome` |
| CloudKit container | `iCloud.com.reojacob.myhome` |
| App Group | `group.com.reojacob.myhome` |
| Min deployment | iOS 17.0 |

CloudKit is **wired as container-ready** even though v1 runs local-only.
Flip `cloudKitDatabase: .none` → `.private("iCloud.com.reojacob.myhome")` post paid-account upgrade.

## Phase Roadmap

| Phase | Goal |
|-------|------|
| 01 | Foundation: Xcode project + privacy manifest + test harness skeleton |
| 02 | Expense model: SwiftData @Model + VersionedSchema + ModelContainer |
| 03 | Expense UI: Add/Edit/Delete/List screens |
| 04 | Overview + charts |
| 05 | Face ID + Settings |
| 06 | Gmail OAuth (proof of concept) |
| 07 | Gmail ingestion pipeline + bank parsers |
