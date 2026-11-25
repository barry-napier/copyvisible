import AppIntents
import AppKit

/// Shortcuts app support: capture, read pictures, and run smart actions.

struct CaptureTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Text from Screen"
    static let description = IntentDescription("Lets you drag over part of the screen and returns the text in it.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let controller = AppDelegate.shared?.controller else { throw IntentError.notReady }
        let capture: Capture? = await withCheckedContinuation { continuation in
            controller.capture { continuation.resume(returning: $0) }
        }
        guard let capture else { throw IntentError.cancelled }
        return .result(value: capture.bestText(joinLines: Prefs.shared.joinLines))
    }
}

struct ReadImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Read Text in Picture"
    static let description = IntentDescription("Returns the text in a picture or PDF.")

    @Parameter(title: "Picture or PDF", supportedContentTypes: [.image, .pdf])
    var file: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let controller = AppDelegate.shared?.controller else { throw IntentError.notReady }
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + "-" + file.filename)
        try file.data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        switch FileReader.load(url) {
        case .text(let text):
            return .result(value: text)
        case .images(let images):
            let capture = await controller.read(images: images, name: file.filename, show: false)
            return .result(value: capture?.bestText(joinLines: Prefs.shared.joinLines) ?? "")
        case nil:
            throw IntentError.unreadable
        }
    }
}

struct LastCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Last Capture"
    static let description = IntentDescription("Returns the text of the latest capture.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        if let capture = AppDelegate.shared?.controller.lastCapture {
            return .result(value: capture.bestText(joinLines: Prefs.shared.joinLines))
        }
        return .result(value: HistoryStore.shared.latest?.text ?? "")
    }
}

struct SmartActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Smart Action"
    static let description = IntentDescription("Explains, sums up, shortens, fixes or translates text with Apple’s on-device model.")

    @Parameter(title: "Action")
    var action: SmartActionEntity

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "Language or instruction", description: "The language for Translate, or what to do for Custom.")
    var option: String?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$action) \(\.$text)") {
            \.$option
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let kind = Capture.make(text: text).kind
        let option = option ?? (action == .translate ? Prefs.shared.translateTo : nil)
        let answer = try await Assistant.answer(action.action, text: text, kind: kind, option: option)
        return .result(value: answer)
    }
}

enum SmartActionEntity: String, AppEnum {
    case explain, summarize, concise, fixText, translate, whatWentWrong, findBug, addComments, custom

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Smart Action"
    static let caseDisplayRepresentations: [SmartActionEntity: DisplayRepresentation] = [
        .explain: "Explain",
        .summarize: "Summarize",
        .concise: "Make concise",
        .fixText: "Fix text",
        .translate: "Translate",
        .whatWentWrong: "What went wrong?",
        .findBug: "Find the bug",
        .addComments: "Add comments",
        .custom: "Custom",
    ]

    var action: AIAction { AIAction(rawValue: rawValue) ?? .explain }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case notReady
    case cancelled
    case unreadable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady: "CopyVisible is still starting. Try again."
        case .cancelled: "The capture was cancelled."
        case .unreadable: "CopyVisible could not open that file."
        }
    }
}

struct CopyVisibleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureTextIntent(),
            phrases: ["Capture text with \(.applicationName)", "Copy text from the screen with \(.applicationName)"],
            shortTitle: "Capture Text", systemImageName: "text.viewfinder")
        AppShortcut(
            intent: LastCaptureIntent(),
            phrases: ["Get my last \(.applicationName) capture"],
            shortTitle: "Last Capture", systemImageName: "clock.arrow.circlepath")
    }
}
