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
        try await capture(window: window, targetScale: 1.0)
    }

    /// Captures with optional downscale (0.25…1.0). Scale < 1 sets SCScreenshotConfiguration width/height.
    /// Retries transient stream failures (e.g. while switching Spaces/desktops with Meet) and
    /// falls back to view-layer snapshot when the window is offscreen or ScreenCaptureKit is busy.
    static func capture(window: NSWindow, targetScale: CGFloat) async throws -> CGImage {
        // Fast-path: if window is not on the active Space / is occluded, avoid ScreenCaptureKit stream error
        // and capture the preview view directly via its backing layer. This works even when the desktop
        // is switched to make Google Meet visible.
        if window.occlusionState.rawValue & NSWindow.OcclusionState.visible.rawValue == 0 {
            if let view = window.contentView, let fallback = snapshotContentView(view, window: window, targetScale: targetScale) {
                return fallback
            }
        }

        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let content = try await SCShareableContent.currentProcess
                let windowID = CGWindowID(window.windowNumber)
                guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                    throw CaptureError.windowNotFound
                }
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                let config = SCScreenshotConfiguration()
                config.showsCursor = false
                config.ignoreShadows = true
                if targetScale < 0.999, targetScale > 0.05 {
                    let nativeW = window.contentLayoutRect.width * window.backingScaleFactor
                    let nativeH = window.contentLayoutRect.height * window.backingScaleFactor
                    let w = max(16, Int((nativeW * targetScale).rounded()))
                    let h = max(16, Int((nativeH * targetScale).rounded()))
                    config.width = w - (w % 2)
                    config.height = h - (h % 2)
                }

                let output = try await SCScreenshotManager.captureScreenshot(
                    contentFilter: filter, configuration: config)
                if let img = output.sdrImage { return img }
                if let img = output.hdrImage { return img }
                throw CaptureError.noImage
            } catch {
                lastError = error
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                // Retry only for transient stream failures (common when switching Spaces)
                let isStreamFailure = msg.lowercased().contains("stream") || msg.lowercased().contains("capture failure") || msg.lowercased().contains("failed to start")
                if isStreamFailure && attempt < 2 {
                    // Brief backoff, then retry; keep window ordered front but don't steal Meet focus
                    try? await Task.sleep(nanoseconds: UInt64(180_000_000 + attempt * 120_000_000))
                    continue
                }
                // For stream failures after retries, try view fallback before throwing modal error
                let view = window.contentView
                if let view, let fallback = snapshotContentView(view, window: window, targetScale: targetScale) {
                    return fallback
                }
                throw error
            }
        }
        throw lastError ?? CaptureError.noImage
    }

    /// Fallback: render the window's contentView layer directly. Works when the window is on another Space
    /// (e.g. Meet on Desktop 2) and ScreenCaptureKit reports "Failed to start stream…".
    private static func snapshotContentView(_ contentView: NSView, window: NSWindow, targetScale: CGFloat) -> CGImage? {
        // Must be called on MainActor – caller is already MainActor-isolated via store
        let bounds = contentView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = targetScale < 0.999 && targetScale > 0.05 ? targetScale : 1.0
        let pixelW = max(1, Int((bounds.width * window.backingScaleFactor * scale).rounded()))
        let pixelH = max(1, Int((bounds.height * window.backingScaleFactor * scale).rounded()))
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        contentView.cacheDisplay(in: bounds, to: rep)
        guard let cg = rep.cgImage else { return nil }
        if cg.width == pixelW && cg.height == pixelH { return cg }
        // Resize to target if needed
        guard let ctx = CGContext(data: nil, width: pixelW, height: pixelH, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cg }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
        return ctx.makeImage() ?? cg
    }

    static func nativePixelSize(for view: NSView, window: NSWindow) -> CGSize? {
        let rectInWindow = view.convert(view.bounds, to: nil)
        let scale = window.backingScaleFactor
        return CGSize(width: rectInWindow.width * scale, height: rectInWindow.height * scale)
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
