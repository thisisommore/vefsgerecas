//
//  ContentView.swift
//  YomMock
//
//  Created by Om More on 14/08/26.
//

import AppKit
import RealityKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var status: String?
    @State private var selectedColor: iPhoneColor = .black
    @State private var customColor = Color(red: 0.78, green: 0.32, blue: 0.36)
    @State private var background: StudioBackground = .white
    @State private var customBackground = Color.white
    @State private var zoom: Float = 1
    @State private var cameraReady = false
    @State private var userMovedCamera = false
    @State private var scene = PhoneScene()
    @State private var timeline = CameraTimeline()
    @State private var zoomAnimationTask: Task<Void, Never>?
    @State private var displayImage: NSImage?
    @State private var displayTexture: TextureResource?
    @State private var displayFileName: String?
    @State private var displayStatus: String?
    @State private var displayLoadTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                InspectorPanel(
                    selectedColor: $selectedColor,
                    customColor: $customColor,
                    background: $background,
                    customBackground: $customBackground,
                    displayImage: $displayImage,
                    displayFileName: $displayFileName,
                    displayStatus: $displayStatus
                )
                .frame(width: 268)
            }
            .frame(minHeight: 330)

            Divider()

            TimelineBar(
                timeline: timeline,
                cameraAvailable: cameraReady,
                onSaveCheckpoint: saveCheckpoint
            )
            .frame(height: 148)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: selectedColor) { _, _ in
            refreshMaterials()
        }
        .onChange(of: customColor) { _, _ in
            refreshMaterials()
        }
        .onChange(of: background) { _, _ in }
        .onChange(of: customBackground) { _, _ in }
        .onChange(of: zoom) { _, value in
            guard !timeline.isPlaying else { return }
            scene.zoom = value
            scene.applyZoom()
        }
        .onChange(of: displayImage) { _, newImage in
            setDisplayScreenshot(newImage)
        }
    }

    private var preview: some View {
        ZStack {
            StudioBackdrop(background: background, customColor: customBackground)
            RealityView { content in
                content.camera = .virtual
                content.environment = .default

                let camera = PerspectiveCamera()
                camera.name = "StudioCamera"
                camera.camera.fieldOfViewInDegrees = PhoneScene.fieldOfView
                camera.look(at: .zero, from: OrbitPose.default.position, relativeTo: nil)
                scene.camera = camera
                cameraReady = true
                content.add(camera)

                let url = Bundle.main.url(forResource: "iPhone17", withExtension: "usdz")!

                do {
                    let phone = try await Entity(contentsOf: url)
                    phone.name = "iPhone"
                    scene.phone = phone
                    frame(phone, targetSize: 0.05)
                    applyPhoneMaterials(
                        to: phone,
                        finish: selectedColor.finish(custom: customColor)
                    )
                    applyGroundingShadows(to: phone)

                    let ibl = Entity()
                    ibl.name = "IBL"
                    if let environment = try? await StudioEnvironment.resource() {
                        ibl.components.set(
                            ImageBasedLightComponent(
                                source: .single(environment), intensityExponent: -3.0)
                        )
                    }
                    content.add(ibl)
                    applyIBLReceiver(to: phone, ibl: ibl)

                    content.add(phone)
                    // Don't set cameraTarget — orbit controls use the target
                    // bounds to pick a tight starting distance.
                    scene.apply(orbit: .default, zoom: zoom)
                } catch {
                    status = error.localizedDescription
                }
            } update: { content in
                bindCamera(from: content)
                guard !timeline.isPlaying else { return }
                holdStudioFramingIfNeeded()
            }
            .realityViewCameraControls(timeline.isPlaying ? .none : .orbit)
            .background {
                ScrollZoomCatcher { event in
                    guard !timeline.isPlaying else { return }
                    userMovedCamera = true
                    animateZoom(to: PhoneScene.adjustedZoom(from: zoom, event: event))
                }
            }

            TimelinePlaybackDriver(timeline: timeline, apply: applyEvaluatedPose)

            if let status {
                Text(status)
                    .foregroundStyle(.red)
                    .padding()
            }

            if let displayStatus {
                Text(displayStatus)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 10)
            }
        }
        .clipped()
        .onDrop(of: [.fileURL, .image], isTargeted: nil, perform: handlePreviewDrop)
    }

    /// Smoothly eases the camera zoom toward a target with a strong ease-out
    /// curve. Each new scroll event retargets the animation from the current
    /// value, so rapid scrolling chases the target instead of jumping.
    private func animateZoom(to target: Float) {
        zoomAnimationTask?.cancel()
        let start = zoom
        let duration: TimeInterval = 0.7
        let startTime = CACurrentMediaTime()
        zoomAnimationTask = Task { @MainActor in
            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - startTime
                let t = min(Float(elapsed / duration), 1)
                // Strong ease-out: quintic curve for a long, gentle settle.
                let eased = 1 - pow(1 - t, 5)
                zoom = start + (target - start) * eased
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }

    private func saveCheckpoint() {
        scene.syncPoseFromCamera(zoom: zoom)
        timeline.saveCheckpoint(
            at: timeline.currentTime,
            pose: scene.captureOrbitPose(),
            zoom: zoom
        )
    }

    private func applyEvaluatedPose() {
        let state = timeline.evaluatedState()
        scene.apply(orbit: state.orbit, zoom: state.zoom)
        if zoom != state.zoom {
            zoom = state.zoom
        }
    }

    private func holdStudioFramingIfNeeded() {
        scene.syncPoseFromCamera(zoom: zoom)
        if !userMovedCamera {
            let live = scene.orbitPose
            let studio = OrbitPose.default
            var yawDelta = live.yaw - studio.yaw
            if yawDelta > .pi { yawDelta -= 2 * .pi }
            if yawDelta < -.pi { yawDelta += 2 * .pi }
            // Orbit auto-fit mostly changes radius. Treat a real yaw/pitch
            // change as the user taking over; otherwise keep the studio shot.
            if abs(yawDelta) > 0.08 || abs(live.pitch - studio.pitch) > 0.08 {
                userMovedCamera = true
            } else {
                scene.apply(orbit: studio, zoom: zoom)
                return
            }
        }
        timeline.seedBasePoseIfDefault(scene.orbitPose)
    }

    private func refreshMaterials() {
        guard let phone = scene.phone else { return }
        applyPhoneMaterials(to: phone, finish: selectedColor.finish(custom: customColor))
    }

    private func setDisplayScreenshot(_ image: NSImage?) {
        displayLoadTask?.cancel()
        displayStatus = nil
        guard let image else {
            displayTexture = nil
            refreshMaterials()
            return
        }
        displayLoadTask = Task { @MainActor in
            do {
                let cgImage = try Self.cgImage(from: image)
                let texture = try await TextureResource(
                    image: cgImage,
                    withName: "DisplayScreenshot",
                    options: TextureResource.CreateOptions(
                        semantic: .color,
                        mipmapsMode: .allocateAndGenerateAll
                    )
                )
                guard !Task.isCancelled else { return }
                displayTexture = texture
                refreshMaterials()
            } catch {
                guard !Task.isCancelled else { return }
                displayStatus = error.localizedDescription
                displayTexture = nil
                refreshMaterials()
            }
        }
    }

    private static func cgImage(from nsImage: NSImage) throws -> CGImage {
        var rect = NSRect(origin: .zero, size: nsImage.size)
        if let cg = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return cg
        }
        guard let tiff = nsImage.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let cg = rep.cgImage
        else {
            throw CocoaError(
                .fileReadCorruptFile,
                userInfo: [NSLocalizedDescriptionKey: "Could not convert image to CGImage."])
        }
        return cg
    }

    private func handlePreviewDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier("public.file-url") {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let string = item as? String {
                    url = URL(string: string)
                } else if let itemURL = item as? URL {
                    url = itemURL
                }
                guard let url, let image = NSImage(contentsOf: url) else { return }
                Task { @MainActor in
                    displayFileName = url.lastPathComponent
                    displayImage = image
                }
            }
            return true
        }
        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else { return }
                Task { @MainActor in
                    displayFileName = "Pasted image"
                    displayImage = image
                }
            }
            return true
        }
        return false
    }

    private func bindCamera(from content: RealityViewCameraContent) {
        // Only inspect root entities — cameras live there. Walking the USDZ
        // would redo a full scene traversal every update.
        for entity in content.entities {
            guard var perspective = entity.components[PerspectiveCameraComponent.self] else {
                continue
            }
            scene.camera = entity
            if abs(perspective.fieldOfViewInDegrees - PhoneScene.fieldOfView) > 0.01 {
                perspective.fieldOfViewInDegrees = PhoneScene.fieldOfView
                entity.components.set(perspective)
            }
        }
        if !cameraReady, scene.camera != nil {
            cameraReady = true
        }
    }

    private func frame(_ entity: Entity, targetSize: Float) {
        let bounds = entity.visualBounds(relativeTo: nil)
        let maxDim = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        guard maxDim > 0 else { return }
        scene.baseScale = targetSize / maxDim
        scene.modelCenter = bounds.center
        scene.zoom = zoom
        scene.applyZoom()
    }

    private func applyPhoneMaterials(to entity: Entity, finish: PhoneFinish) {
        if var model = entity.components[ModelComponent.self] {
            let material = material(for: entity.name, finish: finish)
            model.materials = Array(repeating: material, count: max(model.materials.count, 1))
            entity.components.set(model)
        }
        for child in entity.children {
            applyPhoneMaterials(to: child, finish: finish)
        }
    }

    private func applyIBLReceiver(to entity: Entity, ibl: Entity) {
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
        for child in entity.children {
            applyIBLReceiver(to: child, ibl: ibl)
        }
    }

    private func applyGroundingShadows(to entity: Entity) {
        if entity.components.has(ModelComponent.self) {
            entity.components.set(
                GroundingShadowComponent(castsShadow: true, receivesShadow: false))
        }
        for child in entity.children {
            applyGroundingShadows(to: child)
        }
    }

    private func material(for name: String, finish: PhoneFinish) -> PhysicallyBasedMaterial {
        let key = name.lowercased()

        if key.contains("screen") && !key.contains("glass") && !key.contains("edge") {
            if let displayTexture {
                return screenMaterial(with: displayTexture)
            }
            return pbr(
                color: NSColor(calibratedWhite: 0.015, alpha: 1),
                metallic: 0,
                roughness: 0.018,
                specular: 1,
                clearcoat: 1,
                clearcoatRoughness: 0.012
            )
        }
        if key.contains("screen_edge") || (key.contains("screen") && key.contains("edge")) {
            return pbr(
                color: NSColor(calibratedWhite: 0.025, alpha: 1),
                metallic: 0.08,
                roughness: 0.22,
                specular: 0.55
            )
        }
        // The cover glass sits directly in front of the LCD (Mesh_013_Glass_Screen).
        // When a screenshot is active it must be transparent, otherwise the opaque
        // dark glass hides the textured 043_Screen plane behind it.
        if key.contains("glass_screen") {
            if displayTexture != nil {
                var material = PhysicallyBasedMaterial()
                material.baseColor = .init(tint: NSColor(white: 1, alpha: 0))
                material.metallic = .init(floatLiteral: 0)
                material.roughness = .init(floatLiteral: 0.015)
                material.specular = .init(floatLiteral: 1)
                material.clearcoat = .init(floatLiteral: 1)
                material.clearcoatRoughness = .init(floatLiteral: 0.015)
                material.blending = .transparent(opacity: 0.0)
                return material
            }
            // No screenshot — keep the original dark glass so the off-screen looks correct.
            return pbr(
                color: NSColor(calibratedRed: 0.03, green: 0.032, blue: 0.036, alpha: 1),
                metallic: 0,
                roughness: 0.028,
                specular: 1,
                clearcoat: 1,
                clearcoatRoughness: 0.02
            )
        }
        if key.contains("glass_back")
            || key.contains("glass_rough")
            || key.contains("matte")
            || (key.contains("back") && !key.contains("antenna"))
        {
            let roughBack = key.contains("glass_rough") || key.contains("matte")
            return pbr(
                color: finish.back,
                metallic: roughBack ? max(finish.backMetallic - 0.06, 0.08) : finish.backMetallic,
                roughness: roughBack ? max(finish.backRoughness, 0.32) : finish.backRoughness,
                specular: 1,
                clearcoat: roughBack ? 0.4 : finish.backClearcoat,
                clearcoatRoughness: roughBack ? 0.26 : 0.028
            )
        }
        if key.contains("glass") {
            return pbr(
                color: NSColor(calibratedRed: 0.03, green: 0.032, blue: 0.036, alpha: 1),
                metallic: 0,
                roughness: 0.028,
                specular: 1,
                clearcoat: 1,
                clearcoatRoughness: 0.02
            )
        }
        if key.contains("lens") {
            return pbr(
                color: NSColor(calibratedWhite: 0.012, alpha: 1),
                metallic: 0.04,
                roughness: 0.012,
                specular: 1,
                clearcoat: 1,
                clearcoatRoughness: 0.01
            )
        }
        if key.contains("flash") {
            return pbr(
                color: NSColor(calibratedRed: 0.94, green: 0.93, blue: 0.88, alpha: 1),
                metallic: 0,
                roughness: 0.3,
                specular: 0.68,
                emissive: NSColor(calibratedRed: 0.95, green: 0.93, blue: 0.86, alpha: 1),
                emissiveIntensity: 0.12
            )
        }
        if key.contains("logo") {
            return pbr(
                color: NSColor(calibratedWhite: 0.66, alpha: 1),
                metallic: 1,
                roughness: 0.16,
                specular: 1,
                anisotropy: 0.28
            )
        }
        if key.contains("antenna") {
            return pbr(
                color: NSColor(calibratedRed: 0.18, green: 0.185, blue: 0.195, alpha: 1),
                metallic: 0.72,
                roughness: 0.3
            )
        }
        if key.contains("plastic") || key.contains("black") || key.contains("mic") {
            return pbr(
                color: NSColor(calibratedWhite: 0.035, alpha: 1),
                metallic: 0,
                roughness: 0.4,
                specular: 0.28
            )
        }
        if key.contains("edge") || key.contains("gray") {
            return pbr(
                color: finish.frame,
                metallic: 1,
                roughness: 0.2,
                specular: 1,
                clearcoat: 0.18,
                clearcoatRoughness: 0.12,
                anisotropy: 0.3
            )
        }

        return pbr(
            color: finish.frame,
            metallic: 1,
            roughness: 0.22,
            specular: 1,
            anisotropy: 0.26
        )
    }

    private func pbr(
        color: NSColor,
        metallic: Float,
        roughness: Float,
        specular: Float = 0.5,
        clearcoat: Float = 0,
        clearcoatRoughness: Float = 0.1,
        anisotropy: Float = 0,
        emissive: NSColor? = nil,
        emissiveIntensity: Float = 0
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.metallic = .init(floatLiteral: metallic)
        material.roughness = .init(floatLiteral: roughness)
        material.specular = .init(floatLiteral: specular)
        material.clearcoat = .init(floatLiteral: clearcoat)
        material.clearcoatRoughness = .init(floatLiteral: clearcoatRoughness)
        if anisotropy > 0 {
            material.anisotropyLevel = .init(floatLiteral: anisotropy)
            material.anisotropyAngle = .init(floatLiteral: 0.25)
        }
        if let emissive, emissiveIntensity > 0 {
            material.emissiveColor = .init(color: emissive)
            material.emissiveIntensity = emissiveIntensity
        }
        return material
    }

    private func screenMaterial(with texture: TextureResource) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        let tex = MaterialParameters.Texture(texture)
        material.baseColor = .init(texture: tex)
        // Keep a hint of physical response so the screen still reads as glass
        // under the studio lights, but let the image dominate.
        material.metallic = .init(floatLiteral: 0)
        material.roughness = .init(floatLiteral: 0.02)
        material.specular = .init(floatLiteral: 0.08)
        material.clearcoat = .init(floatLiteral: 0.95)
        material.clearcoatRoughness = .init(floatLiteral: 0.08)
        // Brighter emissive so the screenshot reads like a lit display
        // even when angled away from the key light.
        material.emissiveColor = .init(texture: tex)
        material.emissiveIntensity = 1.4
        return material
    }
}

