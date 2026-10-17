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
    var paper: PaperStyle
    var ink: InkStyle
    var inkSeed: Int

    init(_ page: Page) {
        title = page.displayTitle
        body = page.body
        strikes = page.strikes
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
            try TextExport.markdown(title: page.title, body: page.body, strikes: page.strikes).write(to: url, atomically: true, encoding: .utf8)
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
                try TextExport.markdown(title: page.title, body: page.body, strikes: page.strikes).write(to: url, atomically: true, encoding: .utf8)
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
        let storage = NSTextStorage(attributedString: styler.attributedText(body: page.body, strikes: page.strikes))
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

    private static func drawStrikes(storage: NSTextStorage, layout: NSLayoutManager, container: NSTextContainer, glyphs: NSRange,
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
