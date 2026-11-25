import AppKit
import Sparkle
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static private(set) weak var shared: AppDelegate?

    let controller = CaptureController()
    private let hotKeys = HotKeys()
    private var statusItem: NSStatusItem!
    private var welcomeWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var logWindow: NSWindow?
    private var trustTimer: Timer?
    private var couldRecord = false
    #if DEBUG
    private var selfTest: SelfTest?
    #endif
    /// Shortcuts another app already uses.
    private(set) var takenShortcuts: [HotKeys.Action] = []

    /// Sparkle checks GitHub for new versions. Off in debug builds, which
    /// are not signed for release.
    let updater = SPUStandardUpdaterController(
        startingUpdater: AppDelegate.isReleaseBuild, updaterDelegate: nil, userDriverDelegate: nil)

    static var isReleaseBuild: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        Log.shared.add("CopyVisible \(version) launched from \(Bundle.main.bundlePath)")
        if Bundle.main.bundlePath != "/Applications/CopyVisible.app" {
            Log.shared.add("Warning: not running from /Applications. Use scripts/build.sh so permissions stick.")
        }

        #if DEBUG
        selfTest = SelfTest(controller: controller)
        #endif
        setUpStatusItem()
        hotKeys.onPress = { [weak self] action in self?.hotKey(action) }
        registerShortcuts()
        controller.onNeedsPermission = { [weak self] in self?.showWelcome(at: .permission) }

        couldRecord = Permissions.canRecordScreen
        Log.shared.add("Screen Recording: \(couldRecord ? "on" : "not on")")
        HistoryStore.shared.prune()
        if !Prefs.shared.welcomeDone {
            showWelcome(at: .hello)
        } else if !couldRecord {
            showWelcome(at: .permission)
        }
        // Notice the permission being granted while CopyVisible runs.
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { AppDelegate.shared?.checkPermission() }
        }
    }

    // MARK: - Shortcuts

    func registerShortcuts() {
        takenShortcuts = hotKeys.register(Prefs.shared.shortcuts)
        for action in takenShortcuts {
            Log.shared.add("Shortcut for \(action) is used by another app. Pick another in Settings.")
        }
    }

    /// Stops the shortcuts while the user records a new one.
    func pauseShortcuts() { hotKeys.unregisterAll() }

    private func hotKey(_ action: HotKeys.Action) {
        switch action {
        case .capture: controller.capture()
        case .again: controller.captureAgain()
        case .watch: controller.toggleWatch()
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "CopyVisible")
        // Drop a picture or PDF on the icon to read it.
        let drop = DropView(frame: button.bounds)
        drop.autoresizingMask = [.width, .height]
        drop.onDrop = { [weak self] urls in self?.controller.read(files: urls) }
        drop.onDropImage = { [weak self] image in
            Task { await self?.controller.read(images: [image], name: "Dropped picture") }
        }
        button.addSubview(drop)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let prefs = Prefs.shared
        if !Permissions.canRecordScreen {
            menu.addItem(item("Screen Recording Is Off. Turn On…", symbol: "exclamationmark.triangle") { [weak self] in
                self?.showWelcome(at: .permission)
            })
            menu.addItem(.separator())
        }
        menu.addItem(item("Capture Text", symbol: "text.viewfinder", shortcut: prefs.captureShortcut) { [weak self] in
            self?.controller.capture()
        })
        let again = item("Capture Same Box Again", symbol: "arrow.clockwise", shortcut: prefs.againShortcut) { [weak self] in
            self?.controller.captureAgain()
        }
        again.isEnabled = controller.lastBox != nil
        menu.addItem(again)
        menu.addItem(item(
            controller.isWatching ? "Stop Watching" : "Watch a Box",
            symbol: controller.isWatching ? "stop.circle" : "eye", shortcut: prefs.watchShortcut
        ) { [weak self] in self?.controller.toggleWatch() })
        menu.addItem(.separator())
        menu.addItem(item("Read Text from File…", symbol: "doc.text.magnifyingglass") { [weak self] in self?.openFile() })
        let clip = item("Read Picture on Clipboard", symbol: "doc.on.clipboard") { [weak self] in
            self?.controller.readClipboardImage()
        }
        clip.isEnabled = Clipboard.hasImage
        menu.addItem(clip)
        menu.addItem(item("Show Last Result", symbol: "rectangle.on.rectangle") { [weak self] in
            self?.controller.showLast()
        })
        menu.addItem(.separator())
        menu.addItem(item("History…", symbol: "clock.arrow.circlepath") { [weak self] in self?.showHistory() })
        let settings = item("Settings…", symbol: "gearshape") { [weak self] in self?.showSettings() }
        settings.keyEquivalent = ","
        menu.addItem(settings)
        let updates = item("Check for Updates…", symbol: "arrow.down.circle") { [weak self] in
            self?.updater.checkForUpdates(nil)
        }
        updates.isEnabled = Self.isReleaseBuild
        menu.addItem(updates)
        menu.addItem(item("Show Debug Log", symbol: "ladybug") { [weak self] in self?.showDebugLog() })
        #if DEBUG
        menu.addItem(item("Show Welcome Again", symbol: "hand.wave") { [weak self] in self?.showWelcome(at: .hello) })
        #endif
        menu.addItem(.separator())
        let quit = item("Quit CopyVisible", symbol: nil) { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func item(_ title: String, symbol: String?, shortcut: Shortcut? = nil, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, action: action)
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        if let shortcut {
            // Shown only: Carbon handles the real key press everywhere.
            item.keyEquivalent = shortcut.key.count == 1 ? shortcut.key.lowercased() : ""
            item.keyEquivalentModifierMask = shortcut.flags
        }
        return item
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = FileReader.types
        panel.allowsMultipleSelection = true
        panel.message = "Pick pictures or PDFs to read the text from."
        NSApp.activate()
        if panel.runModal() == .OK { controller.read(files: panel.urls) }
    }

    // MARK: - Windows

    func showWelcome(at step: WelcomeView.Step) {
        let view = WelcomeView(start: step) { [weak self] in
            Prefs.shared.welcomeDone = true
            self?.welcomeWindow?.close()
        }
        if welcomeWindow == nil {
            welcomeWindow = Windows.make(title: "Welcome to CopyVisible", size: NSSize(width: 520, height: 460), content: view)
        } else {
            welcomeWindow?.contentView = NSHostingView(rootView: view)
        }
        Windows.present(welcomeWindow!)
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = Windows.make(
                title: "CopyVisible Settings", size: NSSize(width: 520, height: 640),
                content: SettingsView(app: self))
        }
        Windows.present(settingsWindow!)
    }

    func showHistory() {
        if historyWindow == nil {
            historyWindow = Windows.make(
                title: "History", size: NSSize(width: 820, height: 560),
                content: HistoryView(store: HistoryStore.shared) { [weak self] item in self?.controller.show(item) })
        }
        Windows.present(historyWindow!)
    }

    func showDebugLog() {
        if logWindow == nil {
            logWindow = Windows.make(
                title: "CopyVisible Debug Log", size: NSSize(width: 720, height: 420),
                content: DebugLogView(log: Log.shared))
        }
        Windows.present(logWindow!)
    }

    // MARK: - Permission

    private func checkPermission() {
        let can = Permissions.canRecordScreen
        guard can != couldRecord else { return }
        couldRecord = can
        Log.shared.add("Screen Recording turned \(can ? "on" : "off")")
    }
}

/// A menu item that runs a closure.
private final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, action: @escaping () -> Void) {
        run = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { run() }
}

/// Sits on the menu bar icon and takes dropped pictures and PDFs. Clicks
/// pass through to the icon.
private final class DropView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onDropImage: ((CGImage) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .tiff, .png])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // Clicks go on to the icon underneath, which opens the menu.
    override func mouseDown(with event: NSEvent) { superview?.mouseDown(with: event) }
    override func rightMouseDown(with event: NSEvent) { superview?.rightMouseDown(with: event) }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        canRead(sender) ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let board = sender.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: FileReader.types.map(\.identifier),
        ]
        if let urls = board.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            onDrop?(urls)
            return true
        }
        if let image = NSImage(pasteboard: board),
           let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            onDropImage?(cg)
            return true
        }
        return false
    }

    private func canRead(_ sender: any NSDraggingInfo) -> Bool {
        let board = sender.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: FileReader.types.map(\.identifier),
        ]
        return board.canReadObject(forClasses: [NSURL.self], options: options)
            || board.canReadObject(forClasses: [NSImage.self], options: nil)
    }
}
