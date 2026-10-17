import UIKit

/// How the paper is presented.
enum PaperPresentation: Equatable {
    /// The typewriter: fixed typing line, platen, moving carriage, input from the typewriter keys or a hardware keyboard.
    case typing
    /// Plain reading and light editing with the system keyboard: the closed outer screen, or the accessibility setting.
    case editing
}

struct PaperConfiguration: Equatable {
    var presentation: PaperPresentation = .typing
    var face: Typeface = .preferred
    var lineWidth: LineWidth = .standard
    var spacing: LineSpacing = .single
    var carriage: CarriageTravel = .gentle
    var paper: PaperStyle = .bond
    var ink: InkStyle = .black
    var finish: MachineFinish = .seafoam
    var typebars = true
    var reduceMotion = false
    var inkSeed = 1
}

/// The measurements everything on the paper is laid out from.
struct PaperMetrics: Equatable {
    var fontSize: CGFloat
    var advance: CGFloat
    var margin: CGFloat
    var paperWidth: CGFloat
    var columns: Int

    var bellColumn: Int { max(1, columns - 7) }

    static func make(width: CGFloat, configuration c: PaperConfiguration) -> PaperMetrics {
        let ratio = c.face.advance(size: 100) / 100
        let standardMargin: CGFloat = 6
        switch c.presentation {
        case .typing:
            // Fit the full line at a readable size. Where even the smallest readable size won't fit (a regular
            // iPhone in portrait), the line gets shorter instead; text is soft-wrapped, so nothing is lost.
            let usable = min(width * 0.96, 900)
            let narrow = width < 520
            let marginColumns: CGFloat = narrow ? 3.5 : standardMargin
            let fitted = usable / ((CGFloat(c.lineWidth.rawValue) + marginColumns * 2) * ratio)
            let size = min(max(fitted, narrow ? 12.5 : 13.5), 21).rounded(toPlaces: 1)
            let advance = c.face.advance(size: size)
            let margin = (advance * marginColumns).rounded()
            let fits = Int((usable - margin * 2) / advance)
            let columns = max(24, min(c.lineWidth.rawValue, fits))
            return PaperMetrics(fontSize: size, advance: advance, margin: margin,
                                paperWidth: (advance * CGFloat(columns) + margin * 2).rounded(.up),
                                columns: columns)
        case .editing:
            // Reading: a comfortable size, with the text rewrapped to the screen.
            let paperWidth = min(width - 20, 720)
            let size: CGFloat = width < 420 ? 15 : 17
            let advance = c.face.advance(size: size)
            let margin = max(18, min(48, (paperWidth * 0.07).rounded()))
            let columns = Int((paperWidth - margin * 2) / advance)
            return PaperMetrics(fontSize: size, advance: advance, margin: margin, paperWidth: paperWidth, columns: columns)
        }
    }
}

/// The top of the typewriter: paper, platen, scale, type guide and the typebar that strikes.
final class PaperView: UIView {
    let textView = PaperTextView()
    let keyCatcher = KeyCatcher()
    /// Clips the paper where it wraps under the platen, while letting its side shadows show.
    private let clip = UIView()

    var onTap: (() -> Void)?
    /// Called after the whole page is re-inked (which clears spelling underlines).
    var onRestyle: (() -> Void)?
    var onReturnLever: (() -> Void)?

    private(set) var configuration = PaperConfiguration()
    private(set) var metrics = PaperMetrics(fontSize: 14, advance: 8.4, margin: 50, paperWidth: 620, columns: 62)
    private(set) var styler: InkStyler

    private let desk = CAGradientLayer()
    /// The rest of the sheet, standing up behind the platen on the paper table.
    private let rearSheet = UIView()
    private let rearShade = CAGradientLayer()
    private let vignette = CAGradientLayer()
    private let platen = PlatenView()
    private let scale = MarginScaleView()
    private let guide = TypeGuideView()
    private let lever = ReturnLeverView()
    private let typebar = CAShapeLayer()
    private let freshInk = UILabel()

    /// Room to leave for system UI, set by the layout: the controls and status area on top, the home indicator below.
    private var chromeInsets = UIEdgeInsets.zero

