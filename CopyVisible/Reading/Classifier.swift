import Foundation

/// What a capture looks like. Each kind gets its own help in the panel.
enum CaptureKind: String, Codable, CaseIterable, Sendable {
    case plain
    case code
    case log
    case table
    case contact
    case qr

    var title: String {
        switch self {
        case .plain: "Text"
        case .code: "Code"
        case .log: "Log or error"
        case .table: "Table"
        case .contact: "Contact"
        case .qr: "QR code"
        }
    }

    var symbol: String {
        switch self {
        case .plain: "text.alignleft"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .log: "exclamationmark.triangle"
        case .table: "tablecells"
        case .contact: "person.crop.circle"
        case .qr: "qrcode"
        }
    }

    /// Code and logs keep their exact lines and spacing.
    var keepsLayout: Bool { self == .code || self == .log }
}

/// Decides the kind of a capture from its text.
enum Classifier {
    static func kind(
        text: String, tableShare: Double, barcodes: [String], detected: Detected
    ) -> CaptureKind {
        let words = text.split(whereSeparator: \.isWhitespace)
        if !barcodes.isEmpty, words.count <= 12 { return .qr }
        if tableShare >= 0.6 { return .table }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard !lines.isEmpty else { return barcodes.isEmpty ? .plain : .qr }

        if logScore(lines) >= 0.35 { return .log }
        if codeScore(lines) >= 0.3 { return .code }

        let hasContactDetails = !detected.emails.isEmpty || !detected.phones.isEmpty
        if hasContactDetails, lines.count <= 10, text.count <= 400,
           !detected.names.isEmpty || !detected.organizations.isEmpty || !detected.addresses.isEmpty
            || detected.emails.count + detected.phones.count >= 2 {
            return .contact
        }
        return .plain
    }

    /// Share of lines that look like log output or an error.
    static func logScore(_ lines: [String]) -> Double {
        let patterns: [Regex<Substring>] = [
            /\d{1,2}:\d{2}:\d{2}/,
            /\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}/,
            /\b(?:ERROR|WARN|WARNING|INFO|DEBUG|TRACE|FATAL|CRITICAL)\b/,
            /\b[A-Z][A-Za-z]*(?:Error|Exception)\b/,
            /^\s*at [\w.$<>]+\(/,
            /Traceback \(most recent call last\)/,
            /^\s*File ".*", line \d+/,
            /\b(?:panic|Segmentation fault|exit code|errno|failed|undefined is not)\b/,
        ]
        let hits = lines.filter { line in patterns.contains { line.firstMatch(of: $0) != nil } }.count
        return Double(hits) / Double(lines.count)
    }

    /// How much the lines look like source code, from 0 to 1.
    static func codeScore(_ lines: [String]) -> Double {
        let keywords: Set<String> = [
            "func", "let", "var", "const", "def", "class", "struct", "enum", "import", "return",
            "public", "private", "static", "function", "fn", "impl", "async", "await", "elif",
            "else", "for", "while", "if", "switch", "case", "guard", "self", "this", "nil", "null",
            "None", "true", "false", "package", "interface", "extends", "#include", "lambda", "try",
            "catch", "throw", "throws", "new", "void", "int", "string", "echo", "SELECT", "FROM", "WHERE",
        ]
        var score = 0.0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            var lineScore = 0.0
            if trimmed.hasSuffix(";") || trimmed.hasSuffix("{") || trimmed.hasSuffix("}")
                || trimmed.hasSuffix(":") && line.hasPrefix(" ") || trimmed == "}" || trimmed.hasSuffix(")") {
                lineScore += 0.5
            }
            let tokens = trimmed.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "#" && $0 != "_" })
            if let first = tokens.first, keywords.contains(String(first)) { lineScore += 0.5 }
            if trimmed.contains("=>") || trimmed.contains("->") || trimmed.contains("==")
                || trimmed.contains("()") || trimmed.contains("//") || trimmed.hasPrefix("#")
                || trimmed.contains(" = ") || trimmed.contains("::") || trimmed.contains("$(") {
                lineScore += 0.4
            }
            let symbols = trimmed.filter { "{}()[];=<>_.$".contains($0) }.count
            if trimmed.count > 0, Double(symbols) / Double(trimmed.count) > 0.08 { lineScore += 0.3 }
            if tokens.contains(where: { $0.contains("_") || isCamelCase($0) }) { lineScore += 0.2 }
            score += min(1, lineScore)
        }
        // Prose ends sentences with full stops; code rarely does.
        let sentences = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasSuffix(".") }.count
        score -= Double(sentences) * 0.4
        return max(0, score / Double(lines.count))
    }

    private static func isCamelCase(_ word: Substring) -> Bool {
        guard word.count > 3, word.first?.isLowercase == true else { return false }
        return word.dropFirst().contains(where: \.isUppercase)
    }
}
