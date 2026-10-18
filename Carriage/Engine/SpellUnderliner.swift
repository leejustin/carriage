import UIKit

/// Optional spell check that only underlines. Nothing is ever corrected.
enum SpellUnderliner {
    private static let checker = UITextChecker()

    static func underline(_ storage: NSTextStorage) {
        let text = storage.string
        let language = Locale.preferredLanguages.first.map { UITextChecker.availableLanguages.contains($0) ? $0 : "en_US" } ?? "en_US"
        storage.beginEditing()
        clearMarks(storage)
        var location = 0
        let length = (text as NSString).length
        while location < length {
            let range = checker.rangeOfMisspelledWord(in: text, range: NSRange(location: 0, length: length), startingAt: location, wrap: false, language: language)
            guard range.location != NSNotFound else { break }
            // Don't flag the word still being typed at the end of the page.
            if NSMaxRange(range) < length, storage.attribute(.carriageStrike, at: range.location, effectiveRange: nil) == nil,
               storage.attribute(.carriageUnderline, at: range.location, effectiveRange: nil) == nil {
                storage.addAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                    .underlineColor: UIColor(hex: 0xC0392B, alpha: 0.75),
                    .carriageSpelling: true,
                ], range: range)
            }
            location = NSMaxRange(range)
        }
        storage.endEditing()
    }

    static func clear(_ storage: NSTextStorage) {
        storage.beginEditing()
        clearMarks(storage)
        storage.endEditing()
    }

    private static func clearMarks(_ storage: NSTextStorage) {
        storage.enumerateAttribute(.carriageSpelling, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value != nil else { return }
            storage.removeAttribute(.underlineStyle, range: range)
            storage.removeAttribute(.underlineColor, range: range)
            storage.removeAttribute(.carriageSpelling, range: range)
            // Put back any real underline the spelling mark was covering.
            storage.enumerateAttribute(.carriageUnderline, in: range) { value, underlined, _ in
                guard value != nil else { return }
                storage.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue], range: underlined)
            }
        }
    }
}
