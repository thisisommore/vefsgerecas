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
    @Bindable var store: YomMockStore
    @State private var status: String?
    @State private var cameraReady = false
    @State private var userMovedCamera = false
    @State private var previewViewBox = PreviewViewBox()
    @State private var scene = PhoneScene()
    @State private var zoomAnimationTask: Task<Void, Never>?
    @State private var displayTexture: TextureResource?
    @State private var displayAverageColor: NSColor?
    @State private var displayStatus: String?
    @State private var displayLoadTask: Task<Void, Never>?
    @EnvironmentObject private var unsavedGuard: UnsavedChangesGuard

    var body: some View {
        mainContent
        .task {
            if store.displayImage == nil {
                loadDefaultDisplayImage(for: store.device)
            }
            store.frameCaptureViewProvider = { [previewViewBox] in previewViewBox.view }
            updateWindowTitle()
        }
        .onChange(of: store.isDirty) { _, _ in updateWindowTitle() }
        .onChange(of: store.projectURL) { _, _ in
            updateWindowTitle()
            applyEvaluatedPose()
            refreshMaterials()
        }
        .onAppear { updateWindowTitle() }
        .alert("Error", isPresented: Binding(get: { store.projectError != nil }, set: { if !$0 { store.handleSaveErrorDismiss() } })) {
            Button("OK") { store.handleSaveErrorDismiss() }
        } message: {
            Text(store.projectError ?? "")
        }
        .overlay(alignment: .bottom) { exportSuccessOverlay }
        .overlay(alignment: .bottom) { videoExportOverlay }
        .overlay { videoFreezeOverlay }
        .sheet(isPresented: $store.showVideoOptions) {
            VideoExportOptionsView(store: store)
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                InspectorPanel(
                    device: $store.device,
                    lidAngle: $store.lidAngle,
                    selectedColor: $store.selectedColor,
                    customColor: $store.customColor,
                    background: $store.background,
                    customBackground: $store.customBackground,
                    displayImage: $store.displayImage,
                    displayFileName: $store.displayFileName,
                    displayStatus: $displayStatus
                )
                .frame(width: 210)
            }
            .frame(minHeight: 330)

            Divider()

            TimelineBar(
                timeline: store.timeline,
                cameraAvailable: cameraReady,
                onSaveCheckpoint: saveCheckpoint
            )
            .frame(height: 148)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: store.device) { oldDevice, newDevice in
            // Swap the bundled default screenshot when the user hasn't
            // overridden it; keep user-provided images across device switches.
            if store.displayFileName == oldDevice.defaultDisplayImageName {
                loadDefaultDisplayImage(for: newDevice)
            }
            store.markDirty()
        }
        .onChange(of: store.selectedColor) { _, _ in
            refreshMaterials()
            store.markDirty()
        }
        .onChange(of: store.customColor) { _, _ in
            refreshMaterials()
            store.markDirty()
        }
        .onChange(of: store.background) { _, _ in
            store.markDirty()
        }
        .onChange(of: store.customBackground) { _, _ in
            store.markDirty()
        }
        .onChange(of: store.zoom) { _, value in
            guard !store.timeline.isPlaying else { return }
            scene.zoom = value
            scene.applyZoom()
            store.markDirty()
        }
        .onChange(of: store.lidAngle) { _, value in
            scene.applyLidAngle(value)
            refreshMaterials()
            store.markDirty()
        }
        .onChange(of: store.displayImage) { _, newImage in
            setDisplayScreenshot(newImage)
            store.markDirtyForImageChange()
        }
        .onChange(of: store.timeline.checkpoints) { _, _ in
            store.markDirty()
        }
        .onChange(of: store.timeline.duration) { _, _ in
            store.markDirty()
        }
    }

    private func updateWindowTitle() {
        DispatchQueue.main.async {
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                window.title = store.windowTitleWithStar
                window.isDocumentEdited = store.isDirty
            }
        }
    }

    /// Loads the bundled default screenshot for a device (iphone_home.jpg /
    /// mac_home.jpg) — used at launch and when switching devices before the
    /// user has supplied their own image.
    private func loadDefaultDisplayImage(for device: Device) {
        let name = device.defaultDisplayImageName
        let url = Bundle.main.url(forResource: name, withExtension: nil)
            ?? Bundle.main.url(
                forResource: name.replacingOccurrences(of: ".jpg", with: ""), withExtension: "jpg")
        guard let url, let img = NSImage(contentsOf: url) else { return }
        store.displayFileName = name
        store.displayImage = img
    }

    @ViewBuilder
    private var exportSuccessOverlay: some View {
        if store.showExportSuccess {
            ExportSuccessToast(store: store)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: store.showExportSuccess)
        }
    }

    @ViewBuilder
    private var videoExportOverlay: some View {
        ZStack {
            if store.isExportingVideo {
                // Freeze HUD moved to full-screen videoFreezeOverlay; keep bottom empty while exporting
                Color.clear
            } else if store.showVideoSuccess {
                VideoExportSuccessToast(store: store)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: store.isExportingVideo)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: store.showVideoSuccess)
    }

    @ViewBuilder
    private var videoFreezeOverlay: some View {
        if store.isExportingVideo {
            // Offscreen GPU rendering never touches the window, so the UI stays
            // fully interactive — the HUD is just a floating progress toast.
            VideoExportProgressHUD(progress: store.videoExportProgress) {
                store.cancelVideoExport()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: store.isExportingVideo)
        }
    }

    private var preview: some View {
        ZStack {
            StudioBackdrop(background: store.background, customColor: store.customBackground)
            FrameCaptureAnchor { [previewViewBox] view in
                previewViewBox.view = view
            }
            RealityView { content in
                content.camera = .virtual
                content.environment = .default

                let camera = PerspectiveCamera()
                camera.name = "StudioCamera"
                camera.camera.fieldOfViewInDegrees = PhoneScene.fieldOfView
                let startState = store.timeline.evaluatedState(at: 0)
                camera.look(at: .zero, from: startState.orbit.position, relativeTo: nil)
                scene.camera = camera
                scene.orbitPose = startState.orbit
                scene.zoom = startState.zoom
                scene.panOffset = startState.pan
                cameraReady = true
                content.add(camera)

                guard let url = Bundle.main.url(
                    forResource: store.device.modelResource,
                    withExtension: store.device.modelExtension
                ) else {
                    status = "\(store.device.modelResource).\(store.device.modelExtension) missing from bundle."
                    return
                }

                do {
                    let model = try await Entity(contentsOf: url)
                    model.name = store.device.modelResource
                    scene.phone = model
                    scene.framePhone(model, targetSize: store.device.frameTargetSize)
                    PhoneStyling.liftKeyboardLegends(on: model)
                    PhoneStyling.applyMaterials(
                        to: model,
                        device: store.device,
                        finish: store.selectedColor.finish(custom: store.customColor),
                        displayTexture: displayTexture,
                        lidGlow: scene.lidRig?.glowFactor ?? 0,
                        displayAverageColor: displayAverageColor
                    )
                    PhoneStyling.applyGroundingShadows(to: model)

                    if store.device == .macBookPro {
                        scene.lidRig = MacBookLidRig.install(on: model)
                        scene.lidRig?.displayOn = displayTexture != nil
                        scene.lidRig?.setLidAngle(store.lidAngle)
                        // Re-apply with lidGlow now that rig exists
                        if displayTexture != nil {
                            PhoneStyling.applyMaterials(
                                to: model,
                                device: store.device,
                                finish: store.selectedColor.finish(custom: store.customColor),
                                displayTexture: displayTexture,
                                lidGlow: scene.lidRig?.glowFactor ?? 0,
                                displayAverageColor: displayAverageColor
                            )
                        }
                    } else {
                        scene.lidRig = nil
                    }

                    let ibl = Entity()
                    ibl.name = "IBL"
                    if let environment = try? await StudioEnvironment.resource() {
                        ibl.components.set(
                            ImageBasedLightComponent(
                                source: .single(environment), intensityExponent: -3.0)
                        )
                    }
                    content.add(ibl)
                    applyIBLReceiver(to: model, ibl: ibl)

                    content.add(model)
                    // Don't set cameraTarget — orbit controls use the target
                    // bounds to pick a tight starting distance.
                    let initial = store.timeline.evaluatedState(at: 0)
                    scene.apply(orbit: initial.orbit, zoom: initial.zoom, pan: initial.pan)
                    Task { @MainActor in
                        if store.zoom != initial.zoom {
                            store.zoom = initial.zoom
                        }
                    }
                } catch {
                    status = error.localizedDescription
                }
            } update: { content in
                bindCamera(from: content)
                guard !store.timeline.isPlaying else { return }
                holdStudioFramingIfNeeded()
            }
            .realityViewCameraControls(.none)
            // Rebuild the whole scene when the device model changes.
            .id(store.device)
            .background {
                ZStack {
                    ScrollZoomCatcher { event in
                        guard !store.timeline.isPlaying else { return }
                        userMovedCamera = true
                        scene.hasUserInteracted = true
                        animateZoom(to: PhoneScene.adjustedZoom(from: store.zoom, event: event))
                    }
                    CameraPanCatcher(
                        onPan: { delta in
                            guard !store.timeline.isPlaying else { return }
                            userMovedCamera = true
                            scene.hasUserInteracted = true
                            scene.pan(by: delta)
                        },
                        onOrbit: { delta in
                            guard !store.timeline.isPlaying else { return }
                            userMovedCamera = true
                            scene.hasUserInteracted = true
                            scene.orbit(by: delta)
                        }
                    )
                    WASDZoomCatcher(
                        onZoomIn: {
                            guard !store.timeline.isPlaying else { return }
                            userMovedCamera = true
                            scene.hasUserInteracted = true
                            let target = min(store.zoom * Float(exp(0.08)), PhoneScene.maxZoom)
                            animateZoom(to: target)
                        },
                        onZoomOut: {
                            guard !store.timeline.isPlaying else { return }
                            userMovedCamera = true
                            scene.hasUserInteracted = true
                            let target = max(store.zoom * Float(exp(-0.08)), PhoneScene.minZoom)
                            animateZoom(to: target)
                        },
                        onRotateLeft: {
                            guard !store.timeline.isPlaying else { return }
                            userMovedCamera = true
                            scene.hasUserInteracted = true
                            scene.rotateYaw(by: -0.09)
                        },
                        onRotateRight: {
                            guard !store.timeline.isPlaying else { return }
                            userMovedCamera = true
                            scene.hasUserInteracted = true
                            scene.rotateYaw(by: 0.09)
                        }
                    )
                }
            }

            TimelinePlaybackDriver(timeline: store.timeline, apply: applyEvaluatedPose)

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
        let start = store.zoom
        let duration: TimeInterval = 0.7
        let startTime = CACurrentMediaTime()
        zoomAnimationTask = Task { @MainActor in
            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - startTime
                let t = min(Float(elapsed / duration), 1)
                // Strong ease-out: quintic curve for a long, gentle settle.
                let eased = 1 - pow(1 - t, 5)
                store.zoom = start + (target - start) * eased
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }

    private func saveCheckpoint() {
        scene.syncPoseFromCamera(zoom: store.zoom)
        store.timeline.saveCheckpoint(
            at: store.timeline.currentTime,
            pose: scene.captureOrbitPose(),
            zoom: store.zoom,
            pan: scene.panOffset,
            lidAngle: store.lidAngle
        )
        store.markDirty()
        updateWindowTitle()
    }

    private func applyEvaluatedPose() {
        let state = store.timeline.evaluatedState()
        scene.apply(orbit: state.orbit, zoom: state.zoom, pan: state.pan)
        scene.applyLidAngle(state.lidAngle)
        if store.device == .macBookPro {
            // Screen-spill emissive follows the lid angle.
            refreshMaterials()
        }
        if store.zoom != state.zoom {
            store.zoom = state.zoom
        }
        if store.lidAngle != state.lidAngle {
            store.lidAngle = state.lidAngle
        }
    }

    private func holdStudioFramingIfNeeded() {
        // Demo timeline has explicit checkpoints - show its start pose instead of holding studio default.
        if store.timeline.checkpoints.count > 1 {
            return
        }
        scene.syncPoseFromCamera(zoom: store.zoom)
        if !userMovedCamera && !scene.hasUserInteracted {
            let live = scene.orbitPose
            let studio = OrbitPose.default
            var yawDelta = live.yaw - studio.yaw
            if yawDelta > .pi { yawDelta -= 2 * .pi }
            if yawDelta < -.pi { yawDelta += 2 * .pi }
            // Orbit auto-fit mostly changes radius. Treat a real yaw/pitch
            // change as the user taking over; otherwise keep the studio shot.
            if abs(yawDelta) > 0.08 || abs(live.pitch - studio.pitch) > 0.08 {
                userMovedCamera = true
                scene.hasUserInteracted = true
            } else {
                scene.apply(orbit: studio, zoom: store.zoom, pan: .zero)
                return
            }
        }
        store.timeline.seedBasePoseIfDefault(scene.orbitPose)
    }

    private func refreshMaterials() {
        guard let model = scene.phone else { return }
        PhoneStyling.applyMaterials(
            to: model,
            device: store.device,
            finish: store.selectedColor.finish(custom: store.customColor),
            displayTexture: displayTexture,
            lidGlow: scene.lidRig?.glowFactor ?? 0,
            displayAverageColor: displayAverageColor
        )
    }

    private func setDisplayScreenshot(_ image: NSImage?) {
        displayLoadTask?.cancel()
        displayStatus = nil
        guard let image else {
            displayTexture = nil
            displayAverageColor = nil
            scene.lidRig?.displayOn = false
            refreshMaterials()
            return
        }
        // Compute average color synchronously for immediate spill tint
        if let cg = try? PhoneStyling.sRGBCGImage(from: image),
           let avg = PhoneStyling.averageColor(from: cg) {
            displayAverageColor = avg
        } else {
            displayAverageColor = nil
        }
        displayLoadTask = Task { @MainActor in
            do {
                let texture = try await PhoneStyling.displayTexture(from: image)
                guard !Task.isCancelled else { return }
                displayTexture = texture
                scene.lidRig?.displayOn = true
                refreshMaterials()
            } catch {
                guard !Task.isCancelled else { return }
                displayStatus = error.localizedDescription
                displayTexture = nil
                displayAverageColor = nil
                scene.lidRig?.displayOn = false
                refreshMaterials()
            }
        }
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
                    store.displayFileName = url.lastPathComponent
                    store.displayImage = image
                }
            }
            return true
        }
        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else { return }
                Task { @MainActor in
                    store.displayFileName = "Pasted image"
                    store.displayImage = image
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

    private func applyIBLReceiver(to entity: Entity, ibl: Entity) {
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
        for child in entity.children {
            applyIBLReceiver(to: child, ibl: ibl)
        }
    }
}

