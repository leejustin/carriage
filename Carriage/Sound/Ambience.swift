import Foundation

/// A real room under the keys, for writers who like one: recorded rain on a window, or a fire in the grate.
nonisolated enum Ambience: String, CaseIterable, Identifiable, Codable, Sendable {
    case off, rain, fire

    var id: String { rawValue }

    var name: String {
        switch self {
        case .off: "Off"
        case .rain: "Rain on the window"
        case .fire: "Fireplace"
        }
    }
}
