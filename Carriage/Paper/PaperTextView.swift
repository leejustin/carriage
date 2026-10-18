import UIKit

/// The sheet of paper: a TextKit 2 text view with the paper drawn behind the text and x-strikes drawn over it.
///
/// Never touch `layoutManager` on this view; doing so drops UITextView back to TextKit 1.
final class PaperTextView: UITextView {
    let sheet = UIView()
    private let strikeOverlay = StrikeOverlayView()
    private var lastOverlayBounds: CGRect = .null

    /// The width of one character, for splitting strike segments into cells.
    var advance: CGFloat = 9 { didSet { strikeOverlay.advance = advance } }
    var inkColor: UIColor = .black { didSet { strikeOverlay.inkColor = inkColor } }
    /// How far the paper extends past the last line, so it runs under the platen.
    var sheetTail: CGFloat = 400
    /// Off in Typewriter mode: undo would take back typed text, which that mode never allows.
    var allowsUndo = true

    override var undoManager: UndoManager? { allowsUndo ? super.undoManager : nil }

    init() {
        super.init(frame: .zero, textContainer: nil)
        backgroundColor = .clear
        clipsToBounds = false
        sheet.isUserInteractionEnabled = false
        sheet.layer.shadowColor = UIColor.black.cgColor
        sheet.layer.shadowOpacity = 0.22
        sheet.layer.shadowRadius = 7
        sheet.layer.shadowOffset = CGSize(width: 0, height: 1)
        insertSubview(sheet, at: 0)
        strikeOverlay.textView = self
        addSubview(strikeOverlay)
        autocorrectionType = .no
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        spellCheckingType = .no
        inlinePredictionType = .no
        // No Apple Intelligence rewrite panel over the page either: a typewriter doesn't suggest.
        writingToolsBehavior = .none
        textContainer.lineFragmentPadding = 0
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        isFindInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setPaper(_ style: PaperStyle, night: Bool = false) {
        sheet.backgroundColor = UIColor(patternImage: night ? PaperTexture.nightPaper() : PaperTexture.paper(style))
        sheet.alpha = night ? 1 : style.opacity
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = max(contentSize.height, bounds.height) + sheetTail
        let frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        if sheet.frame != frame {
            sheet.frame = frame
            sheet.layer.shadowPath = UIBezierPath(rect: sheet.bounds).cgPath
        }
        sendSubviewToBack(sheet)
        strikeOverlay.frame = bounds
        strikeOverlay.layer.zPosition = 10
        if bounds != lastOverlayBounds {
            lastOverlayBounds = bounds
            strikeOverlay.setNeedsDisplay()
        }
    }

    func refreshStrikes() {
        strikeOverlay.setNeedsDisplay()
    }

    /// The rectangles of `range` in this view's content coordinates, one per line.
    func segmentRects(for range: NSRange) -> [CGRect] {
        guard let layout = textLayoutManager, let content = layout.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else { return [] }
        var rects: [CGRect] = []
        layout.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            rects.append(frame.offsetBy(dx: self.textContainerInset.left, dy: self.textContainerInset.top))
            return true
        }
        return rects
    }

    /// The characters TextKit has laid out around the visible area (the whole page if it can't say).
    var visibleCharacterRange: NSRange {
        let all = NSRange(location: 0, length: textStorage.length)
        guard let layout = textLayoutManager, let content = layout.textContentManager,
              let viewport = layout.textViewportLayoutController.viewportRange else { return all }
        let start = content.offset(from: content.documentRange.location, to: viewport.location)
        let length = content.offset(from: viewport.location, to: viewport.endLocation)
        return NSIntersectionRange(NSRange(location: start, length: length), all)
    }

    /// Lays out the end of the page now, where typing happens. TextKit 2 otherwise estimates the height of a long
    /// page and only lays out the end on the first key press, which drew a blank sheet and made that key slow.
    func ensureLayoutNearEnd(characters: Int = 4000) {
        guard let layout = textLayoutManager, let content = layout.textContentManager else { return }
        let end = content.documentRange.endLocation
        let back = min(characters, textStorage.length)
        guard let start = content.location(end, offsetBy: -back), let range = NSTextRange(location: start, end: end) else { return }
        layout.ensureLayout(for: range)
    }

    /// Where the next character will land, in content coordinates.
    var endCaretRect: CGRect {
        caretRect(for: endOfDocument)
    }
}

/// Draws an x over every struck character in view.
private final class StrikeOverlayView: UIView {
    weak var textView: PaperTextView?
    var advance: CGFloat = 9
    var inkColor: UIColor = .black

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let textView, textView.textStorage.length > 0 else { return }
        let storage = textView.textStorage
        let visible = textView.bounds
        let font = (storage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont) ?? .monospacedSystemFont(ofSize: 14, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: inkColor.withAlphaComponent(0.9),
            .strokeWidth: -2.0,
            .strokeColor: inkColor.withAlphaComponent(0.9),
        ]
        let x = "x" as NSString
        let glyph = x.size(withAttributes: attributes)
        storage.enumerateAttribute(.carriageStrike, in: textView.visibleCharacterRange) { value, range, _ in
            guard value != nil else { return }
            for segment in textView.segmentRects(for: range) where segment.intersects(visible) && segment.width >= advance * 0.5 {
                let cells = Int((segment.width / advance).rounded())
                for cell in 0..<cells {
                    let cx = segment.minX + (CGFloat(cell) + 0.5) * advance
                    // Each x lands slightly differently, as it would by hand.
                    let wobble = CGFloat((cell * 7 + range.location * 3) % 5) * 0.18 - 0.36
                    let origin = CGPoint(x: cx - glyph.width / 2 - visible.minX + wobble, y: segment.midY - glyph.height / 2 - visible.minY + wobble * 0.5)
                    x.draw(at: origin, withAttributes: attributes)
                }
            }
        }
    }
}
