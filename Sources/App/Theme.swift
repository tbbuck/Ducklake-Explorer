import SwiftUI
import AppKit
import CoreText

/// The Stratum palette (DESIGN-TOKENS.md). Two appearances — **limestone** day and
/// **JetBrains-Islands** night — resolved dynamically. One file so re-skinning is trivial.
enum Palette {
    // Surfaces
    static let backdrop      = Color.stratum(0xE3E1D8, 0x131417)  // desktop behind the window
    static let base          = Color.stratum(0xEFEEE7, 0x1E1F22)  // bg — window ground
    static let surface       = Color.stratum(0xF7F6F0, 0x2B2D30)  // panel — lifted sidebars
    static let surfaceRaised = Color.stratum(0xFCFBF6, 0x303236)  // panel-2 — cards/inputs
    static let track         = Color.stratum(0xF0EEE5, 0x35373C)  // panel-3 — hover/inset

    // Lines
    static let hairline      = Color.stratum(0xDAD5C9, 0x393B40)  // line
    static let border        = Color.stratum(0xC6C0B1, 0x45474D)  // line-2

    // Text
    static let textPrimary   = Color.stratum(0x223038, 0xE3E5EA)  // text
    static let textSecondary = Color.stratum(0x515B5A, 0xB4B8C0)  // muted
    static let textTertiary  = Color.stratum(0x6C736E, 0x8B9099)  // muted-2

    // Accents
    static let accent        = Color.stratum(0x1E7A72, 0x3FA091)  // ink-teal
    static let accent2       = Color.stratum(0xA97B36, 0xD6A55D)  // brass — types, deletes
    static let accentDim     = Color.stratum(0x66A398, 0x3E8C83)  // s-marl, for inactive marks
    static let accentSoft    = Color.stratum(0x1E7A72, 0x3FA091, alpha: (0.12, 0.16))
    static let accentLine    = Color.stratum(0x1E7A72, 0x3FA091, alpha: (0.34, 0.42))
    static let onCool        = Color.stratum(0xEEF5F2, 0xEEF5F2)  // text on an accent fill

    static let geometry      = accent2                            // the ⌖ geospatial flag
    static let danger        = Color.stratum(0xC0453A, 0xF0897B)  // errors only

    // Strata ramp (water depth: surface → bedrock) — the Core identity.
    static let strataSand  = Color.stratum(0xC4D6CE, 0x7CC8BD)
    static let strataSilt  = Color.stratum(0x99C1B6, 0x57ABA1)
    static let strataMarl  = Color.stratum(0x66A398, 0x3E8C83)
    static let strataShale = Color.stratum(0x3F857C, 0x2E6E68)
    static let strataSlate = Color.stratum(0x256560, 0x204F4C)

    /// The history core-spine depth gradient.
    static let coreSpine = LinearGradient(
        stops: [
            .init(color: strataSand, location: 0.00),
            .init(color: strataSilt, location: 0.28),
            .init(color: strataMarl, location: 0.52),
            .init(color: strataShale, location: 0.76),
            .init(color: strataSlate, location: 1.00),
        ],
        startPoint: .top, endPoint: .bottom
    )
}

extension Font {
    /// Hanken Grotesk — display, headings, UI, body.
    static func stratumDisplay(_ size: CGFloat, _ weight: Weight = .bold) -> Font {
        .custom("Hanken Grotesk", size: size).weight(weight)
    }
    static func stratumUI(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .custom("Hanken Grotesk", size: size).weight(weight)
    }
    /// JetBrains Mono — data, SQL, paths, numerics, badges.
    static func stratumMono(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .custom("JetBrains Mono", size: size).weight(weight)
    }
}

extension Color {
    /// A dynamic colour resolving to `light`/`dark` (0xRRGGBB), with optional per-appearance alpha.
    static func stratum(_ light: UInt32, _ dark: UInt32, alpha: (Double, Double) = (1, 1)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? alpha.1 : alpha.0)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}

/// Registers the bundled Stratum fonts so `Font.custom` can find them.
enum StratumFonts {
    static func register() {
        for name in ["HankenGrotesk", "JetBrainsMono"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// Colours a column's type label per the tokens: accent-2 (brass), but accent (teal) for
/// geometry and boolean types.
func typeColor(_ dataType: String?) -> Color {
    let t = (dataType ?? "").uppercased()
    if t.contains("GEOMETRY") || t.contains("BOOL") { return Palette.accent }
    return Palette.accent2
}
