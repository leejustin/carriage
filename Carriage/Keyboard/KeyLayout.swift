import CoreGraphics

/// What a key does.
enum KeyAction: Equatable, Hashable {
    case character(String, shifted: String)
    case space
    case carriageReturn
    case delete
    case shift
    case tab

    /// What VoiceOver reads.
    var accessibilityLabel: String {
        switch self {
        case let .character(lower, shifted):
            let name = Self.spoken[lower] ?? lower.uppercased()
            if let shiftedName = Self.spoken[shifted], shifted != lower.uppercased() {
                return "\(name), shift \(shiftedName)"
            }
            return name
        case .space: return "Space"
        case .carriageReturn: return "Return"
        case .delete: return "Delete"
        case .shift: return "Shift"
        case .tab: return "Tab"
        }
    }

    private static let spoken: [String: String] = [
        "!": "exclamation mark", "@": "at", "#": "number sign", "$": "dollar", "%": "percent", "^": "caret",
        "&": "ampersand", "*": "asterisk", "(": "left parenthesis", ")": "right parenthesis", "-": "hyphen",
        "—": "em dash", "/": "slash", "?": "question mark", ";": "semicolon", ":": "colon", "'": "apostrophe",
        "\"": "quote", ",": "comma", "<": "less than", ".": "period", ">": "greater than",
    ]
}

enum KeyShape: Equatable {
    case round
    /// A rounded lozenge for the modifier keys.
    case pill
    /// The chrome space bar.
    case bar
}

struct KeySpec: Equatable, Identifiable {
    let id: String
    let action: KeyAction
    /// The small legend printed above, for keys with a shifted symbol.
    let upper: String?
    /// The main legend.
    let lower: String
    let units: CGFloat
    let shape: KeyShape

    static func letter(_ c: String) -> KeySpec {
        KeySpec(id: c, action: .character(c, shifted: c.uppercased()), upper: nil, lower: c.uppercased(), units: 1, shape: .round)
    }

    static func symbol(_ lower: String, _ upper: String) -> KeySpec {
        KeySpec(id: lower, action: .character(lower, shifted: upper), upper: upper, lower: lower, units: 1, shape: .round)
    }
}

struct KeyRow {
    let keys: [KeySpec]
    /// Indent from the left, in key units, for the typewriter stagger.
    let offset: CGFloat

    var units: CGFloat { offset + keys.reduce(0) { $0 + $1.units } }
}

/// The typewriter layouts: four staggered rows of round keys and a space bar row.
enum KeyLayout {
    enum Variant {
        /// The full machine, for the Duo's half-folded and open-flat decks.
        case wide
        /// For narrow screens: ten keys a row like the system keyboard, so each key gets as much width as it does
        /// there. Punctuation moves down beside the space bar.
        case compact
        /// Two halves at the edges of a wide deck, one for each thumb.
        case split

        /// Split needs a deck at least this wide; narrower, each half's keys would be too small to hit.
        static let minimumSplitWidth: CGFloat = 520

        static func forWidth(_ width: CGFloat, style: KeyboardStyle = .full) -> Variant {
            if width < minimumSplitWidth { return .compact }
            return style == .split ? .split : .wide
        }
    }

    /// The rows of each block of keys: one block, or two for the split layout (left half, then right half).
    static func blocks(_ variant: Variant) -> [[KeyRow]] {
        switch variant {
        case .wide: [rows]
        case .compact: [compactRows]
        case .split: [splitLeft, splitRight]
        }
    }

    static func rows(_ variant: Variant) -> [KeyRow] {
        blocks(variant).flatMap { $0 }
    }

    static func widestRow(_ variant: Variant) -> CGFloat {
        blocks(variant).map { block in block.map(\.units).max() ?? 0 }.max() ?? 12
    }

    static let splitLeft: [KeyRow] = [
        KeyRow(keys: [.symbol("1", "!"), .symbol("2", "@"), .symbol("3", "#"), .symbol("4", "$"), .symbol("5", "%")], offset: 0),
        KeyRow(keys: "qwert".map { .letter(String($0)) }, offset: 0.3),
        KeyRow(keys: "asdfg".map { .letter(String($0)) }, offset: 0.5),
        KeyRow(keys: [KeySpec(id: "shift", action: .shift, upper: nil, lower: "SHIFT", units: 1.5, shape: .pill)]
            + "zxcv".map { .letter(String($0)) }, offset: 0),
        KeyRow(keys: [
            .symbol(",", ";"), .symbol("-", "—"),
            KeySpec(id: "space", action: .space, upper: nil, lower: "", units: 3.4, shape: .bar),
        ], offset: 0),
    ]

