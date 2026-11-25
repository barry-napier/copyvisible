import Foundation

/// One capture: the text read from part of the screen (or a file), sorted
/// into a kind, with everything the panel can offer for it.
struct Capture: Identifiable, Sendable {
    let id: UUID
    let date: Date
    var kind: CaptureKind
    /// The lines as they looked, with indentation for code and logs.
    var layoutText: String
    /// The same text with lines that only wrapped joined back together.
    var joinedText: String
    /// The first table found, as rows of cells.
    var table: [[String]]?
    var barcodes: [String]
    var detected: Detected
    var appName: String?
    var bundleID: String?
    /// A small PNG of what was captured, for history.
    var thumbnail: Data?

    init(
        id: UUID = UUID(), date: Date = Date(), kind: CaptureKind, layoutText: String,
        joinedText: String, table: [[String]]? = nil, barcodes: [String] = [],
        detected: Detected = Detected(), appName: String? = nil, bundleID: String? = nil,
        thumbnail: Data? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.layoutText = layoutText
        self.joinedText = joinedText
        self.table = table
        self.barcodes = barcodes
        self.detected = detected
        self.appName = appName
        self.bundleID = bundleID
        self.thumbnail = thumbnail
    }

    /// Builds a capture from what the text reader found.
    static func make(from read: ReadResult, appName: String? = nil, bundleID: String? = nil) -> Capture {
        let plainLayout = TextLayout.arrange(read.lines, keepIndent: false)
        let quickDetect = Detected.scan(plainLayout, findDates: false)
        let kind = Classifier.kind(
            text: plainLayout, tableShare: read.tableShare, barcodes: read.barcodes, detected: quickDetect)
        let layout = kind.keepsLayout ? TextLayout.arrange(read.lines, keepIndent: true) : plainLayout
        let joined = kind.keepsLayout || kind == .table ? layout : TextLayout.joinBrokenLines(layout)
        let detected = Detected.scan(
            kind == .qr ? read.barcodes.joined(separator: "\n") + "\n" + layout : layout,
            findDates: kind == .plain || kind == .contact || kind == .qr)
        return Capture(
            kind: kind, layoutText: layout, joinedText: joined,
            table: kind == .table ? read.tables.first : nil,
            barcodes: read.barcodes, detected: detected, appName: appName, bundleID: bundleID)
    }

    /// Builds a capture from text that already exists, like a PDF's own text.
    static func make(text: String, appName: String? = nil) -> Capture {
        let detected = Detected.scan(text, findDates: false)
        let kind = Classifier.kind(text: text, tableShare: 0, barcodes: [], detected: detected)
        return Capture(
            kind: kind, layoutText: text,
            joinedText: kind.keepsLayout ? text : TextLayout.joinBrokenLines(text),
            detected: Detected.scan(text, findDates: !kind.keepsLayout), appName: appName)
    }

    /// The text that goes to the clipboard first.
    func bestText(joinLines: Bool) -> String {
        switch kind {
        case .qr:
            return barcodes.isEmpty ? layoutText : barcodes.joined(separator: "\n")
        case .table:
            // Tabs paste as cells in Numbers, Excel and Google Sheets.
            return table.map(PasteFormat.tabSeparated) ?? layoutText
        case .code, .log:
            return layoutText
        case .plain, .contact:
            return joinLines ? joinedText : layoutText
        }
    }

    var isEmpty: Bool {
        layoutText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && barcodes.isEmpty
    }
}
