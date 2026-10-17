import CoreGraphics

/// A stand-in fold for building and testing on SDKs or simulators that have no hinge.
///
/// Until the iOS 27.1 SDK and an iPhone Duo simulator are in the build, this is the only way to see the
/// half-folded and flat layouts. It is also handy for screenshots and UI tests.
public enum FoldSimulation: String, CaseIterable, Identifiable, Sendable {
    case off
    case regular
    case closed
    case halfOpen
    case flat
    case flatBook

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: "Off (use the hardware)"
        case .regular: "Regular iPhone"
        case .closed: "Closed (outer screen)"
        case .halfOpen: "Half-folded"
        case .flat: "Open flat, fold across"
        case .flatBook: "Open flat, fold down the middle"
        }
    }

    /// The width of the simulated crease plus its margins, in points.
    public static let creaseThickness: CGFloat = 28

    func state(in size: CGSize, hardwareKeyboard: Bool) -> FoldState? {
        let margins = FoldInsets(top: 10, left: 10, bottom: 10, right: 10)
        func across() -> FoldDivision {
            let t = Self.creaseThickness
            return FoldDivision(
                frame: CGRect(x: 0, y: (size.height - t) / 2, width: size.width, height: t),
                margins: FoldInsets(top: margins.top, bottom: margins.bottom)
            )
        }
        func down() -> FoldDivision {
            let t = Self.creaseThickness
            return FoldDivision(
                frame: CGRect(x: (size.width - t) / 2, y: 0, width: t, height: size.height),
                margins: FoldInsets(left: margins.left, right: margins.right)
            )
        }
        switch self {
        case .off:
            return nil
        case .regular:
            return FoldState(posture: .regular, hardwareKeyboard: hardwareKeyboard, isSimulated: true)
        case .closed:
            return FoldState(posture: .closed, hingeAngle: 0, hasHinge: true, hardwareKeyboard: hardwareKeyboard, isSimulated: true)
        case .halfOpen:
            return FoldState(posture: .halfOpen, hingeAngle: 105, hasHinge: true, division: across(), hardwareKeyboard: hardwareKeyboard, isSimulated: true)
        case .flat:
            return FoldState(posture: .flat, hingeAngle: 180, hasHinge: true, division: across(), hardwareKeyboard: hardwareKeyboard, isSimulated: true)
        case .flatBook:
            return FoldState(posture: .flat, hingeAngle: 180, hasHinge: true, division: down(), hardwareKeyboard: hardwareKeyboard, isSimulated: true)
        }
    }
}