final class PhoneScene {
    static let fieldOfView: Float = 100
    static let minZoom: Float = 0.06
    static let maxZoom: Float = 21

    var camera: Entity?
    var phone: Entity?
    var floor: Entity?
    var orbitPose = OrbitPose.default
    var zoom: Float = 1
    var baseScale: Float = 1
    var modelCenter = SIMD3<Float>.zero

    func apply(orbit: OrbitPose, zoom: Float) {
        orbitPose = orbit
        self.zoom = zoom
        applyCamera(from: orbit.position)
        applyZoom()
    }

    func syncPoseFromCamera(zoom: Float) {
        guard let camera else { return }
        let position = camera.position(relativeTo: nil)
        guard simd_length(position) > 1e-4 else { return }
        orbitPose = OrbitPose(position: position)
        self.zoom = zoom
    }

    func captureOrbitPose() -> OrbitPose {
        orbitPose
    }

    static func adjustedZoom(from zoom: Float, event: NSEvent) -> Float {
        guard event.momentumPhase.isEmpty else { return zoom }
        let raw = Float(event.scrollingDeltaY)
        guard abs(raw) > 0.01 else { return zoom }
        let units = event.hasPreciseScrollingDeltas ? raw / 50 : raw
        let step = min(max(units, -1), 1)
        return min(max(zoom * exp(step * 0.04), minZoom), maxZoom)
    }

