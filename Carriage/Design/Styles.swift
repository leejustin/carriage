import SwiftUI
import UIKit

/// The enamel finish of the machine body. All finishes are free.
enum MachineFinish: String, CaseIterable, Identifiable, Codable {
    case seafoam, bottle, enamel, cherry, sand

    var id: String { rawValue }

    var name: String {
        switch self {
        case .seafoam: "Seafoam"
        case .bottle: "Bottle Green"
        case .enamel: "Black Enamel"
        case .cherry: "Cherry"
        case .sand: "Desert Sand"
        }
    }

    /// The main body colour.
    var body: UIColor {
        switch self {
        case .seafoam: UIColor(hex: 0x9EC4B4)
        case .bottle: UIColor(hex: 0x2E4A3D)
        case .enamel: UIColor(hex: 0x1D1C1B)
        case .cherry: UIColor(hex: 0x9C3530)
        case .sand: UIColor(hex: 0xD3BE98)
        }
    }

    /// A darker shade for the recess behind the paper and the deck's lower edge.
    var shadow: UIColor { body.mixed(with: .black, amount: isDark ? 0.45 : 0.32) }
    /// A lighter shade for highlights along the top of the deck.
    var highlight: UIColor { body.mixed(with: .white, amount: isDark ? 0.12 : 0.28) }

    var isDark: Bool { self == .enamel || self == .bottle || self == .cherry }

    /// Colour for small labels printed on the body (the badge, the scale).
    var printColor: UIColor { isDark ? UIColor(hex: 0xE9DFC6) : UIColor(hex: 0x2A2723) }
}

/// Paper stock. Every stock is included; bond is the default.
enum PaperStyle: String, CaseIterable, Identifiable, Codable {
    case bond, cream, onionSkin, carbon

    var id: String { rawValue }

    var name: String {
        switch self {
        case .bond: "Bond"
        case .cream: "Cream"
        case .onionSkin: "Onion Skin"
        case .carbon: "Carbon Copy"
        }
    }

    var blurb: String {
        switch self {
        case .bond: "Crisp 20 lb white."
        case .cream: "Warm laid stock."
        case .onionSkin: "Thin, faintly see-through."
        case .carbon: "The copy underneath, slightly smudged."
        }
    }

    var color: UIColor {
        switch self {
        case .bond: UIColor(hex: 0xFBF9F3)
        case .cream: UIColor(hex: 0xF4EBD3)
        case .onionSkin: UIColor(hex: 0xEEF0EC)
        case .carbon: UIColor(hex: 0xE6E4DE)
        }
    }

    /// How strong the fibre grain is.
    var grain: CGFloat {
        switch self {
        case .bond: 0.035
        case .cream: 0.06
        case .onionSkin: 0.03
        case .carbon: 0.07
        }
    }

    /// Onion skin is translucent: the desk shows through a little.
    var opacity: CGFloat { self == .onionSkin ? 0.93 : 1 }

    /// Carbon copies blur the type a touch.
    var inkSpread: CGFloat { self == .carbon ? 0.9 : 0 }
}

/// Ribbon ink. Every ribbon is included; black is the default.
enum InkStyle: String, CaseIterable, Identifiable, Codable {
    case black, red, faded, carbonBlue

    var id: String { rawValue }

    var name: String {
        switch self {
        case .black: "Black Ribbon"
        case .red: "Red Ribbon"
        case .faded: "Faded Ribbon"
        case .carbonBlue: "Carbon Blue"
        }
    }

    var color: UIColor {
        switch self {
        case .black: UIColor(hex: 0x1F1D1B)
        case .red: UIColor(hex: 0xA22D27)
        case .faded: UIColor(hex: 0x3B3936)
        case .carbonBlue: UIColor(hex: 0x2D3263)
        }
    }

    /// The ribbon on night paper: light ink on dark stock.
    var nightColor: UIColor {
        switch self {
        case .black, .faded: UIColor(hex: 0xECE4D0)
        case .red: UIColor(hex: 0xEC8F83)
        case .carbonBlue: UIColor(hex: 0xB4BCEB)
        }
    }

    /// The range of per-character ink density. A worn ribbon is lighter and less even.
    var density: ClosedRange<CGFloat> {
        switch self {
        case .black: 0.80...1.0
        case .red: 0.78...0.98
        case .faded: 0.42...0.78
        case .carbonBlue: 0.62...0.92
        }
    }
}

/// How far the paper slides as you type.
enum CarriageTravel: String, CaseIterable, Identifiable, Codable {
    case classic, gentle, fixed

    var id: String { rawValue }

    var name: String {
        switch self {
        case .classic: "Classic"
        case .gentle: "Gentle"
        case .fixed: "Fixed"
        }
    }

    var detail: String {
        switch self {
        case .classic: "The paper travels the full line, like the real thing."
        case .gentle: "The paper rests centred and eases along as you type."
        case .fixed: "The paper stays put and the type guide moves."
        }
    }
}

/// When to type white-on-dark: night paper with a light ribbon.
enum NightDesk: String, CaseIterable, Identifiable, Codable {
    case off, on, system

    var id: String { rawValue }

    var name: String {
        switch self {
        case .off: "Off"
        case .on: "On"
        case .system: "Match iPhone"
        }
    }
}

/// How the typewriter keys are arranged on a wide deck.
enum KeyboardStyle: String, CaseIterable, Identifiable, Codable {
    /// One piece across the deck, for typing with all ten fingers.
    case full
    /// Two halves at the edges, one for each thumb, for typing while holding the phone.
    case split

    var id: String { rawValue }

    var name: String {
        switch self {
        case .full: "Full"
        case .split: "Split for thumbs"
        }
    }
}

enum TypingMode: String, CaseIterable, Identifiable, Codable {
    /// Delete works as you'd expect.
    case free
    /// No delete: the delete key types an x over the last character instead.
    case typewriter

    var id: String { rawValue }

    var name: String {
        switch self {
        case .free: "Free"
        case .typewriter: "Typewriter"
        }
    }

    var detail: String {
        switch self {
        case .free: "Delete works."
        case .typewriter: "No delete. Strike through with x and keep going."
        }
    }
}

enum LineWidth: Int, CaseIterable, Identifiable, Codable {
    case narrow = 50, standard = 62, wide = 72

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .narrow: "Narrow · 50"
        case .standard: "Standard · 62"
        case .wide: "Wide · 72"
        }
    }
}

enum LineSpacing: Double, CaseIterable, Identifiable, Codable {
    case single = 1.0, oneAndHalf = 1.5, double = 2.0

    var id: Double { rawValue }

    var name: String {
        switch self {
        case .single: "Single"
        case .oneAndHalf: "One and a half"
        case .double: "Double"
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = max(0, min(1, amount))
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }

    /// The app's printed-matter palette, used by menus and the library.
    static let paperWhite = Color(hex: 0xFBF9F3)
    static let ink = Color(hex: 0x1F1D1B)
    static let inkSoft = Color(hex: 0x6A645B)
    static let ribbonRed = Color(hex: 0xA22D27)
    static let brass = Color(hex: 0xB8955A)

    /// Text set straight on the desk (not on paper), which darkens in dark mode.
    static let deskInk = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xEDE6D6) : UIColor(hex: 0x1F1D1B) })
    static let deskInkSoft = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xA9A194) : UIColor(hex: 0x6A645B) })
}
