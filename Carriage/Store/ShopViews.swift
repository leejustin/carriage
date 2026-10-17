import SwiftUI

/// The unlock, written as a typed letter.
struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        let limit = model.store.freePageLimit ?? 3
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Dear writer,")
                Text("You've filled your \(limit) free pages. Thank you for typing them here.")
                Text("Carriage is a one-time purchase: no subscription and no ads. Unlock it once and every sheet is yours, on all your devices, for as long as you keep writing.")
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
                            dismiss()
                            model.newSheet()
                        }
                        working = false
                    }
                } label: {
                    HStack {
                        if working { ProgressView().tint(.white) }
                        Text("Unlock Carriage · \(model.store.price(ProductID.unlock) ?? "$6.99")")
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

/// Paper, ribbons and machine voices.
struct ShopView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    PackCard(
                        title: "Paper & Ink",
                        blurb: "Cream, onion skin and carbon copy stock, with red, faded and carbon blue ribbons.",
                        productID: ProductID.paperInk,
                        owned: model.store.hasPaperInk
                    ) {
                        HStack(spacing: -18) {
                            ForEach(Array(PaperStyle.allCases.enumerated()), id: \.offset) { i, style in
                                Rectangle()
                                    .fill(Color(uiColor: style.color))
                                    .overlay(Image(uiImage: PaperTexture.paper(style)).resizable(resizingMode: .tile))
                                    .overlay(alignment: .topLeading) {
                                        Text("Aa").font(.typewriter(16)).foregroundStyle(Color(uiColor: InkStyle.allCases[i % InkStyle.allCases.count].color))
                                            .padding(8)
                                    }
                                    .frame(width: 70, height: 90)
                                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                                    .rotationEffect(.degrees(Double(i) * 4 - 6))
                            }
                        }
                        .frame(height: 110)
                    }

                    PackCard(
                        title: "Machine Sounds",
                        blurb: "Three more machines: a heavy office upright, a quick electric and a rattly tin traveller.",
                        productID: ProductID.sounds,
                        owned: model.store.hasSounds
                    ) {
                        VStack(spacing: 8) {
                            ForEach(MachineSound.allCases.filter(\.isPremium)) { machine in
                                Button {
                                    SoundEngine.shared.preview(machine)
                                } label: {
                                    HStack {
                                        Image(systemName: "play.circle.fill").foregroundStyle(Color.ribbonRed)
                                        Text(machine.name).font(.typewriter(15)).foregroundStyle(Color.ink)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Preview \(machine.name)")
                            }
                        }
                    }

                    Button("Restore purchases") {
                        Task { await model.store.restore(); model.enforceEntitlements() }
                    }
                    .font(Legend.font(size: 13))
                    .foregroundStyle(Color.inkSoft)

                    if let error = model.store.lastError {
                        Text(error).font(.footnote).foregroundStyle(Color.ribbonRed)
                    }
                }
                .padding(20)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(DeskBackground())
            .navigationTitle("Supply shop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SUPPLY SHOP").font(Legend.font(size: 15)).tracking(4)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Color.ribbonRed)
        .task { await model.store.loadProductsIfNeeded() }
        .onDisappear { model.store.lastError = nil }
    }
}

struct PackCard<Preview: View>: View {
    @Environment(AppModel.self) private var model
    var title: String
    var blurb: String
    var productID: String
    var owned: Bool
    @ViewBuilder var preview: Preview
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            preview.frame(maxWidth: .infinity)
            Text(title.uppercased())
                .font(Legend.font(size: 16))
                .tracking(3)
                .foregroundStyle(Color.ink)
            Text(blurb)
                .font(.typewriter(14))
                .foregroundStyle(Color.ink.opacity(0.8))
            if owned {
                Label("In your supply drawer", systemImage: "checkmark.seal.fill")
                    .font(Legend.font(size: 13))
                    .foregroundStyle(Color.ribbonRed)
            } else {
                Button {
                    Task {
                        working = true
                        if await model.store.purchase(productID) { SoundEngine.shared.play(.bell) }
                        working = false
                    }
                } label: {
                    HStack {
                        if working { ProgressView().tint(.white) }
                        Text("Buy · \(model.store.price(productID) ?? "$1.99")")
                    }
                    .font(Legend.font(size: 14))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Capsule().fill(Color.ink))
                }
                .buttonStyle(.plain)
                .disabled(working)
            }
        }
        .padding(20)
        .background(
            Rectangle()
                .fill(Color.paperWhite)
                .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
        )
    }
}