final class PhoneScene {
    static let fieldOfView: Float = 60
    static let minZoom: Float = 0.06
    static let maxZoom: Float = 21

    var camera: Entity?
    var phone: Entity?
    var floor: Entity?
    var lidRig: MacBookLidRig?
    var orbitPose = OrbitPose.default
    var zoom: Float = 1
    var baseScale: Float = 1
    var modelCenter = SIMD3<Float>.zero
    var panOffset = SIMD3<Float>.zero
    var hasUserInteracted = false

    func applyLidAngle(_ angle: Float) {
        lidRig?.setLidAngle(angle)
    }

    func apply(orbit: OrbitPose, zoom: Float, pan: SIMD3<Float> = .zero) {
        orbitPose = orbit
        self.zoom = zoom
        panOffset = pan
        applyCamera(from: orbit.position)
        applyZoom()
    }

    func applyWithCurrentPan(orbit: OrbitPose, zoom: Float) {
        apply(orbit: orbit, zoom: zoom, pan: panOffset)
    }

    func syncPoseFromCamera(zoom: Float) {
        guard let camera else { return }
        let position = camera.position(relativeTo: nil)
        guard simd_length(position) > 1e-4 else { return }
        orbitPose = OrbitPose(position: position)
        self.zoom = zoom
    }

