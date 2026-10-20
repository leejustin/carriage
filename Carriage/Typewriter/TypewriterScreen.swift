import FoldKit
import os
import SwiftUI

/// The machine. One paper view and one keyboard view live for the whole session and are only moved and
/// resized as the phone folds, so the page, the scroll position and the carriage all survive a fold.
struct TypewriterScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// False for a moment after launch: a Duo's hinge reports a beat after the first layout, and that first
    /// correction (say, regular to closed) should snap into place rather than animate.
    @State private var settled = false

    private var night: Bool {
        switch model.settings.nightDesk {
        case .on: true
        case .off: false
        case .system: colorScheme == .dark
        }
    }

    var body: some View {
        // The outer reader sees the safe area; the inner one fills the whole screen.
        GeometryReader { outer in
            let safe = outer.safeAreaInsets
            GeometryReader { proxy in
                #if DEBUG
                if DemoContent.laptopPreview {
                    // The simulator holds the Duo like a book; turn the machine a quarter so it lays out as it does
                    // on its side, the way a writer sets it down like a laptop. Screenshots get turned back.
                    let turned = CGSize(width: proxy.size.height, height: proxy.size.width)
                    desk(size: turned, safe: EdgeInsets())
                        .frame(width: turned.width, height: turned.height)
                        .rotationEffect(.degrees(90))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    desk(size: proxy.size, safe: safe)
                }
                #else
                desk(size: proxy.size, safe: safe)
                #endif
            }
            .ignoresSafeArea(.container)
        }
        .onChange(of: reduceMotion) { _, value in model.engine.applyConfiguration(reduceMotion: value) }
        .onChange(of: night, initial: true) { _, value in model.engine.applyConfiguration(night: value) }
        .task {
            try? await Task.sleep(for: .seconds(0.6))
            settled = true
        }
        .onAppear {
            let appModel = model
            appModel.engine.paper.onTap = { [weak appModel] in appModel?.paperTapped() }
        }
    }

    private func desk(size: CGSize, safe: EdgeInsets) -> some View {
        let layout = DeskLayout.make(size: size, fold: model.fold.state, useSystemKeyboard: model.settings.useSystemKeyboard)
        return Desk(layout: layout, size: size, safe: safe)
            .foldProbe(model.fold)
            .animation(reduceMotion || !settled ? nil : .spring(duration: 0.45, bounce: 0.12), value: layout)
            .onChange(of: layout.presentation, initial: true) { _, presentation in
                model.engine.applyConfiguration(presentation: presentation, reduceMotion: reduceMotion)
                DispatchQueue.main.async { model.engine.paper.activateHardwareInput() }
            }
            .onChange(of: layout.showsBadge, initial: true) { _, shows in
                model.engine.keyboard.showsBadge = shows
            }
            .onChange(of: model.fold.state.hingeAngle, initial: true) { _, angle in
                model.engine.paper.setHingeAngle(angle)
                model.rememberHinge()
            }
            .onChange(of: PaperInsets(layout: layout, size: size, safe: safe), initial: true) { _, insets in
                model.engine.paper.setChromeInsets(insets.value)
            }
            .onChange(of: controlsFade(layout: layout, safe: safe), initial: true) { _, height in
                model.engine.paper.setTopFade(height)
            }
            .onChange(of: layout.kind) { old, new in
                foldChanged(from: old, to: new)
            }
            #if DEBUG
            .onChange(of: layout, initial: true) { _, layout in
                logLayout(layout, size: size)
            }
            #endif
    }

    /// How far the controls reach down over the paper, while they're showing.
    private func controlsFade(layout: DeskLayout, safe: EdgeInsets) -> CGFloat {
        guard !ControlsBar.isHidden(model: model, layout: layout) else { return 0 }
        return Desk.controlsTop(layout: layout, safe: safe) + ControlsBar.height
    }

    #if DEBUG
    /// For checking postures on the Duo simulator: one log line per layout.
    private func logLayout(_ layout: DeskLayout, size: CGSize) {
        let fold = model.fold.state
        let crease = layout.crease.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "none"
        let angle = fold.hingeAngle.map { String(format: "%.0f", $0) } ?? "none"
        let line = "layout=\(layout.kind.rawValue) posture=\(fold.posture.rawValue) angle=\(angle) simulated=\(fold.isSimulated) window=\(Int(size.width))x\(Int(size.height)) crease=\(crease)"
        Logger(subsystem: "Carriage", category: "Fold").notice("\(line, privacy: .public)")
        FoldCapture.capture(name: layout.kind.rawValue, line: line)
    }
    #endif

    /// Folding shut saves the page behind the machine's cover; opening lifts the cover again.
    private func foldChanged(from old: DeskLayout.Kind, to new: DeskLayout.Kind) {
        guard !reduceMotion else {
            if new == .closed { model.engine.save() }
            return
        }
        if new == .closed, old != .closed {
            model.engine.save()
            Haptics.shared.carriageReturn(slide: 0.25)
            SoundEngine.shared.play(.shift)
            withAnimation(.easeOut(duration: 0.3)) { model.foldCurtain = FoldCurtain(closing: true) }
        } else if old == .closed, new != .closed {
            model.foldCurtain = FoldCurtain(closing: false)
        }
    }
}

