import UIKit

extension NSAttributedString.Key {
    /// Marks a character that's been struck through with an x in Typewriter mode.
    static let carriageStrike = NSAttributedString.Key("CarriageStrike")
    /// Marks a misspelling underline added by the spell checker, so it can be cleared without touching ink.
    static let carriageSpelling = NSAttributedString.Key("CarriageSpelling")
    /// Marks a character typed over with an underscore.
    static let carriageUnderline = NSAttributedString.Key("CarriageUnderline")
}

/// Gives every character its own bit of ink: a little lighter or darker, a hair above or below the line,
/// an occasional heavy strike. Deterministic per page and position, so a page always looks the same.
struct InkStyler {
    let font: UIFont
    let ink: InkStyle
    /// The colour the ribbon prints in: its own, or a light one on night paper.
    let inkColor: UIColor
    let paper: PaperStyle
    let face: Typeface
    let seed: Int
    let lineHeight: CGFloat
    let tabWidth: CGFloat

    /// A small palette of attribute sets, so a long page has a handful of distinct runs, not thousands.
    private let palette: [[NSAttributedString.Key: Any]]
    /// A faint second impression, offset a hair, for the odd key that bounced and struck twice.
    private let ghost: NSShadow
    private static let densitySteps = 7
    private static let baselineSteps: [CGFloat] = [-0.45, -0.2, 0, 0.2, 0.45]
    private static let strokeSteps = 3

    init(font: UIFont, ink: InkStyle, paper: PaperStyle, face: Typeface, seed: Int, lineSpacing: LineSpacing, advance: CGFloat, night: Bool = false) {
        inkColor = night ? ink.nightColor : ink.color
        self.font = font
        self.ink = ink
        self.paper = paper
        self.face = face
        self.seed = seed
        let natural = font.lineHeight
        lineHeight = (natural * CGFloat(lineSpacing.rawValue)).rounded()
        tabWidth = advance * 5

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.tabStops = (1...24).map { NSTextTab(textAlignment: .left, location: advance * 5 * CGFloat($0)) }
        paragraph.defaultTabInterval = advance * 5

        let shadow: NSShadow? = {
            guard paper.inkSpread > 0 else { return nil }
            let s = NSShadow()
            s.shadowBlurRadius = paper.inkSpread
            s.shadowOffset = .zero
            s.shadowColor = (night ? ink.nightColor : ink.color).withAlphaComponent(0.55)
            return s
        }()

        var palette: [[NSAttributedString.Key: Any]] = []
        let density = ink.density
        // Centre glyphs in the taller line box.
        let lift = (lineHeight - natural) / 2
        for d in 0..<Self.densitySteps {
            let alpha = density.lowerBound + (density.upperBound - density.lowerBound) * CGFloat(d) / CGFloat(Self.densitySteps - 1)
            let color = (night ? ink.nightColor : ink.color).withAlphaComponent(alpha)
            for baseline in Self.baselineSteps {
                for s in 0..<Self.strokeSteps {
                    var attributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: paragraph,
                        .baselineOffset: baseline + lift,
                        // Negative stroke width fills and strokes, which reads as ink soaking in.
                        .strokeWidth: -(face.strokeBoost + CGFloat(s) * 0.9),
                        .strokeColor: color,
                    ]
                    if let shadow { attributes[.shadow] = shadow }
                    palette.append(attributes)
                }
            }
        }
        self.palette = palette
        let ghost = NSShadow()
        ghost.shadowBlurRadius = 0
        ghost.shadowOffset = CGSize(width: 0.6, height: -0.35)
        ghost.shadowColor = (night ? ink.nightColor : ink.color).withAlphaComponent(0.3)
        self.ghost = ghost
    }

    /// Attributes for typing at the end of the page, before the character's own texture is known.
    var baseAttributes: [NSAttributedString.Key: Any] { palette[palette.count / 2] }

    func attributes(at index: Int) -> [NSAttributedString.Key: Any] {
        var h = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(truncatingIfNeeded: index) &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 31
        h &*= 0x94D0_49BB_1331_11EB
        h ^= h >> 29
        // The ribbon wears unevenly: a slow wave along the text, plus each strike's own force.
        let wave = (sin(Double(index) / 37.0 + Double(seed % 97)) + 1) / 2
        let force = Double(h & 0xFF) / 255
        var d = Int(((wave * 0.45 + force * 0.55) * Double(Self.densitySteps - 1)).rounded())
        let heavy = (h >> 8) & 0x1F == 0 // About one in 32 keys gets hit hard.
        if heavy { d = Self.densitySteps - 1 }
        let b = Int((h >> 16) % UInt64(Self.baselineSteps.count))
        let s = heavy ? Self.strokeSteps - 1 : Int((h >> 24) % 2)
        let attributes = palette[(d * Self.baselineSteps.count + b) * Self.strokeSteps + s]
        // About one key in 55 bounces and prints a second, fainter impression beside the first.
        guard !heavy, (h >> 40) % 55 == 0 else { return attributes }
        var doubled = attributes
        doubled[.shadow] = ghost
        return doubled
    }

    /// Re-inks `range` of `storage`, keeping strike and underline marks.
    func style(_ storage: NSMutableAttributedString, range: NSRange) {
        let length = storage.length
        let range = NSIntersectionRange(range, NSRange(location: 0, length: length))
        guard range.length > 0 else { return }
        let text = storage.string as NSString
        var i = range.location
        while i < NSMaxRange(range) {
            let composed = text.rangeOfComposedCharacterSequence(at: i)
            let strike = storage.attribute(.carriageStrike, at: i, effectiveRange: nil)
            let underline = storage.attribute(.carriageUnderline, at: i, effectiveRange: nil) != nil
            storage.setAttributes(attributes(at: i), range: composed)
            if let strike { storage.addAttribute(.carriageStrike, value: strike, range: composed) }
            if underline { addUnderline(to: storage, range: composed) }
            i = NSMaxRange(composed)
        }
    }

    /// Marks `range` as typed over with underscores, drawn as an inky rule under the letters.
    func addUnderline(to storage: NSMutableAttributedString, range: NSRange) {
        storage.addAttributes([
            .carriageUnderline: true,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: inkColor.withAlphaComponent(0.85),
        ], range: range)
    }

    func removeUnderline(from storage: NSMutableAttributedString, range: NSRange) {
        storage.removeAttribute(.carriageUnderline, range: range)
        storage.removeAttribute(.underlineStyle, range: range)
        storage.removeAttribute(.underlineColor, range: range)
    }

    /// Builds the full attributed text for a page. A plain attributed string, not a text storage: a storage would
    /// re-process the whole text after every character, which made long pages take minutes to open.
    func attributedText(body: String, strikes: [NSRange], underlines: [NSRange] = []) -> NSAttributedString {
        let storage = NSMutableAttributedString(string: body)
        style(storage, range: NSRange(location: 0, length: storage.length))
        for range in strikes where NSMaxRange(range) <= storage.length {
            storage.addAttribute(.carriageStrike, value: true, range: range)
        }
        for range in underlines where NSMaxRange(range) <= storage.length {
            addUnderline(to: storage, range: range)
        }
        return storage
    }
}
