import SwiftUI
import WidgetKit

/// Today's words, the goal and the streak, read from what the app shares in the app group.
struct WritingEntry: TimelineEntry {
    let date: Date
    let words: Int
    let goal: Int
    let streak: Int
    let lastLine: String

    static let placeholder = WritingEntry(date: .now, words: 412, goal: 500, streak: 6, lastLine: "It was the summer the river forgot its banks.")

    var progress: Double { goal > 0 ? min(1, Double(words) / Double(goal)) : 0 }
    var met: Bool { goal > 0 && words >= goal }
}

struct WritingProvider: TimelineProvider {
    func placeholder(in context: Context) -> WritingEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WritingEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WritingEntry>) -> Void) {
        let now = Date()
        // A fresh day starts at zero; the app reloads the timeline whenever the count changes.
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: [entry(at: now), entry(at: midnight)], policy: .after(midnight)))
    }

    private func entry(at date: Date) -> WritingEntry {
        let defaults = UserDefaults(suiteName: "group.com.carriage.app")
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let key = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        let isToday = defaults?.string(forKey: "day") == key
        return WritingEntry(
            date: date,
            words: isToday ? (defaults?.integer(forKey: "wordsToday") ?? 0) : 0,
            goal: defaults?.integer(forKey: "goal") ?? 0,
            streak: defaults?.integer(forKey: "streak") ?? 0,
            lastLine: isToday ? (defaults?.string(forKey: "lastLine") ?? "") : ""
        )
    }
}

private let ink = Color(red: 0.12, green: 0.11, blue: 0.106)
private let inkSoft = Color(red: 0.42, green: 0.39, blue: 0.36)
private let ribbon = Color(red: 0.635, green: 0.176, blue: 0.153)
private let paper = Color(red: 0.984, green: 0.976, blue: 0.953)

private func typed(_ size: CGFloat) -> Font { .custom("CourierPrime-Regular", size: size) }
private func legend(_ size: CGFloat) -> Font { .custom("Futura-Medium", size: size) }

struct WritingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WritingEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.progress) {
                Image(systemName: "pencil.line")
            } currentValueLabel: {
                Text("\(entry.words)").font(.system(.body, design: .monospaced))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("CARRIAGE").font(.caption2.weight(.semibold))
                Text(entry.goal > 0 ? "\(entry.words) of \(entry.goal) words" : "\(entry.words) words today")
                    .font(.system(.body, design: .monospaced))
                if entry.streak > 1 {
                    Text("\(entry.streak)-day streak").font(.caption2)
                }
            }
        case .accessoryInline:
            Text(entry.goal > 0 ? "\(entry.words)/\(entry.goal) words" : "\(entry.words) words today")
        case .systemMedium:
            HStack(alignment: .top, spacing: 16) {
                counts
                VStack(alignment: .leading, spacing: 6) {
                    Text("WHERE YOU LEFT OFF").font(legend(9)).tracking(1.5).foregroundStyle(ribbon)
                    Text(entry.lastLine.isEmpty ? "A fresh sheet is waiting." : entry.lastLine)
                        .font(typed(13))
                        .foregroundStyle(ink)
                        .lineLimit(4)
                }
            }
        default:
            counts
        }
    }

    private var counts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TODAY").font(legend(9)).tracking(1.5).foregroundStyle(ribbon)
            Text("\(entry.words)").font(typed(34)).foregroundStyle(ink).minimumScaleFactor(0.6)
            Text(entry.goal > 0 ? (entry.met ? "goal met" : "of \(entry.goal) words") : "words")
                .font(typed(12)).foregroundStyle(entry.met ? ribbon : inkSoft)
            Spacer(minLength: 0)
            if entry.goal > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(ink.opacity(0.1))
                        Capsule().fill(entry.met ? ribbon : ink).frame(width: proxy.size.width * entry.progress)
                    }
                }
                .frame(height: 4)
            }
            if entry.streak > 1 {
                Text("\(entry.streak)-day streak").font(legend(10)).foregroundStyle(inkSoft)
            }
        }
    }
}

struct WritingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CarriageWriting", provider: WritingProvider()) { entry in
            WritingWidgetView(entry: entry)
                .containerBackground(for: .widget) { paper }
                .widgetURL(URL(string: "carriage://focus"))
        }
        .configurationDisplayName("Words today")
        .description("Today's words, your goal and your streak.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct CarriageWidgets: WidgetBundle {
    var body: some Widget {
        WritingWidget()
    }
}
