import FoldKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mirrorLocation = ""
    @State private var diagnostics: [URL] = []

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            Form {
                Section {
                    FinishPicker(selection: $settings.finish)
                    Picker("Typeface", selection: $settings.typeface) {
                        ForEach(Typeface.available) { face in
                            Text(face.name).font(.typewriter(15, face: face)).tag(face)
                        }
                    }
                    NavigationLink {
                        MachineSoundPicker()
                    } label: {
                        LabeledContent("Machine sound", value: model.settings.machineSound.name)
                    }
                } header: {
                    header("The machine")
                }

                Section {
                    Picker("Layout", selection: $settings.keyboardStyle) {
                        ForEach(KeyboardStyle.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    header("Keyboard")
                } footer: {
                    Text(model.settings.keyboardStyle == .full
                         ? "One piece across the deck, for typing with all ten fingers. Best with the phone half-folded on a table."
                         : "Two halves at the edges, one for each thumb, for typing while you hold the phone. Used on the half-folded Duo and in landscape; on a narrower screen the keys stay in one piece so they're big enough to hit.")
                }

                Section {
                    Picker("New sheets start in", selection: $settings.defaultMode) {
                        ForEach(TypingMode.allCases) { Text($0.name).tag($0) }
                    }
                    Picker("Line width", selection: $settings.lineWidth) {
                        ForEach(LineWidth.allCases) { Text($0.name).tag($0) }
                    }
                    Picker("Line spacing", selection: $settings.lineSpacing) {
                        ForEach(LineSpacing.allCases) { Text($0.name).tag($0) }
                    }
                    Picker("Carriage", selection: $settings.carriage) {
                        ForEach(CarriageTravel.allCases) { Text($0.name).tag($0) }
                    }
                    Picker("Default paper", selection: $settings.defaultPaper) {
                        ForEach(PaperStyle.allCases) { Text($0.name).tag($0) }
                    }
                    Picker("Default ribbon", selection: $settings.defaultInk) {
                        ForEach(InkStyle.allCases) { Text($0.name).tag($0) }
                    }
                } header: {
                    header("The page")
                } footer: {
                    Text(model.settings.carriage.detail + " " + model.settings.defaultMode.detail)
                }

                Section {
                    Toggle("Sounds", isOn: $settings.soundsOn)
                    if settings.soundsOn {
                        HStack {
                            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                            Slider(value: $settings.volume, in: 0.1...1)
                            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Volume")
                        Toggle("Play in Silent Mode", isOn: $settings.playsInSilentMode)
                    }
                    Toggle("Haptics", isOn: $settings.hapticsOn)
                    Toggle("Margin bell", isOn: $settings.marginBell)
                    Toggle("Bell on return", isOn: $settings.bellOnReturn)
                    Toggle("Typebar animation", isOn: $settings.typebarsOn)
                } header: {
                    header("Sound and feel")
                } footer: {
                    Text("The margin bell rings seven characters before the end of the line, like the real thing.")
                }

                Section {
                    Picker("Daily goal", selection: $settings.dailyGoal) {
                        Text("No goal").tag(0)
                        ForEach([250, 500, 750, 1000, 1500, 2000], id: \.self) { Text("\($0) words").tag($0) }
                    }
                    Toggle("Capitalize new sentences", isOn: $settings.autoCapitalize)
                    Toggle("Underline misspellings", isOn: $settings.spellCheck)
                    Toggle("Hide controls while typing", isOn: $settings.autoHideControls)
                    Button("Silence notifications while you write") { model.showFocusSetup = true }
                } header: {
                    header("Writing")
                } footer: {
                    Text("Nothing is ever autocorrected. Capitalizing only lights the shift key for you; spell check only underlines.")
                }

                Section {
                    Menu {
                        ForEach(ExportFormat.allCases) { format in
                            Button(format.name, systemImage: format.symbol) {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.exportAllPages(format: format) }
                            }
                        }
                    } label: {
                        Label("Export all pages to Files", systemImage: "folder")
                    }
                    Toggle("Keep a Markdown copy in Files", isOn: $settings.mirrorToFiles)
                } header: {
                    header("Your writing")
                } footer: {
                    Text(CarriageApp.storage.summary + (settings.mirrorToFiles && !mirrorLocation.isEmpty
                        ? " A Markdown copy of every page is kept in \(mirrorLocation), updated as you type."
                        : " Exports are yours to keep in Files, iCloud Drive or anywhere else."))
                }

                Section {
                    Picker("Night desk", selection: $settings.nightDesk) {
                        ForEach(NightDesk.allCases) { Text($0.name).tag($0) }
                    }
                } header: {
                    header("Night")
                } footer: {
                    Text("Dark paper and a light ribbon for typing in the dark. Exports and prints stay on white paper.")
                }

                Section {
                    Toggle("Use the system keyboard", isOn: $settings.useSystemKeyboard)
                } header: {
                    header("Accessibility")
                } footer: {
                    Text("Swaps the typewriter keys for the standard iOS keyboard, for dictation, other languages and assistive input. Sounds still play.")
                }

                Section {
                    if model.store.freePageLimit != nil {
                        Button("Unlock Carriage") { model.showPaywall = true }
                    }
                    Button("Restore purchases") { Task { await model.store.restore() } }
                } header: {
                    header("Purchases")
                }

                Section {
                    LabeledContent("Machine", value: model.isDuo ? "iPhone Duo" : "Pocket (made for iPhone Duo)")
                    Button("Show the tour again") { model.replayOnboarding() }
                    if !diagnostics.isEmpty {
                        Button("Share crash reports (\(diagnostics.count))") {
                            model.exportRequest = ExportRequest(items: diagnostics)
                        }
                        Button("Delete crash reports", role: .destructive) {
                            DiagnosticsStore.shared.deleteAll()
                            diagnostics = []
                        }
                    }
                    LabeledContent("Version", value: Bundle.main.versionString)
                    LabeledContent("Privacy", value: "Nothing collected")
                    Text("Every sound is synthesized on your phone. Pages sync through your own iCloud account. Crash reports stay on this iPhone unless you choose to share them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    header("About")
                }

                #if DEBUG
                DeveloperSection()
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(DeskBackground())
            .onAppear {
                diagnostics = DiagnosticsStore.shared.reports()
                MarkdownMirror.shared.locationDescription { location in
                    Task { @MainActor in mirrorLocation = location }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SETTINGS").font(Legend.font(size: 15)).tracking(4)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Color.ribbonRed)
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased()).font(Legend.font(size: 12)).tracking(2.5)
    }
}

/// The enamel colours, as paint chips.
struct FinishPicker: View {
    @Binding var selection: MachineFinish

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Finish")
            HStack(spacing: 14) {
                ForEach(MachineFinish.allCases) { finish in
                    Button {
                        selection = finish
                    } label: {
                        Circle()
                            .fill(Color(uiColor: finish.body))
                            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1).padding(3))
                            .overlay(Circle().strokeBorder(selection == finish ? Color.ink : .clear, lineWidth: 2))
                            .frame(width: 34, height: 34)
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(finish.name)
                    .accessibilityAddTraits(selection == finish ? .isSelected : [])
                }
            }
            Text(selection.name).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct MachineSoundPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(MachineSound.allCases) { machine in
                Button {
                    model.selectMachine(machine)
                    playDemo()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(machine.name).font(.typewriter(16)).foregroundStyle(.primary)
                            Text(machine.blurb).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.settings.machineSound == machine {
                            Image(systemName: "checkmark").foregroundStyle(Color.ribbonRed)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DeskBackground())
        .navigationTitle("Machine sound")
    }

    /// A few keys and a return, so the writer can hear the machine.
    private func playDemo() {
        let script: [(SoundKind, Double)] = [(.key, 0.25), (.key, 0.38), (.space, 0.55), (.key, 0.66), (.key, 0.78), (.key, 0.88), (.bell, 1.05), (.carriageReturn, 1.25)]
        for (kind, delay) in script {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { SoundEngine.shared.play(kind) }
        }
    }
}

#if DEBUG
/// Lets you see every posture on simulators and SDKs without a hinge.
struct DeveloperSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var fold = model.fold
        Section {
            Picker("Simulate posture", selection: Binding(get: { fold.simulation }, set: { value in
                fold.simulation = value
                UserDefaults.standard.set(value.rawValue, forKey: "foldSimulation")
            })) {
                ForEach(FoldSimulation.allCases) { Text($0.displayName).tag($0) }
            }
            LabeledContent("Posture", value: model.fold.state.posture.displayName + (model.fold.state.isSimulated ? " (simulated)" : ""))
            LabeledContent("Hinge APIs", value: FoldMonitor.supportsHingeAPIs ? "Available" : "Not in this SDK")
            LabeledContent("Hinge angle", value: model.fold.hinge.map { String(format: "%.0f°", $0.angle) } ?? "None")
            LabeledContent("Hardware keyboard", value: model.fold.hardwareKeyboard ? "Yes" : "No")
        } header: {
            Text("DEVELOPER").font(Legend.font(size: 12)).tracking(2.5)
        }
    }
}
#endif

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
