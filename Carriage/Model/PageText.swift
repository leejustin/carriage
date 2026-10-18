import Foundation
import SwiftData
import UIKit

/// A page's text and marks, for comparing what's on the paper with what's stored.
struct PageText: Equatable {
    var body = ""
    var strikes: [NSRange] = []
    var underlines: [NSRange] = []

    init() {}

    init(_ page: Page) {
        body = page.body
        strikes = StrikeRanges.merge(page.strikes)
        underlines = StrikeRanges.merge(page.underlines)
    }

    init(_ storage: NSAttributedString) {
        body = storage.string
        var strikes: [NSRange] = []
        var underlines: [NSRange] = []
        let all = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.carriageStrike, in: all) { value, range, _ in
            if value != nil { strikes.append(range) }
        }
        storage.enumerateAttribute(.carriageUnderline, in: all) { value, range, _ in
            if value != nil { underlines.append(range) }
        }
        self.strikes = StrikeRanges.merge(strikes)
        self.underlines = StrikeRanges.merge(underlines)
    }
}

/// Saved versions of pages: taken when a page is opened, every ten minutes of writing, and before a restore.
enum PageHistory {
    /// Versions kept per page; older ones are thinned out.
    static let limit = 60

    static func snapshot(_ page: Page, reason: String, in context: ModelContext, ifOlderThan age: TimeInterval) {
        guard !page.body.isEmpty else { return }
        let id = page.id
        let descriptor = FetchDescriptor<PageVersion>(predicate: #Predicate { $0.pageID == id }, sortBy: [SortDescriptor(\.savedAt, order: .reverse)])
        let versions = (try? context.fetch(descriptor)) ?? []
        if let latest = versions.first {
            // Nothing new to keep, or one was kept too recently.
            if latest.body == page.body && latest.strikeData == page.strikeData && latest.underlineData == page.underlineData { return }
            if Date().timeIntervalSince(latest.savedAt) < age { return }
        }
        context.insert(PageVersion(page: page, reason: reason))
        if versions.count >= limit {
            for old in versions.suffix(versions.count - limit + 1) { context.delete(old) }
        }
    }

    static func versions(of page: Page, in context: ModelContext) -> [PageVersion] {
        let id = page.id
        let descriptor = FetchDescriptor<PageVersion>(predicate: #Predicate { $0.pageID == id }, sortBy: [SortDescriptor(\.savedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func deleteAll(of pageID: UUID, in context: ModelContext) {
        let descriptor = FetchDescriptor<PageVersion>(predicate: #Predicate { $0.pageID == pageID })
        for version in (try? context.fetch(descriptor)) ?? [] { context.delete(version) }
    }
}
