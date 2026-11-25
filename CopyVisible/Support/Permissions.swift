import AppKit
import CoreGraphics

/// Screen Recording permission. CopyVisible needs it to see the screen.
enum Permissions {
    static var canRecordScreen: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Adds CopyVisible to the Screen Recording list in System Settings and
    /// shows the system prompt the first time. The user still has to switch it on.
    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openScreenRecordingSettings() {
        let link = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    /// Opens a new copy of the app and quits this one. macOS often applies a
    /// new Screen Recording grant only to a fresh process.
    @MainActor
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
