import UIKit

/// The typewriter keys. Drawn by the app, not the system keyboard.
///
/// Touches are handled in `touchesBegan`, so a key fires the moment a finger lands: no gesture recognizer
/// delay, and several fingers can be down at once.
final class KeyboardView: UIView {
    /// Fires on touch-down with the key and its horizontal position, 0 (left) to 1 (right).
    var onKey: ((KeyAction, CGFloat) -> Void)?

    var finish: MachineFinish = .seafoam { didSet { if finish != oldValue { applyFinish() } } }
    var mode: TypingMode = .free { didSet { if mode != oldValue { refreshCaps() } } }
    var shiftState: ShiftState = .off { didSet { if shiftState != oldValue { refreshCaps() } } }
    var reduceMotion = false
    var showsBadge = true { didSet { badge.isHidden = !showsBadge } }
    /// Full or split. Split only applies where the deck is wide enough (see `KeyLayout.Variant`).
    var style: KeyboardStyle = .full {
        didSet {
            guard style != oldValue else { return }
            lastLayoutSize = .zero
            setNeedsLayout()
        }
    }

    enum ShiftState { case off, once, locked }

    /// Below this key size a finger hides the key it's pressing, so a preview pops up above it, as on the system keyboard.
    static let previewBelowDiameter: CGFloat = 46

    private(set) var variant: KeyLayout.Variant = .wide
    private var caps: [KeyCapView] = []
    private var rowFrames: [CGRect] = []
    private var active: [UITouch: KeyCapView] = [:]
    private var previews: [UITouch: CALayer] = [:]
    private var repeatTimer: Timer?
    private var lastLayoutSize: CGSize = .zero
    private var diameter: CGFloat = 40

    private let deck = CAGradientLayer()
    private let enamel = CALayer()
    private let trim = CAGradientLayer()
    private let badge = BadgeView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        // Key previews rise above the deck, over the bottom of the paper.
        clipsToBounds = false
        layer.addSublayer(enamel)
        layer.addSublayer(deck)
        trim.colors = [UIColor(hex: 0xF2F4F4).cgColor, UIColor(hex: 0x8E9496).cgColor, UIColor(hex: 0xD5D8D9).cgColor, UIColor(hex: 0x4E5356).cgColor]
        trim.locations = [0, 0.4, 0.6, 1]
        layer.addSublayer(trim)
        addSubview(badge)
        buildCaps()
        applyFinish()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildCaps() {
        caps.forEach { $0.removeFromSuperview() }
        caps = KeyLayout.rows(variant).flatMap(\.keys).map { spec in
            let cap = KeyCapView(spec: spec)
            cap.onAccessibilityActivate = { [weak self, weak cap] in
                guard let self, let cap else { return }
                self.fire(cap)
            }
            addSubview(cap)
            return cap
        }
        accessibilityElements = caps
    }

