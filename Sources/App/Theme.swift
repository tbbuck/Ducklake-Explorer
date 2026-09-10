import SwiftUI
import AppKit
import CoreText

/// The Stratum palette as semantic tokens. Two appearances — **limestone** (day) and a
/// **JetBrains-Islands**-flavoured night — resolved dynamically from the system/override
/// appearance. Values are a first pass; they live here so re-skinning is one file.
enum Palette {
    static let base          = Color.stratum(0xEFEAE1, 0x14201F)  // window ground
    static let surface       = Color.stratum(0xF5F1E8, 0x1A2826)  // panels / rails
    static let surfaceRaised = Color.stratum(0xFBF8F1, 0x223330)  // cards
    static let textPrimary   = Color.stratum(0x2A2925, 0xE8EEEB)
    static let textSecondary = Color.stratum(0x6B665C, 0x9DAFAB)
    static let textTertiary  = Color.stratum(0x958E80, 0x647672)
    static let accent        = Color.stratum(0x0F7E8A, 0x40D0C0)  // teal — the Core identity
    static let accentDim     = Color.stratum(0x86BCC0, 0x235F5A)
    static let hairline      = Color.stratum(0xDDD5C6, 0x2B3D39)
    static let selection     = Color.stratum(0xE3EFEC, 0x2C4B46)
    static let geometry      = Color.stratum(0x9A6A00, 0xE2B550)  // amber for the ⌖ marker
    static let danger        = Color.stratum(0xB23A2E, 0xF08A7C)
}

extension Font {
    /// Hanken Grotesk, for display headings.
    static func stratumDisplay(_ size: CGFloat, _ weight: Weight = .semibold) -> Font {
        .custom("Hanken Grotesk", size: size).weight(weight)
    }
    /// Hanken Grotesk, for UI body/labels.
    static func stratumUI(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .custom("Hanken Grotesk", size: size).weight(weight)
    }
    /// JetBrains Mono, for data, SQL, versions, and metrics.
    static func stratumMono(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .custom("JetBrains Mono", size: size).weight(weight)
    }
}

extension Color {
    /// A dynamic colour that resolves to `light` or `dark` (0xRRGGBB) per the appearance.
    static func stratum(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Registers the bundled Stratum fonts with the process so `Font.custom` can find them.
enum StratumFonts {
    static func register() {
        for name in ["HankenGrotesk", "JetBrainsMono"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
