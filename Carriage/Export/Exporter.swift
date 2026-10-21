import UIKit
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf, markdown, plainText

    var id: String { rawValue }

    var name: String {
        switch self {
        case .pdf: "PDF (typed page)"
        case .markdown: "Markdown"
        case .plainText: "Plain text"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: "pdf"
        case .markdown: "md"
        case .plainText: "txt"
        }
    }

    var symbol: String {
        switch self {
        case .pdf: "doc.richtext"
        case .markdown: "number"
        case .plainText: "doc.plaintext"
        }
    }
}

/// A snapshot of a page for exporting, so export work never touches the live model.
struct PageSnapshot {
    var title: String
    var body: String
    var strikes: [NSRange]
    var underlines: [NSRange]
    var paper: PaperStyle
    var ink: InkStyle
    var inkSeed: Int

    init(_ page: Page) {
        title = page.displayTitle
        body = page.body
        strikes = page.strikes
        underlines = page.underlines
        paper = page.paper
        ink = page.ink
        inkSeed = page.inkSeed
    }

    var plainText: String { TextExport.plainText(body: body, strikes: strikes) }
}

enum Exporter {
    /// Writes the page to a temporary file named after its title.
    static func file(for page: PageSnapshot, format: ExportFormat, face: Typeface, spacing: LineSpacing) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName(page.title)).appendingPathExtension(format.fileExtension)
        switch format {
        case .plainText:
            try page.plainText.write(to: url, atomically: true, encoding: .utf8)
        case .markdown:
            try TextExport.markdown(title: page.title, body: page.body, strikes: page.strikes, underlines: page.underlines).write(to: url, atomically: true, encoding: .utf8)
        case .pdf:
            try TypedPagePDF.render(page, face: face, spacing: spacing).write(to: url)
        }
        return url
    }

    /// Writes every page into one folder, for "Export all pages". Names are made unique so nothing overwrites.
    static func folder(for pages: [PageSnapshot], format: ExportFormat, face: Typeface, spacing: LineSpacing, date: Date = .now) throws -> URL {
        let stamp = date.formatted(.iso8601.year().month().day())
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Export-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Carriage Pages \(stamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var used: Set<String> = []
        for page in pages {
            var name = fileName(page.title)
            var n = 2
            while used.contains(name.lowercased()) {
                name = "\(fileName(page.title)) \(n)"
                n += 1
            }
            used.insert(name.lowercased())
            let url = directory.appendingPathComponent(name).appendingPathExtension(format.fileExtension)
            switch format {
            case .plainText:
                try page.plainText.write(to: url, atomically: true, encoding: .utf8)
            case .markdown:
                try TextExport.markdown(title: page.title, body: page.body, strikes: page.strikes, underlines: page.underlines).write(to: url, atomically: true, encoding: .utf8)
            case .pdf:
                try TypedPagePDF.render(page, face: face, spacing: spacing).write(to: url)
            }
        }
        return directory
    }

    static func fileName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:")).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let short = cleaned.count > 60 ? String(cleaned.prefix(60)) : cleaned
        return short.isEmpty ? "Carriage Page" : short
    }
}

/// Renders a page as a PDF that looks typed: Letter-size paper with grain, 12-point type at ten characters
/// to the inch, uneven ink, x'd-out mistakes and centred page numbers.
enum TypedPagePDF {
    static let pageSize = CGSize(width: 612, height: 792)
    static let margins = UIEdgeInsets(top: 72, left: 72, bottom: 72, right: 72)

