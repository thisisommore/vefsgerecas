//  FrameCapture.swift
//  YomMock
//
//  Captures the on-screen preview region of the app window for
//  "Export Current Frame". Uses ScreenCaptureKit — capturing the app's
//  own window (desktopIndependentWindow) does not require screen-recording
//  permission on macOS 14.4+.

import AppKit
import ScreenCaptureKit

enum FrameCapture {
    enum CaptureError: LocalizedError {
        case windowNotFound
        case cropFailed
        case noImage

        var errorDescription: String? {
            switch self {
            case .windowNotFound:
                return "The preview window could not be captured. Make sure it is visible on screen."
            case .cropFailed:
                return "The captured frame could not be cropped to the preview area."
            case .noImage:
                return "The screenshot did not contain an image."
            }
        }
    }

    /// Captures the window at native backing resolution using
    /// SCContentFilter(desktopIndependentWindow:). No TCC prompt for own window.
    static func capture(window: NSWindow) async throws -> CGImage {
        // Current-process shareable content is permission-free and available macOS 14.4+.
        // Target is 26.1 so always available.
        let content = try await SCShareableContent.currentProcess
        let windowID = CGWindowID(window.windowNumber)
        guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCScreenshotConfiguration()
        config.showsCursor = false
        // Default width/height == window size at best resolution; keep default
        // to avoid scaling artifacts. Ignore shadows for a clean export.
        config.ignoreShadows = true

        let output = try await SCScreenshotManager.captureScreenshot(
            contentFilter: filter, configuration: config)
        if let img = output.sdrImage {
            return img
        }
        if let img = output.hdrImage {
            return img
        }
        throw CaptureError.noImage
    }

    /// Crops a full-window capture to a view rect given in window
    /// (content) coordinates — bottom-left origin. Handles both
    /// frame-including and content-only image variants by detecting
    /// image height.
    static func crop(_ image: CGImage, toViewRect rectInWindow: CGRect, window: NSWindow) -> CGImage? {
        let contentRect = window.contentLayoutRect
        let contentWidth = contentRect.width
        let contentHeight = contentRect.height
        let frameHeight = window.frame.height
        guard contentWidth > 0, contentHeight > 0, frameHeight > 0 else { return nil }

        // Scale from points to pixels (width is same for frame and content).
        let scale = CGFloat(image.width) / contentWidth
        guard scale > 0 else { return nil }

        let imageHeight = CGFloat(image.height)
        let expectedContentPixels = contentHeight * scale
        let expectedFramePixels = frameHeight * scale
        // Detect whether the screenshot includes the titlebar.
        let isFrameImage = abs(imageHeight - expectedFramePixels) < abs(imageHeight - expectedContentPixels)

        let topY: CGFloat
        if isFrameImage {
            let titleBarHeight = frameHeight - contentHeight
            topY = titleBarHeight + (contentHeight - rectInWindow.maxY)
        } else {
            topY = contentHeight - rectInWindow.maxY
        }

        let cropRect = CGRect(
            x: rectInWindow.minX * scale,
            y: topY * scale,
            width: rectInWindow.width * scale,
            height: rectInWindow.height * scale
        ).integral

        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clipped = cropRect.intersection(bounds)
        guard !clipped.isNull, !clipped.isEmpty else { return nil }
        return image.cropping(to: clipped)
    }
}