    static let splitRight: [KeyRow] = [
        KeyRow(keys: [.symbol("6", "^"), .symbol("7", "&"), .symbol("8", "*"), .symbol("9", "("), .symbol("0", ")")], offset: 0.3),
        KeyRow(keys: "yuiop".map { .letter(String($0)) }, offset: 0.4),
        KeyRow(keys: "hjkl".map { .letter(String($0)) } + [.symbol("'", "\"")], offset: 0.6),
        KeyRow(keys: "bnm".map { .letter(String($0)) }
            + [KeySpec(id: "delete", action: .delete, upper: nil, lower: "BACK", units: 1.6, shape: .pill)], offset: 0.9),
        KeyRow(keys: [
            KeySpec(id: "space2", action: .space, upper: nil, lower: "", units: 1.8, shape: .bar),
            .symbol(".", ":"), .symbol("?", "/"),
            KeySpec(id: "return", action: .carriageReturn, upper: nil, lower: "RETURN", units: 1.5, shape: .pill),
        ], offset: 0.3),
    ]

    static let compactRows: [KeyRow] = [
        KeyRow(keys: [
            .symbol("1", "!"), .symbol("2", "@"), .symbol("3", "#"), .symbol("4", "$"), .symbol("5", "%"),
            .symbol("6", "^"), .symbol("7", "&"), .symbol("8", "*"), .symbol("9", "("), .symbol("0", ")"),
        ], offset: 0),
        KeyRow(keys: "qwertyuiop".map { .letter(String($0)) }, offset: 0.15),
        KeyRow(keys: "asdfghjkl".map { .letter(String($0)) } + [.symbol("'", "\"")], offset: 0.35),
        KeyRow(keys: [KeySpec(id: "shift", action: .shift, upper: nil, lower: "SHIFT", units: 1.45, shape: .pill)]
            + "zxcvbnm".map { .letter(String($0)) }
            + [KeySpec(id: "delete", action: .delete, upper: nil, lower: "BACK", units: 1.45, shape: .pill)], offset: 0.25),
        KeyRow(keys: [
            .symbol(",", ";"), .symbol("-", "—"),
            KeySpec(id: "space", action: .space, upper: nil, lower: "", units: 4.3, shape: .bar),
            .symbol(".", ":"), .symbol("?", "/"),
            KeySpec(id: "return", action: .carriageReturn, upper: nil, lower: "RETURN", units: 2, shape: .pill),
        ], offset: 0),
    ]

    static let rows: [KeyRow] = [
        KeyRow(keys: [
            .symbol("1", "!"), .symbol("2", "@"), .symbol("3", "#"), .symbol("4", "$"), .symbol("5", "%"),
            .symbol("6", "^"), .symbol("7", "&"), .symbol("8", "*"), .symbol("9", "("), .symbol("0", ")"),
            .symbol("-", "—"),
            KeySpec(id: "delete", action: .delete, upper: nil, lower: "BACK", units: 1.5, shape: .pill),
        ], offset: 0),
        KeyRow(keys: "qwertyuiop".map { .letter(String($0)) } + [.symbol("/", "?")], offset: 0.45),
        KeyRow(keys: "asdfghjkl".map { .letter(String($0)) } + [.symbol(";", ":"), .symbol("'", "\"")], offset: 0.7),
        KeyRow(keys: [KeySpec(id: "shift", action: .shift, upper: nil, lower: "SHIFT", units: 1.5, shape: .pill)]
            + "zxcvbnm".map { .letter(String($0)) }
            + [.symbol(",", "<"), .symbol(".", ">"),
               KeySpec(id: "shift2", action: .shift, upper: nil, lower: "SHIFT", units: 1.5, shape: .pill)], offset: 0.2),
        KeyRow(keys: [
            KeySpec(id: "tab", action: .tab, upper: nil, lower: "TAB", units: 1.6, shape: .pill),
            KeySpec(id: "space", action: .space, upper: nil, lower: "", units: 7.2, shape: .bar),
            KeySpec(id: "return", action: .carriageReturn, upper: nil, lower: "RETURN", units: 2.2, shape: .pill),
        ], offset: 0.9),
    ]

}