    static func render(_ page: PageSnapshot, face: Typeface, spacing: LineSpacing) -> Data {
        let font = face.font(size: 12)
        let advance = face.advance(size: 12)
        let styler = InkStyler(font: font, ink: page.ink, paper: page.paper, face: face, seed: page.inkSeed, lineSpacing: spacing, advance: advance)
        let storage = NSTextStorage(attributedString: styler.attributedText(body: page.body, strikes: page.strikes, underlines: page.underlines))
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let textSize = CGSize(width: pageSize.width - margins.left - margins.right, height: pageSize.height - margins.top - margins.bottom)

        // Add pages until the text runs out.
        var containers: [NSTextContainer] = []
        while true {
            let container = NSTextContainer(size: textSize)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            containers.append(container)
            let range = layout.glyphRange(for: container)
            if range.length == 0 || NSMaxRange(range) >= layout.numberOfGlyphs || containers.count >= 500 { break }
        }

        let texture = PaperTexture.paper(page.paper)
        let bounds = CGRect(origin: .zero, size: pageSize)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: page.title,
            kCGPDFContextCreator as String: "Carriage",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        return renderer.pdfData { context in
            for (index, container) in containers.enumerated() {
                context.beginPage()
                let cg = context.cgContext
                cg.saveGState()
                UIColor(patternImage: texture).setFill()
                cg.fill(bounds)
                cg.restoreGState()

                let origin = CGPoint(x: margins.left, y: margins.top)
                let glyphs = layout.glyphRange(for: container)
                layout.drawGlyphs(forGlyphRange: glyphs, at: origin)
                drawStrikes(storage: storage, layout: layout, container: container, glyphs: glyphs, origin: origin, font: font, advance: advance, ink: page.ink)

                if containers.count > 1 {
                    let number = "- \(index + 1) -" as NSString
                    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: page.ink.color.withAlphaComponent(0.85)]
                    let size = number.size(withAttributes: attributes)
                    number.draw(at: CGPoint(x: (pageSize.width - size.width) / 2, y: pageSize.height - margins.bottom / 2 - size.height / 2), withAttributes: attributes)
                }
            }
        }
    }

    static func drawStrikes(storage: NSTextStorage, layout: NSLayoutManager, container: NSTextContainer, glyphs: NSRange,
                                    origin: CGPoint, font: UIFont, advance: CGFloat, ink: InkStyle) {
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: ink.color.withAlphaComponent(0.88),
            .strokeWidth: -2.0,
            .strokeColor: ink.color.withAlphaComponent(0.88),
        ]
        let x = "x" as NSString
        let size = x.size(withAttributes: attributes)
        storage.enumerateAttribute(.carriageStrike, in: characters) { value, range, _ in
            guard value != nil else { return }
            for i in range.location..<NSMaxRange(range) {
                let glyph = layout.glyphRange(forCharacterRange: NSRange(location: i, length: 1), actualCharacterRange: nil)
                let rect = layout.boundingRect(forGlyphRange: glyph, in: container)
                guard rect.width > 0 else { continue }
                let point = CGPoint(x: origin.x + rect.midX - size.width / 2, y: origin.y + rect.midY - size.height / 2)
                x.draw(at: point, withAttributes: attributes)
            }
        }
    }
}

/// A typed page as a picture for sharing: 4:5, the opening of the page on paper, signed "Typed on Carriage".
enum TypedPageImage {
    /// The shapes people post in: a feed post and a full-screen story.
    enum Format: CaseIterable {
        case post, story

        var size: CGSize {
            switch self {
            case .post: CGSize(width: 1080, height: 1350)
            case .story: CGSize(width: 1080, height: 1920)
            }
        }
    }

    static let size = Format.post.size

