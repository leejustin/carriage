import UIKit

// The hinge and reserved-region APIs ship in the iOS 27.1 SDK. Swift can't tell SDK versions apart with
// `#if compiler` (Xcode 27.0 and 27.1 both use Swift 6.4), so the gate below checks UIKit's own version.
// The iOS 27.0 SDK's UIKit is 9127.0.84; anything newer is the 27.1 SDK or later.
#if canImport(UIKit, _version: 9127.0.85)
private let sdkHasHingeAPIs = true
#else
private let sdkHasHingeAPIs = false
#endif

/// An invisible view that reads the hinge and the fold line for the hierarchy it sits in.
final class FoldProbeView: UIView {
    var onChange: ((HingeReading?, FoldDivision?, CGSize) -> Void)?

    private var hinge: HingeReading?

    static var hasHingeAPIs: Bool {
        guard sdkHasHingeAPIs else { return false }
        if #available(iOS 27.1, *) { return true }
        return false
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        installHingeInteraction()
        registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self]) { (view: FoldProbeView, _) in
            view.report()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        report()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        report()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        report()
    }

    private func report() {
        guard window != nil else { return }
        onChange?(hinge, readDivision(), bounds.size)
    }

    private func installHingeInteraction() {
        #if canImport(UIKit, _version: 9127.0.85)
        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { [weak self] _, update in
                guard let self else { return }
                self.hinge = update.hinge.map { hinge in
                    HingeReading(status: HingeReading.Status(hinge.status), angle: Double(hinge.angle) * 180 / .pi)
                }
                self.report()
            }
            addInteraction(interaction)
        }
        #endif
    }

    private func readDivision() -> FoldDivision? {
        #if canImport(UIKit, _version: 9127.0.85)
        if #available(iOS 27.1, *) {
            guard let region = reservedRegions(kind: .division).first(where: \.isActive) else { return nil }
            let m = region.margins
            return FoldDivision(frame: region.frame, margins: FoldInsets(top: m.top, left: m.left, bottom: m.bottom, right: m.right))
        }
        #endif
        return nil
    }
}

#if canImport(UIKit, _version: 9127.0.85)
@available(iOS 27.1, *)
private extension HingeReading.Status {
    init(_ status: UIHinge.Status) {
        switch status {
        case .closed: self = .closed
        case .partiallyOpen: self = .partiallyOpen
        case .fullyOpen: self = .fullyOpen
        case .unknown: self = .unknown
        @unknown default: self = .unknown
        }
    }
}
#endif
