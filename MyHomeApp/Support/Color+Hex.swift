import SwiftUI

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
