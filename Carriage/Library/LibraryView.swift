import SwiftData
import SwiftUI

/// Drafts and finished pages, laid out like sheets on a desk, grouped by notebook.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Page> { $0.trashedAt == nil }, sort: \Page.modifiedAt, order: .reverse)
    private var pages: [Page]
    @Query(filter: #Predicate<Page> { $0.trashedAt != nil }) private var trashed: [Page]
    @Query(sort: \Notebook.createdAt) private var notebooks: [Notebook]

    @State private var search = ""
    @State private var renaming: Page?
    @State private var draftTitle = ""
    /// The notebook being shown, or nil for every page.
    @State private var notebookID: UUID?
    @State private var naming: NotebookNaming?
    @State private var notebookName = ""
    @State private var importing = false

    private enum NotebookNaming: Identifiable {
        case new
        case rename(Notebook)

        var id: String {
            switch self {
            case .new: "new"
            case let .rename(notebook): notebook.id.uuidString
            }
        }
    }

    private var filtered: [Page] {
        var result = pages
        if let notebookID { result = result.filter { $0.notebookID == notebookID } }
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return result }
        return result.filter { $0.displayTitle.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query) }
    }

    private var drafts: [Page] { filtered.filter { !$0.isFiled } }
    private var filed: [Page] { filtered.filter(\.isFiled) }
    private var currentNotebook: Notebook? { notebooks.first { $0.id == notebookID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if model.focusMode.showsGoals {
                        NavigationLink {
                            WritingHistoryView()
                        } label: {
                            StatsStrip()
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows your writing history.")
                    }
                    if let limit = model.store.freeWordLimit, let left = model.freeWordsLeft {
                        FreeWordsNote(left: left, limit: limit)
                    }
                    notebookBar
                    if let currentNotebook {
                        Text("\(currentNotebook.name) · \(filtered.reduce(0) { $0 + $1.wordCount }.formatted()) words")
                            .font(.typewriter(14))
                            .foregroundStyle(Color.deskInkSoft)
                    }
                    section("Drafts", pages: drafts, empty: "No drafts. Feed a fresh sheet to start one.")
                    section("Pages", pages: filed, empty: "Finished pages land here when you file them.")
                    if !trashed.isEmpty {
                        NavigationLink {
                            WastebasketView()
                        } label: {
                            Label("Wastebasket (\(trashed.count))", systemImage: "trash")
                                .font(Legend.font(size: 13))
                                .tracking(1)
                                .foregroundStyle(Color.deskInkSoft)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(DeskBackground())
            .searchable(text: $search, prompt: "Search pages")
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .alert("Name this page", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Title", text: $draftTitle)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    renaming?.title = draftTitle
                    renaming?.modifiedAt = .now
                    if let page = renaming { model.mirror(page) }
                }
            }
            .alert(namingTitle, isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
                TextField("Name", text: $notebookName)
                Button("Cancel", role: .cancel) {}
                Button("Save") { saveNotebookName() }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: AppModel.importTypes, allowsMultipleSelection: true) { result in
                if case let .success(urls) = result { model.importFiles(urls) }
            }
        }
        .tint(Color.ribbonRed)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .principal) {
            Text("LIBRARY")
                .font(Legend.font(size: 15))
                .tracking(4)
                .foregroundStyle(Color.deskInk)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("New Sheet", systemImage: "doc.badge.plus") { model.newSheet(notebookID: notebookID, inheritNotebook: false) }
                Button("Today's Journal Page", systemImage: "book.closed") { model.openTodaysJournal() }
                Button("New Notebook", systemImage: "folder.badge.plus") {
                    notebookName = ""
                    naming = .new
                }
                Divider()
                Button("Import from Files", systemImage: "square.and.arrow.down") { importing = true }
            } label: {
                Label("Add", systemImage: "plus")
            } primaryAction: {
                model.newSheet(notebookID: notebookID, inheritNotebook: false)
            }
            .accessibilityLabel("New sheet")
            .accessibilityHint("Hold for a journal page, a notebook or an import.")
        }
    }

    /// All pages, then each notebook, as tabs along the top.
    private var notebookBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: notebookID == nil) { notebookID = nil }
                ForEach(notebooks) { notebook in
                    chip(notebook.name, selected: notebookID == notebook.id) { notebookID = notebook.id }
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                                notebookName = notebook.name
                                naming = .rename(notebook)
                            }
                            Button("Delete Notebook", systemImage: "trash", role: .destructive) {
                                if notebookID == notebook.id { notebookID = nil }
                                model.delete(notebook)
                            }
                        }
                }
                Button {
                    notebookName = ""
                    naming = .new
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(Circle().strokeBorder(Color.deskInkSoft.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        .foregroundStyle(Color.deskInkSoft)
                }
                .accessibilityLabel("New notebook")
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(Legend.font(size: 11, relativeTo: .caption))
                .tracking(1.5)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .foregroundStyle(selected ? Color(uiColor: .systemBackground) : Color.deskInk)
                .background(Capsule().fill(selected ? Color.deskInk : Color.deskInkSoft.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var namingTitle: String {
        if case .rename = naming { return "Rename notebook" }
        return "New notebook"
    }

    private func saveNotebookName() {
        switch naming {
        case .new:
            if let notebook = model.createNotebook(named: notebookName) { notebookID = notebook.id }
        case let .rename(notebook):
            model.rename(notebook, to: notebookName)
        case nil:
            break
        }
        naming = nil
    }

    @ViewBuilder
    private func section(_ title: String, pages: [Page], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(Legend.font(size: 13))
                .tracking(3)
                .foregroundStyle(Color.deskInkSoft)
            if pages.isEmpty {
                Text(empty)
                    .font(.typewriter(13))
                    .foregroundStyle(Color.deskInkSoft.opacity(0.8))
                    .padding(.vertical, 6)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 138, maximum: 200), spacing: 18)], spacing: 22) {
                    ForEach(pages) { page in
                        Button { model.open(page) } label: {
                            SheetCard(page: page, isInMachine: model.engine.page?.id == page.id)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { menu(for: page) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for page: Page) -> some View {
        Button("Open", systemImage: "doc.text") { model.open(page) }
        Button("Rename", systemImage: "pencil") {
            draftTitle = page.title
            renaming = page
        }
        Menu("Move to Notebook", systemImage: "folder") {
            Button("No Notebook") { model.move(page, to: nil) }
            ForEach(notebooks) { notebook in
                Button(notebook.name) { model.move(page, to: notebook) }
            }
        }
        Button("Version History", systemImage: "clock.arrow.circlepath") { model.versionsPage = page }
        Divider()
        Menu("Save to Files", systemImage: "folder") {
            ForEach(ExportFormat.allCases) { format in
                Button(format.name, systemImage: format.symbol) { model.saveToFiles(page, format: format) }
            }
        }
        Menu("Share", systemImage: "square.and.arrow.up") {
            ForEach(ExportFormat.allCases) { format in
                Button(format.name, systemImage: format.symbol) { model.export(page, format: format) }
            }
        }
        Button("Share as Image", systemImage: "photo") { model.shareImage(page) }
        Button("Print", systemImage: "printer") { model.print(page) }
        Button("Send to Notes", systemImage: "note.text") { model.sendToNotes(page) }
        Button("Copy Text", systemImage: "doc.on.doc") { model.copyText(page) }
        Divider()
        if page.isFiled {
            Button("Move to Drafts", systemImage: "tray.and.arrow.up") { page.isFiled = false }
        } else {
            Button("File as Page", systemImage: "tray.and.arrow.down") { page.isFiled = true }
        }
        Button("Move to Wastebasket", systemImage: "trash", role: .destructive) { model.trash(page) }
    }
}

/// Words today, the streak, and the last two weeks.
struct StatsStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let goal = model.settings.dailyGoal
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(model.stats.wordsToday)")
                    .font(.typewriter(34))
                    .foregroundStyle(Color.ink)
                    .contentTransition(.numericText())
                Text(goal > 0 ? "OF \(goal) WORDS TODAY" : "WORDS TODAY")
                    .font(Legend.font(size: 10))
                    .tracking(2)
                    .foregroundStyle(Color.inkSoft)
            }
            if goal > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(model.stats.streak)")
                        .font(.typewriter(34))
                        .foregroundStyle(model.stats.streak > 0 ? Color.ribbonRed : Color.ink)
                    Text(model.stats.streak == 1 ? "DAY STREAK" : "DAYS STREAK")
                        .font(Legend.font(size: 10))
                        .tracking(2)
                        .foregroundStyle(Color.inkSoft)
                }
            }
            Spacer()
            RecentDaysChart(days: model.stats.recentDays(14))
                .frame(width: 128, height: 44)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.paperWhite)
                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        )
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Fourteen little bars, red where the goal was met.
struct RecentDaysChart: View {
    var days: [(date: Date, words: Int, met: Bool)]

