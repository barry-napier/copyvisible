import Foundation
import NaturalLanguage

/// A date or time found in captured text.
struct FoundDate: Sendable, Equatable, Hashable {
    var date: Date
    /// Seconds. Zero when the text gave no length.
    var duration: TimeInterval
    /// The words the date was found in, like "Friday at 3pm".
    var phrase: String
    /// The whole line around it, used as the event's title.
    var line: String
}

/// Things in captured text that can become a button: links, emails,
/// phone numbers, dates, addresses and people's names.
struct Detected: Sendable, Equatable {
    var links: [URL] = []
    var emails: [String] = []
    var phones: [String] = []
    var dates: [FoundDate] = []
    var addresses: [String] = []
    var names: [String] = []
    var organizations: [String] = []

    var isEmpty: Bool {
        links.isEmpty && emails.isEmpty && phones.isEmpty && dates.isEmpty && addresses.isEmpty
    }

    /// - Parameter findDates: off for code and logs, where every timestamp
    ///   would look like a calendar event.
    static func scan(_ text: String, findDates: Bool, now: Date = Date()) -> Detected {
        var found = Detected()
        guard !text.isEmpty else { return found }
        var types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber, .address]
        if findDates { types.insert(.date) }
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return found }
        let ns = text as NSString

        for match in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let phrase = ns.substring(with: match.range)
            switch match.resultType {
            case .link:
                guard let url = match.url else { continue }
                if url.scheme == "mailto" {
                    let email = url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
                    if !found.emails.contains(email) { found.emails.append(email) }
                } else if !found.links.contains(url) {
                    found.links.append(url)
                }
            case .phoneNumber:
                if let number = match.phoneNumber, !found.phones.contains(number) {
                    found.phones.append(number)
                }
            case .address:
                let address = phrase.replacingOccurrences(of: "\n", with: ", ")
                if !found.addresses.contains(address) { found.addresses.append(address) }
            case .date:
                guard let date = match.date else { continue }
                // Skip dates far away: they are usually not plans.
                let years = abs(date.timeIntervalSince(now)) / (365 * 24 * 3600)
                guard years < 3 else { continue }
                let line = ns.substring(with: ns.lineRange(for: match.range))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let item = FoundDate(date: date, duration: match.duration, phrase: phrase, line: line)
                if !found.dates.contains(where: { $0.date == date }) { found.dates.append(item) }
            default:
                break
            }
        }

        // People and companies, for "Add to Contacts".
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            let value = String(text[range])
            if tag == .personalName, !found.names.contains(value) { found.names.append(value) }
            if tag == .organizationName, !found.organizations.contains(value) { found.organizations.append(value) }
            return true
        }
        return found
    }
}
