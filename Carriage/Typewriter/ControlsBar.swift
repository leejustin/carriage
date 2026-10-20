import SwiftUI
import TipKit

/// The few controls over the paper. They fade away while you type and come back on a tap or a pause.
struct ControlsBar: View {
    @Environment(AppModel.self) private var model
    var layout: DeskLayout

    @State private var renaming = false
    @State private var draftTitle = ""

    private var hidden: Bool { Self.isHidden(model: model, layout: layout) }

    /// The controls fade while you type, and stay away in focus until a tap on the paper.
    static func isHidden(model: AppModel, layout: DeskLayout) -> Bool {
        guard layout.presentation == .typing else { return false }
        if model.focusMode.isOn { return !model.focusMode.isPeeking }
        return model.settings.autoHideControls && model.engine.isTyping
    }

    /// The bar's height, not counting the padding above it.
    static let height: CGFloat = 34

    var body: some View {
        HStack(spacing: 8) {
            KnobButton(symbol: "square.stack", label: "Library") { model.showLibrary = true }
                .keyboardShortcut("l", modifiers: .command)

            titlePill
                .layoutPriority(-1)

            Spacer(minLength: 0)

            if layout.kind == .hardware {
                KnobButton(symbol: "keyboard", label: "Show typewriter keys") {
                    model.fold.dismissHardwareKeyboard()
                }
            }

            ModeSwitch(mode: model.engine.mode, compact: layout.paper.width < 520) { model.engine.setMode($0) }

            KnobButton(symbol: model.focusMode.isOn ? "moon.fill" : "moon", label: model.focusMode.isOn ? "Leave focus" : "Focus",
                       active: model.focusMode.isOn) {
                model.toggleFocus()
            }
            .popoverTip(FocusTip(), arrowEdge: .top)

            // On a narrow page the timer lives in the … menu, and shows here only while it runs.
            if !compact || model.focus.isRunning {
                FocusButton()
            }

            sheetMenu
                .popoverTip(PageMenuTip(), arrowEdge: .top)

            KnobButton(symbol: "gearshape", label: "Settings") { model.showSettings = true }
                .keyboardShortcut(",", modifiers: .command)
        }
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(!hidden)
        .animation(.easeInOut(duration: hidden ? 0.6 : 0.2), value: hidden)
        .alert("Name this page", isPresented: $renaming) {
            TextField("Title", text: $draftTitle)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                model.engine.page?.title = draftTitle
                model.engine.page?.modifiedAt = .now
                if let page = model.engine.page { model.mirror(page) }
            }
        }
    }

    private var titlePill: some View {
        Button {
            draftTitle = model.engine.page?.title ?? ""
            renaming = true
        } label: {
            HStack(spacing: 8) {
                // On a narrow paper there's only room for the count; the title lives in the library.
                Text(layout.paper.width < 520 ? "\(model.engine.wordCount) w" : (model.engine.page?.displayTitle ?? ""))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.numericText())
                if model.settings.dailyGoal > 0, model.focusMode.showsGoals {
                    GoalRing(progress: Double(model.stats.wordsToday) / Double(model.settings.dailyGoal))
                        .frame(width: 14, height: 14)
                }
            }
            .font(.typewriterFixed(13, face: model.settings.typeface))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(.black.opacity(0.32)))
            .background(Capsule().fill(.ultraThinMaterial).opacity(0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page title: \(model.engine.page?.displayTitle ?? ""). \(model.stats.wordsToday) words today.")
        .accessibilityHint("Renames the page.")
    }

    private var compact: Bool { layout.paper.width < 520 }

    private var sheetMenu: some View {
        Menu {
            // Reassurance, not a button: pages save as you type.
            Text(CarriageApp.storage.short)
            if compact && !model.focus.isRunning {
                Menu("Focus Timer", systemImage: "timer") {
                    ForEach([10, 15, 25, 45, 60], id: \.self) { minutes in
                        Button("\(minutes) minutes") {
                            model.settings.focusMinutes = minutes
                            model.focus.start(minutes: minutes, wordsToday: model.stats.wordsToday)
                        }
                    }
                }
                Divider()
            }
            Button("New Sheet", systemImage: "doc.badge.plus") { model.newSheet() }
                .keyboardShortcut("n", modifiers: .command)
            Button("File This Page", systemImage: "tray.and.arrow.down") { model.fileCurrentSheet() }
            Button("Today's Journal Page", systemImage: "book.closed") { model.openTodaysJournal() }
            Button("Version History", systemImage: "clock.arrow.circlepath") { model.versionsPage = model.engine.page }
            Divider()
            Menu("Save to Files", systemImage: "folder") {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.name, systemImage: format.symbol) { model.saveToFiles(format: format) }
                }
            }
            Menu("Share", systemImage: "square.and.arrow.up") {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.name, systemImage: format.symbol) { model.export(format) }
                }
            }
            Button("Share as Image", systemImage: "photo") { model.shareImage() }
            Button("Print", systemImage: "printer") { model.print() }
            Button("Send to Notes", systemImage: "note.text") { model.sendToNotes() }
            Button("Copy Text", systemImage: "doc.on.doc") { model.copyText() }
            Divider()
            Menu("Paper", systemImage: "doc") {
                ForEach(PaperStyle.allCases) { style in
                    Button {
                        model.engine.setPaper(style)
                    } label: {
                        choiceLabel(style.name, selected: model.engine.page?.paper == style)
                    }
                }
            }
            Menu("Ribbon", systemImage: "paintbrush.pointed") {
                ForEach(InkStyle.allCases) { ink in
                    Button {
                        model.engine.setInk(ink)
                    } label: {
                        choiceLabel(ink.name, selected: model.engine.page?.ink == ink)
                    }
                }
            }
        } label: {
            KnobLabel(symbol: "ellipsis")
        }
        .accessibilityLabel("Page actions")
    }
}

