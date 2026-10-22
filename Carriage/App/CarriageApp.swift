import os
import StoreKit
import SwiftData
import SwiftUI
import TipKit

@main
struct CarriageApp: App {
    @State private var model = AppModel()
    private let container: ModelContainer

    init() {
        Typeface.registerBundledFonts()
        #if DEBUG
        CloudKitSchema.initializeIfRequested()
        #endif
        container = Self.makeContainer()
        try? Tips.configure([.displayFrequency(.immediate)])
        DiagnosticsStore.shared.start()
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
        let schema = Schema([Page.self, WritingDay.self, Notebook.self, PageVersion.self])
        let log = Logger(subsystem: "Carriage", category: "Storage")
        let inMemory = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        if !inMemory {
            do {
                let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .private("iCloud.com.carriage.app"))
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
        TypewriterScreen()
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .modifier(AppSheets(reactivate: reactivate))
            .modifier(AppReactions(reactivate: reactivate))
            .onAppear { model.start(context: context) }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background, .inactive:
                    model.engine.save()
                case .active:
                    Task { await model.focusMode.syncWithSystem() }
                    model.stats.refresh()
                    model.focus.tick()
                    model.scheduleReconcile()
                    reactivate()
                @unknown default:
                    break
                }
            }
    }

    private func reactivate() {
        DispatchQueue.main.async {
            model.engine.paper.activateHardwareInput()
            model.engine.resettle()
        }
    }
}

/// Every sheet the machine can show.
private struct AppSheets: ViewModifier {
    @Environment(AppModel.self) private var model
    var reactivate: () -> Void

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .sheet(isPresented: $model.showLibrary, onDismiss: reactivate) { LibraryView() }
            .sheet(isPresented: $model.showSettings, onDismiss: reactivate) { SettingsView() }
            .sheet(isPresented: $model.showPaywall, onDismiss: reactivate) { PaywallView() }
            .sheet(isPresented: $model.showFocusSetup, onDismiss: reactivate) { FocusSetupView() }
            .sheet(isPresented: $model.showOnboarding, onDismiss: reactivate) { OnboardingView() }
            .sheet(item: $model.versionsPage, onDismiss: reactivate) { page in VersionHistoryView(page: page) }
            .modifier(ExportSheets(reactivate: reactivate))
    }
}

private struct ExportSheets: ViewModifier {
    @Environment(AppModel.self) private var model
    var reactivate: () -> Void

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
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
    }
}

/// Keeping the machine in step with settings, purchases and what's on screen.
private struct AppReactions: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.requestReview) private var requestReview
    var reactivate: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: AppearanceSignature(model.settings)) {
                model.engine.applyConfiguration()
                model.engine.resettle()
            }
            .onChange(of: AudioSignature(model.settings)) { model.applyAudioSettings() }
            .onChange(of: model.settings.spellCheck) { model.engine.refreshSpellCheck() }
            .onChange(of: model.settings.mirrorToFiles) { _, on in if on { model.mirrorAllPages() } }
            .onChange(of: model.settings.dailyGoal) { _, goal in
                model.stats.goal = goal
                model.publishStats()
            }
            .onChange(of: model.store.purchased) {
                model.updateTypingLock()
                model.applyMachine()
            }
            .onChange(of: model.isPresentingSheet) { _, presenting in
                // Keep hardware typing off the page while a sheet is up, and make sure the library, exports and
                // anything else in the sheet see the last few keystrokes.
                if presenting {
                    model.engine.save()
                    model.engine.paper.keyCatcher.resignFirstResponder()
                } else {
                    model.engine.resettle()
                }
            }
            .onChange(of: model.engine.goalReachedAt) { _, date in
                // In focus nothing interrupts, not even good news.
                guard date != nil, !model.focusMode.isOn else { return }
                SoundEngine.shared.play(.bell)
                Haptics.shared.bell()
                model.toast = Toast(text: "Goal met: \(model.settings.dailyGoal) words", symbol: "checkmark.seal")
            }
            .onChange(of: model.reviewRequestedAt) { _, date in
                guard date != nil else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { requestReview() }
            }
            .onOpenURL { url in IntentRouter.handle(url, model: model) }
            .onChange(of: IntentRouter.shared.pending) { _, action in
                if let action { IntentRouter.perform(action, model: model) }
            }
    }
}

/// Settings that change how the paper and keys look.
private struct AppearanceSignature: Equatable {
    var values: [String]

    init(_ s: AppSettings) {
        values = [s.finish.rawValue, s.typeface.rawValue, s.carriage.rawValue, "\(s.lineWidth.rawValue)", "\(s.lineSpacing.rawValue)", "\(s.typebarsOn)", s.keyboardStyle.rawValue, s.nightDesk.rawValue, s.engraving]
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
        values = ["\(s.soundsOn)", "\(s.volume)", "\(s.playsInSilentMode)", "\(s.hapticsOn)", s.ambience.rawValue]
    }
}