/// The status area and home indicator, where the paper reaches the edge of the screen.
private struct PaperInsets: Equatable {
    var value: UIEdgeInsets

    init(layout: DeskLayout, size: CGSize, safe: EdgeInsets) {
        value = UIEdgeInsets(
            // The closed Duo shows a glance line under the controls.
            top: (layout.paper.minY <= 0 ? safe.top : 0) + (layout.kind == .closed ? 46 : 0),
            left: 0,
            bottom: layout.paper.maxY >= size.height - 0.5 ? safe.bottom : 0,
            right: 0
        )
    }
}

/// Everything on screen for one layout.
private struct Desk: View {
    @Environment(AppModel.self) private var model
    var layout: DeskLayout
    var size: CGSize
    var safe: EdgeInsets

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(uiColor: model.settings.finish.shadow.mixed(with: .black, amount: 0.3))
            paper
            keys
            hinge
            hint
            readingFade
            glance
            controls
            toast
            spread
            curtain
        }
    }

    @ViewBuilder
    private var glance: some View {
        if layout.kind == .closed {
            GlanceStrip()
                .offset(x: layout.paper.minX + 24, y: layout.paper.minY + max(safe.top, 8) + 46)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var spread: some View {
        if layout.kind == .book, let facing = layout.facing {
            ReadingSpreadView(left: layout.paper, right: facing)
                .frame(width: size.width, height: size.height)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var curtain: some View {
        if let curtain = model.foldCurtain {
            FoldCurtainView(curtain: curtain)
                .frame(width: size.width, height: size.height)
        }
    }

    private var paper: some View {
        PaperHost(paper: model.engine.paper)
            .frame(width: layout.paper.width, height: layout.paper.height)
            .offset(x: layout.paper.minX, y: layout.paper.minY)
    }

    private var keys: some View {
        let frame = layout.keyboard ?? hiddenKeyboard
        return KeyboardHost(keyboard: model.engine.keyboard)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .opacity(layout.showsKeyboard ? 1 : 0)
            .allowsHitTesting(layout.showsKeyboard)
            .accessibilityHidden(!layout.showsKeyboard)
    }

    @ViewBuilder
    private var hinge: some View {
        if let crease = layout.crease {
            HingeView(axis: crease.width >= crease.height ? .horizontal : .vertical, finish: model.settings.finish)
                .frame(width: crease.width, height: crease.height)
                .offset(x: crease.minX, y: crease.minY)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var hint: some View {
        if model.engine.isBlank && layout.presentation == .typing {
            BlankSheetHint(layout: layout)
                .frame(width: layout.paper.width, height: layout.paper.height)
                .offset(x: layout.paper.minX, y: layout.paper.minY)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// In reading mode the page scrolls freely, so it fades out under the controls instead of colliding with them.
    @ViewBuilder
    private var readingFade: some View {
        if layout.presentation == .editing {
            let paper = Color(uiColor: model.engine.paper.paperColor)
            LinearGradient(stops: [.init(color: paper, location: 0), .init(color: paper, location: 0.6), .init(color: paper.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                // Matches the reading sheet's width (see PaperMetrics for .editing).
                .frame(width: sheetWidth, height: safe.top + 64 + (layout.kind == .closed ? 46 : 0))
                .offset(x: layout.paper.minX + ((layout.paper.width - sheetWidth) / 2).rounded(), y: layout.paper.minY)
                .allowsHitTesting(false)
        }
    }

    private var sheetWidth: CGFloat { min(layout.paper.width - 20, 720) }

    static func controlsTop(layout: DeskLayout, safe: EdgeInsets) -> CGFloat {
        layout.paper.minY > 0 ? 8 : max(safe.top, 8)
    }

    private var controls: some View {
        let top = Self.controlsTop(layout: layout, safe: safe)
        let leading: CGFloat = layout.paper.minX == 0 ? max(safe.leading, 10) : 10
        let trailing: CGFloat = layout.paper.maxX >= size.width ? max(safe.trailing, 10) : 10
        return ControlsBar(layout: layout)
            .padding(.top, top)
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .frame(width: layout.paper.width, alignment: .top)
            .offset(x: layout.paper.minX, y: layout.paper.minY)
    }

    private var toast: some View {
        let bottom: CGFloat = layout.kind == .hardware || layout.presentation == .editing ? max(safe.bottom, 16) : 60
        return ToastView()
            .padding(.bottom, bottom)
            .frame(width: layout.paper.width, height: layout.paper.height, alignment: .bottom)
            .offset(x: layout.paper.minX, y: layout.paper.minY)
            .allowsHitTesting(false)
    }

    /// Where the keys wait while hidden, so they slide rather than pop when they come back.
    private var hiddenKeyboard: CGRect {
        let height = min(size.width * 0.72, size.height * 0.44)
        return CGRect(x: 0, y: size.height, width: size.width, height: height)
    }
}

struct PaperHost: UIViewRepresentable {
    let paper: PaperView

    func makeUIView(context: Context) -> PaperView { paper }
    func updateUIView(_ uiView: PaperView, context: Context) {}
}

struct KeyboardHost: UIViewRepresentable {
    let keyboard: KeyboardView

    func makeUIView(context: Context) -> KeyboardView { keyboard }
    func updateUIView(_ uiView: KeyboardView, context: Context) {}
}

/// The physical hinge between the two halves: a dark recess with a line of chrome.
struct HingeView: View {
    var axis: FoldAxis
    var finish: MachineFinish

    var body: some View {
        let dark = Color(uiColor: finish.shadow.mixed(with: .black, amount: 0.55))
        let gradient = LinearGradient(
            stops: [
                .init(color: dark, location: 0),
                .init(color: Color(uiColor: finish.shadow), location: 0.35),
                .init(color: Color(hex: 0xC9CDCE), location: 0.5),
                .init(color: Color(uiColor: finish.shadow), location: 0.65),
                .init(color: dark, location: 1),
            ],
            startPoint: axis == .horizontal ? .top : .leading,
            endPoint: axis == .horizontal ? .bottom : .trailing
        )
        Rectangle().fill(gradient)
            .accessibilityHidden(true)
    }
}

/// A faint typed hint on a fresh sheet.
struct BlankSheetHint: View {
    @Environment(AppModel.self) private var model
    var layout: DeskLayout

    var body: some View {
        VStack(spacing: 8) {
            Text("A fresh sheet.")
                .font(.typewriterFixed(18, face: model.settings.typeface))
            Text(layout.showsKeyboard ? "Start typing." : "Start typing on your keyboard.")
                .font(.typewriterFixed(14, face: model.settings.typeface))
        }
        .foregroundStyle(Color.ink.opacity(0.28))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, layout.paper.height * 0.25)
        .accessibilityHidden(true)
    }
}

/// A slip of paper with a short message, for confirmations.
struct ToastView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if let toast = model.toast {
                Label(toast.text, systemImage: toast.symbol)
                    .font(.typewriterFixed(14))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Rectangle()
                            .fill(Color.paperWhite)
                            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    )
                    .rotationEffect(.degrees(-1.2))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(2.4))
                        withAnimation(.easeIn(duration: 0.25)) {
                            if model.toast?.id == toast.id { model.toast = nil }
                        }
                    }
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.spring(duration: 0.35), value: model.toast)
    }
}

#if DEBUG
/// For checking postures on the Duo simulator without anyone watching: each layout change saves a picture of the
/// window and its log line to Documents/FoldCapture once the layout has settled.
@MainActor
enum FoldCapture {
    private static var count = 0

    static func capture(name: String, line: String) {
        count += 1
        let index = count
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first?.keyWindow,
                  let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let folder = documents.appendingPathComponent("FoldCapture", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let stem = String(format: "%02d-%@", index, name)
            try? image.pngData()?.write(to: folder.appendingPathComponent(stem + ".png"))
            try? (line + "\n").write(to: folder.appendingPathComponent(stem + ".txt"), atomically: true, encoding: .utf8)
        }
    }
}
#endif
