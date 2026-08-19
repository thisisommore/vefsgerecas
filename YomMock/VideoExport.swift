//
//  VideoExport.swift
//  YomMock
//
//  Native GPU video export. Renders the timeline offline with
//  RealityRenderer straight into Metal-backed CVPixelBuffers at any
//  resolution (up to 8K, independent of the screen), and encodes with
//  AVAssetWriter. No ScreenCaptureKit, no window capture, no display
//  sync — frames render as fast as the GPU + encoder allow.
//

import AVFoundation
import AppKit
import CoreVideo
import Metal
import simd

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

    /// Bits per pixel used for the automatic bitrate (ProRes ignores bitrate).
    var autoBitrateBitsPerPixel: Double {
        switch self {
        case .mp4_h264: return 4.0
        case .mov_hevc: return 2.0
        case .mov_prores: return 0
        }
    }
}

enum VideoResolutionPreset: String, CaseIterable, Identifiable {
    case matchPreview = "Match Preview"
    case p720 = "720p"
    case p1080 = "1080p"
    case p1440 = "1440p"
    case p2160 = "4K · 2160p"
    case p4320 = "8K · 4320p"

    var id: String { rawValue }

    /// Short-edge target in pixels. nil = render at native preview pixels.
    var shortEdge: CGFloat? {
        switch self {
        case .matchPreview: return nil
        case .p720: return 720
        case .p1080: return 1080
        case .p1440: return 1440
        case .p2160: return 2160
        case .p4320: return 4320
        }
    }
}

struct VideoExportOptions {
    var resolution: VideoResolutionPreset = .p2160
    var fps: Int = 30
    var format: VideoExportFormat = .mp4_h264
    var bitRateMbps: Double? = nil // nil = auto

    /// Output pixel size derived from the preview's aspect ratio. Since frames
    /// are rendered offscreen by the GPU, presets above the screen resolution
    /// produce true high-res renders — not upscaled screen recordings.
    func outputSize(previewPoints: CGSize, backingScale: CGFloat) -> CGSize {
        let pointW = max(previewPoints.width, 1)
        let pointH = max(previewPoints.height, 1)
        let scale: CGFloat
        if let shortEdge = resolution.shortEdge {
            scale = shortEdge / min(pointW, pointH)
        } else {
            scale = max(backingScale, 1)
        }
        var width = Int((pointW * scale).rounded())
        var height = Int((pointH * scale).rounded())
        // Clamp to the GPU 2D texture limit, preserving aspect.
        let cap = OffscreenSceneRenderer.maxTextureDimension
        if width > cap || height > cap {
            let down = CGFloat(cap) / CGFloat(max(width, height))
            width = Int((CGFloat(width) * down).rounded())
            height = Int((CGFloat(height) * down).rounded())
        }
        // H.264/HEVC require even dimensions.
        width = max(16, width - (width % 2))
        height = max(16, height - (height % 2))
        return CGSize(width: width, height: height)
    }

    var fileExtension: String { format.fileExtension }
}

enum VideoExportError: LocalizedError {
    case writerFailed(String)
    case cancelled
    case unsupportedSize(codec: String, size: CGSize)

    var errorDescription: String? {
        switch self {
        case .writerFailed(let s): return "Video writer failed: \(s)"
        case .cancelled: return "Export cancelled."
        case .unsupportedSize(let codec, let size):
            return "\(codec) cannot encode \(Int(size.width))×\(Int(size.height)). Use HEVC or ProRes for resolutions above 4K."
        }
    }
}

@MainActor
final class VideoExporter {
    private var isCancelled = false
    func cancel() { isCancelled = true }

    /// Exports the timeline as video, rendering every frame offscreen on the
    /// GPU. `inputs` is an immutable snapshot, so the user can keep editing
    /// the live preview while the export runs.
    func export(
        timeline: CameraTimeline,
        previewPoints: CGSize,
        backingScale: CGFloat,
        inputs: OffscreenSceneRenderer.Inputs,
        options: VideoExportOptions,
        outputURL: URL,
        onProgress: @MainActor @escaping (Double) -> Void
    ) async throws {
        isCancelled = false

        let outputSize = options.outputSize(previewPoints: previewPoints, backingScale: backingScale)
        let width = Int(outputSize.width)
        let height = Int(outputSize.height)
        guard width > 0, height > 0 else { throw VideoExportError.writerFailed("Invalid size") }

        // Hardware H.264 tops out at 4K — fail early with a clear message.
        if options.format.codec == .h264, width > 4096 || height > 4096 {
            throw VideoExportError.unsupportedSize(codec: "H.264", size: outputSize)
        }

        // Snapshot the timeline (checkpoints are value types) so edits during
        // export don't change the output and the live preview stays untouched.
        let timelineSnapshot = CameraTimeline(duration: timeline.duration)
        timelineSnapshot.checkpoints = timeline.checkpoints
        let duration = timelineSnapshot.duration
        let totalFrames = max(1, Int((duration * Double(options.fps)).rounded()))

        let renderer = try await OffscreenSceneRenderer(
            outputSize: outputSize,
            previewPointSize: previewPoints,
            inputs: inputs
        )

        // MARK: Writer setup

        try? FileManager.default.removeItem(at: outputURL)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: options.format.fileType)
        } catch {
            throw VideoExportError.writerFailed(error.localizedDescription)
        }

        let codec = options.format.codec
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        if codec != .proRes422 {
            let bitsPerSecond = options.bitRateMbps.map { Int($0 * 1_000_000) }
                ?? min(160_000_000, max(8_000_000, Int(Double(width * height) * options.format.autoBitrateBitsPerPixel)))
            videoSettings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: bitsPerSecond,
                AVVideoExpectedSourceFrameRateKey: options.fps
            ]
        }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let adaptorAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: adaptorAttributes
        )

        guard writer.canAdd(input) else { throw VideoExportError.writerFailed("Cannot add video input") }
        writer.add(input)
        guard writer.startWriting() else {
            throw VideoExportError.writerFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)

        // MARK: Frame loop — fixed timestep, deterministic per frame index

        let deltaTime = 1.0 / Double(options.fps)
        for frameIndex in 0..<totalFrames {
            if isCancelled || Task.isCancelled { throw VideoExportError.cancelled }

            let time = duration * Double(frameIndex) / Double(totalFrames)
            let state = timelineSnapshot.evaluatedState(at: time)

            let pixelBuffer = try await renderer.render(
                orbit: state.orbit,
                zoom: state.zoom,
                pan: state.pan,
                deltaTime: deltaTime
            )

            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 2_000_000)
                if isCancelled || Task.isCancelled { throw VideoExportError.cancelled }
            }

            let pts = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(options.fps))
            if !adaptor.append(pixelBuffer, withPresentationTime: pts) {
                throw VideoExportError.writerFailed(
                    writer.error?.localizedDescription ?? "append failed at frame \(frameIndex)")
            }

            onProgress(Double(frameIndex + 1) / Double(totalFrames))
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
}
