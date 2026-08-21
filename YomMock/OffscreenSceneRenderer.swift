//
//  OffscreenSceneRenderer.swift
//  YomMock
//
//  Native GPU offscreen renderer — the replacement for the old
//  ScreenCaptureKit-based capture. Uses RealityKit's RealityRenderer
//  (macOS 15+) to draw the scene straight into an IOSurface-backed
//  CVPixelBuffer's Metal texture at ANY resolution (up to 16384 px),
//  independent of the screen. No window, no display link, no sleeps.
//
//  Per-frame pipeline (all on GPU, zero CPU pixel copies):
//    1. CIContext renders the studio gradient into the pixel buffer via
//       CIRenderDestination(ioSurface:) — rendering into MTLTexture
//       destinations fails on macOS 26 ("The destination is nil", silently
//       yielding transparent frames) — awaited off the main actor.
//    2. RealityRenderer draws the 3D scene over the existing texture content
//       (cameraSettings.colorBackground = .outputTexture()), then signals
//       a shared event.
//    3. We await the done event and hand the CVPixelBuffer to
//       AVAssetWriter — the hardware encoder reads the IOSurface directly.
//
//  Deterministic: updateAndRender(deltaTime:) advances the ECS with a
//  fixed timestep, so exports are frame-perfect and repeatable.
//

import AVFoundation
import AppKit
import CoreImage
import CoreVideo
import Metal
import RealityKit
import simd

enum OffscreenRenderError: LocalizedError {
    case metalUnavailable
    case sizeTooLarge(CGSize)
    case pixelBufferFailed
    case textureFailed
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .metalUnavailable:
            return "Metal is not available on this Mac."
        case .sizeTooLarge(let size):
            return "Output size \(Int(size.width))×\(Int(size.height)) exceeds the GPU texture limit of \(OffscreenSceneRenderer.maxTextureDimension) px."
        case .pixelBufferFailed:
            return "Could not allocate a pixel buffer for rendering."
        case .textureFailed:
            return "Could not create a Metal texture for the frame buffer."
        case .renderFailed(let message):
            return "Render failed: \(message)"
        }
    }
}

/// Everything needed to render the backdrop gradient off the main actor.
/// CIContext/CIImage are immutable and thread-safe; the destination is used
/// by exactly one task.
private struct GradientRenderJob: @unchecked Sendable {
    let context: CIContext
    let image: CIImage
    let bounds: CGRect
    let destination: CIRenderDestination

    func run() throws {
        let task = try context.startTask(toRender: image, from: bounds, to: destination, at: .zero)
        try task.waitUntilCompleted()
    }
}

@MainActor
final class OffscreenSceneRenderer {
    nonisolated static let maxTextureDimension = 16384

    /// Immutable inputs snapshot for one render session. Colors are resolved
    /// sRGB so output matches the preview regardless of appearance changes.
    struct Inputs {
        var device: Device = .iPhone
        var finish: PhoneFinish
        var displayImage: CGImage?
        var backgroundTop: NSColor
        var backgroundBottom: NSColor
    }

    let outputSize: CGSize

    // Metal / CoreImage
    private let device: MTLDevice
    private let ciContext: CIContext
    private var pixelBufferPool: CVPixelBufferPool?
    private var textureCache: CVMetalTextureCache?
    private let doneEvent: MTLSharedEvent
    private let eventListener: MTLSharedEventListener
    private var frameCounter: UInt64 = 0

    // RealityKit
    private var realityRenderer: RealityRenderer
    private let scene = PhoneScene()
    private var deviceKind: Device = .iPhone
    private var lidRig: MacBookLidRig?
    private var displayTexture: TextureResource?
    private var displayAverageColor: NSColor?
    private var lastDisplayImage: CGImage?
    private var currentFinish: PhoneFinish?
    private var lastAppliedGlow: Float = 0
    private var lastAppliedColor: NSColor?

    // Studio backdrop gradient (resolution-exact, built once per inputs change)
    private var gradientImage: CIImage
    private let gradientScale: CGFloat

    // MARK: - Init

