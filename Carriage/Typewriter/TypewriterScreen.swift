import FoldKit
import SwiftUI

/// The machine. One paper view and one keyboard view live for the whole session and are only moved and
/// resized as the phone folds, so the page, the scroll position and the carriage all survive a fold.
struct TypewriterScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The outer reader sees the safe area; the inner one fills the whole screen.
        GeometryReader { outer in
            let safe = outer.safeAreaInsets
            GeometryReader { proxy in
                desk(size: proxy.size, safe: safe)
            }
            .ignoresSafeArea(.container)
        }
        .onChange(of: reduceMotion) { _, value in model.engine.applyConfiguration(reduceMotion: value) }
        .onAppear {
            let appModel = model
            appModel.engine.paper.onTap = { [weak appModel] in appModel?.paperTapped() }
        }
    }

    private func desk(size: CGSize, safe: EdgeInsets) -> some View {
        let layout = DeskLayout.make(size: size, fold: model.fold.state, useSystemKeyboard: model.settings.useSystemKeyboard)
        return Desk(layout: layout, size: size, safe: safe)
            .foldProbe(model.fold)
            .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.12), value: layout)
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
    }
}

/// The status area and home indicator, where the paper reaches the edge of the screen.
private struct PaperInsets: Equatable {
    var value: UIEdgeInsets

    init(layout: DeskLayout, size: CGSize, safe: EdgeInsets) {
        value = UIEdgeInsets(
            top: layout.paper.minY <= 0 ? safe.top : 0,
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
            controls
            toast
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
            let paper = Color(uiColor: model.engine.page?.paper.color ?? PaperStyle.bond.color)
            LinearGradient(stops: [.init(color: paper, location: 0), .init(color: paper, location: 0.6), .init(color: paper.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                // Matches the reading sheet's width (see PaperMetrics for .editing).
                .frame(width: sheetWidth, height: safe.top + 64)
                .offset(x: layout.paper.minX + ((layout.paper.width - sheetWidth) / 2).rounded(), y: layout.paper.minY)
                .allowsHitTesting(false)
        }
    }

    private var sheetWidth: CGFloat { min(layout.paper.width - 20, 720) }

    private var controls: some View {
        let top: CGFloat = layout.paper.minY > 0 ? 8 : max(safe.top, 8)
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
                .font(.typewriter(18, face: model.settings.typeface))
            Text(layout.showsKeyboard ? "Start typing." : "Start typing on your keyboard.")
                .font(.typewriter(14, face: model.settings.typeface))
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
                    .font(.typewriter(14))
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
