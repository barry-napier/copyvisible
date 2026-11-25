import AppKit
import CoreGraphics
import ImageIO
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers

/// A part of one display, or one window.
struct ScreenBox: Sendable, Equatable {
    var displayID: CGDirectDisplayID
    /// In points, relative to the display's top-left corner.
    var rect: CGRect
    /// Set when the user clicked a window instead of dragging.
    var windowID: CGWindowID?

    /// The same box in AppKit screen coordinates (bottom-left origin), for
    /// placing windows next to it.
    @MainActor
    var appKitFrame: CGRect? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { return nil }
        return CGRect(
            x: screen.frame.minX + rect.minX, y: screen.frame.maxY - rect.maxY,
            width: rect.width, height: rect.height)
    }
}

enum GrabError: LocalizedError {
    case noDisplay
    case noWindow

    var errorDescription: String? {
        switch self {
        case .noDisplay: "That screen is not connected any more."
        case .noWindow: "That window is closed."
        }
    }
}

/// Takes a picture of part of the screen with ScreenCaptureKit. CopyVisible's
/// own windows are always left out, so its overlay and panel never show up.
enum ScreenGrabber {
    static func grab(_ box: ScreenBox) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = true

        let filter: SCContentFilter
        let size: CGSize
        if let windowID = box.windowID {
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw GrabError.noWindow
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            size = window.frame.size
        } else {
            guard let display = content.displays.first(where: { $0.displayID == box.displayID }) else {
                throw GrabError.noDisplay
            }
            let ours = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: ours, exceptingWindows: [])
            config.sourceRect = box.rect
            size = box.rect.size
        }
        // At least 2 pixels per point: small text reads better when bigger.
        let scale = max(2, CGFloat(filter.pointPixelScale))
        config.width = max(1, Int(size.width * scale))
        config.height = max(1, Int(size.height * scale))
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// The front window under a point, in CoreGraphics screen coordinates
    /// (top-left origin of the main display). Skips CopyVisible's own windows.
    static func window(at point: CGPoint) -> (id: CGWindowID, bounds: CGRect)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != me,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict),
                  bounds.contains(point)
            else { continue }
            return (id, bounds)
        }
        return nil
    }

    /// A small PNG for history, at most 640 pixels wide or tall.
    static func thumbnail(_ image: CGImage) -> Data? {
        let longest = max(image.width, image.height)
        let factor = min(1, 640 / CGFloat(longest))
        let width = max(1, Int(CGFloat(image.width) * factor))
        let height = max(1, Int(CGFloat(image.height) * factor))
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let small = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, small, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Converts an AppKit screen point to CoreGraphics coordinates.
    static func cgPoint(fromAppKit point: CGPoint) -> CGPoint {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: mainHeight - point.y)
    }

    /// Converts a CoreGraphics rect to AppKit screen coordinates.
    static func appKitRect(fromCG rect: CGRect) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
