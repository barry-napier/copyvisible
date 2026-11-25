import Foundation
import Observation

/// How the result shows after a capture.
enum PanelStyle: String, CaseIterable, Identifiable, Sendable {
    /// A small window next to what you captured.
    case floating
    /// A tall bar on the right edge of the screen.
    case sideBar
    /// No window. The text only goes to the clipboard.
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .floating: "Window next to the capture"
        case .sideBar: "Bar at the screen edge"
        case .none: "Nothing, just copy"
        }
    }
}

/// How long history keeps captures.
enum HistoryLength: Int, CaseIterable, Identifiable, Sendable {
    case month = 30
    case year = 365
    case forever = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .month: "30 days"
        case .year: "1 year"
        case .forever: "Forever"
        }
    }
}

/// The user's settings, saved in UserDefaults.
@MainActor
@Observable
final class Prefs {
    static let shared = Prefs()

    @ObservationIgnored private let defaults = UserDefaults.standard

    var captureShortcut: Shortcut { didSet { save(captureShortcut, "shortcut.capture") } }
    var againShortcut: Shortcut { didSet { save(againShortcut, "shortcut.again") } }
    var watchShortcut: Shortcut { didSet { save(watchShortcut, "shortcut.watch") } }

    var panelStyle: PanelStyle { didSet { defaults.set(panelStyle.rawValue, forKey: "panelStyle") } }
    var playSound: Bool { didSet { defaults.set(playSound, forKey: "playSound") } }
    var joinLines: Bool { didSet { defaults.set(joinLines, forKey: "joinLines") } }
    var translateTo: String { didSet { defaults.set(translateTo, forKey: "translateTo") } }
    var codeLanguage: String { didSet { defaults.set(codeLanguage, forKey: "codeLanguage") } }
    var keepHistory: Bool { didSet { defaults.set(keepHistory, forKey: "keepHistory") } }
    var historyLength: HistoryLength { didSet { defaults.set(historyLength.rawValue, forKey: "historyLength") } }
    var welcomeDone: Bool { didSet { defaults.set(welcomeDone, forKey: "welcomeDone") } }

    static let languages = [
        "English", "Spanish", "French", "German", "Italian", "Portuguese", "Dutch", "Swedish",
        "Danish", "Norwegian", "Polish", "Turkish", "Vietnamese", "Japanese", "Korean", "Chinese",
    ]
    static let codeLanguages = [
        "Python", "JavaScript", "TypeScript", "Swift", "Kotlin", "Java", "Go", "Rust", "C#", "C++",
        "Ruby", "PHP", "Bash", "SQL",
    ]

    private init() {
        captureShortcut = Self.load("shortcut.capture") ?? .capture
        againShortcut = Self.load("shortcut.again") ?? .again
        watchShortcut = Self.load("shortcut.watch") ?? .watch
        panelStyle = PanelStyle(rawValue: defaults.string(forKey: "panelStyle") ?? "") ?? .floating
        playSound = defaults.object(forKey: "playSound") as? Bool ?? true
        joinLines = defaults.object(forKey: "joinLines") as? Bool ?? true
        let preferred = Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en")
        translateTo = defaults.string(forKey: "translateTo") ?? (Self.languages.contains(preferred ?? "") ? preferred! : "English")
        codeLanguage = defaults.string(forKey: "codeLanguage") ?? "Python"
        keepHistory = defaults.object(forKey: "keepHistory") as? Bool ?? true
        historyLength = HistoryLength(rawValue: defaults.integer(forKey: "historyLength")) ?? .month
        if defaults.object(forKey: "historyLength") == nil { historyLength = .month }
        welcomeDone = defaults.bool(forKey: "welcomeDone")
    }

    var shortcuts: [HotKeys.Action: Shortcut] {
        [.capture: captureShortcut, .again: againShortcut, .watch: watchShortcut]
    }

    private func save(_ shortcut: Shortcut, _ key: String) {
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: key)
    }

    private static func load(_ key: String) -> Shortcut? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }
}
