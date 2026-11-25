import AppKit
import Observation

/// One message in an "Ask about it" conversation.
struct ChatLine: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
}

/// Everything the result panel shows and does for one capture.
@MainActor
@Observable
final class PanelModel {
    private(set) var capture: Capture?
    /// The text in the editor. The user can change it before copying.
    var text = ""
    private(set) var format: PasteFormat = .plain
    private(set) var joined = true
    /// Shows "Copied" for a moment.
    private(set) var copiedAt: Date?
    /// A short message, like "Added to Calendar".
    var status: String?

    // Smart actions
    private(set) var aiAction: AIAction?
    private(set) var aiOutput = ""
    private(set) var aiRunning = false
    private(set) var aiError: String?
    var customOpen = false
    var customInstruction = ""

    // Ask about it
    private(set) var chat: [ChatLine] = []
    var question = ""

    // Watching a box
    private(set) var watchLineCount: Int?

    var speaking = false

    @ObservationIgnored private var formatSource = ""
    @ObservationIgnored private var aiTask: Task<Void, Never>?
    @ObservationIgnored private var conversation: Assistant.Conversation?

    var aiUnavailable: String? { Assistant.unavailableMessage }

    func show(_ capture: Capture) {
        stopAI()
        self.capture = capture
        joined = Prefs.shared.joinLines
        text = capture.bestText(joinLines: joined)
        formatSource = text
        format = .plain
        copiedAt = Date()
        status = nil
        aiAction = nil
        aiOutput = ""
        aiError = nil
        customOpen = false
        customInstruction = ""
        chat = []
        question = ""
        conversation = nil
        watchLineCount = nil
        Assistant.warmUp()
    }

    /// Live text from a box being watched.
    func showWatch(_ capture: Capture, lines: Int) {
        if self.capture?.id != capture.id { show(capture) }
        self.capture = capture
        text = capture.layoutText
        formatSource = text
        watchLineCount = lines
    }

    func endWatch() { watchLineCount = nil }

    // MARK: - Copy and formats

    func copy() {
        Clipboard.copy(text)
        copiedAt = Date()
    }

    func setFormat(_ new: PasteFormat) {
        guard let capture else { return }
        if format == .plain { formatSource = text }
        format = new
        text = new.apply(to: formatSource, table: capture.table, kind: capture.kind)
        copy()
    }

    /// Switches between joined lines and lines as they were on screen.
    func toggleJoin() {
        guard let capture else { return }
        joined.toggle()
        text = capture.bestText(joinLines: joined)
        formatSource = text
        format = .plain
        copy()
    }

    var canJoin: Bool {
        guard let capture else { return false }
        return (capture.kind == .plain || capture.kind == .contact) && capture.layoutText != capture.joinedText
    }

    // MARK: - Smart actions

    func run(_ action: AIAction, option: String? = nil) {
        guard let capture else { return }
        stopAI()
        aiAction = action
        aiOutput = ""
        aiError = nil
        aiRunning = true
        customOpen = false
        let stream = Assistant.run(action, text: formatSource.isEmpty ? text : formatSource, kind: capture.kind, option: option)
        aiTask = Task {
            do {
                for try await partial in stream { self.aiOutput = partial }
            } catch is CancellationError {
            } catch {
                self.aiError = error.localizedDescription
            }
            self.aiRunning = false
        }
    }

    func runCustom() {
        let instruction = customInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        run(.custom, option: instruction)
    }

    func stopAI() {
        aiTask?.cancel()
        aiTask = nil
        aiRunning = false
    }

    func closeAnswer() {
        stopAI()
        aiAction = nil
        aiOutput = ""
        aiError = nil
    }

    func copyAnswer() {
        Clipboard.copy(aiOutput)
        status = "Answer copied."
    }

    /// Puts the answer in the editor in place of the captured text.
    func useAnswer() {
        text = aiOutput
        formatSource = aiOutput
        format = .plain
        copy()
        closeAnswer()
    }

    // MARK: - Ask about it

    func ask() {
        let request = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, let capture, !aiRunning else { return }
        question = ""
        if conversation == nil { conversation = Assistant.Conversation(text: capture.bestText(joinLines: true)) }
        chat.append(ChatLine(role: .user, text: request))
        chat.append(ChatLine(role: .assistant, text: ""))
        let index = chat.count - 1
        let stream = conversation!.send(request)
        aiRunning = true
        aiTask = Task {
            do {
                for try await partial in stream { self.chat[index].text = partial }
            } catch is CancellationError {
            } catch {
                self.chat[index].text = error.localizedDescription
            }
            self.aiRunning = false
        }
    }

    // MARK: - Other actions

    func speak() {
        Speaker.shared.onChange = { [weak self] in self?.speaking = Speaker.shared.isSpeaking }
        Speaker.shared.toggle(aiOutput.isEmpty ? text : aiOutput)
        speaking = Speaker.shared.isSpeaking
    }

    func addEvent(_ date: FoundDate) {
        Task { status = await Planner.addEvent(date, notes: text) }
    }

    func addReminder(_ date: FoundDate) {
        Task { status = await Planner.addReminder(date, notes: text) }
    }

    func addContact() {
        guard let capture else { return }
        do {
            try ContactMaker.open(capture.detected)
            status = "Opened in Contacts. Check it, then click Create."
        } catch {
            status = "Could not make the contact card: \(error.localizedDescription)"
        }
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
