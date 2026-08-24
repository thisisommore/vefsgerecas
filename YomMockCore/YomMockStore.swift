//
//  YomMockStore.swift
//  YomMockCore
//
//  Central document state for project save/restore. Platform-neutral:
//  platform-specific save/open/export UI lives in per-target extensions
//  (YomMockStore+Mac.swift / YomMockStore+iPad.swift).
//

import SwiftUI
import UniformTypeIdentifiers
import Observation

@MainActor
@Observable
final class YomMockStore {
    // MARK: - Savable state

    var device: Device = .iPhone
    var lidAngle: Float = MacBookLidRig.defaultOpenAngle
    var selectedColor: iPhoneColor = .black
    var customColor = Color(red: 0.78, green: 0.32, blue: 0.36)
    var background: StudioBackground = .white
    var customBackground = Color.white
    var camera = StudioCameraSettings()
    var zoom: Float = 1
    var timeline: CameraTimeline = CameraTimeline.demo
    var displayImage: PlatformImage?
    var displayFileName: String?
    /// Active screen recording used as the display content (nil = static
    /// screenshot). Owns the looping preview player + export frame source.
    private(set) var displayVideo: DisplayVideoController?

    // MARK: - Project bookkeeping

    var projectURL: URL?
    private(set) var isDirty = false
    private var lastSavedSnapshot: YomMockProjectDocument?
    private var isRestoring = false
    var projectError: String?
    var lastExportedFrameURL: URL?
    var showExportSuccess = false
    @ObservationIgnored private var exportSuccessTask: Task<Void, Never>?

    // MARK: - Video export
    var isExportingVideo = false
    var videoExportProgress: Double = 0
    var lastExportedVideoURL: URL?
    var showVideoSuccess = false
    var videoExportError: String?
    @ObservationIgnored private var videoExportTask: Task<Void, Never>?
    @ObservationIgnored private var videoExporter: VideoExporter?
    var pendingVideoExportURL: URL?
    var pendingVideoOptions = VideoExportOptions()
    var showVideoOptions = false
    var pendingFrameFormat: FrameExportFormat = .png
    var pendingFrameTransparent: Bool = false
    var showFrameOptions = false

    // MARK: - Pro gating

    /// Set when a non-Pro user attempts to export; each platform's root view
    /// presents the upgrade flow in response. Exporting is Pro-only.
    var showProUpgradePrompt = false

    /// Frames and video may only leave the app with an active Pro entitlement.
    var canExport: Bool { SubscriptionManager.shared.isPro }

    /// Gate shared by every export entry point. Returns `true` when the user
    /// may export; otherwise flags the upgrade prompt and returns `false`.
    @discardableResult
    func requireProForExport() -> Bool {
        guard !canExport else { return true }
        showProUpgradePrompt = true
        return false
    }

    enum FrameExportFormat: String, CaseIterable, Identifiable {
        case png = "PNG"
        case webp = "WebP"
        var id: String { rawValue }
        var fileExtension: String {
            switch self {
            case .png: return "png"
            case .webp: return "webp"
            }
        }
        var utType: String {
            switch self {
            case .png: return "public.png"
            case .webp: return "org.webmproject.webp"
            }
        }
    }
    /// Cached offscreen renderer for "Export Current Frame" stills — reused
    /// across exports so the USDZ + IBL setup cost is paid only once.
    @ObservationIgnored private var stillRenderer: OffscreenSceneRenderer?
    @ObservationIgnored private var stillRendererKey: String?

    /// Set by each platform's view; returns the live preview's point size so
    /// exports can match its aspect ratio and backdrop scale.
    @ObservationIgnored var previewPointSizeProvider: (() -> CGSize?)?
    @ObservationIgnored var previewBackingScaleProvider: (() -> CGFloat)?

    var windowTitle: String {
        let base: String
        if let url = projectURL {
            base = url.deletingPathExtension().lastPathComponent
        } else {
            base = "Untitled"
        }
        return isDirty ? "\(base) •" : base
    }

    var windowTitleWithStar: String {
        let base: String
        if let url = projectURL {
            base = url.deletingPathExtension().lastPathComponent
        } else {
            base = "Untitled"
        }
        return isDirty ? "\(base)*" : base
    }

    /// Display name used by export suggestions and title chips.
    var displayName: String {
        if let url = projectURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return "Untitled"
    }

