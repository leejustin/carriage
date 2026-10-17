import CoreGraphics
import Testing
@testable import FoldKit

@Suite struct ResolveTests {
    @Test func noHingeIsRegular() {
        let state = FoldMonitor.resolve(hinge: nil, division: nil, hardwareKeyboard: false)
        #expect(state.posture == .regular)
        #expect(!state.hasHinge)
    }

    @Test(arguments: [
        (HingeReading.Status.closed, 0.0, FoldPosture.closed),
        (.partiallyOpen, 100, .halfOpen),
        (.fullyOpen, 180, .flat),
        (.unknown, 5, .closed),
        (.unknown, 90, .halfOpen),
        (.unknown, 178, .flat),
    ])
    func statusMapsToPosture(status: HingeReading.Status, angle: Double, expected: FoldPosture) {
        let state = FoldMonitor.resolve(hinge: HingeReading(status: status, angle: angle), division: nil, hardwareKeyboard: false)
        #expect(state.posture == expected)
        #expect(state.hingeAngle == angle)
    }

    @Test func closedDropsTheDivision() {
        let division = FoldDivision(frame: CGRect(x: 0, y: 400, width: 600, height: 20))
        let state = FoldMonitor.resolve(hinge: HingeReading(status: .closed, angle: 0), division: division, hardwareKeyboard: true)
        #expect(state.division == nil)
        #expect(state.hardwareKeyboard)
    }
}

@Suite struct PaneTests {
    @Test func horizontalFoldSplitsTopAndBottom() throws {
        let state = FoldState(posture: .halfOpen, division: FoldDivision(frame: CGRect(x: 0, y: 460, width: 670, height: 30)))
        let panes = try #require(state.panes(in: CGRect(x: 0, y: 0, width: 670, height: 950)))
        #expect(panes.axis == .horizontal)
        #expect(panes.first == CGRect(x: 0, y: 0, width: 670, height: 460))
        #expect(panes.second == CGRect(x: 0, y: 490, width: 670, height: 460))
    }

    @Test func verticalFoldSplitsLeftAndRight() throws {
        let state = FoldState(posture: .flat, division: FoldDivision(frame: CGRect(x: 460, y: 0, width: 30, height: 670)))
        let panes = try #require(state.panes(in: CGRect(x: 0, y: 0, width: 950, height: 670)))
        #expect(panes.axis == .vertical)
        #expect(panes.first.width == 460)
        #expect(panes.second.minX == 490)
    }

    @Test func creaseExcludesMargins() {
        let division = FoldDivision(frame: CGRect(x: 0, y: 100, width: 300, height: 30), margins: FoldInsets(top: 10, bottom: 10))
        #expect(division.crease == CGRect(x: 0, y: 110, width: 300, height: 10))
    }

    @Test func simulationPlacesFoldInTheMiddle() throws {
        let state = try #require(FoldSimulation.halfOpen.state(in: CGSize(width: 600, height: 1000), hardwareKeyboard: false))
        let division = try #require(state.division)
        #expect(division.axis == .horizontal)
        #expect(abs(division.frame.midY - 500) < 0.01)
        #expect(state.isSimulated)
    }
}
