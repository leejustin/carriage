import SwiftData
import SwiftUI

/// Earlier versions of one page, newest first, with a preview and restore.
struct VersionHistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let page: Page
    @State private var versions: [PageVersion] = []
    @State private var selected: PageVersion?

    var body: some View {
        NavigationStack {
            List {
                if versions.isEmpty {
                    Text("No earlier versions yet. Carriage keeps one when you open a page and every ten minutes while you write.")
                        .font(.typewriter(14, relativeTo: .body))
                        .foregroundStyle(.secondary)
                }
                ForEach(versions) { version in
                    Button {
                        selected = version
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(version.savedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.typewriter(15, relativeTo: .body))
                            Text("\(version.wordCount) words · \(version.reason)")
                                .font(Legend.font(size: 11, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                            Text(TextExport.plainText(body: version.body, strikes: StrikeRanges.decode(version.strikeData)).prefix(120))
                                .font(.typewriter(12, relativeTo: .footnote))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DeskBackground())
            .navigationTitle("Versions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $selected) { version in
                VersionPreview(page: page, version: version) { dismiss() }
            }
            .onAppear {
                if let context = model.context { versions = PageHistory.versions(of: page, in: context) }
            }
        }
        .tint(Color.ribbonRed)
    }
}

private struct VersionPreview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let page: Page
    let version: PageVersion
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(TextExport.plainText(body: version.body, strikes: StrikeRanges.decode(version.strikeData)))
                    .font(.typewriter(15, relativeTo: .body))
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .background(Rectangle().fill(Color.paperWhite).shadow(color: .black.opacity(0.15), radius: 6, y: 2))
                    .padding(16)
            }
            .background(DeskBackground())
            .navigationTitle(version.savedAt.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu("Use") {
                        Button("Restore This Version", systemImage: "clock.arrow.circlepath") {
                            model.restore(version, of: page)
                            dismiss()
                            onDone()
                        }
                        Button("Copy as New Page", systemImage: "doc.on.doc") {
                            model.copyAsNewPage(version, of: page)
                            dismiss()
                            onDone()
                        }
                    }
                }
            }
        }
        .tint(Color.ribbonRed)
    }
}

/// Every day you wrote: a calendar, totals, streaks and speed.
struct WritingHistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.calendar) private var calendar

    var body: some View {
        let summary = model.stats.summary()
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 14)], spacing: 14) {
                    figure("\(summary.totalWords.formatted())", "WORDS IN ALL")
                    figure("\(summary.daysWritten)", summary.daysWritten == 1 ? "DAY WRITTEN" : "DAYS WRITTEN")
                    figure("\(summary.currentStreak)", "CURRENT STREAK")
                    figure("\(summary.longestStreak)", "LONGEST STREAK")
                    figure(summary.wordsPerMinute.map { "\($0)" } ?? "–", "WORDS A MINUTE")
                    if let best = summary.bestDay {
                        figure("\(best.words.formatted())", "BEST DAY · " + (WritingStats.date(from: best.date, calendar: calendar)?.formatted(.dateTime.month(.abbreviated).day()) ?? best.date))
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("THE LAST SIX MONTHS")
                        .font(Legend.font(size: 12, relativeTo: .caption))
                        .tracking(3)
                        .foregroundStyle(Color.deskInkSoft)
                    CalendarHeatmap(days: summary.days, goal: model.settings.dailyGoal, weeks: 26)
                        .accessibilityLabel("Calendar of words written each day over the last six months")
                    HStack(spacing: 10) {
                        legend(Color.deskInkSoft.opacity(0.18), "None")
                        legend(Color.deskInk.opacity(0.45), "Some")
                        legend(Color.ribbonRed, "Goal met")
                    }
                    .font(Legend.font(size: 11, relativeTo: .caption))
                    .foregroundStyle(Color.deskInkSoft)
                }
            }
            .padding(20)
        }
        .background(DeskBackground())
        .navigationTitle("Writing history")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.typewriter(28, relativeTo: .title)).foregroundStyle(Color.ink)
            Text(label).font(Legend.font(size: 10, relativeTo: .caption2)).tracking(1.5).foregroundStyle(Color.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Rectangle().fill(Color.paperWhite).shadow(color: .black.opacity(0.12), radius: 4, y: 2))
        .accessibilityElement(children: .combine)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 12)
            Text(text)
        }
    }
}

/// One square per day, a column per week.
struct CalendarHeatmap: View {
    var days: [String: (words: Int, seconds: Double, goal: Int)]
    var goal: Int
    var weeks: Int
    @Environment(\.calendar) private var calendar

    var body: some View {
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today) - calendar.firstWeekday
        let start = calendar.date(byAdding: .day, value: -((weeks - 1) * 7 + (weekday + 7) % 7), to: today) ?? today
        let peak = max(1, days.values.map(\.words).max() ?? 1)
        GeometryReader { proxy in
            let cell = min(18, (proxy.size.width - CGFloat(weeks - 1) * 3) / CGFloat(weeks))
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { day in
                            let date = calendar.date(byAdding: .day, value: week * 7 + day, to: start) ?? start
                            let entry = days[WritingDay.key(for: date, calendar: calendar)]
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(for: entry, peak: peak, future: date > today))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        .frame(height: 7 * 18 + 6 * 3)
    }

    private func color(for entry: (words: Int, seconds: Double, goal: Int)?, peak: Int, future: Bool) -> Color {
        guard !future else { return .clear }
        guard let entry, entry.words > 0 else { return Color.deskInkSoft.opacity(0.18) }
        let target = entry.goal > 0 ? entry.goal : goal
        if target > 0, entry.words >= target { return .ribbonRed }
        return Color.deskInk.opacity(0.25 + 0.45 * Double(entry.words) / Double(peak))
    }
}