    var canSave: Bool { true }

    init() {
        isDirty = false
        lastSavedSnapshot = makeDocument()
    }

    // MARK: - Document snapshot

    func makeDocument() -> YomMockProjectDocument {
        let checkpoints: [ProjectCheckpoint] = timeline.checkpoints.map { cp in
            ProjectCheckpoint(id: cp.id, time: cp.time, yaw: cp.pose.yaw, pitch: cp.pose.pitch, radius: cp.pose.radius, zoom: cp.zoom, pan: cp.pan, lidAngle: cp.lidAngle)
        }
        let doc = YomMockProjectDocument(
            version: YomMockProjectDocument.currentVersion,
            deviceRaw: device.rawValue,
            selectedColorRaw: selectedColor.rawValueForProject,
            customColor: ProjectColor(color: customColor),
            backgroundRaw: background.rawValueForProject,
            customBackground: ProjectColor(color: customBackground),
            zoom: zoom,
            lidAngle: lidAngle,
            timelineDuration: timeline.duration,
            timelineCurrentTime: timeline.currentTime,
            checkpoints: checkpoints,
            selectedCheckpointID: timeline.selectedCheckpointID?.uuidString,
            displayRelativePath: displayImage == nil ? nil : "assets/\(YomMockProject.displayFileName)",
            displayFileName: displayFileName,
            camera: camera
        )
        return doc
    }

    func applyDocument(_ doc: YomMockProjectDocument, displayImage: PlatformImage?) {
        isRestoring = true
        defer { isRestoring = false }

        device = Device(rawValue: doc.deviceRaw ?? "") ?? .iPhone
        lidAngle = doc.lidAngle ?? MacBookLidRig.defaultOpenAngle
        selectedColor = iPhoneColor.from(projectRaw: doc.selectedColorRaw)
        if let pc = doc.customColor {
            customColor = pc.color
        }
        background = StudioBackground.from(projectRaw: doc.backgroundRaw)
        if let pc = doc.customBackground {
            customBackground = pc.color
        }
        camera = doc.camera ?? .default
        zoom = doc.zoom

        let newCheckpoints: [CameraCheckpoint] = doc.checkpoints.map { pc in
            let pose = OrbitPose(yaw: pc.yaw, pitch: pc.pitch, radius: pc.radius)
            let id = UUID(uuidString: pc.id) ?? UUID()
            return CameraCheckpoint(id: id, time: pc.time, pose: pose, zoom: pc.zoom, pan: pc.pan, lidAngle: pc.lidAngle)
        }
        let sorted = newCheckpoints.sorted { $0.time < $1.time }
        timeline.checkpoints = sorted.isEmpty ? [CameraCheckpoint(time: 0, pose: .default, zoom: 1)] : sorted
        timeline.duration = max(doc.timelineDuration, timeline.minDuration)
        timeline.currentTime = min(max(doc.timelineCurrentTime, 0), timeline.duration)
        if let sel = doc.selectedCheckpointID, let uuid = UUID(uuidString: sel) {
            timeline.selectedCheckpointID = uuid
        } else {
            timeline.selectedCheckpointID = timeline.checkpoints.first?.id
        }

        self.displayImage = displayImage
        self.displayFileName = doc.displayFileName
        // The looping player is restored asynchronously by openProject.
        displayVideo = nil

        lastSavedSnapshot = doc
        isDirty = false
        projectError = nil
    }

    func markDirty() {
        guard !isRestoring else { return }
        let current = makeDocument()
        if let last = lastSavedSnapshot, current == last {
            isDirty = false
        } else if lastSavedSnapshot == nil {
            if current == lastSavedSnapshot {
                isDirty = false
            } else {
                isDirty = true
            }
        } else {
            isDirty = true
        }
    }

    /// For display image changes where document equality can't detect pixels, force dirty.
    func markDirtyForImageChange() {
        guard !isRestoring else { return }
        isDirty = true
    }

    func markClean(with document: YomMockProjectDocument? = nil) {
        isDirty = false
        lastSavedSnapshot = document ?? makeDocument()
    }

    // MARK: - New / Open / Save primitives (UI lives in platform extensions)

