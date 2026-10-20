import CoreGraphics
import FoldKit

/// Where the paper and keys go for each way the phone is held.
struct DeskLayout: Equatable {
    enum Kind: String, Equatable {
        /// Half-folded: paper on the top half, keys on the bottom half.
        case hero
        /// Open flat with the fold across: paper above, keys below.
        case flatStacked
        /// Held like a book, the fold down the middle: the page as a two-page spread to read. Typing is top and
        /// bottom only, so the keys wait until the phone is turned on its side.
        case book
        /// A regular iPhone: paper over a smaller keyboard.
        case regular
        /// The outer screen: read and lightly edit with the system keyboard.
        case closed
        /// A hardware keyboard is attached: full-screen paper, keys hidden.
        case hardware
        /// The writer chose the system keyboard (dictation, other languages, assistive input).
        case systemKeyboard
    }

    var kind: Kind
    var paper: CGRect
    var keyboard: CGRect?
    /// The fold line, for drawing the hinge between the halves.
    var crease: CGRect?
    /// The right-hand page when held like a book.
    var facing: CGRect?

    var presentation: PaperPresentation {
        switch kind {
        case .closed, .systemKeyboard: .editing
        default: .typing
        }
    }

    var showsKeyboard: Bool { keyboard != nil }

    /// The maker's plate only fits on a full-size deck.
    var showsBadge: Bool {
        switch kind {
        case .hero, .flatStacked: true
        default: false
        }
    }

    static func make(size: CGSize, fold: FoldState, useSystemKeyboard: Bool) -> DeskLayout {
        let bounds = CGRect(origin: .zero, size: size)
        if fold.posture == .closed {
            return DeskLayout(kind: .closed, paper: bounds)
        }
        if useSystemKeyboard {
            return DeskLayout(kind: .systemKeyboard, paper: bounds)
        }
        if fold.hardwareKeyboard {
            return DeskLayout(kind: .hardware, paper: bounds)
        }
        if let panes = fold.panes(in: bounds), panes.first.width > 100, panes.first.height > 100 {
            switch panes.axis {
            case .horizontal:
                return DeskLayout(kind: fold.posture == .halfOpen ? .hero : .flatStacked,
                                  paper: panes.first, keyboard: panes.second, crease: fold.division?.frame)
            case .vertical:
                return DeskLayout(kind: .book, paper: panes.first, crease: fold.division?.frame, facing: panes.second)
            }
        }
        // A regular iPhone, or a fold with no line to split on.
        let portrait = size.height >= size.width
        let keyboardHeight: CGFloat
        // Tall enough for five rows of comfortable targets (about 48 pt each in portrait).
        if portrait {
            keyboardHeight = min(size.width * 0.72, size.height * 0.44).rounded()
        } else {
            keyboardHeight = (size.height * 0.58).rounded()
        }
        let keyboard = CGRect(x: 0, y: size.height - keyboardHeight, width: size.width, height: keyboardHeight)
        let paper = CGRect(x: 0, y: 0, width: size.width, height: size.height - keyboardHeight)
        return DeskLayout(kind: .regular, paper: paper, keyboard: keyboard)
    }
}
