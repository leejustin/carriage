import GameController
import Observation
import SwiftUI

/// The hinge as the system reports it.
public struct HingeReading: Equatable, Sendable {
    public enum Status: Sendable, Equatable {
        case closed, partiallyOpen, fullyOpen, unknown
    }

    public var status: Status
    /// Degrees, 0 = shut, 180 = flat.
    public var angle: Double

    public init(status: Status, angle: Double) {
        self.status = status
        self.angle = angle
    }
}

/// Watches the hinge, the fold line and the hardware keyboard, and publishes one `FoldState`.
///
/// Folding is a trait change, not a relaunch: views that read `state` simply re-lay themselves out and keep their contents.
///
/// ```swift
/// @State private var fold = FoldMonitor()
///
/// var body: some View {
///     MyLayout(fold: fold.state)
///         .foldProbe(fold)
/// }
/// ```
@Observable
public final class FoldMonitor {
    /// The state to lay out with: the simulation when one is on, otherwise the hardware.
    public private(set) var state: FoldState = .regular

    /// Forces a posture, for SDKs and simulators without a hinge, previews, screenshots and tests.
    public var simulation: FoldSimulation = .off {
        didSet { recompute() }
    }

    /// The most recent hinge reading, or nil on hardware without one.
    public private(set) var hinge: HingeReading?
    /// The real fold line in the probed view's coordinates.
    public private(set) var division: FoldDivision?
    /// The probed view's size, used to place a simulated fold.
    public private(set) var probeSize: CGSize = .zero
    /// Whether a hardware keyboard looks attached, from GameController or from a key press the app reported.
    public private(set) var hardwareKeyboard: Bool = false

    /// True when this build can see real hinge data (built with the iOS 27.1 SDK or later, running on 27.1+).
    public static var supportsHingeAPIs: Bool { FoldProbeView.hasHingeAPIs }

    @ObservationIgnored private var keyboardObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var reportedKeyPress = false

    public init() {
        hardwareKeyboard = GCKeyboard.coalesced != nil
        let center = NotificationCenter.default
        keyboardObservers = [
            center.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setHardwareKeyboard(true) }
            },
            center.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reportedKeyPress = false
                    self?.setHardwareKeyboard(GCKeyboard.coalesced != nil)
                }
            },
        ]
        recompute()
    }

    /// Call when a hardware key press arrives. GameController doesn't see every keyboard (or the Simulator's),
    /// so a real key press is the most reliable sign one is attached.
    public func noteHardwareKeyPress() {
        reportedKeyPress = true
        setHardwareKeyboard(true)
    }

    /// Call when the person asks for the on-screen keys back while a hardware keyboard seems attached.
    public func dismissHardwareKeyboard() {
        reportedKeyPress = false
        setHardwareKeyboard(false)
    }

    private func setHardwareKeyboard(_ value: Bool) {
        guard hardwareKeyboard != value else { return }
        hardwareKeyboard = value
        recompute()
    }

    func update(hinge: HingeReading?, division: FoldDivision?, size: CGSize) {
        guard hinge != self.hinge || division != self.division || size != probeSize else { return }
        self.hinge = hinge
        self.division = division
        probeSize = size
        recompute()
    }

    private func recompute() {
        let next = simulation.state(in: probeSize, hardwareKeyboard: hardwareKeyboard)
            ?? Self.resolve(hinge: hinge, division: division, hardwareKeyboard: hardwareKeyboard)
        if next != state { state = next }
    }

    /// Turns raw readings into a posture. Pure, so it's easy to test.
    public static func resolve(hinge: HingeReading?, division: FoldDivision?, hardwareKeyboard: Bool) -> FoldState {
        guard let hinge else {
            // No hinge: a regular phone. A fold line without a hinge reading shouldn't happen, but treat it as flat.
            return FoldState(posture: division == nil ? .regular : .flat, division: division, hardwareKeyboard: hardwareKeyboard)
        }
        let posture: FoldPosture
        switch hinge.status {
        case .closed: posture = .closed
        case .partiallyOpen: posture = .halfOpen
        case .fullyOpen: posture = .flat
        case .unknown:
            if hinge.angle < 15 {
                posture = .closed
            } else if hinge.angle < 165 {
                posture = .halfOpen
            } else {
                posture = .flat
            }
        }
        return FoldState(
            posture: posture,
            hingeAngle: hinge.angle,
            hasHinge: true,
            division: posture == .closed ? nil : division,
            hardwareKeyboard: hardwareKeyboard
        )
    }
}

public extension View {
    /// Feeds `monitor` the hinge and fold line for this view. Put it on the view that fills the window,
    /// because the fold line is reported in this view's coordinates.
    func foldProbe(_ monitor: FoldMonitor) -> some View {
        background(FoldProbe(monitor: monitor).allowsHitTesting(false).accessibilityHidden(true))
    }
}

struct FoldProbe: UIViewRepresentable {
    let monitor: FoldMonitor

    func makeUIView(context: Context) -> FoldProbeView {
        let view = FoldProbeView()
        view.onChange = { [weak monitor] hinge, division, size in
            monitor?.update(hinge: hinge, division: division, size: size)
        }
        return view
    }

    func updateUIView(_ uiView: FoldProbeView, context: Context) {}
}