    func rotateYaw(by delta: Float) {
        syncPoseFromCamera(zoom: zoom)
        hasUserInteracted = true
        let newYaw = orbitPose.yaw + delta
        orbitPose = OrbitPose(yaw: newYaw, pitch: orbitPose.pitch, radius: orbitPose.radius)
        applyCamera(from: orbitPose.position)
    }

    func orbit(by delta: SIMD2<Float>) {
        // No sync — we are the source of truth now (custom orbit).
        hasUserInteracted = true
        let yawDelta = -delta.x * 0.005
        let pitchDelta = -delta.y * 0.005
        orbitPose = OrbitPose(
            yaw: orbitPose.yaw + yawDelta,
            pitch: orbitPose.pitch + pitchDelta,
            radius: orbitPose.radius
        )
        applyCamera(from: orbitPose.position)
    }

    /// Pan by moving the phone in the camera's right/up plane.
    /// This keeps the RealityKit orbit target at the origin, so the
    /// built-in `.orbit` controls don't snap back after shift-drag.
    func pan(by delta: SIMD2<Float>) {
        guard let camera, let phone else { return }
        let t = camera.transformMatrix(relativeTo: nil)
        let right = SIMD3<Float>(t.columns.0.x, t.columns.0.y, t.columns.0.z)
        let up = SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z)
        let distance = max(simd_length(orbitPose.position), 0.5)
        let zoomFactor = max(zoom, 0.1)
        let factor = distance * 0.0012 / zoomFactor
        // X inverted per feedback, Y kept as original (reverted).
        panOffset -= right * delta.x * factor
        panOffset += up * delta.y * factor
        // Reapply phone position with current pan
        let scale = baseScale * zoom
        phone.position = -modelCenter * scale + panOffset
        if let floor {
            let bounds = phone.visualBounds(relativeTo: nil)
            floor.position = [0, bounds.min.y - 0.0004, 0]
        }
    }

    func resetPan() {
        panOffset = .zero
        applyCamera(from: orbitPose.position)
        applyZoom()
    }

    func captureOrbitPose() -> OrbitPose {
        orbitPose
    }

    /// Scales and centers the phone so it fits the studio framing.
    func framePhone(_ entity: Entity, targetSize: Float) {
        let bounds = entity.visualBounds(relativeTo: nil)
        let maxDim = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        guard maxDim > 0 else { return }
        baseScale = targetSize / maxDim
        modelCenter = bounds.center
        applyZoom()
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
        // Keep a stable up when near the pole to avoid 180° roll.
        let pitch = orbitPose.pitch
        if abs(pitch) > 1.30 {
            let eye = position
            let forward = normalize(SIMD3<Float>.zero - eye)
            let worldUp: SIMD3<Float> = [0, 1, 0]
            let right = normalize(cross(forward, worldUp))
            let up = cross(right, forward)
            var m = matrix_identity_float4x4
            m.columns.0 = SIMD4<Float>(right.x, right.y, right.z, 0)
            m.columns.1 = SIMD4<Float>(up.x, up.y, up.z, 0)
            m.columns.2 = SIMD4<Float>(-forward.x, -forward.y, -forward.z, 0)
            m.columns.3 = SIMD4<Float>(eye.x, eye.y, eye.z, 1)
            camera.setTransformMatrix(m, relativeTo: nil)
        } else {
            camera.look(at: .zero, from: position, relativeTo: nil)
        }
    }

    func applyZoom() {
        guard let phone else { return }
        let scale = baseScale * zoom
        guard scale > 0 else { return }
        phone.scale = SIMD3(repeating: scale)
        phone.position = -modelCenter * scale + panOffset
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

/// Shift + drag pans and drag without shift orbits.
/// Owns all orbit + pan so PhoneScene is single source of truth.
private struct CameraPanCatcher: NSViewRepresentable {
    var onPan: (SIMD2<Float>) -> Void
    var onOrbit: (SIMD2<Float>) -> Void

    func makeNSView(context: Context) -> PanMonitorView {
        let view = PanMonitorView()
        view.onPan = onPan
        view.onOrbit = onOrbit
        return view
    }

    func updateNSView(_ view: PanMonitorView, context: Context) {
        view.onPan = onPan
        view.onOrbit = onOrbit
    }

    final class PanMonitorView: NSView {
        var onPan: ((SIMD2<Float>) -> Void)?
        var onOrbit: ((SIMD2<Float>) -> Void)?
        private var flagsMonitor: Any?
        private var dragMonitor: Any?
        private var isShiftHeld = false
        private var isDraggingInside = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installMonitors()
        }

        deinit {
            removeMonitors()
        }

        private func installMonitors() {
            removeMonitors()
            guard window != nil else { return }
            // Keep shift state in sync even without drag, for future use.
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self else { return event }
                self.isShiftHeld = event.modifierFlags.contains(.shift)
                return event
            }
            dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let location = self.convert(event.locationInWindow, from: nil)
                switch event.type {
                case .leftMouseDown:
                    isDraggingInside = bounds.contains(location)
                    return event
                case .leftMouseUp:
                    isDraggingInside = false
                    return event
                case .leftMouseDragged:
                    let shift = event.modifierFlags.contains(.shift)
                    isShiftHeld = shift
                    let dx = Float(event.deltaX)
                    let dy = Float(event.deltaY)
                    if (isDraggingInside || bounds.contains(location)) && shift {
                        onPan?(SIMD2<Float>(dx, dy))
                        return nil
                    } else if isDraggingInside || bounds.contains(location) {
                        onOrbit?(SIMD2<Float>(dx, dy))
                        return nil
                    }
                    return event
                default:
                    return event
                }
            }
        }

        private func removeMonitors() {
            if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
            if let m = dragMonitor { NSEvent.removeMonitor(m); dragMonitor = nil }
        }
    }
}

