import AppKit

/// Runs every way of getting text: drag a box, the same box again, watching
/// a box, and reading files. Then copies the text, saves it to history and
/// shows the result.
@MainActor
final class CaptureController {
    let panel = ResultPanel()
    private let overlay = SelectionOverlay()
    private let watchFrame = WatchFrame()
    private(set) var lastBox: ScreenBox?
    private(set) var isWatching = false
    private var watchTask: Task<Void, Never>?

    /// Called when a capture needs Screen Recording and does not have it.
    var onNeedsPermission: (() -> Void)?

    /// The latest capture, for "Show Last Result" and Shortcuts.
    private(set) var lastCapture: Capture?

    // MARK: - Capture a box

    /// Shows the overlay. `completion` gets the capture, or nil if cancelled.
    func capture(completion: ((Capture?) -> Void)? = nil) {
        guard !overlay.isShowing else { return }
        if isWatching { stopWatching() }
        guard Permissions.canRecordScreen else {
            completion?(nil)
            onNeedsPermission?()
            return
        }
        let app = NSWorkspace.shared.frontmostApplication
        overlay.begin(.capture) { [weak self] box in
            guard let self, let box else {
                completion?(nil)
                return
            }
            self.lastBox = box
            Task {
                let capture = await self.read(box, app: app)
                completion?(capture)
            }
        }
    }

    /// Captures the last box again, without the overlay.
    func captureAgain() {
        guard let lastBox else { return capture() }
        guard Permissions.canRecordScreen else { return onNeedsPermission?() ?? () }
        let app = NSWorkspace.shared.frontmostApplication
        Task { await read(lastBox, app: app) }
    }

    @discardableResult
    private func read(_ box: ScreenBox, app: NSRunningApplication?) async -> Capture? {
        // Let the overlay leave the screen first.
        try? await Task.sleep(for: .milliseconds(60))
        do {
            let image = try await ScreenGrabber.grab(box)
            let result = try await TextReader.read(image)
            var capture = Capture.make(from: result, appName: app?.localizedName, bundleID: app?.bundleIdentifier)
            capture.thumbnail = ScreenGrabber.thumbnail(image)
            deliver(capture, near: box.appKitFrame)
            return capture
        } catch {
            Log.shared.add("Capture failed: \(error.localizedDescription)")
            if !Permissions.canRecordScreen {
                onNeedsPermission?()
            } else {
                Toast.show("Could not capture: \(error.localizedDescription)", near: box.appKitFrame)
            }
            return nil
        }
    }

    // MARK: - Files and the clipboard

    func read(files: [URL]) {
        Task {
            for url in files.prefix(10) {
                guard let contents = FileReader.load(url) else {
                    Toast.show("Could not open \(url.lastPathComponent)", near: nil)
                    continue
                }
                switch contents {
                case .text(let text):
                    deliver(Capture.make(text: text, appName: url.lastPathComponent), near: nil)
                case .images(let images):
                    await read(images: images, name: url.lastPathComponent)
                }
            }
        }
    }

    func readClipboardImage() {
        guard let image = Clipboard.image else {
            return Toast.show("There is no picture on the clipboard", near: nil)
        }
        Task { await read(images: [image], name: "Clipboard") }
    }

    /// Reads one or more pictures, like the pages of a scanned PDF.
    @discardableResult
    func read(images: [CGImage], name: String?, show: Bool = true) async -> Capture? {
        do {
            var captures: [Capture] = []
            for image in images {
                var capture = Capture.make(from: try await TextReader.read(image), appName: name)
                capture.thumbnail = ScreenGrabber.thumbnail(image)
                captures.append(capture)
            }
            guard var capture = captures.first else { return nil }
            if captures.count > 1 {
                let text = captures.map { $0.bestText(joinLines: Prefs.shared.joinLines) }.joined(separator: "\n\n")
                capture = Capture.make(text: text, appName: name)
                capture.thumbnail = captures.first?.thumbnail
            }
            if show { deliver(capture, near: nil) }
            return capture
        } catch {
            Log.shared.add("Reading a picture failed: \(error.localizedDescription)")
            if show { Toast.show("Could not read the picture", near: nil) }
            return nil
        }
    }

    // MARK: - Deliver

