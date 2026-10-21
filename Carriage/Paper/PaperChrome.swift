import UIKit

/// The rubber platen the paper wraps around, with bakelite knobs at each end.
final class PlatenView: UIView {
    var knobWidth: CGFloat = 26 { didSet { setNeedsDisplay() } }
    /// How far the knobs' grip ridges have turned, in points; animates as the roller advances the paper.
    private var ridgePhase: CGFloat = 0 { didSet { setNeedsDisplay() } }
    private var turnTimer: Timer?

    /// Turns the roller, as when a line feeds or a sheet rolls in: the knob ridges scroll by `ridges` notches.
    func turn(ridges: CGFloat, over duration: TimeInterval) {
        turnTimer?.invalidate()
        let start = ridgePhase
        let began = Date()
        turnTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let x = min(1, Date().timeIntervalSince(began) / max(0.01, duration))
                // Ease out, like a ratchet coming to rest.
                let eased = 1 - pow(1 - x, 3)
                self.ridgePhase = (start + ridges * 3 * CGFloat(eased)).truncatingRemainder(dividingBy: 3)
                if x >= 1 {
                    self.turnTimer?.invalidate()
                    self.turnTimer = nil
                }
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        let b = bounds
        let roller = b.insetBy(dx: knobWidth - 2, dy: 2)
        // The roller.
        cg.saveGState()
        cg.addPath(UIBezierPath(roundedRect: roller, cornerRadius: 3).cgPath)
        cg.clip()
        let rubber = CGGradient(colorsSpace: nil, colors: [
            UIColor(hex: 0x050505).cgColor, UIColor(hex: 0x2B2927).cgColor, UIColor(hex: 0x1A1918).cgColor,
            UIColor(hex: 0x0E0D0D).cgColor, UIColor(hex: 0x000000).cgColor,
        ] as CFArray, locations: [0, 0.22, 0.42, 0.75, 1])!
        cg.drawLinearGradient(rubber, start: CGPoint(x: 0, y: roller.minY), end: CGPoint(x: 0, y: roller.maxY), options: [])
        // A soft specular line.
        UIColor(white: 1, alpha: 0.09).setFill()
        cg.fill(CGRect(x: roller.minX, y: roller.minY + roller.height * 0.24, width: roller.width, height: 1.2))
        cg.restoreGState()

        drawKnob(in: CGRect(x: b.minX, y: b.minY, width: knobWidth, height: b.height), cg: cg, leftSide: true)
        drawKnob(in: CGRect(x: b.maxX - knobWidth, y: b.minY, width: knobWidth, height: b.height), cg: cg, leftSide: false)
    }

    private func drawKnob(in rect: CGRect, cg: CGContext, leftSide: Bool) {
        let knob = rect.insetBy(dx: 1, dy: -2)
        let path = UIBezierPath(roundedRect: knob, cornerRadius: knob.width * 0.32)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor(white: 0, alpha: 0.45).cgColor)
        UIColor(hex: 0x111010).setFill()
        path.fill()
        cg.restoreGState()
        cg.saveGState()
        path.addClip()
        let shade = CGGradient(colorsSpace: nil, colors: [
            UIColor(hex: 0x3A3836).cgColor, UIColor(hex: 0x0D0C0C).cgColor, UIColor(hex: 0x262423).cgColor,
        ] as CFArray, locations: [0, 0.6, 1])!
        cg.drawLinearGradient(shade, start: CGPoint(x: knob.minX, y: 0), end: CGPoint(x: knob.maxX, y: 0), options: [])
        // Grip ridges.
        cg.setStrokeColor(UIColor(white: 1, alpha: 0.07).cgColor)
        cg.setLineWidth(1)
        var y = knob.minY + 3 - ridgePhase
        while y < knob.maxY - 2 {
            cg.move(to: CGPoint(x: knob.minX + 2, y: y))
            cg.addLine(to: CGPoint(x: knob.maxX - 2, y: y))
            y += 3
        }
        cg.strokePath()
        cg.restoreGState()
        // The chrome hub where the knob meets the roller.
        let hubWidth: CGFloat = 4
        let hub = CGRect(x: leftSide ? knob.maxX - hubWidth : knob.minX, y: knob.midY - knob.height * 0.3, width: hubWidth, height: knob.height * 0.6)
        Chrome.fill(hub, in: cg, vertical: false)
    }
}

