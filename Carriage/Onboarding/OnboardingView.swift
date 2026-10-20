import SwiftUI
import TipKit

/// The first-run tour: four typed cards. On a regular iPhone the first card says Carriage is made for iPhone Duo.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    #if DEBUG
    /// `-onboardingPage 2` opens the tour on that card, for checking it.
    @State private var page = UserDefaults.standard.integer(forKey: "onboardingPage")
    #else
    @State private var page = 0
    #endif

    private var cards: [Card] {
        [
            model.isDuo
                ? Card(symbol: "rectangle.split.1x2", kicker: "HALF-FOLD IT",
                       title: "Your Duo is now a typewriter.",
                       text: "Fold it like a tiny laptop: the page rolls up on top, a full typewriter waits below. Hold it like a book to read your pages as a spread. Close it to read on the outer screen.")
                : Card(symbol: "rectangle.split.1x2", kicker: "MADE FOR IPHONE DUO",
                       title: "This is the pocket machine.",
                       text: "Carriage was made for iPhone Duo: half-fold a Duo and the bottom half becomes a full typewriter. On this iPhone you get the same paper, ink and sounds on a smaller deck."),
            Card(symbol: "xmark", kicker: "TWO WAYS TO TYPE",
                 title: "Free, or no going back.",
                 text: "In Free mode, delete works. In Typewriter mode there is no delete: X-OUT types an x over your mistake and you keep going. Switch with the lever at the top of the page."),
            Card(symbol: "arrow.right.to.line", kicker: "LIKE THE REAL THING",
                 title: "Push the carriage.",
                 text: "The bell rings near the margin. Drag the paper to the right to return the carriage, or press RETURN. How should the carriage move?",
                 choosesCarriage: true),
            Card(symbol: "moon", kicker: "MAKE IT QUIET",
                 title: "Just you and the page.",
                 text: "Tap the moon for Focus: the controls, counts and messages go away until you tap the paper. Then let iOS silence your notifications whenever Carriage is open."),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    CardView(card: card)
                        .tag(index)
                        .padding(.horizontal, 20)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 12) {
                if page == cards.count - 1 {
                    Button {
                        model.finishOnboarding()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { model.showFocusSetup = true }
                    } label: {
                        Text("Set up Do Not Disturb")
                            .font(Legend.font(size: 15))
                            .tracking(1.5)
                            .foregroundStyle(Color.paperWhite)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Capsule().fill(Color.ribbonRed))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    if page < cards.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        model.finishOnboarding()
                    }
                } label: {
                    Text(page < cards.count - 1 ? "Next" : "Start typing")
                        .font(Legend.font(size: 15))
                        .tracking(1.5)
                        .foregroundStyle(Color.paperWhite)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Capsule().fill(Color.ink))
                }
                .buttonStyle(.plain)
                if page < cards.count - 1 {
                    Button("Skip") { model.finishOnboarding() }
                        .font(Legend.font(size: 13))
                        .foregroundStyle(Color.deskInkSoft)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
        }
        .background(DeskBackground())
        .interactiveDismissDisabled()
    }

    struct Card {
        var symbol: String
        var kicker: String
        var title: String
        var text: String
        /// Shows the carriage choices under the text.
        var choosesCarriage = false
    }

    private struct CardView: View {
        var card: Card
        @Environment(AppModel.self) private var model

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: card.symbol)
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Color.ribbonRed)
                        .frame(height: 44)
                        .accessibilityHidden(true)
                    Text(card.kicker)
                        .font(Legend.font(size: 12))
                        .tracking(3)
                        .foregroundStyle(Color.ribbonRed)
                    Text(card.title)
                        .font(.typewriter(22))
                    Text(card.text)
                        .font(.typewriter(16))
                        .lineSpacing(3)
                    if card.choosesCarriage {
                        carriageChoices
                    }
                }
                .foregroundStyle(Color.ink)
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Rectangle()
                        .fill(Color.paperWhite)
                        .overlay(Image(uiImage: PaperTexture.paper(.bond)).resizable(resizingMode: .tile))
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                )
                .padding(.top, 40)
                .padding(.bottom, 50)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }

        /// Gentle first: it's the default. The same choice lives in Settings › The page › Carriage.
        private var carriageChoices: some View {
            VStack(spacing: 8) {
                ForEach([CarriageTravel.gentle, .classic, .fixed]) { travel in
                    let chosen = model.settings.carriage == travel
                    Button {
                        model.settings.carriage = travel
                        SoundEngine.shared.play(.carriageReturn, gain: 0.5)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: chosen ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(chosen ? Color.ribbonRed : Color.inkSoft)
                                .font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(travel == .gentle ? "\(travel.name) (recommended)" : travel.name)
                                    .font(Legend.font(size: 14))
                                    .tracking(1)
                                Text(travel.detail)
                                    .font(.typewriter(13))
                                    .foregroundStyle(Color.inkSoft)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).stroke(chosen ? Color.ribbonRed : Color.inkSoft.opacity(0.3), lineWidth: chosen ? 1.5 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            .padding(.top, 4)
        }
    }
}

/// Tips that point at controls after the tour, once each.
struct FocusTip: Tip {
    @Parameter static var tourFinished: Bool = false

    var title: Text { Text("Focus") }
    var message: Text? { Text("Clear everything but the page. Tap the paper to bring the controls back.") }
    var image: Image? { Image(systemName: "moon") }
    var rules: [Rule] { [#Rule(Self.$tourFinished) { $0 == true }] }
}

struct PageMenuTip: Tip {
    var title: Text { Text("Your page") }
    var message: Text? { Text("Save to Files, print, share as a picture, open today's journal, and see earlier versions.") }
    var image: Image? { Image(systemName: "ellipsis.circle") }
    var rules: [Rule] { [#Rule(FocusTip.$tourFinished) { $0 == true }] }
    var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
}
