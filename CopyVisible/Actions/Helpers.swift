import AppKit
import AVFoundation
import Contacts
import EventKit
import PDFKit
import UniformTypeIdentifiers

/// Puts text on the clipboard.
@MainActor
enum Clipboard {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// An image on the clipboard, like one from ⌃⇧⌘4.
    static var image: CGImage? {
        guard let image = NSImage(pasteboard: NSPasteboard.general) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    static var hasImage: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
    }
}

/// Reads text aloud with the system voice.
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()
    var onChange: (() -> Void)?

    private override init() {
        super.init()
        synth.delegate = self
    }

    var isSpeaking: Bool { synth.isSpeaking }

    func toggle(_ text: String) {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        } else {
            synth.speak(AVSpeechUtterance(string: text))
        }
        onChange?()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onChange?() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onChange?() }
    }
}

/// Adds events to Calendar and reminders to Reminders.
@MainActor
enum Planner {
    private static let store = EKEventStore()

    /// Adds an event. Returns a message for the user.
    static func addEvent(_ found: FoundDate, notes: String) async -> String {
        do {
            guard try await store.requestWriteOnlyAccessToEvents() else {
                return "CopyVisible may not add events. Allow it in System Settings > Privacy & Security > Calendars."
            }
            let event = EKEvent(eventStore: store)
            event.title = title(from: found)
            event.startDate = found.date
            event.endDate = found.date.addingTimeInterval(found.duration > 0 ? found.duration : 3600)
            event.notes = String(notes.prefix(2000))
            event.calendar = store.defaultCalendarForNewEvents
            try store.save(event, span: .thisEvent)
            return "Added “\(event.title ?? "")” to Calendar."
        } catch {
            return "Could not add the event: \(error.localizedDescription)"
        }
    }

    /// Adds a reminder. Returns a message for the user.
    static func addReminder(_ found: FoundDate, notes: String) async -> String {
        do {
            guard try await store.requestFullAccessToReminders() else {
                return "CopyVisible may not add reminders. Allow it in System Settings > Privacy & Security > Reminders."
            }
            let reminder = EKReminder(eventStore: store)
            reminder.title = title(from: found)
            reminder.notes = String(notes.prefix(2000))
            reminder.calendar = store.defaultCalendarForNewReminders()
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: found.date)
            reminder.addAlarm(EKAlarm(absoluteDate: found.date))
            try store.save(reminder, commit: true)
            return "Added “\(reminder.title ?? "")” to Reminders."
        } catch {
            return "Could not add the reminder: \(error.localizedDescription)"
        }
    }

    /// The line the date was in, without the date words, as a title.
    private static func title(from found: FoundDate) -> String {
        var title = found.line.replacingOccurrences(of: found.phrase, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        title = title.replacing(/\s{2,}/, with: " ")
        if title.count < 3 { title = found.line }
        return String(title.prefix(80))
    }
}

/// Makes a contact card and opens it in Contacts, which asks before adding.
/// This needs no permission, because CopyVisible never reads Contacts.
@MainActor
enum ContactMaker {
    static func open(_ detected: Detected) throws {
        let contact = CNMutableContact()
        if let name = detected.names.first {
            let parts = name.split(separator: " ")
            contact.givenName = parts.first.map(String.init) ?? name
            contact.familyName = parts.dropFirst().joined(separator: " ")
        }
        if let organization = detected.organizations.first { contact.organizationName = organization }
        contact.emailAddresses = detected.emails.map { CNLabeledValue(label: CNLabelWork, value: $0 as NSString) }
        contact.phoneNumbers = detected.phones.map {
            CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: $0))
        }
        contact.urlAddresses = detected.links.prefix(2).map {
            CNLabeledValue(label: CNLabelURLAddressHomePage, value: $0.absoluteString as NSString)
        }
        if let address = detected.addresses.first {
            let postal = CNMutablePostalAddress()
            postal.street = address
            contact.postalAddresses = [CNLabeledValue(label: CNLabelWork, value: postal)]
        }
        let data = try CNContactVCardSerialization.data(with: [contact])
        let name = (detected.names.first ?? "Contact").replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).vcf")
        try data.write(to: url)
        NSWorkspace.shared.open(url)
    }
}

/// Gets text out of image and PDF files.
enum FileReader {
    static let types: [UTType] = [.image, .pdf]

    enum Contents {
        case images([CGImage])
        /// A PDF that already has real text in it.
        case text(String)
    }

    static func load(_ url: URL) -> Contents? {
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
            guard let pdf = PDFDocument(url: url) else { return nil }
            if let text = pdf.string, text.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 {
                return .text(text)
            }
            // A scanned PDF: draw up to 20 pages and read the pictures.
            var images: [CGImage] = []
            for index in 0..<min(pdf.pageCount, 20) {
                guard let page = pdf.page(at: index) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let size = CGSize(width: bounds.width * 2, height: bounds.height * 2)
                let thumb = page.thumbnail(of: size, for: .mediaBox)
                if let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) { images.append(cg) }
            }
            return .images(images)
        }
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return .images([cg])
    }
}
