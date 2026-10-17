import CoreText
import SwiftUI
import UIKit

/// The typewriter faces. Courier Prime is used when its font files are bundled; Courier always works.
enum Typeface: String, CaseIterable, Identifiable, Codable {
    case prime, courier, courierNew

    var id: String { rawValue }

    var name: String {
        switch self {
        case .prime: "Pica (Courier Prime)"
        case .courier: "Elite (Courier)"
        case .courierNew: "Office (Courier New)"
        }
    }

    var postScriptName: String {
        switch self {
        case .prime: "CourierPrime-Regular"
        case .courier: "Courier"
        case .courierNew: "CourierNewPSMT"
        }
    }

    var isAvailable: Bool { UIFont(name: postScriptName, size: 12) != nil }

    /// Courier is thin on screen; it gets a heavier ink stroke to look struck rather than printed.
    var strokeBoost: CGFloat {
        switch self {
        case .prime: 0.4
        case .courier: 1.6
        case .courierNew: 1.2
        }
    }

    static var available: [Typeface] { allCases.filter(\.isAvailable) }

    static var preferred: Typeface { Typeface.prime.isAvailable ? .prime : .courier }

    func font(size: CGFloat) -> UIFont {
        UIFont(name: postScriptName, size: size) ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// The advance of one character, in points, at `size`.
    func advance(size: CGFloat) -> CGFloat {
        let font = font(size: size)
        return ("M" as NSString).size(withAttributes: [.font: font]).width
    }

    /// Registers any font files bundled with the app. Safe to call more than once.
    static func registerBundledFonts() {
        let urls = ["ttf", "otf"].flatMap { Bundle.main.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// Small caps labels in the mid-century style, for keycaps, badges and headers.
enum Legend {
    static func uiFont(size: CGFloat, condensed: Bool = false) -> UIFont {
        let name = condensed ? "Futura-CondensedMedium" : "Futura-Medium"
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .semibold)
    }

    static func font(size: CGFloat, condensed: Bool = false) -> Font {
        Font(uiFont(size: size, condensed: condensed))
    }
}

extension Font {
    /// The typewriter face as a SwiftUI font, for library cards and menus.
    static func typewriter(_ size: CGFloat, face: Typeface = .preferred) -> Font {
        Font(face.font(size: size))
    }
}
