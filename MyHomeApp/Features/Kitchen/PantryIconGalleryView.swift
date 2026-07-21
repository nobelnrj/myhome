#if DEBUG
import SwiftUI

/// DEBUG-only tile gallery — the one thing no test can do.
///
/// A non-existent SF Symbol renders **nothing** and raises **no error**. That bug shipped in 20-03
/// (`takeoutbag.fill.and.rectangle.portrait`) and survived a passing unit test, because the test
/// asserted the string the function returned, not that the string named a real symbol. Phase 22
/// designs the failure out for the *model* (it names a category, never a symbol) — but the static
/// `PantryCategory.presentation` table is still hand-written Swift, so every string in it has to be
/// looked at on a real render surface once.
///
/// This view draws every `PantryCategory.allCases` tile beside its **literal symbol string**. The
/// string is what makes a screenshot diagnostic rather than merely alarming: a blank square tells
/// you something is wrong, a blank square labelled `scroll.fill` tells you exactly which name to
/// replace.
///
/// Reached with the `-iconGallery` launch argument, mirroring the existing `-startTab` /
/// `-seedSampleData` hooks. `simctl` cannot navigate the app, so a launch argument is the only way
/// to get a deterministic screenshot of all 17 tiles in both appearances.
///
/// **Entirely inside `#if DEBUG`**, view and call site both (T-22-10) — the hook does not exist in
/// a Release build.
struct PantryIconGalleryView: View {

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ZStack {
            DesignTokens.bgCanvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pantry icon gallery")
                        .font(.title2.weight(.semibold))
                    Text("\(PantryCategory.allCases.count) categories — every tile must show a glyph.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(PantryCategory.allCases, id: \.self) { category in
                            row(for: category)
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder
    private func row(for category: PantryCategory) -> some View {
        let presentation = category.presentation
        HStack(spacing: 10) {
            // The SAME tile the pantry rows draw — same size, same corner radius, same glyph
            // treatment — so a symbol that looks fine here looks fine on the shelf.
            IconTile(symbol: presentation.symbol, color: presentation.color, size: 38, cornerRadius: 11)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.rawValue)
                    .font(.subheadline.weight(.medium))
                Text(presentation.symbol)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

extension PantryIconGalleryView {
    /// True when the app was launched with `-iconGallery`.
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-iconGallery")
    }
}
#endif
