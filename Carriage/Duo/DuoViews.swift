import SwiftUI
import UIKit

/// The machine's cover coming down as the Duo folds shut (the page is saved), or lifting as it opens.
struct FoldCurtainView: View {
    @Environment(AppModel.self) private var model
    let curtain: FoldCurtain

    var body: some View {
        let finish = model.settings.finish
        ZStack {
            Rectangle()
                .fill(LinearGradient(colors: [Color(uiColor: finish.highlight), Color(uiColor: finish.body), Color(uiColor: finish.shadow)],
                                     startPoint: .top, endPoint: .bottom))
            VStack(spacing: 14) {
                Text(plate)
                    .font(Legend.fixedFont(size: 13))
                    .tracking(5)
                    .foregroundStyle(Color(hex: 0x3B2A12))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0xF2DCA6), Color(hex: 0xB8955A)], startPoint: .top, endPoint: .bottom)))
                if curtain.closing {
                    Text("SAVED")
                        .font(Legend.fixedFont(size: 12))
                        .tracking(4)
                        .foregroundStyle(Color(uiColor: finish.printColor).opacity(0.8))
                } else if curtain.unveiling {
                    Text(String(format: "No. %06d", model.settings.serialNumber))
                        .font(.typewriterFixed(13))
                        .tracking(2)
                        .foregroundStyle(Color(uiColor: finish.printColor).opacity(0.75))
                }
            }
        }
        .ignoresSafeArea()
        .transition(.move(edge: .top))
        .task(id: curtain.id) {
            try? await Task.sleep(for: .seconds(curtain.closing ? 0.9 : curtain.unveiling ? 1.3 : 0.5))
            if curtain.unveiling {
                // The case latches let go and the lid comes off.
                SoundEngine.shared.play(.shift)
                Haptics.shared.paperRelease()
            }
            withAnimation(.easeInOut(duration: curtain.unveiling ? 0.7 : 0.45)) {
                if model.foldCurtain?.id == curtain.id { model.foldCurtain = nil }
            }
        }
        .accessibilityLabel(curtain.closing ? "Page saved" : "")
    }

    private var plate: String {
        let name = model.settings.engraving.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "CARRIAGE" : "CARRIAGE · \(name.uppercased())"
    }
}

/// On the closed Duo: today's count and where you left off.
struct GlanceStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let goal = model.settings.dailyGoal
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if goal > 0, model.focusMode.showsGoals {
                    GoalRing(progress: Double(model.stats.wordsToday) / Double(goal))
                        .frame(width: 14, height: 14)
                        .environment(\.colorScheme, .light)
                }
                Text(goal > 0 ? "\(model.stats.wordsToday) of \(goal) words today" : "\(model.stats.wordsToday) words today")
                if model.stats.streak > 1 {
                    Text("· \(model.stats.streak)-day streak")
                }
            }
            // The machine is at its best opened up; say so plainly, without taking typing away from here.
            HStack(spacing: 6) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 12, weight: .semibold))
                Text("Open your Duo for the full typewriter")
            }
            .foregroundStyle(Color.ribbonRed)
            .padding(.top, 2)
            Text("Or keep typing here with the keyboard.")
                .foregroundStyle(Color.inkSoft)
        }
        .font(.typewriterFixed(12, face: model.settings.typeface))
        .foregroundStyle(Color.ink)
        .accessibilityElement(children: .combine)
    }
}