/// W/S dolly zoom + A/D yaw orbit — keyboard camera controls.
private struct WASDZoomCatcher: NSViewRepresentable {
    var onZoomIn: () -> Void
    var onZoomOut: () -> Void
    var onRotateLeft: () -> Void
    var onRotateRight: () -> Void

    func makeNSView(context: Context) -> KeyMonitorView {
        let view = KeyMonitorView()
        view.onZoomIn = onZoomIn
        view.onZoomOut = onZoomOut
        view.onRotateLeft = onRotateLeft
        view.onRotateRight = onRotateRight
        return view
    }

    func updateNSView(_ view: KeyMonitorView, context: Context) {
        view.onZoomIn = onZoomIn
        view.onZoomOut = onZoomOut
        view.onRotateLeft = onRotateLeft
        view.onRotateRight = onRotateRight
    }

    final class KeyMonitorView: NSView {
        var onZoomIn: (() -> Void)?
        var onZoomOut: (() -> Void)?
        var onRotateLeft: (() -> Void)?
        var onRotateRight: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installMonitor()
        }

        deinit { removeMonitor() }

        private func installMonitor() {
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                // Don't steal typing in text fields
                if let fr = window.firstResponder as? NSText, fr is NSTextView { return event }
                guard let chars = event.charactersIgnoringModifiers?.lowercased() else { return event }
                if chars == "w" {
                    self.onZoomIn?()
                    return nil
                } else if chars == "s" {
                    self.onZoomOut?()
                    return nil
                } else if chars == "a" {
                    self.onRotateLeft?()
                    return nil
                } else if chars == "d" {
                    self.onRotateRight?()
                    return nil
                }
                return event
            }
        }

        private func removeMonitor() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        }
    }
}