/// The scale along the front of the carriage, with a tick per character and the margin stops.
final class MarginScaleView: UIView {
    var advance: CGFloat = 9 { didSet { setNeedsDisplay() } }
    var leftMargin: CGFloat = 40 { didSet { setNeedsDisplay() } }
    var columns: Int = 62 { didSet { setNeedsDisplay() } }
    var bellColumn: Int = 55 { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        let b = bounds
        Chrome.fill(b, in: cg, vertical: true)
        let ink = UIColor(hex: 0x1B1A19, alpha: 0.8)
        ink.setFill()
        let numberFont = Legend.uiFont(size: max(6, b.height * 0.5), condensed: true)
        // The scale runs a few characters past each margin, like the real one.
        let start = -6, end = columns + 6
        for column in start...end {
            let x = leftMargin + CGFloat(column) * advance
            guard x >= 0, x <= b.width else { continue }
            let major = column % 10 == 0
            let mid = column % 5 == 0
            let height = major ? b.height * 0.42 : (mid ? b.height * 0.3 : b.height * 0.18)
            cg.fill(CGRect(x: x - 0.35, y: b.maxY - height, width: 0.7, height: height))
            if major, column >= 0 {
                let label = "\(column)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: ink]
                let size = label.size(withAttributes: attributes)
                label.draw(at: CGPoint(x: x - size.width / 2, y: b.minY - 0.5), withAttributes: attributes)
            }
        }
        // Margin stops: little brass tabs at the start and end of the line.
        for column in [0, columns] {
            let x = leftMargin + CGFloat(column) * advance
            let tab = CGRect(x: x - 2.5, y: b.minY, width: 5, height: b.height * 0.5)
            UIColor(hex: 0xB8955A).setFill()
            UIBezierPath(roundedRect: tab, cornerRadius: 1).fill()
        }
        // A tiny bell mark where the margin bell rings.
        let bx = leftMargin + CGFloat(bellColumn) * advance
        UIColor(hex: 0xA22D27, alpha: 0.85).setFill()
        cg.fillEllipse(in: CGRect(x: bx - 1.6, y: b.minY + 1, width: 3.2, height: 3.2))
    }
}

/// The card holder at the printing point: two clear tabs and a red pointer.
final class TypeGuideView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        let b = bounds
        let tabWidth = b.width * 0.22
        let gap = b.width * 0.36
        for x in [b.midX - gap / 2 - tabWidth, b.midX + gap / 2] {
            let tab = CGRect(x: x, y: b.height * 0.42, width: tabWidth, height: b.height * 0.58)
            let path = UIBezierPath(roundedRect: tab, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 2, height: 2))
            UIColor(white: 1, alpha: 0.2).setFill()
            path.fill()
            UIColor(white: 0.3, alpha: 0.35).setStroke()
            path.lineWidth = 0.6
            path.stroke()
        }
        // The pointer, aimed up at the printing point.
        let tip = CGPoint(x: b.midX, y: b.height * 0.55)
        let pointer = UIBezierPath()
        pointer.move(to: tip)
        pointer.addLine(to: CGPoint(x: tip.x - 3.5, y: b.maxY))
        pointer.addLine(to: CGPoint(x: tip.x + 3.5, y: b.maxY))
        pointer.close()
        UIColor(hex: 0xA22D27).setFill()
        cg.setShadow(offset: CGSize(width: 0, height: 0.5), blur: 1, color: UIColor(white: 0, alpha: 0.3).cgColor)
        pointer.fill()
    }
}

/// The carriage return lever on the left end of the carriage. Tap it to return.
final class ReturnLeverView: UIControl {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityLabel = "Carriage return lever"
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.transform = self.isHighlighted ? CGAffineTransform(rotationAngle: 0.14).translatedBy(x: 4, y: 0) : .identity
            }
        }
    }

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        let b = bounds
        // A bent chrome arm rising from the carriage, ending in a flat paddle.
        let arm = UIBezierPath()
        arm.move(to: CGPoint(x: b.maxX - 2, y: b.maxY - 4))
        arm.addCurve(to: CGPoint(x: b.minX + 8, y: b.minY + 8),
                     controlPoint1: CGPoint(x: b.maxX - 6, y: b.midY),
                     controlPoint2: CGPoint(x: b.midX, y: b.minY + 10))
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 3, color: UIColor(white: 0, alpha: 0.4).cgColor)
        cg.setLineCap(.round)
        cg.setLineWidth(5)
        cg.setStrokeColor(UIColor(hex: 0x8D9294).cgColor)
        cg.addPath(arm.cgPath)
        cg.strokePath()
        cg.restoreGState()
        cg.setLineWidth(2)
        cg.setStrokeColor(UIColor(white: 1, alpha: 0.75).cgColor)
        cg.addPath(arm.cgPath)
        cg.strokePath()
        let paddle = CGRect(x: b.minX + 1, y: b.minY + 2, width: 15, height: 10)
        Chrome.fill(paddle, in: cg, vertical: true, radius: 4)
    }
}

/// Shared chrome rendering.
enum Chrome {
    static func fill(_ rect: CGRect, in cg: CGContext, vertical: Bool, radius: CGFloat = 1.5) {
        cg.saveGState()
        cg.addPath(UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath)
        cg.clip()
        let gradient = CGGradient(colorsSpace: nil, colors: [
            UIColor(hex: 0xF4F5F5).cgColor, UIColor(hex: 0xA9AEB0).cgColor, UIColor(hex: 0xE2E5E6).cgColor,
            UIColor(hex: 0x7C8183).cgColor, UIColor(hex: 0xC9CDCE).cgColor,
        ] as CFArray, locations: [0, 0.35, 0.55, 0.8, 1])!
        let start = vertical ? CGPoint(x: 0, y: rect.minY) : CGPoint(x: rect.minX, y: 0)
        let end = vertical ? CGPoint(x: 0, y: rect.maxY) : CGPoint(x: rect.maxX, y: 0)
        cg.drawLinearGradient(gradient, start: start, end: end, options: [])
        cg.restoreGState()
    }
}
