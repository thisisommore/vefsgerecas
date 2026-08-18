//
//  VideoExport.swift
//  YomMock
//
//  Offline video export of the Timeline by stepping through
//  CameraTimeline and capturing the preview region per frame.
//  Supports res downscale and mp4/mov formats via AVAssetWriter.
//

import AVFoundation
import AppKit
import CoreVideo
import ScreenCaptureKit

enum VideoExportFormat: String, CaseIterable, Identifiable {
    case mp4_h264 = "MP4 (H.264)"
    case mov_hevc = "MOV (HEVC)"
    case mov_prores = "MOV (ProRes 422)"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .mp4_h264: return "mp4"
        case .mov_hevc, .mov_prores: return "mov"
        }
    }

    var fileType: AVFileType {
        switch self {
        case .mp4_h264: return .mp4
        case .mov_hevc, .mov_prores: return .mov
        }
    }

    var codec: AVVideoCodecType {
        switch self {
        case .mp4_h264: return .h264
        case .mov_hevc: return .hevc
        case .mov_prores: return .proRes422
        }
    }

    var allowedContentTypes: [String] {
        switch self {
        case .mp4_h264: return ["public.mpeg-4"]
        case .mov_hevc, .mov_prores: return ["com.apple.quicktime-movie"]
        }
    }
}

enum VideoResolutionPreset: String, CaseIterable, Identifiable {
    case native = "Native"
    case p1080 = "1080p"
    case p720 = "720p"
    case p540 = "540p"
    case half = "50%"
    case quarter = "25%"

    var id: String { rawValue }

    /// Scale factor relative to native preview pixels. p1080/p720/p540 are long-edge targets.
    var scaleHint: CGFloat? {
        switch self {
        case .native: return 1.0
        case .half: return 0.5
        case .quarter: return 0.25
        case .p1080, .p720, .p540: return nil
        }
    }

    var longEdge: CGFloat? {
        switch self {
        case .p1080: return 1920
        case .p720: return 1280
        case .p540: return 960
        default: return nil
        }
    }
}

struct VideoExportOptions {
    var resolution: VideoResolutionPreset = .native
    var customScale: CGFloat = 1.0 // used when resolution is native/half/quarter as override
    var fps: Int = 30
    var format: VideoExportFormat = .mp4_h264
    var bitRateMbps: Double? = nil // nil = auto

    /// Compute output pixel size from native preview size and chosen preset
    func outputSize(for native: CGSize) -> CGSize {
        let baseScale: CGFloat
        if let hint = resolution.scaleHint {
            baseScale = hint
        } else if let longEdge = resolution.longEdge {
            let nativeLong = max(native.width, native.height)
            guard nativeLong > 0 else { return native }
            baseScale = min(1.0, longEdge / nativeLong)
        } else {
            baseScale = 1.0
        }
        // For native preset allow customScale (1.0)
        let scale = resolution == .native ? customScale : baseScale
        let w = max(16, Int((native.width * scale).rounded()))
        let h = max(16, Int((native.height * scale).rounded()))
        // H.264/HEVC require even dimensions
        let evenW = w - (w % 2)
        let evenH = h - (h % 2)
        return CGSize(width: evenW, height: evenH)
    }

    var fileExtension: String { format.fileExtension }
}

enum VideoExportError: LocalizedError {
    case noPreview
    case writerFailed(String)
    case pixelBufferFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noPreview: return "The preview could not be captured."
        case .writerFailed(let s): return "Video writer failed: \(s)"
        case .pixelBufferFailed: return "Could not create pixel buffer."
        case .cancelled: return "Export cancelled."
        }
    }
}