    private func applyFinish() {
        enamel.backgroundColor = UIColor(patternImage: PaperTexture.enamel(finish)).cgColor
        deck.colors = [
            finish.highlight.withAlphaComponent(0.55).cgColor,
            UIColor.clear.cgColor,
            finish.shadow.withAlphaComponent(0.6).cgColor,
        ]
        deck.locations = [0, 0.25, 1]
        badge.finish = finish
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        enamel.frame = bounds
        deck.frame = bounds
        trim.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 3)
        CATransaction.commit()
        guard bounds.size != lastLayoutSize, bounds.width > 0 else { return }
        lastLayoutSize = bounds.size
        let newVariant = KeyLayout.Variant.forWidth(bounds.width, style: style)
        if newVariant != variant || caps.isEmpty {
            releaseAll()
            variant = newVariant
            buildCaps()
        }
        layoutKeys()
    }

    private func layoutKeys() {
        let insets = safeAreaInsets
        let area = bounds.inset(by: UIEdgeInsets(top: 10, left: max(6, insets.left), bottom: max(8, insets.bottom), right: max(6, insets.right)))
        let blocks = KeyLayout.blocks(variant)
        // In split the plate sits in the gap between the halves, so it takes no height.
        let badgeHeight: CGFloat = area.height > 300 && blocks.count == 1 ? 22 : 0
        let rowCount = blocks[0].count
        let widest = KeyLayout.widestRow(variant)
        let pitch: CGFloat
        if variant == .split {
            // Each half is sized for a thumb: anchored to its edge and no wider than a thumb sweeps comfortably
            // (about 48 mm), with keys up to 54 pt apart.
            let halfWidth = min(area.width * 0.42, (widest + 0.15) * 54)
            pitch = halfWidth / (widest + 0.15)
        } else {
            pitch = min(area.width / (widest + 0.15), 82)
        }
        // Rows are at least 48 pt where there's room (Apple's minimum target is 44), and tall panes (open flat,
        // side by side) get a roomier deck rather than a small keyboard adrift in the middle.
        let ideal = max(pitch * (area.height > area.width ? 1.3 : 1.12), 48)
        let rowHeight = min((area.height - badgeHeight) / CGFloat(rowCount), ideal)
        diameter = min(pitch, rowHeight) * (variant == .wide ? 0.86 : 0.9)
        let blockWidth = pitch * widest
        let origins: [CGFloat] = variant == .split
            ? [area.minX + 4, area.maxX - blockWidth - 4]
            : [area.minX + (area.width - blockWidth) / 2]
        let usedHeight = rowHeight * CGFloat(rowCount)
        // Thumbs rest low on a held phone, so the split halves sit at the bottom of the deck.
        let originY = variant == .split
            ? area.maxY - usedHeight
            : area.minY + (area.height - badgeHeight - usedHeight) / 2

        // One hit band per row across the whole deck; within a band the nearest key wins, so a touch in the
        // split's gap still goes to the closer half.
        rowFrames = (0..<rowCount).map { r in
            CGRect(x: bounds.minX, y: originY + CGFloat(r) * rowHeight, width: bounds.width, height: rowHeight)
        }
        var index = 0
        for (b, block) in blocks.enumerated() {
            for (r, row) in block.enumerated() {
                let y = originY + CGFloat(r) * rowHeight
                var x = origins[b] + row.offset * pitch
                // Centre the space bar row of a one-piece keyboard.
                if blocks.count == 1, r == block.count - 1 { x = origins[b] + (blockWidth - (row.units - row.offset) * pitch) / 2 }
                for spec in row.keys {
                    let cell = CGRect(x: x, y: y, width: spec.units * pitch, height: rowHeight)
                    let size: CGSize
                    switch spec.shape {
                    case .round: size = CGSize(width: diameter, height: diameter)
                    case .pill: size = CGSize(width: cell.width - (pitch - diameter), height: diameter * 0.86)
                    case .bar: size = CGSize(width: cell.width - pitch * 0.3, height: diameter * 0.62)
                    }
                    caps[index].layout(cell: cell, size: size, diameter: diameter)
                    index += 1
                    x += spec.units * pitch
                }
            }
        }
        let gap = blocks.count == 2 ? (origins[1] - origins[0] - blockWidth) : 0
        if badgeHeight > 0 {
            badge.isHidden = !showsBadge
            badge.frame = CGRect(x: bounds.midX - 52, y: originY + usedHeight + 2, width: 104, height: 18)
        } else if gap > 112, area.height > 300 {
            badge.isHidden = !showsBadge
            badge.frame = CGRect(x: bounds.midX - 52, y: originY + usedHeight / 2 - 9, width: 104, height: 18)
        } else {
            badge.isHidden = true
        }
        refreshCaps()
    }

    private func refreshCaps() {
        for cap in caps {
            cap.render(mode: mode, shift: shiftState)
        }
    }

    // MARK: Touches

    /// The key for a touch: the row it lands in, then the nearest key in that row. Every point on the deck
    /// belongs to some key, so a near miss between two keys still types the closer one.
    private func cap(at point: CGPoint) -> KeyCapView? {
        guard let row = rowFrames.firstIndex(where: { $0.minY <= point.y && point.y < $0.maxY })
            ?? (point.y < (rowFrames.first?.minY ?? 0) ? 0 : rowFrames.indices.last) else { return nil }
        let rowY = rowFrames[row].midY
        return caps
            .filter { abs($0.cell.midY - rowY) < 1 }
            .min { abs($0.cell.midX - point.x) - $0.cell.width / 2 < abs($1.cell.midX - point.x) - $1.cell.width / 2 }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let cap = cap(at: touch.location(in: self)) else { continue }
            active[touch] = cap
            cap.setPressed(true, reduceMotion: reduceMotion)
            showPreview(for: cap, touch: touch)
            fire(cap)
            if cap.spec.action == .delete { startRepeat(cap) }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches)
    }

    private func release(_ touches: Set<UITouch>) {
        for touch in touches {
            hidePreview(for: touch)
            guard let cap = active.removeValue(forKey: touch) else { continue }
            if !active.values.contains(where: { $0 === cap }) {
                cap.setPressed(false, reduceMotion: reduceMotion)
                Haptics.shared.keyUp()
            }
            if cap.spec.action == .delete { stopRepeat() }
        }
    }

    private func releaseAll() {
        release(Set(active.keys))
        stopRepeat()
    }

    private func fire(_ cap: KeyCapView) {
        let fan = bounds.width > 0 ? cap.center.x / bounds.width : 0.5
        onKey?(cap.spec.action, fan)
    }

    // MARK: Previews

    /// Pops the character up above the finger, as a larger key, while the key is held.
    private func showPreview(for cap: KeyCapView, touch: UITouch) {
        guard diameter < Self.previewBelowDiameter, case let .character(lower, shifted) = cap.spec.action else { return }
        let character = shiftState == .off ? lower : shifted
        let size = CGSize(width: diameter * 1.6, height: diameter * 1.6)
        let preview = CALayer()
        preview.contents = KeyCapRenderer.image(shape: .round, size: size, upper: nil, lower: character).cgImage
        preview.contentsScale = traitCollection.displayScale
        preview.shadowColor = UIColor.black.cgColor
        preview.shadowOpacity = 0.45
        preview.shadowRadius = 6
        preview.shadowOffset = CGSize(width: 0, height: 3)
        preview.shadowPath = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).cgPath
        let center = cap.convert(CGPoint(x: cap.bounds.midX, y: cap.bounds.midY), to: self)
        let x = min(max(center.x, size.width / 2 + 2), bounds.width - size.width / 2 - 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = CGRect(x: x - size.width / 2, y: center.y - diameter / 2 - size.height - 6, width: size.width, height: size.height)
        layer.addSublayer(preview)
        CATransaction.commit()
        previews.removeValue(forKey: touch)?.removeFromSuperlayer()
        previews[touch] = preview
    }

    private func hidePreview(for touch: UITouch) {
        guard let preview = previews.removeValue(forKey: touch) else { return }
        // Linger a moment so a quick tap still shows what it typed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            preview.removeFromSuperlayer()
        }
    }

    private func startRepeat(_ cap: KeyCapView) {
        stopRepeat()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.085, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.active.values.contains(where: { $0 === cap }) else {
                            self?.stopRepeat()
                            return
                        }
                        self.fire(cap)
                    }
                }
            }
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}