    var body: some View {
        let peak = max(1, days.map(\.words).max() ?? 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                RoundedRectangle(cornerRadius: 1)
                    .fill(day.met ? Color.ribbonRed : Color.ink.opacity(day.words > 0 ? 0.55 : 0.12))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, 44 * CGFloat(day.words) / CGFloat(peak)))
            }
        }
        .accessibilityLabel("Words written over the last two weeks")
    }
}

struct FreeWordsNote: View {
    @Environment(AppModel.self) private var model
    var left: Int
    var limit: Int

    var body: some View {
        Button { model.showPaywall = true } label: {
            HStack {
                Text(left == 0 ? "You've typed your \(limit.formatted()) free words." : "\(left.formatted()) of \(limit.formatted()) free words left.")
                Spacer()
                Text("UNLOCK")
                    .font(Legend.font(size: 11))
                    .tracking(2)
            }
            .font(.typewriter(13))
            .foregroundStyle(Color.deskInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.deskInk.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(.plain)
    }
}

/// One page as a small sheet of paper.
struct SheetCard: View {
    @Environment(AppModel.self) private var model
    var page: Page
    var isInMachine: Bool

    var body: some View {
        let tilt = Double(Int(page.id.uuid.0) % 7) * 0.35 - 1.05
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(uiColor: page.paper.color))
                    .overlay(Image(uiImage: PaperTexture.paper(page.paper)).resizable(resizingMode: .tile).opacity(0.9))
                Text(preview)
                    .font(.typewriterFixed(6.4, face: model.settings.typeface))
                    .foregroundStyle(Color(uiColor: page.ink.color).opacity(0.88))
                    .lineSpacing(1)
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                if isInMachine {
                    Text("IN THE MACHINE")
                        .font(Legend.fixedFont(size: 7.5))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.ribbonRed))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .aspectRatio(8.5 / 11, contentMode: .fit)
            .clipShape(Rectangle())
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
            .rotationEffect(.degrees(tilt))

            VStack(alignment: .leading, spacing: 2) {
                Text(page.displayTitle)
                    .font(.typewriter(13, face: model.settings.typeface))
                    .foregroundStyle(Color.deskInk)
                    .lineLimit(1)
                Text("\(page.modifiedAt.formatted(.dateTime.month(.abbreviated).day())) · \(page.wordCount) words")
                    .font(Legend.font(size: 10, relativeTo: .caption))
                    .tracking(0.8)
                    .foregroundStyle(Color.deskInkSoft)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(page.displayTitle), \(page.wordCount) words, edited \(page.modifiedAt.formatted(date: .abbreviated, time: .omitted))")
        .accessibilityAddTraits(.isButton)
    }

    private var preview: String {
        let text = TextExport.plainText(body: page.body, strikes: page.strikes)
        return String(text.prefix(900))
    }
}

/// Pages moved to the wastebasket. They're emptied after 30 days.
struct WastebasketView: View {
    @Environment(AppModel.self) private var model
    @Query(filter: #Predicate<Page> { $0.trashedAt != nil }, sort: \Page.modifiedAt, order: .reverse)
    private var pages: [Page]
    @State private var confirming: Page?

    var body: some View {
        List {
            Section {
                ForEach(pages) { page in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(page.displayTitle).font(.typewriter(15))
                        Text("\(page.wordCount) words").font(Legend.font(size: 11, relativeTo: .caption)).foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) { confirming = page }
                    }
                    .swipeActions(edge: .leading) {
                        Button("Restore") { model.restore(page) }.tint(.green)
                    }
                    .contextMenu {
                        Button("Restore", systemImage: "arrow.uturn.backward") { model.restore(page) }
                        Button("Delete Forever", systemImage: "trash", role: .destructive) { confirming = page }
                    }
                }
            } footer: {
                Text("Pages here are deleted for good after 30 days.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(DeskBackground())
        .navigationTitle("Wastebasket")
        .confirmationDialog("Delete this page forever?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible) {
            Button("Delete Forever", role: .destructive) {
                if let page = confirming { model.deleteForever(page) }
            }
        } message: {
            Text("This can't be undone.")
        }
    }
}

/// A warm blotter for the library and settings: cream by day, walnut by night.
struct DeskBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color(hex: scheme == .dark ? 0x1D1A17 : 0xEFE9DC)
            Image(uiImage: PaperTexture.paper(.cream)).resizable(resizingMode: .tile).opacity(scheme == .dark ? 0.04 : 0.5)
        }
        .ignoresSafeArea()
    }
}
