import os
import SwiftData
import SwiftUI

@main
struct CarriageApp: App {
    @State private var model = AppModel()
    private let container: ModelContainer

    init() {
        Typeface.registerBundledFonts()
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(container)
        }
    }

    /// Pages sync through the writer's private iCloud database. If iCloud isn't available (no account,
    /// no entitlement in a local build), the library still works on this device alone.
    /// Where pages are being kept, for telling the writer.
    static private(set) var storage: PageStorage = .device

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Page.self, WritingDay.self])
        let log = Logger(subsystem: "Carriage", category: "Storage")
        let inMemory = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        if !inMemory {
            do {
                let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .private("iCloud.com.leejustin.carriage"))
                let container = try ModelContainer(for: schema, configurations: cloud)
                storage = FileManager.default.ubiquityIdentityToken == nil ? .iCloudSignedOut : .iCloud
                return container
            } catch {
                log.error("iCloud store unavailable, using local storage: \(error.localizedDescription)")
            }
        }
        do {
            let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            fatalError("Couldn't open the page store: \(error)")
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TypewriterScreen()
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .sheet(isPresented: $model.showLibrary, onDismiss: reactivate) {
                LibraryView().preferredColorScheme(.light)
            }
            .sheet(isPresented: $model.showSettings, onDismiss: reactivate) {
                SettingsView().preferredColorScheme(.light)
            }
            .sheet(isPresented: $model.showPaywall, onDismiss: reactivate) {
                PaywallView().preferredColorScheme(.light)
            }
            .sheet(isPresented: $model.showShop, onDismiss: reactivate) {
                ShopView().preferredColorScheme(.light)
            }
            .sheet(isPresented: $model.showFocusSetup, onDismiss: reactivate) {
                FocusSetupView().preferredColorScheme(.light)
            }
            .sheet(isPresented: $model.showDuoLetter, onDismiss: {
                model.dismissDuoLetter()
                reactivate()
            }) {
                DuoLetterView().preferredColorScheme(.light)
            }
            .sheet(item: $model.filesRequest, onDismiss: reactivate) { request in
                FilesExporter(urls: request.urls) {
                    model.toast = Toast(text: request.label, symbol: "folder")
                }
                .ignoresSafeArea()
            }
            .sheet(item: $model.exportRequest, onDismiss: reactivate) { request in
                ShareSheet(items: request.items)
                    .presentationDetents([.medium, .large])
            }
            .onAppear { model.start(context: context) }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background, .inactive:
                    model.engine.save()
                case .active:
                    Task { await model.focusMode.syncWithSystem() }
                    model.stats.refresh()
                    model.focus.tick()
                    reactivate()
                @unknown default:
                    break
                }
            }
            .onChange(of: AppearanceSignature(model.settings)) { model.engine.applyConfiguration() }
            .onChange(of: AudioSignature(model.settings)) { model.applyAudioSettings() }
            .onChange(of: model.settings.spellCheck) { model.engine.refreshSpellCheck() }
            .onChange(of: model.settings.dailyGoal) { _, goal in model.stats.goal = goal }
            .onChange(of: model.store.purchased) {
                model.enforceEntitlements()
                model.applyPurchasedChoices()
            }
            .onChange(of: model.isPresentingSheet) { _, presenting in
                // Keep hardware typing off the page while a sheet is up, and make sure the library, exports and
                // anything else in the sheet see the last few keystrokes.
                if presenting {
                    model.engine.save()
                    model.engine.paper.keyCatcher.resignFirstResponder()
                }
            }
            .onChange(of: model.engine.goalReachedAt) { _, date in
                // In focus nothing interrupts, not even good news.
                guard date != nil, !model.focusMode.isOn else { return }
                SoundEngine.shared.play(.bell)
                Haptics.shared.bell()
                model.toast = Toast(text: "Goal met: \(model.settings.dailyGoal) words", symbol: "checkmark.seal")
            }
    }

    private func reactivate() {
        DispatchQueue.main.async { model.engine.paper.activateHardwareInput() }
    }
}

/// Settings that change how the paper and keys look.
private struct AppearanceSignature: Equatable {
    var values: [String]

    init(_ s: AppSettings) {
        values = [s.finish.rawValue, s.typeface.rawValue, s.carriage.rawValue, "\(s.lineWidth.rawValue)", "\(s.lineSpacing.rawValue)", "\(s.typebarsOn)", s.keyboardStyle.rawValue]
    }
}

enum PageStorage {
    case iCloud, iCloudSignedOut, device

    var summary: String {
        switch self {
        case .iCloud: "Saved as you type, and synced with iCloud."
        case .iCloudSignedOut: "Saved as you type on this iPhone. Sign in to iCloud to sync and back up your pages."
        case .device: "Saved as you type on this iPhone only. Export your pages to keep a copy elsewhere."
        }
    }

    var short: String {
        switch self {
        case .iCloud: "Saved · iCloud"
        case .iCloudSignedOut, .device: "Saved · this iPhone"
        }
    }
}

private struct AudioSignature: Equatable {
    var values: [String]

    init(_ s: AppSettings) {
        values = ["\(s.soundsOn)", "\(s.volume)", "\(s.playsInSilentMode)", "\(s.hapticsOn)"]
    }
}
