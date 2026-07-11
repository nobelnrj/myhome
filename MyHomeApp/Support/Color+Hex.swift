import SwiftUI
import UIKit

extension Color {
    /// Initialize a `Color` from a CSS-style hex string (e.g. `"#FF3B30"` or `"FF3B30"`).
    ///
    /// Falls back to `.gray` for malformed or unsupported strings. Supports 6-digit hex only.
    /// Used to decode `Account.colorHex` (stored as hex per CloudKit-readiness rule 8).
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16) else {
            self = .gray
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }

    /// Encode a `Color` to a 6-digit uppercase hex string (e.g. `"#FF3B30"`).
    ///
    /// Uses UIColor to extract RGB components in sRGB space. Falls back to `"#636366"`
    /// (system gray) when components cannot be resolved.
    var hexString: String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return "#636366"
        }
        return String(format: "#%02X%02X%02X",
                      Int(r * 255),
                      Int(g * 255),
                      Int(b * 255))
    }
}

// MARK: - Adaptive (light/dark) color factory — Phase 17 (D-06)

extension UIColor {
    /// Initialize a `UIColor` from a 6-digit CSS-style hex string plus an alpha.
    ///
    /// Uses the IDENTICAL 6-digit sRGB parsing contract as `Color.init(hex:)`:
    /// trim whitespace, strip `#`, require exactly 6 hex digits, decode
    /// `((value >> 16) & 0xFF)/255` per component. On any parse failure it falls
    /// back to `.gray` — component-identical to `Color.init(hex:)`'s fallback —
    /// so a malformed value degrades to gray and never crashes (threat T-17-01).
    ///
    /// This is the dark-branch parser for `Color.adaptive`; its byte-for-byte
    /// agreement with the legacy `Color(hex:)` path is what guarantees D-06 dark
    /// bit-identity, enforced by `DarkBitIdentityTests`.
    convenience init(hex: String, alpha: CGFloat = 1) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16) else {
            // Match Color(hex:)'s `.gray` fallback exactly.
            self.init(Color.gray)
            return
        }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

extension Color {
    /// Build an adaptive light/dark `Color` from two hex strings (with optional
    /// per-scheme alpha), backed by a `UIColor(dynamicProvider:)` so it resolves
    /// against the SwiftUI environment's `colorScheme`.
    ///
    /// The **dark branch must pass the token's current hex verbatim** (D-06):
    /// its output is component-identical to the legacy `Color(hex:)` path because
    /// `UIColor(hex:alpha:)` shares the same sRGB parsing math. This is the single
    /// mechanism every `DesignTokens` color migrates to from Plan 02 onward.
    static func adaptive(light: String, lightAlpha: CGFloat = 1,
                         dark: String, darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}
