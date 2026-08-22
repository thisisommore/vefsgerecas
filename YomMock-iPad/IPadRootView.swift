//
//  IPadRootView.swift
//  YomMock-iPad
//
//  Native iPadOS editor: edge-to-edge 3D stage with direct-manipulation
//  camera gestures, floating Liquid Glass chrome, trailing inspector and a
//  touch-sized timeline card.
//

import PhotosUI
import RealityKit
import SwiftUI
import UniformTypeIdentifiers

struct IPadRootView: View {
    @Bindable var store: YomMockStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Camera / scene state (mirrors the Mac editor).
    @State private var cameraReady = false
    @State private var userMovedCamera = false
    @State private var scene = PhoneScene()
    @State private var displayTexture: TextureResource?
    @State private var displayAverageColor: PlatformColor?
    @State private var displayStatus: String?
    @State private var displayLoadTask: Task<Void, Never>?

    // Chrome state.
    @State private var showInspector = true
    @State private var showInspectorSheet = false
    @State private var showOpenImporter = false
    @State private var showImageImporter = false
    @State private var showNewConfirm = false
    @State private var showOpenConfirm = false
    @State private var pendingOpenURL: URL?
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showSavedToast = false
    @State private var savedToastTask: Task<Void, Never>?
    @State private var photoItem: PhotosPickerItem?
    @State private var sharePayload: SharePayload?
    @State private var viewportSize: CGSize = .zero
    @State private var viewportScale: CGFloat = 2

