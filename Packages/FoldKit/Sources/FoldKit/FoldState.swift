import CoreGraphics
import Foundation

/// How the device is physically held, as far as an app can tell.
public enum FoldPosture: String, Sendable, CaseIterable, Identifiable {
    /// A phone without a hinge.
    case regular
    /// A foldable that is shut; the app is on the outer screen.
    case closed
    /// A foldable bent partway, like a tiny laptop or a book.
    case halfOpen
    /// A foldable opened all the way flat.
    case flat

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .regular: "Regular iPhone"
        case .closed: "Closed"
        case .halfOpen: "Half-folded"
        case .flat: "Open flat"
        }
    }
}

/// Which way the fold line runs across the window.
public enum FoldAxis: String, Sendable {
    /// The fold runs left to right, so content splits into top and bottom.
    case horizontal
    /// The fold runs top to bottom, so content splits into left and right.
    case vertical
}

/// The fold line ("division" reserved region) in the coordinate space of the view that was probed.
public struct FoldDivision: Equatable, Sendable {
    /// The full region, including the margins where interactive content shouldn't go.
    public var frame: CGRect
    /// The part of `frame` that is margin rather than the crease itself.
    public var margins: FoldInsets

    public init(frame: CGRect, margins: FoldInsets = .zero) {
        self.frame = frame
        self.margins = margins
    }

    public var axis: FoldAxis {
        frame.width >= frame.height ? .horizontal : .vertical
    }

    /// The crease itself, without its margins.
    public var crease: CGRect {
        CGRect(
            x: frame.minX + margins.left,
            y: frame.minY + margins.top,
            width: max(0, frame.width - margins.left - margins.right),
            height: max(0, frame.height - margins.top - margins.bottom)
        )
    }
}

/// A Sendable stand-in for UIEdgeInsets so FoldKit's value types stay platform-neutral.
public struct FoldInsets: Equatable, Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = FoldInsets()
}

/// Everything an app needs to lay itself out around a fold.
public struct FoldState: Equatable, Sendable {
    public var posture: FoldPosture
    /// The hinge angle in degrees (0 = shut, 180 = flat), when the system reports one.
    public var hingeAngle: Double?
    /// Whether the device has a hinge at all.
    public var hasHinge: Bool
    /// The active fold line inside the probed view, if any.
    public var division: FoldDivision?
    /// Whether a hardware keyboard is attached.
    public var hardwareKeyboard: Bool
    /// True when this state comes from `FoldSimulation` rather than the real hardware.
    public var isSimulated: Bool

    public init(
        posture: FoldPosture = .regular,
        hingeAngle: Double? = nil,
        hasHinge: Bool = false,
        division: FoldDivision? = nil,
        hardwareKeyboard: Bool = false,
        isSimulated: Bool = false
    ) {
        self.posture = posture
        self.hingeAngle = hingeAngle
        self.hasHinge = hasHinge
        self.division = division
        self.hardwareKeyboard = hardwareKeyboard
        self.isSimulated = isSimulated
    }

    public static let regular = FoldState()

    /// Splits `bounds` into the two panes on either side of the fold, keeping both clear of the crease margins.
    /// Returns nil when there's no fold to split around.
    public func panes(in bounds: CGRect) -> (first: CGRect, second: CGRect, axis: FoldAxis)? {
        guard let division else { return nil }
        let region = division.frame
        switch division.axis {
        case .horizontal:
            let top = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: max(0, region.minY - bounds.minY))
            let bottom = CGRect(x: bounds.minX, y: region.maxY, width: bounds.width, height: max(0, bounds.maxY - region.maxY))
            return (top, bottom, .horizontal)
        case .vertical:
            let left = CGRect(x: bounds.minX, y: bounds.minY, width: max(0, region.minX - bounds.minX), height: bounds.height)
            let right = CGRect(x: region.maxX, y: bounds.minY, width: max(0, bounds.maxX - region.maxX), height: bounds.height)
            return (left, right, .vertical)
        }
    }
}
