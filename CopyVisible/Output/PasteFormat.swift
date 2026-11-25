import Foundation

/// The shapes text can be copied as.
enum PasteFormat: String, CaseIterable, Identifiable, Sendable {
    case plain
    case markdown
    case csv
    case json
    case snakeCase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain: "Plain"
        case .markdown: "Markdown"
        case .csv: "CSV"
        case .json: "JSON"
        case .snakeCase: "snake_case"
        }
    }

    /// Converts text. A table, when there is one, is used for Markdown, CSV
    /// and JSON so that cells stay cells.
    func apply(to text: String, table: [[String]]?, kind: CaptureKind) -> String {
        switch self {
        case .plain:
            return text
        case .markdown:
            if let table { return Self.markdownTable(table) }
            if kind.keepsLayout { return "```\n" + text + "\n```" }
            return Self.markdownText(text)
        case .csv:
            return Self.csv(table ?? Self.columns(text))
        case .json:
            if let table { return Self.json(table: table) }
            let lines = text.components(separatedBy: "\n")
            return Self.jsonString(lines.count > 1 ? lines as Any : text as Any)
        case .snakeCase:
            return text.components(separatedBy: "\n").map(Self.snakeCase).joined(separator: "\n")
        }
    }

    // MARK: - Helpers

    static func tabSeparated(_ table: [[String]]) -> String {
        table.map { $0.joined(separator: "\t") }.joined(separator: "\n")
    }

    static func markdownTable(_ table: [[String]]) -> String {
        guard let header = table.first else { return "" }
        let width = table.map(\.count).max() ?? header.count
        func row(_ cells: [String]) -> String {
            let padded = cells + Array(repeating: "", count: max(0, width - cells.count))
            return "| " + padded.map { $0.replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |"
        }
        let divider = "| " + Array(repeating: "---", count: width).joined(separator: " | ") + " |"
        return ([row(header), divider] + table.dropFirst().map(row)).joined(separator: "\n")
    }

    /// Bullets become "- ", and paragraphs get a blank line between them.
    static func markdownText(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let match = trimmed.wholeMatch(of: /^[•◦▪●‣–—*]\s+(.*)/) {
                return "- " + match.1
            }
            return line
        }.joined(separator: "\n")
    }

    /// Splits each line into columns at tabs or runs of two or more spaces.
    static func columns(_ text: String) -> [[String]] {
        text.components(separatedBy: "\n").map { line in
            line.split(separator: /\t|\s{2,}/).map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    static func csv(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { cell in
                if cell.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) {
                    return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                return cell
            }.joined(separator: ",")
        }.joined(separator: "\n")
    }

    /// A table becomes a list of objects when its first row looks like
    /// headings (filled and all different), or a list of rows when not.
    static func json(table: [[String]]) -> String {
        guard let header = table.first, table.count > 1 else { return jsonString(table) }
        let looksLikeHeader = !header.contains(where: \.isEmpty) && Set(header).count == header.count
        guard looksLikeHeader else { return jsonString(table) }
        let objects = table.dropFirst().map { row in
            Dictionary(uniqueKeysWithValues: header.enumerated().map { index, key in
                (key, index < row.count ? row[index] : "")
            })
        }
        return jsonString(objects)
    }

    static func jsonString(_ value: Any) -> String {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: options) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func snakeCase(_ line: String) -> String {
        // Split camelCase first, so "userName" becomes "user_name".
        let spaced = line.replacing(/([a-z0-9])([A-Z])/) { "\($0.1) \($0.2)" }
        return spaced.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "_")
    }
}