    var body: some View {
        stageWithChrome
            .sheetsAndAlerts(
                store: store,
                showOpenImporter: $showOpenImporter,
                showImageImporter: $showImageImporter,
                showNewConfirm: $showNewConfirm,
                showOpenConfirm: $showOpenConfirm,
                pendingOpenURL: $pendingOpenURL,
                showRenameAlert: $showRenameAlert,
                renameText: $renameText,
                sharePayload: $sharePayload,
                onSaved: showSavedToastBriefly
            )
            .storeChangeWatchers(store: store, photoItem: $photoItem)
            .sceneChangeWatchers(
                store: store,
                onDeviceSwitch: { oldDevice, newDevice in
                    if store.displayFileName == oldDevice.defaultDisplayImageName {
                        store.loadDefaultDisplayImage(for: newDevice)
                    }
                },
                refreshMaterials: refreshMaterials,
                applyZoomToScene: { value in
                    guard !store.timeline.isPlaying else { return }
                    scene.zoom = value
                    scene.applyZoom()
                },
                applyLidAngleToScene: { value in
                    scene.applyLidAngle(value)
                    refreshMaterials()
                },
                onDisplayImageChanged: { image in
                    setDisplayScreenshot(image)
                }
            )
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: store.isExportingVideo)
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: store.showVideoSuccess)
            .onOpenURL { url in
                if store.isDirty {
                    pendingOpenURL = url
                    showOpenConfirm = true
                } else {
                    store.importProject(from: url)
                }
            }
            .onAppear {
                store.previewPointSizeProvider = { [self] in viewportSize }
                store.previewBackingScaleProvider = { [self] in viewportScale }
            }
    }

    // MARK: - Stage + chrome composition

    private var stageWithChrome: some View {
        editorStage
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                topChrome
                    .padding(.top, 8)
                    .padding(.trailing, trailingInspectorClearance)
            }
            .overlay(alignment: .bottom) { bottomChrome.padding(.bottom, 8) }
            .overlay(alignment: .trailing) { inspectorColumn }
            .overlay(alignment: .bottom) { savedToast }
            .sheet(isPresented: $showInspectorSheet) {
                IPadInspectorPanel(
                    store: store,
                    displayStatus: $displayStatus,
                    onPickFromFiles: { showImageImporter = true }
                )
                .presentationDetents([.medium, .large])
            }
    }

    private var editorStage: some View {
        ZStack {
            StudioBackdrop(background: store.background, customColor: store.customBackground)
            previewRealityView
            cameraGestures
            TimelinePlaybackDriver(timeline: store.timeline, apply: applyEvaluatedPose)
            videoExportOverlays
            displayStatusOverlay
        }
        .onDrop(of: [.fileURL, .image], isTargeted: nil, perform: handlePreviewDrop)
    }

    private var previewRealityView: some View {
        RealityView { content in
            // Sync setup first — the make closure's content is inout until
            // the first suspension point.
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

            await loadSceneEntities(content)
        } update: { content in
            bindCamera(from: content)
            guard !store.timeline.isPlaying else { return }
            holdStudioFramingIfNeeded()
        }
        .realityViewCameraControls(.none)
        .id(store.device)
    }

    private var cameraGestures: some View {
        CameraTouchController(
            gesturesEnabled: !store.timeline.isPlaying,
            onOrbit: { delta in
                userMovedCamera = true
                scene.hasUserInteracted = true
                scene.orbit(by: delta)
                store.markDirty()
            },
            onPan: { delta in
                userMovedCamera = true
                scene.hasUserInteracted = true
                scene.pan(by: delta)
                store.markDirty()
            },
            onPinchZoom: { factor in
                userMovedCamera = true
                scene.hasUserInteracted = true
                let target = min(max(store.zoom * factor, PhoneScene.minZoom), PhoneScene.maxZoom)
                store.zoom = target
            },
            onDoubleTap: {
                scene.resetPan()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            },
            onViewportChange: { size, scale in
                viewportSize = size
                viewportScale = scale
            }
        )
    }

    @ViewBuilder
    private var videoExportOverlays: some View {
        if store.isExportingVideo {
            IPadVideoProgressHUD(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 120)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if store.showVideoSuccess {
            IPadVideoSuccessToast(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 120)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var displayStatusOverlay: some View {
        if let displayStatus {
            VStack {
                Spacer()
                Text(displayStatus)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 130)
            }
        }
    }

    // MARK: - Top chrome

    private var topChrome: some View {
        HStack(spacing: 12) {
            documentMenu

            Spacer()

            HStack(spacing: 4) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    chromeIcon("photo.on.rectangle.angled")
                }
                .buttonStyle(GlassCircleButtonStyle())

                inspectorToggleButton
                exportMenu
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal, 16)
    }

    private var inspectorToggleButton: some View {
        Button {
            if horizontalSizeClass == .compact {
                showInspectorSheet = true
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showInspector.toggle()
                }
            }
        } label: {
            chromeIcon(showInspector ? "sidebar.trailing" : "sidebar.leading")
        }
        .buttonStyle(GlassCircleButtonStyle())
    }

    private var documentMenu: some View {
        Menu {
            Button {
                if store.isDirty {
                    showNewConfirm = true
                } else {
                    store.resetToNewProject()
                }
            } label: {
                Label("New Project", systemImage: "square.and.pencil")
            }
            .keyboardShortcut("n")

            Button {
                if store.isDirty {
                    showOpenConfirm = true
                } else {
                    showOpenImporter = true
                }
            } label: {
                Label("Open…", systemImage: "folder")
            }
            .keyboardShortcut("o")

            Button {
                if store.saveProjectToSandbox() != nil {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showSavedToastBriefly()
                }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s")
            .disabled(!store.canSave)

            Button {
                renameText = store.displayName
                showRenameAlert = true
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button {
                let url = store.projectURL ?? store.saveProjectToSandbox()
                if let url {
                    sharePayload = SharePayload(items: [url])
                }
            } label: {
                Label("Share Project", systemImage: "square.and.arrow.up")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 15, weight: .semibold))
                Text(store.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if store.isDirty {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var exportMenu: some View {
        Menu {
            Button {
                Task {
                    do {
                        let url = try await store.exportFrameForSharing()
                        sharePayload = SharePayload(items: [url])
                    } catch {
                        store.projectError =
                            (error as? LocalizedError)?.errorDescription
                            ?? error.localizedDescription
                    }
                }
            } label: {
                Label("Share Frame as PNG", systemImage: "photo")
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button {
                store.exportVideo()
            } label: {
                Label("Export Video…", systemImage: "film")
            }
        } label: {
            chromeIcon("square.and.arrow.up")
        }
        .disabled(store.isExportingVideo)
    }

    private func chromeIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.85))
            .frame(width: 40, height: 40)
            .contentShape(Circle())
    }

    // MARK: - Bottom chrome (timeline)

    private var bottomChrome: some View {
        IPadTimelineBar(
            timeline: store.timeline,
            cameraAvailable: cameraReady,
            onSaveCheckpoint: saveCheckpoint,
            onEdited: { store.markDirty() }
        )
        .padding(.leading, 16)
        .padding(.trailing, 16 + trailingInspectorClearance)
    }

    /// Extra trailing space so the timeline card stops short of the inspector
    /// panel instead of extending underneath it.
    private var trailingInspectorClearance: CGFloat {
        horizontalSizeClass == .regular && showInspector ? 320 + 12 : 0
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorColumn: some View {
        if horizontalSizeClass == .regular && showInspector {
            IPadInspectorPanel(
                store: store,
                displayStatus: $displayStatus,
                onPickFromFiles: { showImageImporter = true }
            )
            .frame(width: 320)
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 0.5)
            }
        }
    }

    // MARK: - Toasts

    @ViewBuilder
    private var savedToast: some View {
        if showSavedToast {
            Label("Project Saved", systemImage: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .glassEffect(.regular.interactive(), in: .capsule)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                .padding(.bottom, 120)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Scene setup

    private func loadSceneEntities(_ content: RealityViewCameraContent) async {
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
            displayStatus = error.localizedDescription
        }
    }

    // MARK: - Actions

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
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func showSavedToastBriefly() {
        savedToastTask?.cancel()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            showSavedToast = true
        }
        savedToastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                showSavedToast = false
            }
        }
    }

    private func handlePreviewDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let string = item as? String {
                    url = URL(string: string)
                } else if let itemURL = item as? URL {
                    url = itemURL
                }
                guard let url else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let image = PlatformImageLoader.image(contentsOf: url) else { return }
                Task { @MainActor in
                    store.displayFileName = url.lastPathComponent
                    store.displayImage = image
                }
            }
            return true
        }
        if provider.canLoadObject(ofClass: UIImage.self) {
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else { return }
                Task { @MainActor in
                    store.displayFileName = "Dropped image"
                    store.displayImage = image
                }
            }
            return true
        }
        return false
    }

    private func applyEvaluatedPose() {
        let state = store.timeline.evaluatedState()
        scene.apply(orbit: state.orbit, zoom: state.zoom, pan: state.pan)
        scene.applyLidAngle(state.lidAngle)
        if store.device == .macBookPro {
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

    private func setDisplayScreenshot(_ image: PlatformImage?) {
        displayLoadTask?.cancel()
        displayStatus = nil
        guard let image else {
            displayTexture = nil
            displayAverageColor = nil
            scene.lidRig?.displayOn = false
            refreshMaterials()
            return
        }
        if let cg = try? PhoneStyling.sRGBCGImage(from: image),
            let avg = PhoneStyling.averageColor(from: cg)
        {
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

    private func bindCamera(from content: RealityViewCameraContent) {
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

// MARK: - Store-level change watchers

private struct StoreChangeWatchers: ViewModifier {
    @Bindable var store: YomMockStore
    @Binding var photoItem: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .task {
                if store.displayImage == nil {
                    store.loadDefaultDisplayImage(for: store.device)
                }
            }
            .onChange(of: store.background) { _, _ in store.markDirty() }
            .onChange(of: store.customBackground) { _, _ in store.markDirty() }
            .onChange(of: store.timeline.checkpoints) { _, _ in store.markDirty() }
            .onChange(of: store.timeline.duration) { _, _ in store.markDirty() }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                        let image = PlatformImageLoader.image(data: data)
                    {
                        store.displayFileName = "Photo Library"
                        store.displayImage = image
                    }
                    photoItem = nil
                }
            }
    }
}

private extension View {
    func storeChangeWatchers(store: YomMockStore, photoItem: Binding<PhotosPickerItem?>) -> some View {
        modifier(StoreChangeWatchers(store: store, photoItem: photoItem))
    }
}

// MARK: - Scene-coupled change watchers

private struct SceneChangeWatchers: ViewModifier {
    @Bindable var store: YomMockStore
    var onDeviceSwitch: (Device, Device) -> Void
    var refreshMaterials: () -> Void
    var applyZoomToScene: (Float) -> Void
    var applyLidAngleToScene: (Float) -> Void
    var onDisplayImageChanged: (PlatformImage?) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: store.device) { oldDevice, newDevice in
                onDeviceSwitch(oldDevice, newDevice)
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
            .onChange(of: store.zoom) { _, value in
                applyZoomToScene(value)
                store.markDirty()
            }
            .onChange(of: store.lidAngle) { _, value in
                applyLidAngleToScene(value)
                store.markDirty()
            }
            .onChange(of: store.displayImage) { _, newImage in
                onDisplayImageChanged(newImage)
                store.markDirtyForImageChange()
            }
    }
}

private extension View {
    func sceneChangeWatchers(
        store: YomMockStore,
        onDeviceSwitch: @escaping (Device, Device) -> Void,
        refreshMaterials: @escaping () -> Void,
        applyZoomToScene: @escaping (Float) -> Void,
        applyLidAngleToScene: @escaping (Float) -> Void,
        onDisplayImageChanged: @escaping (PlatformImage?) -> Void
    ) -> some View {
        modifier(
            SceneChangeWatchers(
                store: store,
                onDeviceSwitch: onDeviceSwitch,
                refreshMaterials: refreshMaterials,
                applyZoomToScene: applyZoomToScene,
                applyLidAngleToScene: applyLidAngleToScene,
                onDisplayImageChanged: onDisplayImageChanged
            )
        )
    }
}

private struct EditorSheetsAndAlerts: ViewModifier {
    @Bindable var store: YomMockStore
    @Binding var showOpenImporter: Bool
    @Binding var showImageImporter: Bool
    @Binding var showNewConfirm: Bool
    @Binding var showOpenConfirm: Bool
    @Binding var pendingOpenURL: URL?
    @Binding var showRenameAlert: Bool
    @Binding var renameText: String
    @Binding var sharePayload: SharePayload?
    var onSaved: () -> Void

    private func proceedWithOpen() {
        if let url = pendingOpenURL {
            pendingOpenURL = nil
            store.importProject(from: url)
        } else {
            showOpenImporter = true
        }
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $store.showVideoOptions) {
                IPadVideoExportOptionsView(store: store)
            }
            .sheet(item: $sharePayload) { payload in
                ActivityView(items: payload.items)
                    .ignoresSafeArea()
            }
            .fileImporter(
                isPresented: $showOpenImporter,
                allowedContentTypes: [UTType.yomMockProject],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    store.importProject(from: url)
                }
            }
            .fileImporter(
                isPresented: $showImageImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let image = PlatformImageLoader.image(contentsOf: url) {
                        store.displayFileName = url.lastPathComponent
                        store.displayImage = image
                    }
                }
            }
            .confirmationDialog(
                "New Project",
                isPresented: $showNewConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard Changes & Start New", role: .destructive) {
                    store.resetToNewProject()
                }
                Button("Save Current First") {
                    store.saveProjectToSandbox()
                    if !store.isDirty {
                        store.resetToNewProject()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your current project has unsaved changes.")
            }
            .confirmationDialog(
                "Open Project",
                isPresented: $showOpenConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard Changes & Open", role: .destructive) {
                    proceedWithOpen()
                }
                Button("Save Current First") {
                    store.saveProjectToSandbox()
                    if !store.isDirty {
                        proceedWithOpen()
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingOpenURL = nil
                }
            } message: {
                Text("Your current project has unsaved changes.")
            }
            .alert("Rename Project", isPresented: $showRenameAlert) {
                TextField("Project name", text: $renameText)
                Button("Save") {
                    if store.saveProjectToSandboxAs(renameText) != nil {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onSaved()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { store.projectError != nil },
                    set: { if !$0 { store.handleSaveErrorDismiss() } }
                )
            ) {
                Button("OK") { store.handleSaveErrorDismiss() }
            } message: {
                Text(store.projectError ?? "")
            }
    }
}

private extension View {
    func sheetsAndAlerts(
        store: YomMockStore,
        showOpenImporter: Binding<Bool>,
        showImageImporter: Binding<Bool>,
        showNewConfirm: Binding<Bool>,
        showOpenConfirm: Binding<Bool>,
        pendingOpenURL: Binding<URL?>,
        showRenameAlert: Binding<Bool>,
        renameText: Binding<String>,
        sharePayload: Binding<SharePayload?>,
        onSaved: @escaping () -> Void
    ) -> some View {
        modifier(
            EditorSheetsAndAlerts(
                store: store,
                showOpenImporter: showOpenImporter,
                showImageImporter: showImageImporter,
                showNewConfirm: showNewConfirm,
                showOpenConfirm: showOpenConfirm,
                pendingOpenURL: pendingOpenURL,
                showRenameAlert: showRenameAlert,
                renameText: renameText,
                sharePayload: sharePayload,
                onSaved: onSaved
            )
        )
    }
}

// MARK: - Store change watchers (split out for type-check speed)


// MARK: - Helpers

/// Identifiable box for share-sheet presentation.
struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct GlassCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
