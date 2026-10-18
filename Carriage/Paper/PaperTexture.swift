import UIKit

/// Procedural paper grain and enamel speckle, rendered once per style and tiled.
enum PaperTexture {
    private static var cache: [String: UIImage] = [:]

    /// A tile of paper with fibres and grain.
    static func paper(_ style: PaperStyle) -> UIImage {
        let key = "paper-\(style.rawValue)"
        if let image = cache[key] { return image }
        let size = CGSize(width: 220, height: 220)
        var rng = SplitMix64(seed: style.rawValue.unicodeScalars.reduce(7) { $0 &* 31 &+ UInt64($1.value) })
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            style.color.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            // Grain: thousands of tiny light and dark specks.
            for _ in 0..<5200 {
                let x = rng.unit() * size.width, y = rng.unit() * size.height
                let dark = rng.unit() < 0.55
                let alpha = CGFloat(rng.unit()) * style.grain
                (dark ? UIColor.black : UIColor.white).withAlphaComponent(alpha).setFill()
                cg.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
            // Fibres: short, faint, mostly horizontal strokes.
            cg.setLineCap(.round)
            for _ in 0..<70 {
                let x = rng.unit() * size.width, y = rng.unit() * size.height
                let length = 3 + rng.unit() * 9
                let angle = (rng.unit() - 0.5) * 0.9
                cg.setStrokeColor(UIColor(white: rng.unit() < 0.5 ? 0.45 : 1, alpha: style.grain * 1.4).cgColor)
                cg.setLineWidth(0.5)
                cg.move(to: CGPoint(x: x, y: y))
                cg.addLine(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length))
                cg.strokePath()
            }
            if style == .carbon {
                // Faint smudges from the carbon sheet.
                for _ in 0..<6 {
                    let rect = CGRect(x: rng.unit() * size.width, y: rng.unit() * size.height, width: 30 + rng.unit() * 50, height: 4 + rng.unit() * 8)
                    UIColor(hex: 0x2D3263, alpha: 0.025).setFill()
                    cg.fillEllipse(in: rect)
                }
            }
        }
        cache[key] = image
        return image
    }

    /// Night paper: a deep, faintly warm sheet with light grain, for typing light-on-dark.
    static func nightPaper() -> UIImage {
        let key = "paper-night"
        if let image = cache[key] { return image }
        let size = CGSize(width: 220, height: 220)
        var rng = SplitMix64(seed: 99)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            UIColor(hex: 0x1F1E1B).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            for _ in 0..<4200 {
                let x = rng.unit() * size.width, y = rng.unit() * size.height
                UIColor(white: 1, alpha: CGFloat(rng.unit()) * 0.035).setFill()
                cg.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        cache[key] = image
        return image
    }

    static let nightPaperColor = UIColor(hex: 0x1F1E1B)

    /// A tile of enamel paint with a fine speckle, for the machine body.
    static func enamel(_ finish: MachineFinish) -> UIImage {
        let key = "enamel-\(finish.rawValue)"
        if let image = cache[key] { return image }
        let size = CGSize(width: 160, height: 160)
        var rng = SplitMix64(seed: 41)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            finish.body.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            for _ in 0..<2600 {
                let x = rng.unit() * size.width, y = rng.unit() * size.height
                let light = rng.unit() < 0.5
                let alpha = CGFloat(rng.unit()) * (finish.isDark ? 0.05 : 0.04)
                (light ? UIColor.white : UIColor.black).withAlphaComponent(alpha).setFill()
                cg.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        cache[key] = image
        return image
    }
}