/// The Duo opened flat like a book: the page laid out as a two-page spread, for reading a draft.
struct ReadingSpreadView: View {
    @Environment(AppModel.self) private var model
    let left: CGRect
    let right: CGRect
    @State private var pages: [UIImage] = []
    @State private var spread = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(uiColor: model.settings.finish.shadow.mixed(with: .black, amount: 0.45))
            pageImage(spread * 2, in: left)
            pageImage(spread * 2 + 1, in: right)
            // Typing happens with the phone on its side; say so at the foot of the right-hand page.
            Label("Turn it on its side to type", systemImage: "rotate.right")
                .font(.typewriterFixed(14))
                .foregroundStyle(Color.inkSoft)
                .frame(width: right.width - 24)
                .offset(x: right.minX + 12, y: right.maxY - 64)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.width < -40 { turn(1) } else if value.translation.width > 40 { turn(-1) }
        })
        .onTapGesture { location in
            turn(location.x > right.minX ? 1 : -1)
        }
        .task(id: model.engine.page?.id) {
            guard let page = model.engine.page else { return }
            model.engine.save()
            let size = CGSize(width: left.width - 24, height: left.height - 24)
            pages = SpreadRenderer.pages(for: PageSnapshot(page), size: size, face: model.settings.typeface, scale: 2)
            spread = 0
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Next pages") { turn(1) }
        .accessibilityAction(named: "Previous pages") { turn(-1) }
    }

    @ViewBuilder
    private func pageImage(_ index: Int, in frame: CGRect) -> some View {
        if index >= pages.count, index == spread * 2 + 1 || pages.isEmpty {
            // Past the end of the draft: a blank facing sheet, so the spread still reads as a book.
            Rectangle()
                .fill(Color.paperWhite)
                .frame(width: frame.width - 24, height: frame.height - 24)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                .offset(x: frame.minX + 12, y: frame.minY + 12)
        } else if index < pages.count {
            Image(uiImage: pages[index])
                .resizable()
                .frame(width: frame.width - 24, height: frame.height - 24)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                .offset(x: frame.minX + 12, y: frame.minY + 12)
                .accessibilityLabel("Page \(index + 1) of \(pages.count)")
        }
    }

    private func turn(_ direction: Int) {
        let next = spread + direction
        guard next >= 0, next * 2 < pages.count else { return }
        SoundEngine.shared.play(.paperFeed, gain: 0.35)
        withAnimation(.easeInOut(duration: 0.25)) { spread = next }
    }
}

/// Lays a page out on book-sized pages and draws each one, with paper, ink, x-outs and a folio.
enum SpreadRenderer {
    static func pages(for page: PageSnapshot, size: CGSize, face: Typeface, scale: CGFloat) -> [UIImage] {
        guard size.width > 100, size.height > 100 else { return [] }
        let fontSize: CGFloat = size.width < 420 ? 14 : 16
        let font = face.font(size: fontSize)
        let advance = face.advance(size: fontSize)
        let styler = InkStyler(font: font, ink: page.ink, paper: page.paper, face: face, seed: page.inkSeed, lineSpacing: .oneAndHalf, advance: advance)
        let storage = NSTextStorage(attributedString: styler.attributedText(body: page.body, strikes: page.strikes, underlines: page.underlines))
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let inset = UIEdgeInsets(top: 44, left: 34, bottom: 52, right: 34)
        let textSize = CGSize(width: size.width - inset.left - inset.right, height: size.height - inset.top - inset.bottom)
        var containers: [NSTextContainer] = []
        while containers.count < 400 {
            let container = NSTextContainer(size: textSize)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            containers.append(container)
            let range = layout.glyphRange(for: container)
            if range.length == 0 || NSMaxRange(range) >= layout.numberOfGlyphs { break }
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let texture = PaperTexture.paper(page.paper)
        return containers.enumerated().map { index, container in
            UIGraphicsImageRenderer(size: size, format: format).image { context in
                let cg = context.cgContext
                cg.saveGState()
                UIColor(patternImage: texture).setFill()
                cg.fill(CGRect(origin: .zero, size: size))
                cg.restoreGState()
                let origin = CGPoint(x: inset.left, y: inset.top)
                let glyphs = layout.glyphRange(for: container)
                layout.drawGlyphs(forGlyphRange: glyphs, at: origin)
                TypedPagePDF.drawStrikes(storage: storage, layout: layout, container: container, glyphs: glyphs, origin: origin, font: font, advance: advance, ink: page.ink)
                let folio = "- \(index + 1) -" as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: face.font(size: 12), .foregroundColor: page.ink.color.withAlphaComponent(0.7)]
                let folioSize = folio.size(withAttributes: attributes)
                folio.draw(at: CGPoint(x: (size.width - folioSize.width) / 2, y: size.height - 32), withAttributes: attributes)
            }
        }
    }
}
