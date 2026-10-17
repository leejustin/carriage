import SwiftUI

/// Shown once on a regular iPhone: Carriage was made for iPhone Duo, and this is the pocket version.
struct DuoLetterView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("MADE FOR IPHONE DUO")
                    .font(Legend.font(size: 12))
                    .tracking(3)
                    .foregroundStyle(Color.ribbonRed)
                Text("Dear writer,")
                Text("Carriage was made for iPhone Duo. Half-fold a Duo like a tiny laptop and the bottom half becomes a full typewriter keyboard, with the page rolling up on top.")
                Text("On this iPhone you get the pocket machine: the same paper, ink and sounds, on a smaller deck.")
                Text("Yours,")
                    .padding(.top, 6)
                Text("Carriage")
                    .foregroundStyle(Color.ribbonRed)
                    .rotationEffect(.degrees(-2))

                Button {
                    dismiss()
                } label: {
                    Text("Start typing")
                        .font(Legend.font(size: 15))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Capsule().fill(Color.ink))
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
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
    }
}
