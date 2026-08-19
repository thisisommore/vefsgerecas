//
//  OfflineMetalCompositor.swift
//  YomMock
//
//  Dedicated offline compositor for video export.
//  Replaces ScreenCaptureKit + fixed 55ms sleep with:
//  - Metal-backed CIContext (MTLDevice) for hardware scaling + pixel-buffer render
//  - CVMetalTextureCache for zero-copy path (future)
//  - Display-link aware wait (single vsync) instead of fixed sleep
//
//  Pattern mirrors CineScreen / metalforge / frapser: pipe frames through
//  a Metal compositor and feed AVAssetWriter offline at locked fps.
//

import AVFoundation
import AppKit
import CoreImage
import CoreVideo
import Metal
import QuartzCore

final class OfflineMetalCompositor {
    let device: MTLDevice
    let ciContext: CIContext
    var textureCache: CVMetalTextureCache?

    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.device = device
        // Persistent context bound to Metal device - key for smooth pipeline (ForaSoft pattern)
        self.ciContext = CIContext(mtlDevice: device, options: [
            .cacheIntermediates: false,
            .allowLowPower: false
        ])
        var cache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess {
            self.textureCache = cache
        }
    }

    // MARK: - Pixel buffer

    func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let pb = buffer else { return nil }
        return pb
    }

    /// Render CGImage into pre-allocated pixel buffer via Metal CIContext (zero-copy when possible)
    func render(cgImage: CGImage, to pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cgImage: cgImage)
        // High-quality downscale handled by caller via extent; here just render 1:1 into buffer
        ciContext.render(ciImage, to: pixelBuffer, bounds: ciImage.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    /// Metal-accelerated scale (Lanczos) - replaces CGContext scale in VideoExporter
    func scaled(_ image: CGImage, to size: CGSize) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        let scaleX = size.width / CGFloat(image.width)
        let scaleY = size.height / CGFloat(image.height)
        // Use Lanczos for quality downscale; CIContext is Metal-backed
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else {
            // Fallback to CGContext
            return VideoExporter.scaled(image, to: size)
        }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(scaleX, forKey: kCIInputScaleKey)
        filter.setValue(scaleY, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let output = filter.outputImage else { return nil }
        let rect = CGRect(origin: .zero, size: size)
        guard let cg = ciContext.createCGImage(output, from: rect) else { return nil }
        return cg
    }

    /// One-shot scaled render: CIImage scale + render into pixel buffer in one Metal pass
    func renderScaled(cgImage: CGImage, to pixelBuffer: CVPixelBuffer, outputSize: CGSize) {
        let ciImage = CIImage(cgImage: cgImage)
        let scaleX = outputSize.width / CGFloat(cgImage.width)
        let scaleY = outputSize.height / CGFloat(cgImage.height)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let bounds = CGRect(origin: .zero, size: outputSize)
        ciContext.render(scaled, to: pixelBuffer, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
    }
}

// MARK: - Display sync (replaces fixed 55ms sleep)

enum DisplaySync {
    /// Wait for exactly one display refresh (~16ms @60Hz, ~8ms @120Hz ProMotion)
    /// instead of fixed 55ms. Adapts to GPU/display: good GPU + 120Hz = 3-6x faster.
    static func waitForNextFrame() async {
        // Prefer hardware vsync via CVDisplayLink; fallback gracefully
        if let link = makeDisplayLink() {
            await waitOneTick(link: link)
            CVDisplayLinkStop(link)
        } else {
            // Fallback: minimal estimate based on screen refresh
            let ns: UInt64
            if let screen = NSScreen.main, screen.maximumFramesPerSecond > 0 {
                let frameTime = 1_000_000_000 / UInt64(screen.maximumFramesPerSecond)
                ns = min(frameTime, 16_666_666)
            } else {
                ns = 16_666_666
            }
            await MainActor.run { CATransaction.flush() }
            try? await Task.sleep(nanoseconds: ns)
        }
    }

    private static func makeDisplayLink() -> CVDisplayLink? {
        var link: CVDisplayLink?
        let status = CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard status == kCVReturnSuccess, let link else { return nil }
        return link
    }

    private static func waitOneTick(link: CVDisplayLink) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            final class Box {
                var cont: CheckedContinuation<Void, Never>?
                var resumed = false
                init(_ c: CheckedContinuation<Void, Never>) { cont = c }
            }
            let box = Box(cont)
            // Keep box alive via closure capture; pass unretained pointer to C
            let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo in
                guard let userInfo else { return kCVReturnSuccess }
                let b = Unmanaged<Box>.fromOpaque(userInfo).takeUnretainedValue()
                if !b.resumed, let c = b.cont {
                    b.resumed = true
                    b.cont = nil
                    c.resume()
                }
                return kCVReturnSuccess
            }

            CVDisplayLinkSetOutputCallback(link, callback, Unmanaged.passUnretained(box).toOpaque())
            CVDisplayLinkStart(link)

            // Safety timeout: if display link never fires (headless), resume after 33ms
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.033) {
                if !box.resumed, let c = box.cont {
                    box.resumed = true
                    box.cont = nil
                    c.resume()
                }
            }
        }
    }

    /// Ensure RealityView has flushed its Metal transaction (CATransaction + displayIfNeeded)
    @MainActor
    static func flushTransactions(for view: NSView) {
        view.displayIfNeeded()
        CATransaction.flush()
    }
}
