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
                store.loadDefaultDisplayImage(for: store.device)
            }
            store.previewPointSizeProvider = { [previewViewBox] in
                previewViewBox.view?.bounds.size
            }
            store.previewBackingScaleProvider = { [previewViewBox] in
                previewViewBox.view?.window?.backingScaleFactor ?? 2
            }
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

                InspectorPanel(store: store, displayStatus: $displayStatus)
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
                store.loadDefaultDisplayImage(for: newDevice)
            }
            store.swapDefaultTimelineIfNeeded(from: oldDevice, to: newDevice)
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
        .onChange(of: store.background) { _, _ in store.markDirty() }
        .onChange(of: store.customBackground) { _, _ in store.markDirty() }
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
        .onChange(of: store.timeline.checkpoints) { _, _ in store.markDirty() }
        .onChange(of: store.timeline.duration) { _, _ in store.markDirty() }
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

                do {
                    let entities = try await scene.makeStudioEntities(
                        styling: DeviceStyling(
                            device: store.device,
                            finish: store.selectedColor.finish(custom: store.customColor),
                            displayTexture: displayTexture,
                            lidGlow: 0,
                            displayAverageColor: displayAverageColor
                        ),
                        lidAngle: store.lidAngle
                    )
                    content.add(entities.ibl)
                    content.add(entities.model)
                    // Re-apply materials in case the display texture finished
                    // loading while the model was still loading — the styling
                    // above was captured before the await with a nil texture.
                    scene.lidRig?.displayOn = displayTexture != nil
                    refreshMaterials()
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
            .background { inputCatchers }

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

    private var inputCatchers: some View {
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
                    store.markDirty()
                },
                onOrbit: { delta in
                    guard !store.timeline.isPlaying else { return }
                    userMovedCamera = true
                    scene.hasUserInteracted = true
                    scene.orbit(by: delta)
                    store.markDirty()
                }
            )
            WASDZoomCatcher(
                onZoomIn: { zoomBy(multiplier: exp(0.08)) },
                onZoomOut: { zoomBy(multiplier: exp(-0.08)) },
                onRotateLeft: { rotate(by: -0.09) },
                onRotateRight: { rotate(by: 0.09) }
            )
        }
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

    // MARK: - Actions

    private func zoomBy(multiplier: Float) {
        guard !store.timeline.isPlaying else { return }
        userMovedCamera = true
        scene.hasUserInteracted = true
        let target = min(max(store.zoom * Float(multiplier), PhoneScene.minZoom), PhoneScene.maxZoom)
        animateZoom(to: target)
    }

    private func rotate(by delta: Float) {
        guard !store.timeline.isPlaying else { return }
        userMovedCamera = true
        scene.hasUserInteracted = true
        scene.rotateYaw(by: delta)
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
                let t = min(Float((CACurrentMediaTime() - startTime) / duration), 1)
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
        PhoneStyling.applyMaterials(to: model, styling: DeviceStyling(
            device: store.device,
            finish: store.selectedColor.finish(custom: store.customColor),
            displayTexture: displayTexture,
            lidGlow: scene.lidRig?.glowFactor ?? 0,
            displayAverageColor: displayAverageColor
        ))
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

    private func updateWindowTitle() {
        DispatchQueue.main.async {
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                window.title = store.windowTitleWithStar
                window.isDocumentEdited = store.isDirty
            }
        }
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
}

#Preview {
    ContentView(store: YomMockStore())
}