    /// The page as a typed sheet resting on the desk, a little askew, with the machine's brass plate below it.
    static func render(_ page: PageSnapshot, face: Typeface, format: Format = .post, finish: MachineFinish = .seafoam, engraving: String = "") -> UIImage {
        let size = format.size
        // The sheet: most of the width, its height set by the format, with room for the plate underneath.
        let sheet = CGRect(x: 90, y: format == .story ? 240 : 110, width: size.width - 180, height: size.height - (format == .story ? 520 : 330))
        let font = face.font(size: 28)
        let advance = face.advance(size: 28)
        let styler = InkStyler(font: font, ink: page.ink, paper: page.paper, face: face, seed: page.inkSeed, lineSpacing: .oneAndHalf, advance: advance)
        let storage = NSTextStorage(attributedString: styler.attributedText(body: page.body, strikes: page.strikes, underlines: page.underlines))
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let inset = UIEdgeInsets(top: 80, left: 72, bottom: 90, right: 72)
        let container = NSTextContainer(size: CGSize(width: sheet.width - inset.left - inset.right, height: sheet.height - inset.top - inset.bottom))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        layout.addTextContainer(container)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let bounds = CGRect(origin: .zero, size: size)
            // The desk, in the machine's enamel, with light falling from above.
            let desk = CGGradient(colorsSpace: nil, colors: [finish.highlight.cgColor, finish.body.cgColor, finish.shadow.cgColor] as CFArray, locations: [0, 0.45, 1])!
            cg.drawLinearGradient(desk, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            cg.saveGState()
            UIColor(patternImage: PaperTexture.enamel(finish)).withAlphaComponent(0.35).setFill()
            cg.fill(bounds)
            cg.restoreGState()

            // The sheet, turned a degree, with a soft shadow on the desk.
            cg.saveGState()
            cg.translateBy(x: sheet.midX, y: sheet.midY)
            cg.rotate(by: -0.016)
            cg.translateBy(x: -sheet.midX, y: -sheet.midY)
            cg.setShadow(offset: CGSize(width: 0, height: 14), blur: 40, color: UIColor(white: 0, alpha: 0.35).cgColor)
            UIColor(cgColor: page.paper.color.cgColor).setFill()
            cg.fill(sheet)
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor(patternImage: PaperTexture.paper(page.paper)).setFill()
            cg.fill(sheet)
            let origin = CGPoint(x: sheet.minX + inset.left, y: sheet.minY + inset.top)
            let glyphs = layout.glyphRange(for: container)
            layout.drawGlyphs(forGlyphRange: glyphs, at: origin)
            TypedPagePDF.drawStrikes(storage: storage, layout: layout, container: container, glyphs: glyphs, origin: origin, font: font, advance: advance, ink: page.ink)
            // More to the page than fits: a typed ellipsis, as you'd leave it in the machine.
            if NSMaxRange(glyphs) < layout.numberOfGlyphs {
                let more = NSAttributedString(string: "...", attributes: styler.attributes(at: 0))
                let used = layout.usedRect(for: container)
                more.draw(at: CGPoint(x: origin.x, y: origin.y + used.maxY + 6))
            }
            cg.restoreGState()

            // The brass plate, and a quiet line under it.
            let name = engraving.trimmingCharacters(in: .whitespacesAndNewlines)
            let plateText = NSAttributedString(string: name.isEmpty ? "CARRIAGE" : "CARRIAGE · \(name.uppercased())", attributes: [
                .font: Legend.uiFont(size: 30),
                .foregroundColor: UIColor(hex: 0x3B2A12),
                .kern: 9,
            ])
            let textSize = plateText.size()
            let plate = CGRect(x: (size.width - textSize.width - 90) / 2, y: sheet.maxY + (size.height - sheet.maxY) * 0.36, width: textSize.width + 90, height: 62)
            let platePath = UIBezierPath(roundedRect: plate, cornerRadius: plate.height / 2)
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 4), blur: 8, color: UIColor(white: 0, alpha: 0.35).cgColor)
            UIColor(hex: 0xB8955A).setFill()
            platePath.fill()
            cg.restoreGState()
            cg.saveGState()
            platePath.addClip()
            let brass = CGGradient(colorsSpace: nil, colors: [
                UIColor(hex: 0xF2DCA6).cgColor, UIColor(hex: 0xB8955A).cgColor, UIColor(hex: 0xE3C88E).cgColor, UIColor(hex: 0x8A6A35).cgColor,
            ] as CFArray, locations: [0, 0.45, 0.6, 1])!
            cg.drawLinearGradient(brass, start: CGPoint(x: 0, y: plate.minY), end: CGPoint(x: 0, y: plate.maxY), options: [])
            cg.restoreGState()
            plateText.draw(at: CGPoint(x: plate.midX - textSize.width / 2 + 4, y: plate.midY - textSize.height / 2))

            let line = NSAttributedString(string: "TYPED ON CARRIAGE", attributes: [
                .font: Legend.uiFont(size: 22),
                .foregroundColor: finish.printColor.withAlphaComponent(0.85),
                .kern: 6,
            ])
            let lineSize = line.size()
            line.draw(at: CGPoint(x: (size.width - lineSize.width) / 2, y: plate.maxY + 26))
        }
    }
}
