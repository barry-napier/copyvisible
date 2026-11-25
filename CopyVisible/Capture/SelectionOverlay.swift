import AppKit

/// Dims every screen and lets the user drag a box, or click a window to
/// take all of it. Escape or a right-click cancels.
@MainActor
final class SelectionOverlay {
    enum Purpose {
        case capture
        case watch

        var hint: String {
            switch self {
            case .capture: "Drag over text to copy it  ·  Click a window to take all of it  ·  Esc to cancel"
            case .watch: "Drag over the area to watch, like video subtitles  ·  Esc to cancel"
            }
        }
    }

    private var windows: [OverlayWindow] = []
    private var completion: ((ScreenBox?) -> Void)?
    private var previousApp: NSRunningApplication?

    var isShowing: Bool { !windows.isEmpty }

    /// Calls `completion` with the chosen box, or nil when cancelled.
    func begin(_ purpose: Purpose, completion: @escaping (ScreenBox?) -> Void) {
        guard windows.isEmpty else { return }
        self.completion = completion
        previousApp = NSWorkspace.shared.frontmostApplication
        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen, purpose: purpose)
            window.onFinish = { [weak self] box in self?.finish(box) }
            windows.append(window)
            window.orderFrontRegardless()
        }
        NSApp.activate()
        let mouse = NSEvent.mouseLocation
        let start = windows.first { $0.frame.contains(mouse) } ?? windows.first
        start?.makeKey()
        NSCursor.crosshair.set()
    }

    func cancel() { finish(nil) }

    private func finish(_ box: ScreenBox?) {
        guard let completion else { return }
        self.completion = nil
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        NSCursor.arrow.set()
        // Give focus back to the app the user was in.
        if let previousApp, previousApp != NSRunningApplication.current { previousApp.activate() }
        completion(box)
    }
}

private final class OverlayWindow: NSWindow {
    var onFinish: ((ScreenBox?) -> Void)?

    init(screen: NSScreen, purpose: SelectionOverlay.Purpose) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        setFrame(screen.frame, display: false)
        let view = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.screen = screen
        view.hint = purpose.hint
        view.allowsWindowClick = purpose == .capture
        view.onFinish = { [weak self] box in self?.onFinish?(box) }
        contentView = view
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) } else { super.keyDown(with: event) }
    }
}

private final class OverlayView: NSView {
    weak var screen: NSScreen?
    var hint = ""
    var allowsWindowClick = true
    var onFinish: ((ScreenBox?) -> Void)?

    private var start: CGPoint?
    private var current: CGPoint?
    /// The window under the mouse, in this view's coordinates.
    private var hoverWindow: (id: CGWindowID, rect: CGRect)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(
            x: min(start.x, current.x), y: min(start.y, current.y),
            width: abs(start.x - current.x), height: abs(start.y - current.y))
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        guard allowsWindowClick, start == nil else { return }
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        current = CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
        hoverWindow = nil
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let screen, let rect = selection else { return finish(nil) }
        if rect.width < 4 || rect.height < 4 {
            // A click, not a drag: take the window under the mouse.
            if allowsWindowClick, let hoverWindow, let box = windowBox(hoverWindow, screen: screen) {
                return finish(box)
            }
            start = nil
            current = nil
            needsDisplay = true
            return
        }
        let local = CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
        finish(ScreenBox(displayID: screen.displayID, rect: local))
    }

    override func rightMouseDown(with event: NSEvent) { finish(nil) }

    private func finish(_ box: ScreenBox?) {
        onFinish?(box)
        onFinish = nil
    }

    private func updateHover(at point: CGPoint) {
        guard let screen else { return }
        let global = CGPoint(x: point.x + screen.frame.minX, y: point.y + screen.frame.minY)
        let found = ScreenGrabber.window(at: NSScreen.cgPoint(fromAppKit: global))
        let rect = found.map { window -> CGRect in
            let appKit = NSScreen.appKitRect(fromCG: window.bounds)
            return appKit.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        }
        if hoverWindow?.id != found?.id || hoverWindow?.rect != rect {
            hoverWindow = found.flatMap { found in rect.map { (found.id, $0) } }
            needsDisplay = true
        }
    }

    private func windowBox(_ window: (id: CGWindowID, rect: CGRect), screen: NSScreen) -> ScreenBox? {
        let clipped = window.rect.intersection(bounds)
        guard !clipped.isEmpty else { return nil }
        let local = CGRect(
            x: clipped.minX, y: bounds.height - clipped.maxY, width: clipped.width, height: clipped.height)
        return ScreenBox(displayID: screen.displayID, rect: local, windowID: window.id)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let hole = selection ?? hoverWindow?.rect
        NSColor.black.withAlphaComponent(0.28).setFill()
        let path = NSBezierPath(rect: bounds)
        if let hole {
            path.append(NSBezierPath(rect: hole))
            path.windingRule = .evenOdd
        }
        path.fill()

        if let hole {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: hole.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = selection == nil ? 3 : 1
            if selection == nil { NSColor.controlAccentColor.setStroke() }
            border.stroke()
        }
        if let selection, selection.width > 20 {
            label("\(Int(selection.width)) × \(Int(selection.height))", near: CGPoint(x: selection.maxX, y: selection.minY - 26))
        }
        drawHint()
    }

    private func drawHint() {
        guard let screen, screen.frame.contains(NSEvent.mouseLocation) || NSScreen.screens.first == screen else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white,
        ]
        let size = (hint as NSString).size(withAttributes: attributes)
        let box = CGRect(
            x: (bounds.width - size.width) / 2 - 14, y: bounds.height - size.height - 90,
            width: size.width + 28, height: size.height + 14)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        (hint as NSString).draw(at: CGPoint(x: box.minX + 14, y: box.minY + 7), withAttributes: attributes)
    }

    private func label(_ text: String, near point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var box = CGRect(x: point.x - size.width - 12, y: point.y, width: size.width + 12, height: size.height + 6)
        box.origin.y = max(4, box.origin.y)
        box.origin.x = max(4, box.origin.x)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attributes)
    }
}