actor VideoExporter {
    private var isCancelled = false
    func cancel() { isCancelled = true }

    /// Exports timeline to video. Caller must provide preview anchor info and a way to apply pose per frame.
    func export(
        timeline: CameraTimeline,
        previewView: NSView,
        window: NSWindow,
        nativePreviewSize: CGSize,
        options: VideoExportOptions,
        outputURL: URL,
        applyPose: @MainActor @escaping (OrbitPose, Float, SIMD3<Float>) -> Void,
        onProgress: @MainActor @escaping (Double) -> Void
    ) async throws {
        isCancelled = false
        let duration = await MainActor.run { timeline.duration }
        let totalFrames = max(1, Int((duration * Double(options.fps)).rounded()))
        let outputSize = options.outputSize(for: nativePreviewSize)
        let width = Int(outputSize.width)
        let height = Int(outputSize.height)
        guard width > 0 && height > 0 else { throw VideoExportError.writerFailed("Invalid size") }

        // Remove existing file
        try? FileManager.default.removeItem(at: outputURL)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: options.format.fileType)
        } catch {
            throw VideoExportError.writerFailed(error.localizedDescription)
        }

        let codec = options.format.codec
        // ProRes does not use bitrate; use default
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        if codec != .proRes422 {
            let bitRate = options.bitRateMbps.map { Int($0 * 1_000_000) } ?? max(2_000_000, width * height * 4)
            videoSettings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: options.fps
            ]
        }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)

        guard writer.canAdd(input) else { throw VideoExportError.writerFailed("Cannot add video input") }
        writer.add(input)

        guard writer.startWriting() else { throw VideoExportError.writerFailed(writer.error?.localizedDescription ?? "startWriting failed") }
        writer.startSession(atSourceTime: .zero)

        // Snapshot timeline — access MainActor-isolated props on MainActor
        let originalTime = await MainActor.run { timeline.currentTime }
        let wasPlaying = await MainActor.run { timeline.isPlaying }
        await MainActor.run { timeline.isPlaying = false }

        defer {
            Task { @MainActor in
                timeline.seek(to: originalTime)
                timeline.isPlaying = wasPlaying
            }
        }

        let rectInWindow = await MainActor.run { previewView.convert(previewView.bounds, to: nil) }
        // Pre-calc scale for ScreenCaptureKit downscale
        let nativePixels = FrameCapture.nativePixelSize(for: previewView, window: window) ?? nativePreviewSize
        let targetScale = width > 0 && nativePixels.width > 0 ? CGFloat(width) / nativePixels.width : 1.0

        var frameIndex = 0
        while frameIndex < totalFrames {
            if isCancelled || Task.isCancelled { throw VideoExportError.cancelled }
            let t = duration * Double(frameIndex) / Double(totalFrames)
            let state = await MainActor.run { timeline.evaluatedState(at: t) }

            await MainActor.run {
                applyPose(state.orbit, state.zoom, state.pan)
                timeline.seek(to: t)
            }
            // Let RealityView render ~1-2 frames (30fps → need ~33ms). 50ms is safe.
            try? await Task.sleep(nanoseconds: 55_000_000)
            if isCancelled || Task.isCancelled { throw VideoExportError.cancelled }

            // Capture with downscale
            let cgImage: CGImage
            do {
                // Use targetScale to let ScreenCaptureKit capture at reduced pixels directly when possible
                let raw = try await FrameCapture.capture(window: window, targetScale: targetScale)
                guard let cropped = FrameCapture.crop(raw, toViewRect: rectInWindow, window: window) else {
                    throw VideoExportError.noPreview
                }
                // Ensure output size matches exactly (extra resample if needed due to rounding)
                if cropped.width == width && cropped.height == height {
                    cgImage = cropped
                } else {
                    guard let scaled = VideoExporter.scaled(cropped, to: outputSize) else {
                        throw VideoExportError.pixelBufferFailed
                    }
                    cgImage = scaled
                }
            } catch {
                // If capture fails mid-export, propagate
                throw error
            }

            // Wait for writer readiness
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 5_000_000)
                if isCancelled || Task.isCancelled { throw VideoExportError.cancelled }
            }

            guard let buffer = VideoExporter.makePixelBuffer(from: cgImage, width: width, height: height) else {
                throw VideoExportError.pixelBufferFailed
            }
            let pts = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(options.fps))
            if !adaptor.append(buffer, withPresentationTime: pts) {
                throw VideoExportError.writerFailed(writer.error?.localizedDescription ?? "append failed at frame \(frameIndex)")
            }

            let progress = Double(frameIndex + 1) / Double(totalFrames)
            await onProgress(progress)

            frameIndex += 1
        }

        input.markAsFinished()
        await withCheckedContinuation { cont in
            writer.finishWriting { cont.resume() }
        }
        if let error = writer.error {
            throw VideoExportError.writerFailed(error.localizedDescription)
        }
        if isCancelled { throw VideoExportError.cancelled }
    }

    // MARK: - Helpers

    static func makePixelBuffer(from image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }

    static func scaled(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0 && height > 0 else { return nil }
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }
}