    /// Resets every editable field to a fresh demo project without prompting.
    func resetToNewProject() {
        isRestoring = true
        device = .iPhone
        lidAngle = MacBookLidRig.defaultOpenAngle
        selectedColor = .black
        customColor = Color(red: 0.78, green: 0.32, blue: 0.36)
        background = .white
        customBackground = Color.white
        camera = .default
        zoom = 1
        timeline = CameraTimeline.demo(for: .iPhone)
        displayVideo?.pause()
        displayVideo = nil
        displayImage = nil
        displayFileName = nil
        projectURL = nil
        isRestoring = false
        lastSavedSnapshot = makeDocument()
        isDirty = false
        projectError = nil
    }

    /// On a device switch, if the timeline is still the untouched default demo
    /// for the old device, swap in the new device's default demo (mirrors the
    /// default screenshot swap in the platform views).
    func swapDefaultTimelineIfNeeded(from oldDevice: Device, to newDevice: Device) {
        guard timeline.isDefaultDemo(for: oldDevice) else { return }
        timeline = CameraTimeline.demo(for: newDevice)
    }

    /// Saves into the given URL. `displayVideoSourceURL` (the original
    /// dropped recording) is copied into the package when present.
    func performSave(to url: URL) {
        do {
            let doc = makeDocument()
            let saved = try YomMockProject.save(
                to: url, document: doc, displayImage: displayImage,
                displayVideoSourceURL: displayVideo?.url)
            projectURL = url
            lastSavedSnapshot = saved
            isDirty = false
            projectError = nil
        } catch {
            projectError = error.localizedDescription
        }
    }

    func openProject(at url: URL) {
        do {
            let loaded = try YomMockProject.load(from: url)
            projectURL = url
            applyDocument(loaded.document, displayImage: loaded.displayImage)
            projectError = nil
            if let videoURL = loaded.displayVideoURL {
                let expectedFileName = loaded.document.displayFileName
                Task { @MainActor in
                    await restoreDisplayVideo(at: videoURL, expectedPosterName: expectedFileName)
                }
            }
        } catch {
            projectError = error.localizedDescription
        }
    }

    // MARK: - Display content (screenshot / screen recording)

    /// Sets a static screenshot as the display content, clearing any active
    /// screen recording. All UI entry points for images go through this.
    func setStaticDisplay(_ image: PlatformImage?, fileName: String?) {
        displayVideo?.pause()
        displayVideo = nil
        displayImage = image
        displayFileName = fileName
    }