    private func deliver(_ capture: Capture, near box: CGRect?) {
        guard !capture.isEmpty else {
            Toast.show("No text found there", near: box)
            Log.shared.add("Capture had no text")
            return
        }
        lastCapture = capture
        let text = capture.bestText(joinLines: Prefs.shared.joinLines)
        Clipboard.copy(text)
        if Prefs.shared.playSound { NSSound(named: "Pop")?.play() }
        HistoryStore.shared.add(capture, text: text)
        Log.shared.add("Captured \(capture.kind.title.lowercased()): \(text.count) characters")

        if Prefs.shared.panelStyle == .none {
            let words = text.split(whereSeparator: \.isWhitespace).count
            Toast.show("Copied \(words) word\(words == 1 ? "" : "s")", near: box)
        } else {
            panel.model.show(capture)
            panel.show(near: box, style: Prefs.shared.panelStyle)
        }
    }

    /// Opens the panel for a capture from history.
    func show(_ item: HistoryItem) {
        let capture = Capture.make(text: item.text, appName: item.appName)
        lastCapture = capture
        panel.model.show(capture)
        panel.show(near: nil, style: Prefs.shared.panelStyle == .none ? .floating : Prefs.shared.panelStyle)
    }

    func showLast() {
        guard let lastCapture else {
            if let item = HistoryStore.shared.latest { show(item) }
            return
        }
        panel.model.show(lastCapture)
        panel.show(near: nil, style: Prefs.shared.panelStyle == .none ? .floating : Prefs.shared.panelStyle)
    }

    // MARK: - Watch a box

    func toggleWatch() {
        if isWatching { return stopWatching() }
        guard !overlay.isShowing else { return }
        guard Permissions.canRecordScreen else { return onNeedsPermission?() ?? () }
        let app = NSWorkspace.shared.frontmostApplication
        overlay.begin(.watch) { [weak self] box in
            guard let self, let box else { return }
            self.startWatching(box, app: app)
        }
    }

    private func startWatching(_ box: ScreenBox, app: NSRunningApplication?) {
        isWatching = true
        lastBox = box
        let frame = box.appKitFrame
        if let frame { watchFrame.show(around: frame) { [weak self] in self?.stopWatching() } }
        Log.shared.add("Watching a box")

        var lines: [String] = []
        var capture = Capture(kind: .plain, layoutText: "", joinedText: "", appName: app?.localizedName, bundleID: app?.bundleIdentifier)
        var saved = false
        watchTask = Task {
            while !Task.isCancelled {
                if let image = try? await ScreenGrabber.grab(box),
                   let result = try? await TextReader.read(image, quick: true) {
                    let text = TextLayout.joinBrokenLines(TextLayout.arrange(result.lines, keepIndent: false))
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespaces)
                    if Self.addWatchLine(text, to: &lines) {
                        let all = lines.joined(separator: "\n")
                        Clipboard.copy(all)
                        capture.layoutText = all
                        capture.joinedText = all
                        capture.detected = Detected.scan(all, findDates: true)
                        if capture.thumbnail == nil { capture.thumbnail = ScreenGrabber.thumbnail(image) }
                        lastCapture = capture
                        watchFrame.update(lines: lines.count)
                        if saved {
                            HistoryStore.shared.update(id: capture.id, text: all)
                        } else {
                            HistoryStore.shared.add(capture, text: all)
                            saved = true
                        }
                        if Prefs.shared.panelStyle != .none {
                            panel.model.showWatch(capture, lines: lines.count)
                            if !panel.isVisible { panel.show(near: frame, style: Prefs.shared.panelStyle) }
                        }
                    }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopWatching() {
        guard isWatching else { return }
        isWatching = false
        watchTask?.cancel()
        watchTask = nil
        watchFrame.hide()
        panel.model.endWatch()
        Log.shared.add("Stopped watching")
    }

    /// Adds new text from a watched box. Skips repeats, and replaces the
    /// last line when the new one only grew from it (subtitles that appear
    /// word by word). Returns true when something changed.
    static func addWatchLine(_ text: String, to lines: inout [String]) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else { return false }
        func key(_ value: String) -> String {
            value.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let newKey = key(clean)
        guard !newKey.isEmpty else { return false }
        if let last = lines.last {
            let lastKey = key(last)
            if newKey == lastKey || lastKey.hasSuffix(newKey) { return false }
            if newKey.hasPrefix(lastKey) {
                lines[lines.count - 1] = clean
                return true
            }
        }
        // Text that comes back after something else, like a fixed caption.
        if lines.suffix(3).contains(where: { key($0) == newKey }) { return false }
        lines.append(clean)
        return true
    }
}
