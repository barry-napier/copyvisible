import AppKit
import SwiftUI

/// A panel that floats above other apps without taking focus from them,
/// until the user clicks into it.
final class FloatingPanel: NSPanel {
    var onEscape: (() -> Void)?

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?() ?? close()
    }
}

/// Shows the result panel next to the capture, or as a bar at the edge.
@MainActor
final class ResultPanel {
    let model = PanelModel()
    private var panel: FloatingPanel?

    var isVisible: Bool { panel?.isVisible == true }

    func show(near box: CGRect?, style: PanelStyle) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let screen = box.flatMap { box in NSScreen.screens.first { $0.frame.intersects(box) } }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        var frame: CGRect
        switch style {
        case .sideBar:
            frame = CGRect(x: visible.maxX - 420, y: visible.minY, width: 420, height: visible.height)
        case .floating, .none:
            let width: CGFloat = 440
            let height = min(visible.height - 40, panel.isVisible ? panel.frame.height : 560)
            frame = CGRect(x: 0, y: 0, width: width, height: height)
            if let box {
                // To the right of the box, or the left, or below it.
                if box.maxX + 12 + width <= visible.maxX {
                    frame.origin = CGPoint(x: box.maxX + 12, y: box.maxY - height)
                } else if box.minX - 12 - width >= visible.minX {
                    frame.origin = CGPoint(x: box.minX - 12 - width, y: box.maxY - height)
                } else {
                    frame.origin = CGPoint(x: box.midX - width / 2, y: box.minY - 12 - height)
                }
            } else {
                frame.origin = CGPoint(x: visible.midX - width / 2, y: visible.midY - height / 2)
            }
            frame.origin.x = min(max(frame.origin.x, visible.minX + 8), visible.maxX - width - 8)
            frame.origin.y = min(max(frame.origin.y, visible.minY + 8), visible.maxY - height - 8)
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func close() {
        model.stopAI()
        panel?.orderOut(nil)
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(size: NSSize(width: 440, height: 560))
        panel.onEscape = { [weak self] in self?.close() }
        panel.contentView = NSHostingView(rootView: ResultView(model: model) { [weak self] in self?.close() })
        return panel
    }
}

/// A small "Copied" note that fades away, for when the panel is off.
@MainActor
enum Toast {
    private static var window: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ message: String, near box: CGRect?) {
        hideTask?.cancel()
        window?.orderOut(nil)
        let host = NSHostingView(rootView:
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule()))
        let size = host.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hasShadow = true
        panel.contentView = host
        let screen = NSScreen.screens.first { box.map($0.frame.intersects) ?? false } ?? NSScreen.main
        var origin = CGPoint(x: (screen?.visibleFrame.midX ?? 400) - size.width / 2, y: (screen?.visibleFrame.minY ?? 0) + 80)
        if let box { origin = CGPoint(x: box.midX - size.width / 2, y: box.minY - size.height - 10) }
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        window = panel
        hideTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }
}

/// Draws a dashed frame around a box being watched, with a Stop button.
@MainActor
final class WatchFrame {
    private var frameWindow: NSWindow?
    private var controls: NSPanel?
    private let state = WatchState()

    func show(around box: CGRect, onStop: @escaping () -> Void) {
        let outline = NSWindow(
            contentRect: box.insetBy(dx: -4, dy: -4), styleMask: .borderless, backing: .buffered, defer: false)
        outline.isOpaque = false
        outline.backgroundColor = .clear
        outline.ignoresMouseEvents = true
        outline.level = .statusBar
        outline.isReleasedWhenClosed = false
        outline.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        outline.contentView = NSHostingView(rootView:
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
        outline.orderFrontRegardless()
        frameWindow = outline

        let host = NSHostingView(rootView: WatchControls(state: state, stop: onStop))
        let size = host.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = host
        var origin = CGPoint(x: box.maxX - size.width, y: box.minY - size.height - 8)
        if origin.y < 8 { origin.y = box.maxY + 8 }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        controls = panel
    }

    func update(lines: Int) { state.lines = lines }

    func hide() {
        frameWindow?.orderOut(nil)
        controls?.orderOut(nil)
        frameWindow = nil
        controls = nil
        state.lines = 0
    }
}

@MainActor
@Observable
private final class WatchState {
    var lines = 0
}

private struct WatchControls: View {
    let state: WatchState
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Text("Watching · \(state.lines) line\(state.lines == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
            Button("Stop", action: stop)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .fixedSize()
    }
}