    /// The x of the paper's left edge relative to this view, which moves as the carriage travels.
    private var carriageX: CGFloat = 0
    private lazy var carriagePan = UIPanGestureRecognizer(target: self, action: #selector(carriageDragged(_:)))
    private let rackTick = UISelectionFeedbackGenerator()
    private var dragStartX: CGFloat = 0
    private var dragTravel: CGFloat = 0
    private var dragTicks = 0
    /// Called for each rack tick while the carriage is pushed by hand, for a soft click.
    var onRackTick: (() -> Void)?

    /// The x where the next character prints, relative to this view.
    private(set) var strikeX: CGFloat = 0
    private var lastLayoutSize: CGSize = .zero
    /// Set when the face, spacing or presentation changed, so the next layout re-inks even if the metrics match.
    private var needsRestyle = true

    // Vertical layout of the typing presentation.
    private var platenHeight: CGFloat = 34
    private var scaleHeight: CGFloat = 11
    private var platenY: CGFloat = 0
    private var scaleY: CGFloat { platenY - scaleHeight }
    /// The vertical centre of the line being typed.
    private var typingLineY: CGFloat { scaleY - 5 - styler.lineHeight / 2 }

    override init(frame: CGRect) {
        let c = PaperConfiguration()
        styler = InkStyler(font: c.face.font(size: 14), ink: c.ink, paper: c.paper, face: c.face, seed: 1, lineSpacing: c.spacing, advance: 8.4)
        super.init(frame: frame)
        clipsToBounds = true

        layer.addSublayer(desk)
        rearSheet.isUserInteractionEnabled = false
        rearSheet.layer.shadowColor = UIColor.black.cgColor
        rearSheet.layer.shadowOpacity = 0.25
        rearSheet.layer.shadowRadius = 8
        rearShade.colors = [UIColor(white: 0, alpha: 0.16).cgColor, UIColor(white: 0, alpha: 0.02).cgColor, UIColor(white: 0, alpha: 0.09).cgColor]
        rearShade.locations = [0, 0.7, 1]
        rearSheet.layer.addSublayer(rearShade)
        addSubview(rearSheet)
        clip.clipsToBounds = true
        addSubview(clip)
        clip.addSubview(textView)
        textView.isEditable = false
        textView.isSelectable = false

        freshInk.isUserInteractionEnabled = false
        freshInk.alpha = 0
        textView.addSubview(freshInk)

        vignette.colors = [UIColor(white: 0, alpha: 0.38).cgColor, UIColor(white: 0, alpha: 0).cgColor]
        layer.addSublayer(vignette)

        addSubview(scale)
        addSubview(platen)
        addSubview(guide)
        addSubview(lever)
        lever.addTarget(self, action: #selector(leverPulled), for: .primaryActionTriggered)

        typebar.lineCap = .round
        typebar.lineWidth = 3
        typebar.strokeColor = UIColor(hex: 0x50565A).cgColor
        typebar.fillColor = nil
        typebar.strokeEnd = 0
        typebar.shadowColor = UIColor.black.cgColor
        typebar.shadowOpacity = 0.35
        typebar.shadowRadius = 2
        typebar.shadowOffset = CGSize(width: 0, height: 1)
        layer.addSublayer(typebar)

        addSubview(keyCatcher)

        addGestureRecognizer(carriagePan)
        // Scrolling the page waits to see whether a drag is a push on the carriage.
        textView.panGestureRecognizer.require(toFail: carriagePan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)

        isAccessibilityElement = false
        textView.accessibilityLabel = "Page"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Configuration

    /// Applies new settings. Re-inks the whole page only when something that affects ink changed.
    func configure(_ new: PaperConfiguration) {
        let old = configuration
        configuration = new
        let presentationChanged = old.presentation != new.presentation
        if presentationChanged { applyPresentation() }
        if old.finish != new.finish || desk.colors == nil { applyFinish() }
        if old.paper != new.paper || textView.sheet.backgroundColor == nil {
            textView.setPaper(new.paper)
            rearSheet.backgroundColor = UIColor(patternImage: PaperTexture.paper(new.paper))
            rearSheet.alpha = new.paper.opacity
        }
        let needsMetrics = presentationChanged || old.face != new.face || old.lineWidth != new.lineWidth || old.spacing != new.spacing
        let needsInk = needsMetrics || old.ink != new.ink || old.paper != new.paper || old.inkSeed != new.inkSeed
        if needsMetrics {
            lastLayoutSize = .zero
            needsRestyle = true
            setNeedsLayout()
        }
        if needsInk && !needsMetrics { rebuildStyler(restyle: true) }
        if old.carriage != new.carriage { setNeedsLayout() }
    }

    private func applyPresentation() {
        let typing = configuration.presentation == .typing
        textView.isEditable = !typing
        textView.isSelectable = !typing
        textView.alwaysBounceVertical = true
        [platen, scale, guide, lever, rearSheet].forEach { $0.isHidden = !typing }
        vignette.isHidden = !typing
        typebar.isHidden = !typing
        if typing {
            if textView.isFirstResponder { textView.resignFirstResponder() }
        } else {
            if keyCatcher.isFirstResponder { keyCatcher.resignFirstResponder() }
        }
    }

    private func applyFinish() {
        let f = configuration.finish
        desk.colors = [f.shadow.mixed(with: .black, amount: 0.35).cgColor, f.shadow.cgColor, f.body.mixed(with: .black, amount: 0.12).cgColor]
        desk.locations = [0, 0.55, 1]
    }

    private func rebuildStyler(restyle: Bool) {
        let c = configuration
        let font = c.face.font(size: metrics.fontSize)
        styler = InkStyler(font: font, ink: c.ink, paper: c.paper, face: c.face, seed: c.inkSeed, lineSpacing: c.spacing, advance: metrics.advance)
        textView.typingAttributes = styler.baseAttributes
        textView.advance = metrics.advance
        textView.inkColor = c.ink.color
        freshInk.font = font
        if restyle {
            let storage = textView.textStorage
            storage.beginEditing()
            styler.style(storage, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
            textView.refreshStrikes()
            onRestyle?()
        }
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        desk.frame = bounds
        vignette.frame = CGRect(x: 0, y: 0, width: size.width, height: min(56, size.height * 0.18))
        CATransaction.commit()

        if size != lastLayoutSize {
            lastLayoutSize = size
            let newMetrics = PaperMetrics.make(width: size.width, configuration: configuration)
            // Re-ink only when the type itself changes; a fold or inset change that keeps the metrics just re-lays out.
            if newMetrics != metrics || needsRestyle {
                needsRestyle = false
                metrics = newMetrics
                rebuildStyler(restyle: true)
            }
            layoutPaper()
        }
    }

    private func layoutPaper() {
        let size = bounds.size
        switch configuration.presentation {
        case .typing:
            platenHeight = min(max(size.height * 0.1, 26), 42)
            scaleHeight = min(max(size.height * 0.032, 9), 13)
            platenY = size.height - platenHeight - max(4, size.height * 0.015, chromeInsets.bottom)
            let paperBottom = platenY + platenHeight * 0.55
            textView.textContainerInset = UIEdgeInsets(top: styler.lineHeight * 4, left: metrics.margin, bottom: styler.lineHeight * 2, right: metrics.margin)
            textView.contentInset = UIEdgeInsets(top: size.height, left: 0, bottom: size.height, right: 0)
            textView.sheetTail = size.height
            clip.frame = CGRect(x: 0, y: 0, width: size.width, height: paperBottom)
            textView.frame = CGRect(x: carriageX, y: 0, width: metrics.paperWidth, height: paperBottom)
            textView.isScrollEnabled = true
            scale.advance = metrics.advance
            scale.leftMargin = metrics.margin
            scale.columns = metrics.columns
            scale.bellColumn = metrics.bellColumn
            syncCarriage(.none)
        case .editing:
            // Leave room for the controls floating over the top of the page.
            textView.textContainerInset = UIEdgeInsets(top: chromeInsets.top + 58 + styler.lineHeight, left: metrics.margin, bottom: styler.lineHeight * 3 + chromeInsets.bottom, right: metrics.margin)
            textView.contentInset = .zero
            textView.sheetTail = 0
            carriageX = ((size.width - metrics.paperWidth) / 2).rounded()
            clip.frame = bounds
            textView.frame = CGRect(x: carriageX, y: 0, width: metrics.paperWidth, height: size.height)
        }
        keyCatcher.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    /// The hinge angle, when the system reports one. As the top half leans back, the light on the paper falls
    /// away toward the top, the way it does on a real machine's paper table.
    func setHingeAngle(_ degrees: Double?) {
        let lean = degrees.map { CGFloat(max(0, min(1, (180 - $0) / 90))) } ?? 0.35
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        vignette.colors = [UIColor(white: 0, alpha: 0.22 + 0.3 * lean).cgColor, UIColor(white: 0, alpha: 0).cgColor]
        rearShade.colors = [UIColor(white: 0, alpha: 0.08 + 0.16 * lean).cgColor, UIColor(white: 0, alpha: 0.02).cgColor, UIColor(white: 0, alpha: 0.09).cgColor]
        CATransaction.commit()
    }

    // MARK: The carriage

    enum CarriageMotion {
        case none, step, back, carriageReturn(TimeInterval), snap
    }

    /// Moves the paper so the next character lands on the typing line, sliding the carriage across as needed.
    func syncCarriage(_ motion: CarriageMotion) {
        guard configuration.presentation == .typing, bounds.width > 0 else { return }
        textView.layoutIfNeeded()
        let caret = textView.endCaretRect
        let x = restingCarriageX(forCaretX: caret.minX)
        let targetOffset = CGPoint(x: 0, y: (caret.midY - typingLineY).rounded())
        let apply = { self.placeCarriage(x: x, caretX: caret.minX) }
        let scroll = { self.textView.setContentOffset(targetOffset, animated: false) }
        let reduce = configuration.reduceMotion
        switch motion {
        case .none:
            UIView.performWithoutAnimation { apply(); scroll() }
        case .snap:
            UIView.animate(withDuration: reduce ? 0 : 0.22, delay: 0, options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction]) { apply(); scroll() }
        case .step, .back:
            // The escapement: a quick hop of one character.
            UIView.animate(withDuration: reduce ? 0 : 0.05, delay: 0, options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction], animations: apply)
            if textView.contentOffset != targetOffset {
                UIView.animate(withDuration: reduce ? 0 : 0.12, delay: 0, options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction], animations: scroll)
            }
        case .carriageReturn(let duration):
            // Line feed first, then the long slide back to the margin.
            UIView.animate(withDuration: reduce ? 0 : 0.11, delay: 0, options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction], animations: scroll)
            UIView.animate(withDuration: reduce ? 0 : duration, delay: reduce ? 0 : 0.06, usingSpringWithDamping: 0.86, initialSpringVelocity: 0.2,
                           options: [.beginFromCurrentState, .allowUserInteraction], animations: apply)
        }
    }

    /// Where the paper's left edge sits when the next character prints at `caretX` (in paper coordinates).
    private func restingCarriageX(forCaretX caretX: CGFloat) -> CGFloat {
        let w = bounds.width, p = metrics.paperWidth
        let centered = (w - p) / 2
        var x = centered + configuration.carriage.amount * (p / 2 - caretX)
        // Whatever the setting, keep the printing point on screen.
        let pad = min(56, w * 0.12)
        x = min(max(x, pad - caretX), w - pad - caretX)
        return x.rounded()
    }

    /// Moves everything that rides on the carriage.
    private func placeCarriage(x: CGFloat, caretX: CGFloat) {
        let p = metrics.paperWidth
        carriageX = x
        textView.frame.origin.x = x
        platen.frame = CGRect(x: x - platen.knobWidth - 6, y: platenY, width: p + (platen.knobWidth + 6) * 2, height: platenHeight)
        scale.frame = CGRect(x: x, y: scaleY, width: p, height: scaleHeight)
        lever.frame = CGRect(x: x - platen.knobWidth - 6 - 38, y: platenY - 34, width: 44, height: 44)
        // The sheet leans back, so it reads a touch narrower than the front.
        let inset = p * 0.012
        rearSheet.frame = CGRect(x: x + inset, y: -20, width: p - inset * 2, height: platenY + 20)
        rearSheet.layer.shadowPath = UIBezierPath(rect: rearSheet.bounds).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rearShade.frame = rearSheet.bounds
        CATransaction.commit()
        let strike = x + caretX + metrics.advance / 2
        strikeX = strike
        guide.frame = CGRect(x: strike - 17, y: scaleY - 9, width: 34, height: 12)
    }

    // MARK: Pushing the carriage back by hand

    /// Drag the paper (or the lever) to the right to return the carriage, as on the real machine. The carriage
    /// follows the finger and ticks through the rack; let go past the threshold and it returns. The RETURN key
    /// still does the same thing instantly.
    @objc private func carriageDragged(_ pan: UIPanGestureRecognizer) {
        let caretX = textView.endCaretRect.minX
        switch pan.state {
        case .began:
            dragStartX = carriageX
            // How far the carriage has to travel back to the left margin.
            dragTravel = max(0, restingCarriageX(forCaretX: metrics.margin) - carriageX)
            dragTicks = 0
            rackTick.prepare()
        case .changed:
            let pulled = max(0, pan.translation(in: self).x)
            // Past the margin stop, the carriage only gives a little.
            let offset = pulled <= dragTravel ? pulled : dragTravel + (pulled - dragTravel) * 0.15
            placeCarriage(x: dragStartX + offset, caretX: caretX - min(offset, dragTravel))
            lever.transform = CGAffineTransform(rotationAngle: min(0.25, pulled / 400))
            // A tick every five characters of rack, felt and heard.
            let ticks = Int(min(pulled, max(dragTravel, 60)) / (metrics.advance * 5))
            if ticks > dragTicks {
                dragTicks = ticks
                rackTick.selectionChanged()
                rackTick.prepare()
                onRackTick?()
            }
        case .ended:
            let pulled = max(0, pan.translation(in: self).x)
            let threshold = max(44, dragTravel * 0.4)
            UIView.animate(withDuration: 0.2) { self.lever.transform = .identity }
            if pulled >= threshold || pan.velocity(in: self).x > 700 {
                onReturnLever?()
            } else {
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
                    self.placeCarriage(x: self.dragStartX, caretX: caretX)
                }
            }
        case .cancelled, .failed:
            UIView.animate(withDuration: 0.2) {
                self.lever.transform = .identity
                self.placeCarriage(x: self.dragStartX, caretX: caretX)
            }
        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard gesture === carriagePan else { return super.gestureRecognizerShouldBegin(gesture) }
        guard configuration.presentation == .typing else { return false }
        // Only a sideways push to the right; anything else is scrolling the page.
        let v = carriagePan.velocity(in: self)
        return v.x > 0 && v.x > abs(v.y) * 1.3
    }

    /// The column the next character will print in.
    var currentColumn: Int {
        let caret = textView.endCaretRect
        return max(0, Int(((caret.minX - metrics.margin) / metrics.advance).rounded()))
    }

    /// The vertical position of the next character, in content coordinates.
    var currentLineY: CGFloat { textView.endCaretRect.midY }

    /// A fresh sheet rolls up from behind the platen.
    func feedIn() {
        guard configuration.presentation == .typing, !configuration.reduceMotion else { return }
        let target = textView.contentOffset
        textView.setContentOffset(CGPoint(x: 0, y: target.y - bounds.height * 0.85), animated: false)
        UIView.animate(withDuration: 0.7, delay: 0.04, options: [.curveEaseOut, .allowUserInteraction]) {
            self.textView.contentOffset = target
        }
    }

    /// The finished sheet is pulled up and out of the machine.
    func pullOut(completion: @escaping () -> Void) {
        guard configuration.presentation == .typing, !configuration.reduceMotion else { return completion() }
        let start = textView.contentOffset
        UIView.animate(withDuration: 0.45, delay: 0, options: [.curveEaseIn]) {
            self.textView.contentOffset = CGPoint(x: 0, y: start.y + self.textView.contentSize.height + self.bounds.height)
            self.textView.alpha = 0.0
        } completion: { _ in
            self.textView.alpha = 1
            completion()
        }
    }

    // MARK: Strikes

    /// The typebar swings up from the basket and hits the paper. `fan` is the key's position, 0 (left) to 1 (right).
    func strike(fan: CGFloat, character: String, at range: NSRange?) {
        guard configuration.presentation == .typing else { return }
        if configuration.typebars && !configuration.reduceMotion {
            let target = CGPoint(x: strikeX - metrics.advance, y: typingLineY + 2)
            let pivot = CGPoint(x: strikeX + (fan - 0.5) * min(260, bounds.width * 0.5), y: bounds.height + 60)
            let path = UIBezierPath()
            path.move(to: pivot)
            path.addLine(to: target)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            typebar.path = path.cgPath
            CATransaction.commit()
            let swing = CAKeyframeAnimation(keyPath: "strokeEnd")
            swing.values = [0.6, 1, 0.6]
            swing.keyTimes = [0, 0.38, 1]
            swing.duration = 0.085
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, 1, 1, 0]
            opacity.keyTimes = [0, 0.2, 0.7, 1]
            opacity.duration = 0.085
            typebar.add(swing, forKey: "swing")
            typebar.add(opacity, forKey: "fade")
        }
        guard let range, !character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        flashInk(character, range: range)
    }

