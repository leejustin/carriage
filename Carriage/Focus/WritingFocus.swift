import AppIntents
import Observation
import SwiftUI

/// Writing focus: the page and the keys, and nothing else.
///
/// It turns on from the Focus button, or by itself when an iOS Focus with Carriage's Focus Filter is active.
/// Carriage can't silence notifications itself (iOS has no API for that); `FocusSetupView` shows how to have iOS
/// turn on Do Not Disturb whenever Carriage is open.
@Observable
final class WritingFocus {
    static let shared = WritingFocus()

    /// Turned on by hand with the Focus button.
    private(set) var manual = false
    /// Turned on by an iOS Focus through the Focus Filter.
    private(set) var fromSystem = UserDefaults.standard.bool(forKey: "focusFilterActive")
    /// The Focus Filter can also hide goals and streaks.
    private(set) var hidesGoals = UserDefaults.standard.bool(forKey: "focusFilterHidesGoals")
    /// Until this time the controls show, after a tap on the paper.
    private(set) var peekUntil: Date?

    var isOn: Bool { manual || fromSystem }
    var showsGoals: Bool { !(isOn && hidesGoals) }

    private init() {}

    func toggle() {
        if isOn {
            manual = false
            // Leaving by hand wins over the system Focus until it next changes.
            fromSystem = false
        } else {
            manual = true
            peek(for: 1.6)
        }
    }

    /// Shows the controls for a moment.
    func peek(for seconds: TimeInterval = 4) {
        let until = Date().addingTimeInterval(seconds)
        peekUntil = until
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if self?.peekUntil == until { self?.peekUntil = nil }
        }
    }

    var isPeeking: Bool { peekUntil.map { $0 > Date() } ?? false }

    func applyFilter(active: Bool, hideGoals: Bool) {
        fromSystem = active
        hidesGoals = active && hideGoals
        UserDefaults.standard.set(fromSystem, forKey: "focusFilterActive")
        UserDefaults.standard.set(hidesGoals, forKey: "focusFilterHidesGoals")
    }

    /// Re-reads the active Focus Filter, for when the app comes back to the foreground.
    func syncWithSystem() async {
        do {
            let filter = try await CarriageFocusFilter.current
            applyFilter(active: filter.clearPage, hideGoals: filter.hideGoals)
        } catch {
            // No Focus with Carriage's filter is on.
            applyFilter(active: false, hideGoals: false)
        }
    }
}

/// Carriage's Focus Filter: add it to a Focus in Settings › Focus, and Carriage clears down to the page whenever
/// that Focus is on.
struct CarriageFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Writing focus"
    static let description: IntentDescription? = IntentDescription("Clear Carriage down to the page and the keys while this Focus is on.")

    // Off by default: when the Focus turns off, the system runs the filter with its default values.
    @Parameter(title: "Clear the page", default: false)
    var clearPage: Bool

    @Parameter(title: "Hide goals and streaks", default: false)
    var hideGoals: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: clearPage ? "Writing focus" : "No change",
            subtitle: clearPage && hideGoals ? "Goals and streaks hidden" : nil
        )
    }

    static func suggestedFocusFilters(for context: FocusFilterSuggestionContext) async -> [CarriageFocusFilter] {
        let filter = CarriageFocusFilter()
        filter.clearPage = true
        filter.hideGoals = true
        return [filter]
    }

    func perform() async throws -> some IntentResult {
        let active = clearPage, hide = hideGoals
        await MainActor.run { WritingFocus.shared.applyFilter(active: active, hideGoals: hide) }
        return .result()
    }
}

/// How to have iOS silence notifications whenever Carriage is open.
struct FocusSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("MAKE IT QUIET")
                    .font(Legend.font(size: 12))
                    .tracking(3)
                    .foregroundStyle(Color.ribbonRed)
                Text("Carriage clears the screen, but only iOS can silence your notifications. Set it up once and it happens every time you open Carriage:")
                step(1, "Open Settings › Focus.")
                step(2, "Choose Do Not Disturb, or tap + to make a Writing Focus.")
                step(3, "Under Set a Schedule, tap Add Schedule › App, and choose Carriage.")
                step(4, "Optional: under Focus Filters, add Carriage › Writing focus, so the page clears itself whenever that Focus is on.")
                Text("Now opening Carriage turns the Focus on, and leaving turns it off.")
                    .foregroundStyle(Color.inkSoft)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("Open Settings")
                        .font(Legend.font(size: 15))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Capsule().fill(Color.ink))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)

                Button("Done") { dismiss() }
                    .font(Legend.font(size: 13))
                    .foregroundStyle(Color.inkSoft)
                    .frame(maxWidth: .infinity)
            }
            .font(.typewriter(15))
            .foregroundStyle(Color.ink)
            .padding(28)
            .background(
                Rectangle()
                    .fill(Color.paperWhite)
                    .overlay(Image(uiImage: PaperTexture.paper(.bond)).resizable(resizingMode: .tile))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            )
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(DeskBackground())
        .presentationDetents([.large])
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).").foregroundStyle(Color.ribbonRed)
            Text(text)
        }
    }
}