    private func applyCamera(from position: SIMD3<Float>) {
        guard let camera else { return }
        if var perspective = camera.components[PerspectiveCameraComponent.self],
            abs(perspective.fieldOfViewInDegrees - Self.fieldOfView) > 0.01
        {
            perspective.fieldOfViewInDegrees = Self.fieldOfView
            camera.components.set(perspective)
        }
        camera.look(at: .zero, from: position, relativeTo: nil)
    }

    func applyZoom() {
        guard let phone else { return }
        let scale = baseScale * zoom
        guard scale > 0 else { return }
        phone.scale = SIMD3(repeating: scale)
        phone.position = -modelCenter * scale
        if let floor {
            let bounds = phone.visualBounds(relativeTo: nil)
            floor.position = [0, bounds.min.y - 0.0004, 0]
        }
    }
}

/// Observes scroll-wheel / trackpad scroll without intercepting orbit drags.
private struct ScrollZoomCatcher: NSViewRepresentable {
    var onScroll: (NSEvent) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onScroll = onScroll
    }

    final class MonitorView: NSView {
        var onScroll: ((NSEvent) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installMonitor()
        }

        deinit {
            removeMonitor()
        }

        private func installMonitor() {
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                [weak self] event in
                guard let self, event.window === self.window else { return event }
                let location = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(location) else { return event }
                self.onScroll?(event)
                return nil
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

/// Configurable studio backdrop behind the 3D scene. Defaults to white,
/// independent of the device appearance theme.
private struct StudioBackdrop: View {
    var background: StudioBackground
    var customColor: Color

    var body: some View {
        let colors = background.gradient(custom: customColor)
        return ZStack {
            LinearGradient(
                colors: [colors.top, colors.bottom],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [colors.top.opacity(0.4), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 560
            )
        }
        .ignoresSafeArea()
    }
}

/// Drives playhead ticks and pose apply without invalidating the RealityView
/// on every frame — ContentView must not read `currentTime` in its body.
private struct TimelinePlaybackDriver: View {
    @Bindable var timeline: CameraTimeline
    var apply: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: timeline.currentTime) { _, _ in
                if !timeline.isPlaying {
                    apply()
                }
            }
            .onChange(of: timeline.isPlaying) { _, playing in
                if playing {
                    apply()
                }
            }
            .task(id: timeline.isPlaying) {
                guard timeline.isPlaying else { return }
                var last = CACurrentMediaTime()
                while !Task.isCancelled, timeline.isPlaying {
                    let now = CACurrentMediaTime()
                    timeline.advance(by: now - last)
                    last = now
                    apply()
                    try? await Task.sleep(for: .milliseconds(8))
                }
            }
    }
}

#Preview {
    ContentView()
}