    /// - Parameters:
    ///   - outputSize: Output size in *pixels* (any size up to 16384², even if
    ///     the screen is smaller — this is fully offscreen).
    ///   - previewPointSize: Preview size in points, used to scale the backdrop
    ///     gradient so the render matches what the user sees.
    ///   - inputs: Finish, display screenshot and background colors.
    init(outputSize: CGSize, previewPointSize: CGSize, inputs: Inputs) async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw OffscreenRenderError.metalUnavailable
        }
        let width = Int(outputSize.width)
        let height = Int(outputSize.height)
        guard width > 0, height > 0,
              width <= Self.maxTextureDimension, height <= Self.maxTextureDimension else {
            throw OffscreenRenderError.sizeTooLarge(outputSize)
        }
        guard let doneEvent = device.makeSharedEvent() else {
            throw OffscreenRenderError.metalUnavailable
        }

        // Pixel buffer pool: IOSurface-backed + Metal-compatible so buffers go
        // straight from RealityKit's render target to AVAssetWriter's encoder.
        let poolAttrs: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 4
        ]
        let bufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        var pool: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs as CFDictionary, bufferAttrs as CFDictionary, &pool) == kCVReturnSuccess,
              let pool else {
            throw OffscreenRenderError.pixelBufferFailed
        }

        var cache: CVMetalTextureCache?
        let textureAttrs = [kCVMetalTextureUsage: NSNumber(value: MTLTextureUsage([.renderTarget, .shaderRead]).rawValue)] as CFDictionary
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, textureAttrs, &cache) == kCVReturnSuccess,
              let cache else {
            throw OffscreenRenderError.textureFailed
        }

        // Scale the 560 pt radial highlight into output pixels so the backdrop
        // looks identical to the preview at any output resolution.
        let gradientScale = CGFloat(height) / max(previewPointSize.height, 1)

        // Assign every stored property before touching self's methods/objects.
        self.outputSize = CGSize(width: width, height: height)
        self.device = device
        self.ciContext = CIContext(mtlDevice: device, options: [
            .cacheIntermediates: false,
            .allowLowPower: false
        ])
        self.pixelBufferPool = pool
        self.textureCache = cache
        self.doneEvent = doneEvent
        self.eventListener = MTLSharedEventListener(dispatchQueue: DispatchQueue(label: "yommock.render.events"))
        self.gradientScale = gradientScale
        self.gradientImage = Self.makeGradient(
            top: inputs.backgroundTop,
            bottom: inputs.backgroundBottom,
            width: CGFloat(width),
            height: CGFloat(height),
            scale: gradientScale
        )

        // RealityRenderer: dedicated offscreen scene graph — the live preview
        // is never touched, so the UI stays fully interactive during export.
        let renderer = try RealityRenderer()
        renderer.cameraSettings.colorBackground = .outputTexture()
        self.realityRenderer = renderer
        self.deviceKind = inputs.device
        self.currentFinish = inputs.finish

        guard let bundleURL = Bundle.main.url(
            forResource: inputs.device.modelResource,
            withExtension: inputs.device.modelExtension
        ) else {
            throw OffscreenRenderError.renderFailed(
                "\(inputs.device.modelResource).\(inputs.device.modelExtension) missing from bundle")
        }
        let model = try await Entity(contentsOf: bundleURL)
        model.name = inputs.device.modelResource
        scene.phone = model
        scene.framePhone(model, targetSize: inputs.device.frameTargetSize)

        if let cg = inputs.displayImage {
            displayTexture = try? await TextureResource(
                image: cg,
                withName: "DisplayScreenshot-Offscreen",
                options: TextureResource.CreateOptions(
                    semantic: .color,
                    compression: .none,
                    mipmapsMode: .allocateAndGenerateAll
                )
            )
            lastDisplayImage = cg
            displayAverageColor = PhoneStyling.averageColor(from: cg)
        } else {
            displayAverageColor = nil
        }
        PhoneStyling.liftKeyboardLegends(on: model)
        PhoneStyling.applyMaterials(to: model, device: inputs.device, finish: inputs.finish, displayTexture: displayTexture, lidGlow: lidRig?.glowFactor ?? 0, displayAverageColor: displayAverageColor)
        lastAppliedColor = displayAverageColor
        PhoneStyling.applyGroundingShadows(to: model)
        renderer.entities.append(model)

        // MacBook: hinge rig so the lid can close (screen spill on the
        // keyboard is applied via materials with the rig's glowFactor).
        if inputs.device == .macBookPro {
            lidRig = MacBookLidRig.install(on: model)
            lidRig?.displayOn = displayTexture != nil
        }

        let camera = PerspectiveCamera()
        camera.name = "ExportCamera"
        camera.camera.fieldOfViewInDegrees = PhoneScene.fieldOfView
        scene.camera = camera
        renderer.entities.append(camera)
        renderer.activeCamera = camera

        // Same studio IBL as the preview (intensityExponent -3), scene-wide.
        if let environment = try? await StudioEnvironment.resource() {
            renderer.lighting.resource = environment
            renderer.lighting.intensityExponent = -3.0
        }
    }

    // MARK: - Updates (cheap — used by still-frame export between renders)

    /// Re-applies finish / display image / backdrop colors. Recreates the
    /// display texture only when the image actually changed. The device is
    /// fixed per renderer instance — callers recreate the renderer when it
    /// changes (model load is async and expensive).
    func update(inputs: Inputs) async {
        if let cg = inputs.displayImage, cg !== lastDisplayImage {
            displayTexture = try? await TextureResource(
                image: cg,
                withName: "DisplayScreenshot-Offscreen",
                options: TextureResource.CreateOptions(
                    semantic: .color,
                    compression: .none,
                    mipmapsMode: .allocateAndGenerateAll
                )
            )
            lastDisplayImage = cg
            displayAverageColor = PhoneStyling.averageColor(from: cg)
        } else if inputs.displayImage == nil {
            displayTexture = nil
            lastDisplayImage = nil
            displayAverageColor = nil
        }
        if let model = scene.phone {
            let glow = lidRig?.glowFactor ?? 0
            let colorChanged = displayAverageColor != lastAppliedColor
            if abs(glow - lastAppliedGlow) > 0.004 || colorChanged {
                PhoneStyling.applyMaterials(to: model, device: deviceKind, finish: inputs.finish, displayTexture: displayTexture, lidGlow: glow, displayAverageColor: displayAverageColor)
                lastAppliedGlow = glow
                lastAppliedColor = displayAverageColor
            }
        }
        lidRig?.displayOn = displayTexture != nil
        currentFinish = inputs.finish
        gradientImage = Self.makeGradient(
            top: inputs.backgroundTop,
            bottom: inputs.backgroundBottom,
            width: outputSize.width,
            height: outputSize.height,
            scale: gradientScale
        )
    }

    // MARK: - Rendering

    /// Renders one frame and returns the pixel buffer containing it.
    /// The buffer stays valid until the caller releases it (AVAssetWriter
    /// retains it until encoding completes); the pool recycles buffers.
    func render(orbit: OrbitPose, zoom: Float, pan: SIMD3<Float>, lidAngle: Float = MacBookLidRig.defaultOpenAngle, deltaTime: TimeInterval) async throws -> CVPixelBuffer {
        guard let pool = pixelBufferPool, let textureCache else {
            throw OffscreenRenderError.pixelBufferFailed
        }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw OffscreenRenderError.pixelBufferFailed
        }

        var cvTexture: CVMetalTexture?
        let width = Int(outputSize.width)
        let height = Int(outputSize.height)
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTexture
        ) == kCVReturnSuccess,
              let cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            throw OffscreenRenderError.textureFailed
        }

        frameCounter &+= 1
        let frameValue = frameCounter

        // 1) Studio gradient into the pixel buffer. CIContext cannot render
        //    into MTLTexture destinations on macOS 26 ("The destination is
        //    nil" — silently producing transparent frames), so render into
        //    the buffer's IOSurface instead. The wait runs off the main
        //    actor; its completion also orders the gradient's GPU writes
        //    before RealityKit renders over the texture below.
        guard let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else {
            throw OffscreenRenderError.pixelBufferFailed
        }
        let destination = CIRenderDestination(ioSurface: surface)
        destination.colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let gradientJob = GradientRenderJob(
            context: ciContext,
            image: gradientImage,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            destination: destination
        )
        do {
            try await Task.detached(priority: .userInitiated) { try gradientJob.run() }.value
        } catch {
            throw OffscreenRenderError.renderFailed(error.localizedDescription)
        }

        // 2) Camera pose + lid on the offscreen scene, then render over the gradient.
        scene.apply(orbit: orbit, zoom: zoom, pan: pan)
        if let lidRig {
            lidRig.setLidAngle(lidAngle)
            // Screen-spill emissive follows the lid — re-apply when it moved.
            let glow = lidRig.glowFactor
            if abs(glow - lastAppliedGlow) > 0.004, let model = scene.phone, let finish = currentFinish {
                PhoneStyling.applyMaterials(
                    to: model, device: deviceKind, finish: finish,
                    displayTexture: displayTexture, lidGlow: glow, displayAverageColor: displayAverageColor)
                lastAppliedGlow = glow
            }
        }
        let output = try RealityRenderer.CameraOutput(
            .singleProjection(colorTexture: texture)
        )
        do {
            try realityRenderer.updateAndRender(
                deltaTime: deltaTime,
                cameraOutput: output,
                actionsBeforeRender: [],
                actionsAfterRender: [.signal(doneEvent, value: frameValue)]
            )
        } catch {
            throw OffscreenRenderError.renderFailed(error.localizedDescription)
        }

        // 3) Wait for the GPU to finish without blocking the main actor.
        await waitForEvent(doneEvent, value: frameValue)
        return pixelBuffer
    }

    /// Creates a CGImage from a rendered pixel buffer (for PNG still export).
    /// Copies the BGRA bytes straight out of the buffer — no CoreImage: any
    /// CI render of this IOSurface-backed image at large sizes can silently
    /// fail on some tiles in headless/test processes ("destination is nil"),
    /// leaving black regions. The GPU is done by the time render() returns
    /// (doneEvent), and the Data copy keeps the image valid after the pool
    /// recycles the buffer.
    func makeCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let data = Data(bytes: base, count: bytesPerRow * height)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            // kCVPixelFormatType_32BGRA = little-endian 32-bit, B first.
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGImageByteOrderInfo.order32Little.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// Test hook: the loaded device model (for mesh-level render assertions).
    var modelEntityForTesting: Entity? { scene.phone }

    // MARK: - Helpers

    private func waitForEvent(_ event: MTLSharedEvent, value: UInt64) async {
        if event.signaledValue >= value { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            final class ResumeBox: @unchecked Sendable {
                var resumed = false
                let lock = NSLock()
                let cont: CheckedContinuation<Void, Never>
                init(_ cont: CheckedContinuation<Void, Never>) { self.cont = cont }
                func resume() {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !resumed else { return }
                    resumed = true
                    cont.resume()
                }
            }
            let box = ResumeBox(cont)
            event.notify(eventListener, atValue: value) { _, _ in box.resume() }
            // Re-check in case the event fired between the check and notify.
            if event.signaledValue >= value { box.resume() }
        }
    }

    /// Recreates the SwiftUI `StudioBackdrop`: a vertical linear gradient with
    /// a soft radial highlight in the middle — resolution-independent.
    private static func makeGradient(top: NSColor, bottom: NSColor, width: CGFloat, height: CGFloat, scale: CGFloat) -> CIImage {
        let topCI = CIColor(color: top) ?? CIColor(red: 1, green: 1, blue: 1)
        let bottomCI = CIColor(color: bottom) ?? CIColor(red: 0.9, green: 0.9, blue: 0.9)

        // CoreImage is bottom-up: top color at y = height.
        let linear = CIFilter(
            name: "CILinearGradient",
            parameters: [
                kCIInputPoint0Key: CIVector(x: 0, y: height),
                kCIInputPoint1Key: CIVector(x: 0, y: 0),
                "inputColor0": topCI,
                "inputColor1": bottomCI
            ]
        )?.outputImage ?? CIImage(color: topCI)

        let highlight = CIFilter(
            name: "CIRadialGradient",
            parameters: [
                kCIInputCenterKey: CIVector(x: width / 2, y: height / 2),
                "inputRadius0": 0,
                "inputRadius1": max(1, 560 * scale),
                "inputColor0": CIColor(red: topCI.red, green: topCI.green, blue: topCI.blue, alpha: 0.4),
                "inputColor1": CIColor(red: topCI.red, green: topCI.green, blue: topCI.blue, alpha: 0)
            ]
        )?.outputImage ?? CIImage(color: .clear)

        return highlight
            .composited(over: linear)
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }
}