/// One key: its stem, its shadow and its cap.
final class KeyCapView: UIView {
    let spec: KeySpec
    private(set) var cell: CGRect = .zero
    var onAccessibilityActivate: (() -> Void)?

    private let shadowLayer = CALayer()
    private let stem = CALayer()
    private let capLayer = CALayer()
    private var capSize: CGSize = .zero
    private var diameter: CGFloat = 40
    private var rendered: String = ""

    init(spec: KeySpec) {
        self.spec = spec
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = spec.action.accessibilityLabel
        accessibilityTraits = [.keyboardKey]
        stem.backgroundColor = UIColor(white: 0, alpha: 0.28).cgColor
        layer.addSublayer(stem)
        shadowLayer.shadowColor = UIColor.black.cgColor
        shadowLayer.shadowOpacity = 0.5
        layer.addSublayer(shadowLayer)
        capLayer.contentsGravity = .resize
        layer.addSublayer(capLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func layout(cell: CGRect, size: CGSize, diameter: CGFloat) {
        self.cell = cell
        self.diameter = diameter
        capSize = size
        frame = cell
        let capFrame = CGRect(x: (cell.width - size.width) / 2, y: (cell.height - size.height) / 2 - cell.height * 0.04, width: size.width, height: size.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        capLayer.frame = capFrame
        capLayer.contentsScale = traitCollection.displayScale
        shadowLayer.frame = capFrame
        let radius = spec.shape == .round ? size.width / 2 : size.height / 2
        shadowLayer.shadowPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius).cgPath
        shadowLayer.shadowOffset = CGSize(width: 0, height: diameter * 0.08)
        shadowLayer.shadowRadius = diameter * 0.07
        // The key lever disappearing into the machine below the cap.
        let stemWidth = spec.shape == .bar ? size.width * 0.04 : diameter * 0.16
        stem.frame = CGRect(x: capFrame.midX - stemWidth / 2, y: capFrame.midY, width: stemWidth, height: cell.height * 0.62)
        stem.cornerRadius = stemWidth / 2
        if spec.shape == .bar {
            // The space bar sits on two arms.
            stem.frame = CGRect(x: capFrame.minX + size.width * 0.18, y: capFrame.midY, width: size.width * 0.64, height: size.height * 0.9)
            stem.cornerRadius = 3
            stem.backgroundColor = UIColor(white: 0, alpha: 0.16).cgColor
        }
        CATransaction.commit()
        rendered = ""
    }

    func render(mode: TypingMode, shift: KeyboardView.ShiftState) {
        guard capSize.width > 0 else { return }
        var lower = spec.lower
        var lamp = KeyCapRenderer.Lamp.off
        var red = false
        switch spec.action {
        case .delete:
            lower = mode == .typewriter ? "X-OUT" : "BACK\nSPACE"
            red = mode == .typewriter
            accessibilityLabel = mode == .typewriter ? "Strike out" : "Delete"
            accessibilityHint = mode == .typewriter ? "Types an x over the last character." : nil
        case .shift:
            lamp = shift == .locked ? .locked : (shift == .once ? .on : .off)
            accessibilityValue = shift == .locked ? "Locked" : (shift == .once ? "On" : nil)
        default:
            break
        }
        let key = "\(lower)-\(lamp)-\(red)-\(capSize)"
        guard key != rendered else { return }
        rendered = key
        capLayer.contents = KeyCapRenderer.image(shape: spec.shape, size: capSize, upper: spec.upper, lower: lower, lamp: lamp, red: red).cgImage
    }

    func setPressed(_ pressed: Bool, reduceMotion: Bool) {
        let travel = diameter * 0.07
        if pressed {
            // Down instantly: the key should never feel late.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            capLayer.transform = CATransform3DScale(CATransform3DMakeTranslation(0, travel, 0), 0.955, 0.955, 1)
            shadowLayer.transform = capLayer.transform
            shadowLayer.shadowOffset = CGSize(width: 0, height: diameter * 0.02)
            shadowLayer.shadowRadius = diameter * 0.03
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setAnimationDuration(reduceMotion ? 0 : 0.16)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 1.6, 0.4, 1))
            capLayer.transform = CATransform3DIdentity
            shadowLayer.transform = CATransform3DIdentity
            shadowLayer.shadowOffset = CGSize(width: 0, height: diameter * 0.08)
            shadowLayer.shadowRadius = diameter * 0.07
            CATransaction.commit()
        }
    }

