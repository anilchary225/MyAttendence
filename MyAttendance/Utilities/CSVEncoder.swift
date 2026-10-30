import Foundation

/// Minimal RFC 4180 CSV writer/reader (UTF-8, quotes, commas, line breaks).
enum CSVCodec {

    static func escape(_ field: String) -> String {
        let needsQuotes = field.contains(",") || field.contains("\"")
            || field.contains("\n") || field.contains("\r")
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func encode(header: [String], rows: [[String]]) -> String {
        var lines = [header.map(escape).joined(separator: ",")]
        for row in rows { lines.append(row.map(escape).joined(separator: ",")) }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    enum ParseError: Error, LocalizedError {
        case unterminatedQuote
        var errorDescription: String? { "The CSV file has an unclosed quotation mark." }
    }

    /// Parses CSV text into rows of fields. Strips a leading BOM and skips blank lines.
    static func parse(_ text: String) throws -> [[String]] {
        var input = text
        if input.hasPrefix("\u{FEFF}") { input.removeFirst() }

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var fieldWasQuoted = false

        let chars = Array(input.unicodeScalars)
        var i = 0

        func endField() {
            row.append(field)
            field = ""
            fieldWasQuoted = false
        }
        func endRow() {
            endField()
            let isBlank = row.count == 1 && row[0].isEmpty
            if !isBlank { rows.append(row) }
            row = []
        }

        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.unicodeScalars.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(c)
                }
            } else {
                switch c {
                case "\"":
                    if field.isEmpty && !fieldWasQuoted { inQuotes = true; fieldWasQuoted = true }
                    else { field.unicodeScalars.append(c) }
                case ",":
                    endField()
                case "\r":
                    if i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                    endRow()
                case "\n":
                    endRow()
                default:
                    field.unicodeScalars.append(c)
                }
            }
            i += 1
        }
        if inQuotes { throw ParseError.unterminatedQuote }
        if !field.isEmpty || !row.isEmpty || fieldWasQuoted { endRow() }
        return rows
    }
}