/// Holds a weak reference to the preview's NSView so "Export Current Frame"
/// can locate the region to capture without keeping the view alive.
private final class PreviewViewBox {
    weak var view: NSView?
}

/// Invisible anchor that fills the preview area and reports its NSView,
/// giving FrameCapture an exact on-screen rect for the 3D frame.
private struct FrameCaptureAnchor: NSViewRepresentable {
    var resolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { resolve(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { resolve(nsView) }
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
            .onAppear {
                apply()
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

private struct ExportSuccessToast: View {
    @Bindable var store: YomMockStore

    var body: some View {
        let fileName = store.lastExportedFrameURL?.lastPathComponent ?? "Frame.png"
        let folderName = store.lastExportedFrameURL?.deletingLastPathComponent().lastPathComponent ?? ""
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 32, height: 32)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Frame exported")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(fileName)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !folderName.isEmpty {
                    Text(folderName)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button {
                    store.showExportedFrameInFinder()
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.accentColor)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.dismissExportSuccess()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 420)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
    }
}

private struct VideoExportProgressHUD: View {
    var progress: Double
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .scaleEffect(0.8)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Exporting video…")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 360)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
    }
}

private struct VideoExportSuccessToast: View {
    @Bindable var store: YomMockStore
    var body: some View {
        let fileName = store.lastExportedVideoURL?.lastPathComponent ?? "Video"
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.08)).frame(width: 32, height: 32)
                Image(systemName: "film.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Video exported")
                    .font(.system(size: 13, weight: .semibold))
                Text(fileName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                store.showExportedVideoInFinder()
            } label: {
                Label("Show in Finder", systemImage: "folder")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.accentColor)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { store.dismissVideoSuccess() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 420)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
    }
}

#Preview {
    ContentView(store: YomMockStore())
}