    /// Loads a dropped/chosen screen recording as the display content:
    /// builds the looping preview player and extracts a poster frame that
    /// feeds thumbnails, spill tint and project persistence.
    func setDisplayVideo(at url: URL) async {
        do {
            let controller = try await DisplayVideoController(url: url)
            displayVideo = controller
            let poster = await controller.posterFrame()
            if let cg = poster {
                displayImage = PlatformImageLoader.image(cgImage: cg)
            } else {
                displayImage = nil
                displayVideo = nil
                projectError = "Could not decode a frame from \(url.lastPathComponent)."
                return
            }
            displayFileName = url.lastPathComponent
            markDirtyForImageChange()
            // Never autoplay: show the frame matching the playhead. Playback
            // starts when the camera animation starts.
            controller.scrub(to: min(timeline.currentTime, controller.duration))
        } catch {
            displayVideo = nil
            projectError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Imports a screen recording from a possibly security-scoped URL
    /// (Files app / drop / Photos) by copying it into the app's temporary
    /// directory first — drop URLs can expire between sessions.
    func importDisplayVideo(at externalURL: URL) async {
        let scoped = externalURL.startAccessingSecurityScopedResource()
        defer { if scoped { externalURL.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let ext = externalURL.pathExtension.isEmpty ? "mov" : externalURL.pathExtension
        let destination = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        do {
            try fm.copyItem(at: externalURL, to: destination)
        } catch {
            // Plain sandbox file (no copy needed) — use it directly.
            if fm.isReadableFile(atPath: externalURL.path) {
                await setDisplayVideo(at: externalURL)
            } else {
                projectError = error.localizedDescription
            }
            return
        }
        await setDisplayVideo(at: destination)
    }

    /// Reattaches the looping preview after opening a saved project. The
    /// poster PNG is already in place — only the player/material are rebuilt.
    private func restoreDisplayVideo(at url: URL, expectedPosterName: String?) async {
        // Bail if the user replaced the display content while decoding.
        guard displayVideo == nil, displayFileName == expectedPosterName else { return }
        do {
            let controller = try await DisplayVideoController(url: url)
            guard displayVideo == nil else { return }
            displayVideo = controller
            // Park on the playhead's frame; playback follows the timeline.
            controller.scrub(to: min(timeline.currentTime, controller.duration))
        } catch {
            // Poster still shows; surface a soft warning.
            projectError = "Could not reopen the screen recording: \(error.localizedDescription)"
        }
    }

    // MARK: - Display video ↔ timeline playback sync

    /// The recording only ever moves with the camera animation:
    /// - starts from its first frame when the timeline starts playing,
    ///   including when a finished timeline restarts from the top,
    /// - resumes from where it was when the timeline was paused mid-run,
    /// - pauses whenever the timeline pauses or reaches its end,
    /// - freezes on its final frame if it is shorter than the timeline.
    func timelinePlayStateChanged(_ playing: Bool) {
        guard let video = displayVideo else { return }
        if playing {
            if timeline.currentTime < 0.05 || video.isAtEnd {
                video.restart()
            } else {
                video.resume()
            }
        } else {
            video.pause()
        }
    }

    /// Playhead scrubbing while paused moves the recording to the matching
    /// frame, so the preview and "Export Current Frame" agree.
    func scrubDisplayVideoToPlayhead() {
        guard let video = displayVideo, !timeline.isPlaying else { return }
        video.scrub(to: timeline.currentTime)
    }

    // MARK: - Frame export primitives

    /// Snapshot of everything the offscreen renderer needs — safe to keep
    /// editing the project while an export runs.
    func makeSceneInputs(transparentBackground: Bool = false) -> OffscreenSceneRenderer.Inputs {
        let gradient = background.gradient(custom: customBackground)
        let top = platformColor(gradient.top)
        let bottom = platformColor(gradient.bottom)
        let displayCG = displayImage.flatMap { try? PhoneStyling.sRGBCGImage(from: $0) }
        return OffscreenSceneRenderer.Inputs(
            device: device,
            finish: selectedColor.finish(custom: customColor),
            displayImage: displayCG,
            backgroundTop: top,
            backgroundBottom: bottom,
            transparentBackground: transparentBackground,
            camera: camera
        )
    }

    private func previewPointSize() -> CGSize {
        previewPointSizeProvider?() ?? CGSize(width: 1280, height: 800)
    }

    func previewBackingScale() -> CGFloat {
        previewBackingScaleProvider?() ?? 2
    }

    /// Renders the current timeline state offscreen at 4K class and returns
    /// the PNG-encoded data plus the render size. No UI.


    /// Renders current timeline state offscreen. Supports transparent background (for WebP/PNG).
    func renderFrameData(format: FrameExportFormat = .png, transparentBackground: Bool = false) async throws -> Data {
        let previewPoints = previewPointSize()
        var inputs = makeSceneInputs(transparentBackground: transparentBackground)
        // Live recording: sample the exact frame on screen right now so the
        // exported still matches what the user sees.
        if let video = displayVideo {
            inputs.displayImage = await video.frame(at: video.currentPlaybackTime)
                ?? inputs.displayImage
        }
        let state = timeline.evaluatedState()
        let size = VideoExportOptions(resolution: .p2160).outputSize(
            previewPoints: previewPoints, backingScale: 1)
        let key = "\(device.rawValue)-\(Int(size.width))x\(Int(size.height))-\(format.rawValue)-\(transparentBackground ? "t" : "o")-cam\(Int(camera.fieldOfView * 10))"
        if stillRenderer == nil || stillRendererKey != key {
            stillRenderer = try await OffscreenSceneRenderer(
                outputSize: size, previewPointSize: previewPoints, inputs: inputs)
            stillRendererKey = key
        } else if let stillRenderer {
            try await stillRenderer.update(inputs: inputs)
        }
        guard let renderer = stillRenderer else {
            throw YomMockExportError.renderUnavailable
        }
        let buffer = try await renderer.render(state: state, deltaTime: 1.0 / 30)
        guard let image = renderer.makeCGImage(from: buffer) else {
            throw YomMockExportError.frameEncodeFailed
        }
        let data: Data?
        switch format {
        case .png:
            data = PlatformImageLoader.pngData(from: image)
        case .webp:
            data = PlatformImageLoader.webPData(from: image) ?? PlatformImageLoader.pngData(from: image)
        }
        guard let data else {
            throw YomMockExportError.frameEncodeFailed
        }
        return data
    }

    func renderFramePNGData() async throws -> Data {
        try await renderFrameData(format: .png, transparentBackground: false)
    }

    func renderFramePNGData(transparentBackground: Bool) async throws -> Data {
        try await renderFrameData(format: .png, transparentBackground: transparentBackground)
    }

    // MARK: - Export toasts

    func presentExportedFile(frameURL: URL) {
        lastExportedFrameURL = frameURL
        showExportSuccess = true
        scheduleExportSuccessAutoDismiss()
    }

    func dismissExportSuccess() {
        exportSuccessTask?.cancel()
        exportSuccessTask = nil
        showExportSuccess = false
    }

    private func scheduleExportSuccessAutoDismiss() {
        exportSuccessTask?.cancel()
        exportSuccessTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4.5))
            guard !Task.isCancelled else { return }
            showExportSuccess = false
            exportSuccessTask = nil
        }
    }

    // MARK: - Video export

    func exportVideo() {
        guard requireProForExport() else { return }
        showVideoOptions = true
    }

    /// Opens the frame-export options flow (macOS menu command). Pro-gated
    /// like video export.
    func exportFrame() {
        guard requireProForExport() else { return }
        showFrameOptions = true
    }

    /// Runs the offscreen GPU video export to `outputURL`. The caller has
    /// already resolved the destination (save panel on macOS, share sheet on
    /// iPadOS). Everything is snapshotted so the editor stays interactive.
    func runVideoExport(options: VideoExportOptions, outputURL: URL) {
        isExportingVideo = true
        videoExportProgress = 0
        videoExportError = nil
        showVideoSuccess = false
        showVideoOptions = false

        let previewPoints = previewPointSize()
        let backingScale = previewBackingScale()
        let inputs = makeSceneInputs()
        let timelineSnapshot = timeline
        let videoSnapshot = displayVideo

        let exporter = VideoExporter()
        videoExporter = exporter
        videoExportTask?.cancel()
        videoExportTask = Task { @MainActor in
            do {
                try await exporter.export(
                    timeline: timelineSnapshot,
                    previewPoints: previewPoints,
                    backingScale: backingScale,
                    inputs: inputs,
                    options: options,
                    outputURL: outputURL,
                    videoFrameProvider: videoSnapshot.map { controller in
                        { time in await controller.frame(at: time) }
                    },
                    onProgress: { p in self.videoExportProgress = p }
                )
                isExportingVideo = false
                lastExportedVideoURL = outputURL
                showVideoSuccess = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(4.5))
                    showVideoSuccess = false
                }
            } catch is CancellationError {
                isExportingVideo = false
                videoExportError = nil
            } catch {
                isExportingVideo = false
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if msg.lowercased().contains("cancel") {
                    videoExportError = nil
                } else {
                    videoExportError = msg
                    projectError = msg
                }
            }
            videoExporter = nil
            videoExportTask = nil
        }
    }

    func cancelVideoExport() {
        videoExporter?.cancel()
        videoExportTask?.cancel()
        isExportingVideo = false
        videoExportProgress = 0
    }

    func dismissVideoSuccess() { showVideoSuccess = false }

    func handleSaveErrorDismiss() {
        projectError = nil
    }

    // MARK: - Default screenshot

    /// Loads the bundled default screenshot for the given device into the
    /// display slot (used when the user hasn't provided one).
    func loadDefaultDisplayImage(for targetDevice: Device) {
        let name = targetDevice.defaultDisplayImageName
        let url = Bundle.main.url(forResource: name, withExtension: nil)
            ?? Bundle.main.url(
                forResource: name.replacingOccurrences(of: ".jpg", with: ""), withExtension: "jpg")
        guard let url, let img = PlatformImageLoader.image(contentsOf: url) else { return }
        displayVideo?.pause()
        displayVideo = nil
        displayFileName = name
        displayImage = img
    }
}

enum YomMockExportError: LocalizedError {
    case renderUnavailable
    case frameEncodeFailed
    case proRequired

    var errorDescription: String? {
        switch self {
        case .renderUnavailable: "The frame renderer could not be created."
        case .frameEncodeFailed: "Could not encode the rendered frame."
        case .proRequired: "Exporting requires YomMock Pro."
        }
    }
}
