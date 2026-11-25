import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let app: AppDelegate
    @Bindable private var prefs = Prefs.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var confirmDelete = false
    @State private var canRecord = Permissions.canRecordScreen
    @State private var taken: [HotKeys.Action] = []
    @State private var autoUpdate = true

    var body: some View {
        Form {
            Section("Shortcuts") {
                shortcutRow("Capture text", \.captureShortcut, action: .capture)
                shortcutRow("Capture same box again", \.againShortcut, action: .again)
                shortcutRow("Watch a box", \.watchShortcut, action: .watch)
                Text("Tip: click a window instead of dragging to take all of it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("After a capture") {
                Picker("Show", selection: $prefs.panelStyle) {
                    ForEach(PanelStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Join broken lines", isOn: $prefs.joinLines)
                Text("Puts sentences that wrapped across lines back on one line. Code, logs and tables always keep their lines.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Play a sound", isOn: $prefs.playSound)
            }

            Section("Smart actions") {
                Picker("Translate to", selection: $prefs.translateTo) {
                    ForEach(Prefs.languages, id: \.self) { Text($0).tag($0) }
                }
                Picker("Change code to", selection: $prefs.codeLanguage) {
                    ForEach(Prefs.codeLanguages, id: \.self) { Text($0).tag($0) }
                }
                if let message = Assistant.unavailableMessage {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else {
                    Label("Apple Intelligence is ready. It runs on this Mac.", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }

            Section("History") {
                Toggle("Keep a history of captures", isOn: $prefs.keepHistory)
                Picker("Keep for", selection: $prefs.historyLength) {
                    ForEach(HistoryLength.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!prefs.keepHistory)
                .onChange(of: prefs.historyLength) { HistoryStore.shared.prune() }
                HStack {
                    Button("Show History…") { app.showHistory() }
                    Button("Delete All History…", role: .destructive) { confirmDelete = true }
                }
            }

            Section("General") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                Toggle("Check for updates by itself", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { app.updater.updater.automaticallyChecksForUpdates = autoUpdate }
                    .disabled(!AppDelegate.isReleaseBuild)
                HStack {
                    if canRecord {
                        Label("Screen Recording is on", systemImage: "checkmark.circle").foregroundStyle(.green)
                    } else {
                        Label("Screen Recording is off", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Spacer()
                        Button("Turn On…") { app.showWelcome(at: .permission) }
                    }
                }
            }

            Section("Privacy") {
                Text("CopyVisible reads text on this Mac with Apple's own tools. It has no account and no tracking. It goes online only to check for updates.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Show Data Folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([HistoryStore.shared.folder])
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 560)
        .onAppear {
            canRecord = Permissions.canRecordScreen
            taken = app.takenShortcuts
            autoUpdate = app.updater.updater.automaticallyChecksForUpdates
        }
        .confirmationDialog("Delete all history?", isPresented: $confirmDelete) {
            Button("Delete All", role: .destructive) { HistoryStore.shared.deleteAll() }
        } message: {
            Text("This removes every saved capture from this Mac. You cannot undo it.")
        }
    }

    private func shortcutRow(_ title: String, _ key: ReferenceWritableKeyPath<Prefs, Shortcut>, action: HotKeys.Action) -> some View {
        LabeledContent(title) {
            HStack {
                if taken.contains(action) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .help("Another app uses this shortcut. Pick another.")
                }
                ShortcutRecorder(shortcut: Binding(
                    get: { prefs[keyPath: key] },
                    set: { prefs[keyPath: key] = $0 }),
                    pause: { app.pauseShortcuts() },
                    resume: {
                        app.registerShortcuts()
                        taken = app.takenShortcuts
                    })
            }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.shared.add("Open at login: \(error.localizedDescription)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// A button that records a new shortcut when clicked.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    var pause: () -> Void
    var resume: () -> Void
    @State private var recording = false
    @State private var monitor: Any?
    @State private var warning: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Press keys…" : shortcut.display)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .frame(minWidth: 90)
            }
            if let warning {
                Text(warning).font(.caption).foregroundStyle(.orange)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        warning = nil
        pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Escape
                stop()
                return nil
            }
            guard let new = Shortcut(event: event) else {
                warning = "Use ⌘, ⌃ or ⌥ with a key."
                return nil
            }
            if new.isSystemScreenshot {
                warning = "That one takes screenshots in macOS."
                return nil
            }
            shortcut = new
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            resume()
        }
    }
}
