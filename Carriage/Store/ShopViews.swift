import SwiftUI

/// The unlock, written as a typed letter.
struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        let limit = model.store.freeWordLimit ?? 5000
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Dear writer,")
                Text(model.freeWordsLeft == 0
                     ? "You've typed your first \(limit.formatted()) words here. Thank you for writing them on Carriage."
                     : "Your first \(limit.formatted()) words are on the house, with every paper, ribbon and machine.")
                Text("Carriage is a one-time purchase: no subscription and no ads. Unlock it once and every word after is yours, on all your devices, for as long as you keep writing.")
                Text("Yours,")
                    .padding(.top, 6)
                Text("Carriage")
                    .foregroundStyle(Color.ribbonRed)
                    .rotationEffect(.degrees(-2))

                Button {
                    Task {
                        working = true
                        if await model.store.purchase(ProductID.unlock) {
                            SoundEngine.shared.play(.bell)
                            model.updateTypingLock()
                            dismiss()
                        }
                        working = false
                    }
                } label: {
                    HStack {
                        if working { ProgressView().tint(.white) }
                        Text(model.store.price(ProductID.unlock).map { "Unlock Carriage · \($0)" } ?? "Unlock Carriage")
                    }
                    .font(Legend.font(size: 15))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Capsule().fill(Color.ink))
                }
                .buttonStyle(.plain)
                .disabled(working)
                .padding(.top, 14)

                HStack {
                    Button("Restore purchases") {
                        Task {
                            await model.store.restore()
                            if model.store.isUnlocked { dismiss() }
                        }
                    }
                    Spacer()
                    Button("Not now") { dismiss() }
                }
                .font(Legend.font(size: 13))
                .foregroundStyle(Color.inkSoft)

                if let error = model.store.lastError {
                    Text(error).font(.footnote).foregroundStyle(Color.ribbonRed)
                }
            }
            .font(.typewriter(16))
            .foregroundStyle(Color.ink)
            .padding(32)
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
        .presentationDetents([.medium, .large])
        .task { await model.store.loadProductsIfNeeded() }
        .onDisappear { model.store.lastError = nil }
    }
}
