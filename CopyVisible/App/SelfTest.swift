#if DEBUG
import AppKit

/// Debug builds only. scripts/selftest.sh starts it. It draws sample
/// pictures (code, a log, a table, a contact), reads them, checks the kind,
/// runs smart actions on the code, and writes SELFTEST lines to the log.
/// It needs no Screen Recording, because it reads pictures it drew itself.
@MainActor
final class SelfTest {
    private let controller: CaptureController
    private var failures: [String] = []

    init(controller: CaptureController) {
        self.controller = controller
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.barrynapier.copyvisible.selftest"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.start() }
        }
    }

    private func start() {
        Task { await run() }
    }

    private func check(_ ok: Bool, _ name: String) {
        Log.shared.add("SELFTEST \(ok ? "ok  " : "FAIL") \(name)")
        if !ok { failures.append(name) }
    }

    private func run() async {
        failures = []
        Log.shared.add("SELFTEST start")
        let samples: [(String, [String], NSFont, CaptureKind)] = [
            ("code", ["func total(_ items: [Item]) -> Double {", "    items.reduce(0) { $0 + $1.price }", "}"],
             .monospacedSystemFont(ofSize: 22, weight: .regular), .code),
            ("log", ["2026-11-25 10:02:11 INFO Server started on port 8080",
                     "2026-11-25 10:02:15 ERROR Connection refused: db.local:5432",
                     "2026-11-25 10:02:16 WARN Retrying in 5s"],
             .monospacedSystemFont(ofSize: 18, weight: .regular), .log),
            ("contact", ["Jane Appleseed", "Head of Design, Acme", "jane@example.com", "+1 (415) 555-0132"],
             .systemFont(ofSize: 22), .contact),
            ("prose", ["Reading text from the screen should feel like magic,",
                       "and the lines that only wrapped should come back as",
                       "one sentence when you paste them. Lunch is on Friday at 1pm."],
             .systemFont(ofSize: 22), .plain),
        ]
        var codeCapture: Capture?
        for (name, lines, font, expected) in samples {
            let image = Self.draw(lines, font: font)
            guard let capture = await controller.read(images: [image], name: "Self-test \(name)") else {
                check(false, "\(name): read")
                continue
            }
            check(capture.kind == expected, "\(name): kind is \(capture.kind.rawValue), expected \(expected.rawValue)")
            let copied = NSPasteboard.general.string(forType: .string) ?? ""
            check(copied == capture.bestText(joinLines: Prefs.shared.joinLines), "\(name): text is on the clipboard")
            if name == "code" { codeCapture = capture }
            if name == "prose" {
                check(!capture.joinedText.contains("\n"), "prose: broken lines joined")
                check(!capture.detected.dates.isEmpty, "prose: found the date")
            }
            if name == "contact" {
                check(capture.detected.emails == ["jane@example.com"], "contact: found the email")
            }
            try? await Task.sleep(for: .milliseconds(400))
        }

        if let codeCapture {
            check(controller.panel.isVisible || Prefs.shared.panelStyle == .none, "panel is showing")
            if let message = Assistant.unavailableMessage {
                Log.shared.add("SELFTEST skip smart actions: \(message)")
            } else {
                for action in [AIAction.explain, .findBug, .changeLanguage] {
                    let start = Date()
                    do {
                        let answer = try await Assistant.answer(
                            action, text: codeCapture.layoutText, kind: .code, option: "Python")
                        let seconds = String(format: "%.1f", Date().timeIntervalSince(start))
                        check(!answer.isEmpty, "smart action \(action.rawValue) answered in \(seconds)s")
                        Log.shared.add("SELFTEST answer \(action.rawValue): \(answer.prefix(300).replacingOccurrences(of: "\n", with: " ⏎ "))")
                    } catch {
                        check(false, "smart action \(action.rawValue): \(error.localizedDescription)")
                    }
                }
                // Show a live answer in the panel, for a screenshot.
                controller.panel.model.show(codeCapture)
                controller.panel.model.run(.explain)
                try? await Task.sleep(for: .seconds(4))
            }
        }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            try? await Task.sleep(for: .milliseconds(500))
            Self.snapshotWindows(suffix: appearance == .aqua ? "light" : "dark")
        }
        NSApp.appearance = nil
        Log.shared.add(failures.isEmpty ? "SELFTEST PASS" : "SELFTEST FAIL \(failures.count) check(s)")
    }

    /// Saves a PNG of each visible CopyVisible window to
    /// ~/Library/Logs/CopyVisible/shots, for checking the layout.
    static func snapshotWindows(suffix: String) {
        let folder = Log.shared.fileURL.deletingLastPathComponent().appending(path: "shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, window) in NSApp.windows.enumerated() where window.isVisible {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = window.title.isEmpty ? "window-\(index)" : window.title.replacingOccurrences(of: " ", with: "-")
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appending(path: "\(name)-\(suffix).png"))
            Log.shared.add("SELFTEST shot \(name)-\(suffix).png")
        }
    }

    static func draw(_ lines: [String], font: NSFont) -> CGImage {
        let size = CGSize(width: 900, height: CGFloat(lines.count) * font.pointSize * 1.6 + 60)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        for (index, line) in lines.enumerated() {
            let y = size.height - 30 - font.pointSize * 1.2 - CGFloat(index) * font.pointSize * 1.6
            (line as NSString).draw(at: NSPoint(x: 24, y: y), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
}
#endif
