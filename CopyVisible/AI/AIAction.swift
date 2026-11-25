import Foundation

/// The smart actions in the result panel.
enum AIAction: String, CaseIterable, Identifiable, Sendable {
    case explain
    case summarize
    case concise
    case fixText
    case translate
    case whatWentWrong
    case findBug
    case addComments
    case changeLanguage
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explain: "Explain"
        case .summarize: "Summarize"
        case .concise: "Make concise"
        case .fixText: "Fix text"
        case .translate: "Translate"
        case .whatWentWrong: "What went wrong?"
        case .findBug: "Find the bug"
        case .addComments: "Add comments"
        case .changeLanguage: "Change language"
        case .custom: "Custom…"
        }
    }

    var symbol: String {
        switch self {
        case .explain: "lightbulb"
        case .summarize: "text.badge.minus"
        case .concise: "scissors"
        case .fixText: "wand.and.stars"
        case .translate: "globe"
        case .whatWentWrong: "stethoscope"
        case .findBug: "ladybug"
        case .addComments: "text.bubble"
        case .changeLanguage: "arrow.left.arrow.right"
        case .custom: "pencil"
        }
    }

    /// True when the answer is new text to use in place of the old one.
    /// False when it is an answer about the text.
    var makesText: Bool {
        switch self {
        case .concise, .fixText, .translate, .addComments, .changeLanguage: true
        case .explain, .summarize, .whatWentWrong, .findBug, .custom: false
        }
    }

    /// The actions to show for a kind of capture, most useful first.
    static func actions(for kind: CaptureKind) -> [AIAction] {
        switch kind {
        case .code: [.explain, .findBug, .addComments, .changeLanguage, .fixText, .summarize, .custom]
        case .log: [.whatWentWrong, .explain, .summarize, .fixText, .custom]
        case .table: [.summarize, .explain, .translate, .custom]
        case .plain, .contact, .qr: [.summarize, .explain, .concise, .fixText, .translate, .custom]
        }
    }

    /// The request to the model. `option` is the language for Translate and
    /// Change language, and the user's words for Custom.
    func prompt(kind: CaptureKind, option: String?) -> String {
        let isCode = kind == .code
        switch self {
        case .explain:
            return isCode
                ? "Explain what this code does, in plain words. Start with one sentence that sums it up. Then give up to five short bullet points about the important parts. Do not repeat the code."
                : "Explain what this text means, in plain and simple words. Keep it short."
        case .summarize:
            return isCode
                ? "Sum up what this code does in two or three short sentences."
                : "Sum up this text in at most three short sentences. Keep the key facts, names and numbers."
        case .concise:
            return "Rewrite this text so it is shorter and clearer. Keep every important fact. Reply with only the new text."
        case .fixText:
            return isCode
                ? "This code was read from a picture of a screen, so it can have reading mistakes, like O for 0, l for 1, or missing symbols. Fix only those mistakes. Keep the indentation. Reply with only the code."
                : "This text was read from a picture of a screen, so it can have reading mistakes: wrong letters, words joined together, or words broken apart. Fix only those mistakes. Do not reword anything. Reply with only the fixed text."
        case .translate:
            return "Translate this text into \(option ?? "English"). Reply with only the translation."
        case .whatWentWrong:
            return "This is a log or an error message. Say in plain words what went wrong, the most likely cause, and the first thing to try to fix it. Keep it short."
        case .findBug:
            return "Check this code for real bugs. Only report a problem you are sure about, and never invent one. For each real bug, say what is wrong and how to fix it, in one or two short lines. Small reading mistakes from the picture do not count. If the code looks correct, reply only: I found no clear bugs."
        case .addComments:
            return "Add short, helpful comments to this code. Do not change the code itself. Reply with only the code."
        case .changeLanguage:
            return "Rewrite this code in \(option ?? "Python"). Keep the same behaviour. Reply with only the code."
        case .custom:
            return option ?? "Explain this."
        }
    }
}