    override func accessibilityActivate() -> Bool {
        onAccessibilityActivate?()
        return true
    }
}

/// The little brass maker's plate on the deck.
final class BadgeView: UIView {
    var finish: MachineFinish = .seafoam { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        let plate = bounds.insetBy(dx: 1, dy: 1)
        let path = UIBezierPath(roundedRect: plate, cornerRadius: plate.height / 2)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 1.5, color: UIColor(white: 0, alpha: 0.35).cgColor)
        UIColor(hex: 0xB8955A).setFill()
        path.fill()
        cg.restoreGState()
        cg.saveGState()
        path.addClip()
        let brass = CGGradient(colorsSpace: nil, colors: [
            UIColor(hex: 0xF2DCA6).cgColor, UIColor(hex: 0xB8955A).cgColor, UIColor(hex: 0xE3C88E).cgColor, UIColor(hex: 0x8A6A35).cgColor,
        ] as CFArray, locations: [0, 0.45, 0.6, 1])!
        cg.drawLinearGradient(brass, start: CGPoint(x: 0, y: plate.minY), end: CGPoint(x: 0, y: plate.maxY), options: [])
        cg.restoreGState()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Legend.uiFont(size: plate.height * 0.56),
            .foregroundColor: UIColor(hex: 0x3B2A12),
            .kern: plate.height * 0.24,
        ]
        let text = NSAttributedString(string: "CARRIAGE", attributes: attributes)
        let size = text.size()
        text.draw(at: CGPoint(x: plate.midX - size.width / 2 + plate.height * 0.12, y: plate.midY - size.height / 2))
    }
}
