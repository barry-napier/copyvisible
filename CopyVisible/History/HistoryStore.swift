import Foundation
import Observation
import SQLite3

/// One saved capture.
struct HistoryItem: Identifiable, Sendable, Equatable {
    let id: UUID
    let date: Date
    let kind: CaptureKind
    let text: String
    let appName: String?
    let thumbnail: Data?
}

/// When a history search should look.
enum HistoryWhen: String, CaseIterable, Identifiable, Sendable {
    case any, today, week, month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "Any time"
        case .today: "Today"
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        }
    }

    var since: Date? {
        let calendar = Calendar.current
        switch self {
        case .any: return nil
        case .today: return calendar.startOfDay(for: Date())
        case .week: return calendar.date(byAdding: .day, value: -7, to: Date())
        case .month: return calendar.date(byAdding: .day, value: -30, to: Date())
        }
    }
}

/// Past captures in a SQLite file in
/// ~/Library/Application Support/CopyVisible. Nothing leaves this Mac.
/// Deleting really deletes: the file is vacuumed so old text is not left behind.
@MainActor
@Observable
final class HistoryStore {
    static let shared = HistoryStore()

    /// Goes up by one on every change, so open windows reload.
    private(set) var version = 0

    @ObservationIgnored private var db: OpaquePointer?
    @ObservationIgnored let folder: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "CopyVisible")

    private init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appending(path: "captures.sqlite").path
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            Log.shared.add("History: could not open the database")
            db = nil
            return
        }
        execute("""
            PRAGMA journal_mode = WAL;
            PRAGMA secure_delete = ON;
            CREATE TABLE IF NOT EXISTS captures (
                id TEXT PRIMARY KEY,
                date REAL NOT NULL,
                kind TEXT NOT NULL,
                text TEXT NOT NULL,
                app TEXT,
                thumb BLOB
            );
            CREATE INDEX IF NOT EXISTS captures_date ON captures(date);
            """)
    }

    func add(_ capture: Capture, text: String) {
        guard Prefs.shared.keepHistory, let db else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "INSERT OR REPLACE INTO captures (id, date, kind, text, app, thumb) VALUES (?, ?, ?, ?, ?, ?)"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        bind(statement, 1, capture.id.uuidString)
        sqlite3_bind_double(statement, 2, capture.date.timeIntervalSince1970)
        bind(statement, 3, capture.kind.rawValue)
        bind(statement, 4, text)
        bind(statement, 5, capture.appName)
        if let thumb = capture.thumbnail {
            _ = thumb.withUnsafeBytes { sqlite3_bind_blob(statement, 6, $0.baseAddress, Int32(thumb.count), SQLITE_TRANSIENT) }
        } else {
            sqlite3_bind_null(statement, 6)
        }
        sqlite3_step(statement)
        prune()
        version += 1
    }

    /// Updates the saved text, for example after a watch session grows.
    func update(id: UUID, text: String) {
        guard let db else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "UPDATE captures SET text = ? WHERE id = ?", -1, &statement, nil) == SQLITE_OK else { return }
        bind(statement, 1, text)
        bind(statement, 2, id.uuidString)
        sqlite3_step(statement)
        version += 1
    }

    /// Newest first. Matches the words in the text or the app's name.
    func search(_ query: String, when: HistoryWhen, limit: Int = 300) -> [HistoryItem] {
        guard let db else { return [] }
        var sql = "SELECT id, date, kind, text, app, thumb FROM captures WHERE 1 = 1"
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        for _ in words { sql += " AND (text LIKE ? ESCAPE '\\' OR app LIKE ? ESCAPE '\\')" }
        if when.since != nil { sql += " AND date >= ?" }
        sql += " ORDER BY date DESC LIMIT \(limit)"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        var index: Int32 = 1
        for word in words {
            let escaped = word.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
            bind(statement, index, "%\(escaped)%")
            bind(statement, index + 1, "%\(escaped)%")
            index += 2
        }
        if let since = when.since { sqlite3_bind_double(statement, index, since.timeIntervalSince1970) }

        var items: [HistoryItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(statement, 0) ?? "") else { continue }
            var thumb: Data?
            if let bytes = sqlite3_column_blob(statement, 5) {
                thumb = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 5)))
            }
            items.append(HistoryItem(
                id: id, date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                kind: CaptureKind(rawValue: string(statement, 2) ?? "") ?? .plain,
                text: string(statement, 3) ?? "", appName: string(statement, 4), thumbnail: thumb))
        }
        return items
    }

    var latest: HistoryItem? { search("", when: .any, limit: 1).first }

    func delete(_ id: UUID) {
        guard let db else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "DELETE FROM captures WHERE id = ?", -1, &statement, nil) == SQLITE_OK else { return }
        bind(statement, 1, id.uuidString)
        sqlite3_step(statement)
        version += 1
    }

    func deleteAll() {
        execute("DELETE FROM captures; VACUUM;")
        Log.shared.add("History deleted")
        version += 1
    }

    /// Removes captures older than the chosen length.
    func prune() {
        let days = Prefs.shared.historyLength.rawValue
        guard days > 0, let db else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "DELETE FROM captures WHERE date < ?", -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_double(statement, 1, Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970)
        sqlite3_step(statement)
        if sqlite3_changes(db) > 0 { version += 1 }
    }

    // MARK: - SQLite helpers

    private func execute(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func string(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
