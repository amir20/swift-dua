import AppKit
import DiskKit
import SwiftUI

/// oklch (L 0–1, C chroma, H degrees) → gamma-encoded sRGB components (0–1).
/// The design specifies its palette in oklch; this converts it exactly
/// (oklch → oklab → linear sRGB → gamma).
func oklchToSRGB(_ L: Double, _ c: Double, _ hDeg: Double) -> (r: Double, g: Double, b: Double) {
    let h = hDeg * .pi / 180
    let a = c * cos(h)
    let b = c * sin(h)
    let l_ = L + 0.3963377774 * a + 0.2158037573 * b
    let m_ = L - 0.1055613458 * a - 0.0638541728 * b
    let s_ = L - 0.0894841775 * a - 1.2914855480 * b
    let l = l_ * l_ * l_
    let m = m_ * m_ * m_
    let s = s_ * s_ * s_
    let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    let bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    func gamma(_ v: Double) -> Double {
        let cc = max(0, min(1, v))
        return cc <= 0.0031308 ? 12.92 * cc : 1.055 * pow(cc, 1 / 2.4) - 0.055
    }
    return (gamma(r), gamma(g), gamma(bl))
}

/// An oklch color spec (L 0–1, C chroma, H degrees), authored in the design's
/// color space.
typealias OKLCH = (L: Double, c: Double, h: Double)

extension Color {
    /// Builds an sRGB `Color` from an oklch value (L 0–1, C chroma, H degrees).
    init(oklch L: Double, _ c: Double, _ hDeg: Double) {
        let (r, g, b) = oklchToSRGB(L, c, hDeg)
        self.init(.sRGB, red: r, green: g, blue: b)
    }

    /// A color that resolves to `light` in light mode and `dark` in dark mode,
    /// each authored in oklch. Backed by a dynamic `NSColor`, so every call site
    /// follows the system appearance with no changes in the views.
    static func dynamic(_ light: OKLCH, _ dark: OKLCH) -> Color {
        let l = oklchToSRGB(light.L, light.c, light.h)
        let d = oklchToSRGB(dark.L, dark.c, dark.h)
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let c = isDark ? d : l
                return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
            })
    }
}

/// The Dial color system, authored in oklch with paired light/dark values so the
/// app follows the system appearance.
enum Palette {

    // MARK: Folder lens — a distinct hue per folder

    /// A distinct color for the folder slice at size-rank `index`. Hues step by
    /// the golden angle so any number of folders stay well separated, at a fixed
    /// oklch lightness/chroma so they read as one harmonious family. The *by type*
    /// lens keeps the semantic category colors below.
    static func folderHue(_ index: Int) -> Color {
        let h = (folderStartHue + Double(index) * 137.507_764).truncatingRemainder(dividingBy: 360)
        return .dynamic((0.76, 0.105, h), (0.72, 0.125, h))
    }
    private static let folderStartHue = 35.0

    // MARK: Type lens — semantic category colors

    static func color(_ cat: FileCategory) -> Color {
        switch cat {
        case .deps: return .dynamic((0.80, 0.115, 85), (0.80, 0.130, 85))
        case .cache: return .dynamic((0.79, 0.085, 205), (0.76, 0.105, 205))
        case .build: return .dynamic((0.66, 0.105, 252), (0.72, 0.120, 252))
        case .container: return .dynamic((0.62, 0.100, 300), (0.70, 0.120, 300))
        case .media: return .dynamic((0.70, 0.115, 25), (0.74, 0.130, 25))
        case .code: return .dynamic((0.74, 0.095, 152), (0.76, 0.110, 152))
        case .docs: return .dynamic((0.74, 0.070, 262), (0.76, 0.090, 262))
        case .app: return .dynamic((0.70, 0.035, 250), (0.72, 0.045, 250))
        case .trash: return .dynamic((0.74, 0.045, 40), (0.74, 0.060, 40))
        case .other: return .dynamic((0.83, 0.012, 75), (0.62, 0.020, 75))
        }
    }

    // MARK: Ink (text) — inverts for dark

    static let ink = Color.dynamic((0.24, 0.006, 60), (0.93, 0.006, 80))
    static let ink2 = Color.dynamic((0.46, 0.006, 60), (0.76, 0.006, 80))
    static let ink3 = Color.dynamic((0.60, 0.005, 60), (0.60, 0.005, 80))
    static let ink4 = Color.dynamic((0.73, 0.004, 60), (0.48, 0.005, 80))

    // MARK: Lines & surfaces

    static let line = Color.dynamic((0.91, 0.004, 70), (0.30, 0.004, 80))
    static let line2 = Color.dynamic((0.95, 0.004, 70), (0.26, 0.004, 80))
    static let bg = Color.dynamic((1.00, 0.000, 75), (0.17, 0.005, 75))
    static let bg2 = Color.dynamic((0.985, 0.003, 75), (0.205, 0.005, 75))
    static let bg3 = Color.dynamic((0.970, 0.004, 75), (0.235, 0.006, 75))

    // MARK: Accents

    static let reclaim = Color.dynamic((0.66, 0.15, 58), (0.74, 0.16, 58))
    static let progress = Color.dynamic((0.62, 0.16, 256), (0.70, 0.17, 256))
}
