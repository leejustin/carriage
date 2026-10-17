import UIKit

/// Draws keycaps: black glass tops in chrome rings with cream legends, and the chrome space bar.
/// Images are cached by size and legend, so the keyboard only draws once per layout.
enum KeyCapRenderer {
    enum Lamp: Hashable {
        case off, on, locked
    }

    private static var cache: [String: UIImage] = [:]

    static let legendColor = UIColor(hex: 0xF1E8D0)
    static let redLegend = UIColor(hex: 0xE0675C)

    static func image(shape: KeyShape, size: CGSize, upper: String?, lower: String, lamp: Lamp = .off, red: Bool = false) -> UIImage {
        let key = "\(shape)-\(Int(size.width * 10))x\(Int(size.height * 10))-\(upper ?? "")-\(lower)-\(lamp)-\(red)"
        if let image = cache[key] { return image }
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            switch shape {
            case .round, .pill:
                drawCap(in: CGRect(origin: .zero, size: size), cg: cg, upper: upper, lower: lower, lamp: lamp, red: red, pill: shape == .pill)
            case .bar:
                drawBar(in: CGRect(origin: .zero, size: size), cg: cg)
            }
        }
        cache[key] = image
        return image
    }

    private static func drawCap(in rect: CGRect, cg: CGContext, upper: String?, lower: String, lamp: Lamp, red: Bool, pill: Bool) {
        let d = min(rect.width, rect.height)
        let outer = rect.insetBy(dx: 0.5, dy: 0.5)
        let radius = pill ? outer.height / 2 : d / 2
        let outerPath = UIBezierPath(roundedRect: outer, cornerRadius: radius)

        // The chrome ring, lit from above-left.
        cg.saveGState()
        outerPath.addClip()
        let chrome = CGGradient(colorsSpace: nil, colors: [
            UIColor(hex: 0xFFFFFF).cgColor, UIColor(hex: 0xC6CBCD).cgColor, UIColor(hex: 0x6F7578).cgColor,
            UIColor(hex: 0xB9BEC0).cgColor, UIColor(hex: 0x50555A).cgColor,
        ] as CFArray, locations: [0, 0.28, 0.55, 0.78, 1])!
        cg.drawLinearGradient(chrome, start: CGPoint(x: outer.minX, y: outer.minY), end: CGPoint(x: outer.maxX * 0.7, y: outer.maxY), options: [])
        cg.restoreGState()

        // The black glass top.
        let ring = max(1.6, d * 0.085)
        let inner = outer.insetBy(dx: ring, dy: ring)
        let innerPath = UIBezierPath(roundedRect: inner, cornerRadius: pill ? inner.height / 2 : inner.width / 2)
        cg.saveGState()
        innerPath.addClip()
        let glass = CGGradient(colorsSpace: nil, colors: [
            UIColor(hex: 0x3D3B39).cgColor, UIColor(hex: 0x151413).cgColor, UIColor(hex: 0x070707).cgColor,
        ] as CFArray, locations: [0, 0.55, 1])!
        cg.drawRadialGradient(glass, startCenter: CGPoint(x: inner.midX - inner.width * 0.12, y: inner.minY + inner.height * 0.28), startRadius: 0,
                              endCenter: CGPoint(x: inner.midX, y: inner.midY), endRadius: max(inner.width, inner.height) * 0.62, options: [.drawsAfterEndLocation])
        // A thin dark inner edge where the glass sits in the ring.
        cg.setStrokeColor(UIColor(white: 0, alpha: 0.6).cgColor)
        cg.setLineWidth(1)
        cg.addPath(innerPath.cgPath)
        cg.strokePath()
        cg.restoreGState()

        // Legends.
        let color = red ? redLegend : legendColor
        if let upper {
            draw(upper, size: d * 0.27, color: color.withAlphaComponent(0.82), center: CGPoint(x: inner.midX, y: inner.minY + inner.height * 0.31), cg: cg)
            draw(lower, size: d * 0.29, color: color, center: CGPoint(x: inner.midX, y: inner.minY + inner.height * 0.69), cg: cg)
        } else if pill {
            let lines = lower.split(separator: "\n").map(String.init)
            let size = min(d * 0.25, inner.width / CGFloat(max(4, lines.map(\.count).max() ?? 4)) * 1.3)
            for (i, line) in lines.enumerated() {
                let dy = (CGFloat(i) - CGFloat(lines.count - 1) / 2) * size * 1.05
                draw(line, size: size, color: color, center: CGPoint(x: inner.midX, y: inner.midY + dy), cg: cg, condensed: true, tracking: size * 0.12)
            }
        } else {
            draw(lower, size: d * 0.4, color: color, center: CGPoint(x: inner.midX, y: inner.midY + d * 0.01), cg: cg)
        }

        // A lamp for shift: a small red jewel, brighter when locked.
        if lamp != .off {
            let r = max(2, d * 0.07)
            let dot = CGRect(x: inner.maxX - inner.height * 0.5 - r, y: inner.minY + inner.height * 0.18, width: r * 2, height: r * 2)
            cg.saveGState()
            cg.setShadow(offset: .zero, blur: lamp == .locked ? 6 : 3, color: UIColor(hex: 0xFF5A45, alpha: 0.9).cgColor)
            UIColor(hex: lamp == .locked ? 0xFF5A45 : 0xD9473A).setFill()
            cg.fillEllipse(in: dot)
            cg.restoreGState()
        }

        // The glass dome's reflection.
        cg.saveGState()
        innerPath.addClip()
        let shine = UIBezierPath(ovalIn: CGRect(x: inner.minX + inner.width * 0.12, y: inner.minY - inner.height * 0.02,
                                                width: inner.width * 0.76, height: inner.height * 0.44))
        shine.addClip()
        let gloss = CGGradient(colorsSpace: nil, colors: [UIColor(white: 1, alpha: 0.26).cgColor, UIColor(white: 1, alpha: 0.0).cgColor] as CFArray, locations: [0, 1])!
        cg.drawLinearGradient(gloss, start: CGPoint(x: 0, y: inner.minY), end: CGPoint(x: 0, y: inner.minY + inner.height * 0.42), options: [])
        cg.restoreGState()
    }

    private static func drawBar(in rect: CGRect, cg: CGContext) {
        let bar = rect.insetBy(dx: 1, dy: rect.height * 0.12)
        let path = UIBezierPath(roundedRect: bar, cornerRadius: bar.height / 2)
        cg.saveGState()
        path.addClip()
        let gradient = CGGradient(colorsSpace: nil, colors: [
            UIColor(hex: 0xFFFFFF).cgColor, UIColor(hex: 0xD3D7D8).cgColor, UIColor(hex: 0x8C9194).cgColor,
            UIColor(hex: 0xE4E7E8).cgColor, UIColor(hex: 0x5E6366).cgColor,
        ] as CFArray, locations: [0, 0.25, 0.55, 0.72, 1])!
        cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: bar.minY), end: CGPoint(x: 0, y: bar.maxY), options: [])
        // Fine brushing.
        cg.setStrokeColor(UIColor(white: 1, alpha: 0.12).cgColor)
        cg.setLineWidth(0.5)
        var y = bar.minY + 1
        while y < bar.maxY {
            cg.move(to: CGPoint(x: bar.minX, y: y))
            cg.addLine(to: CGPoint(x: bar.maxX, y: y))
            y += 1.5
        }
        cg.strokePath()
        cg.restoreGState()
        cg.setStrokeColor(UIColor(white: 0, alpha: 0.35).cgColor)
        cg.setLineWidth(0.8)
        cg.addPath(path.cgPath)
        cg.strokePath()
    }

    private static func draw(_ text: String, size: CGFloat, color: UIColor, center: CGPoint, cg: CGContext, condensed: Bool = false, tracking: CGFloat = 0) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Legend.uiFont(size: size, condensed: condensed),
            .foregroundColor: color,
            .kern: tracking,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let bounds = string.boundingRect(with: CGSize(width: 400, height: 400), options: [.usesLineFragmentOrigin], context: nil)
        string.draw(at: CGPoint(x: center.x - bounds.width / 2 + tracking / 2, y: center.y - bounds.height / 2))
    }
}