@ViewBuilder
private func choiceLabel(_ name: String, selected: Bool) -> some View {
    if selected {
        Label(name, systemImage: "checkmark")
    } else {
        Text(name)
    }
}

/// A round control in the machine's dark finish.
struct KnobButton: View {
    var symbol: String
    var label: String
    var active = false
    var action: () -> Void

    var body: some View {
        Button(action: action) { KnobLabel(symbol: symbol, active: active) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }
}

struct KnobLabel: View {
    var symbol: String
    var active = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 34, height: 34)
            .background(Circle().fill(active ? Color(hex: 0xA22D27).opacity(0.85) : .black.opacity(0.32)))
            .background(Circle().fill(.ultraThinMaterial).opacity(0.5))
            .contentShape(Circle())
    }
}

/// Free / Typewriter, as a two-position lever.
struct ModeSwitch: View {
    var mode: TypingMode
    /// On a narrow paper, show only the current mode.
    var compact = false
    var onChange: (TypingMode) -> Void

    var body: some View {
        Button {
            onChange(mode == .free ? .typewriter : .free)
        } label: {
            HStack(spacing: 0) {
                if compact {
                    segment(mode == .free ? "FREE" : "TYPEWRITER", active: true)
                } else {
                    segment("FREE", active: mode == .free)
                    segment("TYPEWRITER", active: mode == .typewriter)
                }
            }
            .padding(3)
            .background(Capsule().fill(.black.opacity(0.32)))
            .background(Capsule().fill(.ultraThinMaterial).opacity(0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mode")
        .accessibilityValue(mode.name)
        .accessibilityHint(mode == .free ? "Switches to Typewriter mode: no delete." : "Switches to Free mode: delete works.")
    }

    private func segment(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(Legend.fixedFont(size: 10, condensed: true))
            .tracking(1.2)
            .foregroundStyle(active ? Color.ink : .white.opacity(0.7))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Capsule().fill(active ? Color(hex: 0xF1E8D0) : .clear))
            .animation(.spring(duration: 0.25), value: active)
    }
}

/// The day's progress toward the word goal.
struct GoalRing: View {
    var progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: min(1, progress))
                .stroke(progress >= 1 ? Color(hex: 0xE0675C) : .white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

/// Starts and shows the focus timer.
struct FocusButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.focus.isRunning {
            Button {
                model.focus.stop()
            } label: {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = Int(model.focus.remaining(at: context.date).rounded(.up))
                    Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                        .font(.typewriterFixed(13).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(Capsule().fill(Color(hex: 0xA22D27).opacity(0.75)))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Focus timer running")
            .accessibilityHint("Stops the timer.")
        } else {
            Menu {
                Section("Focus timer") {
                    ForEach([10, 15, 25, 45, 60], id: \.self) { minutes in
                        Button("\(minutes) minutes") {
                            model.settings.focusMinutes = minutes
                            model.focus.start(minutes: minutes, wordsToday: model.stats.wordsToday)
                        }
                    }
                }
            } label: {
                KnobLabel(symbol: "timer")
            } primaryAction: {
                model.focus.start(minutes: model.settings.focusMinutes, wordsToday: model.stats.wordsToday)
            }
            .accessibilityLabel("Focus timer")
            .accessibilityHint("Starts a \(model.settings.focusMinutes) minute session. Hold for other lengths.")
        }
    }
}
