import Combine
import SwiftUI

/// First-run walk-through: what CopyVisible does, the Screen Recording
/// permission, Apple Intelligence, and how to start.
struct WelcomeView: View {
    enum Step: Int {
        case hello, permission, intelligence, ready
    }

    @State private var step: Step
    @State private var canRecord = Permissions.canRecordScreen
    let finish: () -> Void

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(start: Step, finish: @escaping () -> Void) {
        _step = State(initialValue: start)
        self.finish = finish
    }

    var body: some View {
        VStack(spacing: 18) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                ForEach(0..<4) { index in
                    Circle()
                        .fill(index == step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
                Spacer()
                buttons
            }
        }
        .padding(28)
        .frame(width: 520, height: 460)
        .onReceive(timer) { _ in canRecord = Permissions.canRecordScreen }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .hello:
            page(symbol: "text.viewfinder", title: "Copy anything you can see",
                 text: "Press a shortcut, drag over any part of the screen, and the text in it goes to your clipboard. It works on pictures, videos, PDFs and apps that do not let you select text.\n\nThen Apple’s AI can explain it, sum it up, shorten it or translate it. Everything stays on this Mac.")
        case .permission:
            VStack(spacing: 14) {
                page(symbol: canRecord ? "checkmark.shield" : "rectangle.dashed.badge.record",
                     title: canRecord ? "Screen Recording is on" : "Let CopyVisible see the screen",
                     text: canRecord
                        ? "All set. CopyVisible only looks at the screen when you press the shortcut."
                        : "macOS calls this Screen Recording. CopyVisible only looks when you press the shortcut, and only at the part you choose. It never records video and never sends anything anywhere.")
                if !canRecord {
                    Button("Open System Settings") {
                        Permissions.requestScreenRecording()
                        Permissions.openScreenRecordingSettings()
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    Text("Switch on CopyVisible in the list. If macOS asks, choose Quit & Reopen.\nAlready on? Click Restart.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Restart CopyVisible") { Permissions.relaunch() }
                        .buttonStyle(.link)
                }
            }
        case .intelligence:
            if let message = Assistant.unavailableMessage {
                page(symbol: "sparkles", title: "Smart actions need Apple Intelligence",
                     text: message + "\n\nCopying text still works without it.")
            } else {
                page(symbol: "sparkles", title: "Smart actions are ready",
                     text: "Explain code, find bugs, sum up, shorten, fix reading mistakes, translate, or ask your own question. Apple’s model runs on this Mac, so your text never leaves it.")
            }
        case .ready:
            VStack(spacing: 16) {
                page(symbol: "keyboard", title: "Try it now",
                     text: "Press the shortcut, then drag over some text.")
                Text(Prefs.shared.captureShortcut.display)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                Text("Click a window instead of dragging to take all of it. Drop a picture or PDF on the menu bar icon to read it. The icon’s menu has history, watching a box and settings.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if step != .hello {
            Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .hello }
        }
        switch step {
        case .ready:
            Button("Done", action: finish)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        case .permission:
            Button(canRecord ? "Continue" : "Skip for Now") { step = .intelligence }
                .keyboardShortcut(.defaultAction)
        default:
            Button("Continue") { step = Step(rawValue: step.rawValue + 1) ?? .ready }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func page(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 46))
                .foregroundStyle(.tint)
            Text(title).font(.title2.weight(.semibold))
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
