import Foundation

/// A minimal RFC 4180 reader for the comma separated files inside a GTFS
/// archive.
///
/// Rolling our own rather than splitting on commas matters here because stop
/// names legitimately contain them, quoted: `"Astoria Blvd, Queens"`.
enum DelimitedTextParser {

    static func rows(from text: String) -> [[String]] {
        var rows: [[String]] = []
        var fields: [String] = []
        var field = ""
        var isQuoted = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() {
            fields.append(field)
            field = ""
        }

        func endRow() {
            endField()
            // Skip the blank row a trailing newline produces.
            if fields.count > 1 || fields.first?.isEmpty == false {
                rows.append(fields)
            }
            fields = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil

            if isQuoted {
                if character == "\"" {
                    // A doubled quote inside a quoted field is a literal quote.
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            isQuoted = false
                            pending = next
                        }
                    } else {
                        isQuoted = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }

            switch character {
            case "\"":
                isQuoted = true
            case ",":
                endField()
            // Swift folds CRLF into a single grapheme cluster, so a bare `"\n"`
            // case would silently miss every line break in a CRLF encoded feed.
            case "\n", "\r\n", "\r":
                endRow()
            default:
                field.append(character)
            }
        }

        if !field.isEmpty || !fields.isEmpty {
            endRow()
        }
        return rows
    }
}
