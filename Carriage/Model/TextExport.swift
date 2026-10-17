import Foundation

/// Turns a page into plain text and Markdown.
nonisolated enum TextExport {
    /// The page as it reads with struck characters taken out, and the gaps they leave tidied.
    static func plainText(body: String, strikes: [NSRange]) -> String {
        let text = body as NSString
        let ranges = StrikeRanges.merge(strikes).filter { NSMaxRange($0) <= text.length }
        guard !ranges.isEmpty else { return body }
        let out = NSMutableString()
        var cursor = 0
        for range in ranges {
            out.append(text.substring(with: NSRange(location: cursor, length: range.location - cursor)))
            cursor = NSMaxRange(range)
            // Don't leave a double space (or a space at the start of a line) where the struck word was.
            let before = out.length > 0 ? out.character(at: out.length - 1) : 0x0A
            if cursor < text.length, text.character(at: cursor) == 0x20, before == 0x20 || before == 0x0A {
                cursor += 1
            }
        }
        out.append(text.substring(from: min(cursor, text.length)))
        return out as String
    }

    /// The page as Markdown: a heading for the title, and struck text as ~~strikethrough~~.
    static func markdown(title: String, body: String, strikes: [NSRange]) -> String {
        let text = body as NSString
        let ranges = StrikeRanges.merge(strikes).filter { NSMaxRange($0) <= text.length }
        var out = ""
        var cursor = 0
        for range in ranges {
            out += escape(text.substring(with: NSRange(location: cursor, length: range.location - cursor)))
            out += strike(text.substring(with: range))
            cursor = NSMaxRange(range)
        }
        out += escape(text.substring(from: min(cursor, text.length)))
        // Markdown folds single newlines into one paragraph; a typed page means its line breaks.
        let body = out.replacingOccurrences(of: "\n", with: "  \n") + (out.hasSuffix("\n") ? "" : "\n")
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return heading.isEmpty ? body : "# \(heading)\n\n" + body
    }

    static func wordCount(body: String, strikes: [NSRange]) -> Int {
        plainText(body: body, strikes: strikes).split { $0.isWhitespace || $0.isNewline }.count
    }

    /// Wraps struck text in ~~, line by line, keeping surrounding whitespace outside the markers.
    private static func strike(_ struck: String) -> String {
        struck.components(separatedBy: "\n").map { line in
            let core = line.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else { return line }
            let lead = line.prefix { $0 == " " || $0 == "\t" }
            let trail = String(line.reversed().prefix { $0 == " " || $0 == "\t" })
            return lead + "~~" + escape(core) + "~~" + trail
        }.joined(separator: "\n")
    }

    /// Escapes characters that would otherwise turn typed text into Markdown formatting.
    private static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var atLineStart = true
        for character in text {
            switch character {
            case "\\", "*", "_", "`", "~", "[", "]", "<", ">":
                out.append("\\")
                out.append(character)
            case "#" where atLineStart, "-" where atLineStart, "+" where atLineStart:
                out.append("\\")
                out.append(character)
            default:
                out.append(character)
            }
            atLineStart = character == "\n" || (atLineStart && (character == " " || character == "\t"))
        }
        return out
    }
}