    /// A freshly struck character is darkest for an instant, then settles into the ribbon's colour.
    private func flashInk(_ character: String, range: NSRange) {
        guard !configuration.reduceMotion, let rect = textView.segmentRects(for: range).last else { return }
        freshInk.layer.removeAllAnimations()
        freshInk.text = character
        freshInk.textColor = configuration.ink.color
        freshInk.sizeToFit()
        freshInk.center = CGPoint(x: rect.midX, y: rect.midY + styler.lineHeight * 0.0)
        freshInk.alpha = 0.7
        freshInk.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
        UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.freshInk.alpha = 0
            self.freshInk.transform = .identity
        }
    }

    // MARK: Input

    /// Makes the hidden key catcher first responder so hardware keyboards type onto the page.
    func activateHardwareInput() {
        guard configuration.presentation == .typing, window != nil else { return }
        if !keyCatcher.isFirstResponder { keyCatcher.becomeFirstResponder() }
    }

    /// Sets the room to leave for the status area and home indicator where the paper meets the screen edge.
    func setChromeInsets(_ insets: UIEdgeInsets) {
        guard insets != chromeInsets else { return }
        chromeInsets = insets
        lastLayoutSize = .zero
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        DispatchQueue.main.async { self.activateHardwareInput() }
    }

    @objc private func tapped() {
        onTap?()
        activateHardwareInput()
    }

    @objc private func leverPulled() {
        onReturnLever?()
    }
}

/// An invisible first responder that receives hardware keyboard typing without raising the system keyboard.
final class KeyCatcher: UIView, UIKeyInput {
    var onInsert: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var onHardwarePress: (() -> Void)?

    private let emptyInput = UIView(frame: .zero)

    override var canBecomeFirstResponder: Bool { true }
    override var inputView: UIView? { get { emptyInput } set {} }
    var hasText: Bool { true }

    var autocorrectionType: UITextAutocorrectionType { get { .no } set {} }
    var spellCheckingType: UITextSpellCheckingType { get { .no } set {} }
    var autocapitalizationType: UITextAutocapitalizationType { get { .none } set {} }
    var smartQuotesType: UITextSmartQuotesType { get { .no } set {} }
    var smartDashesType: UITextSmartDashesType { get { .no } set {} }
    var keyboardType: UIKeyboardType { get { .asciiCapable } set {} }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func insertText(_ text: String) { onInsert?(text) }
    func deleteBackward() { onDelete?() }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.key != nil }) { onHardwarePress?() }
        super.pressesBegan(presses, with: event)
    }
}

extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let m = pow(10, CGFloat(places))
        return (self * m).rounded() / m
    }
}
