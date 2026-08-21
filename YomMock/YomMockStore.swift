//
//  YomMockStore.swift
//  YomMock
//
//  Central document state for project save/restore.
//  Mirrors viewio's EditorModel save/load but simplified for YomMock's
//  single-window mock (phone finish, backdrop, timeline, screenshot).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Observation

@MainActor
@Observable
final class YomMockStore {
    // MARK: - Savable state (mirrors ContentView @State)

    var device: Device = .iPhone
    var lidAngle: Float = MacBookLidRig.defaultOpenAngle
    var selectedColor: iPhoneColor = .black
    var customColor = Color(red: 0.78, green: 0.32, blue: 0.36)
    var background: StudioBackground = .white
    var customBackground = Color.white
    var zoom: Float = 1
    var timeline: CameraTimeline = CameraTimeline.demoFromDefaultFile()
    var displayImage: NSImage?
    var displayFileName: String?

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
    /// Cached offscreen renderer for "Export Current Frame" stills — reused
    /// across exports so the USDZ + IBL setup cost is paid only once.
    @ObservationIgnored private var stillRenderer: OffscreenSceneRenderer?
    @ObservationIgnored private var stillRendererKey: String?

    /// Set by ContentView; returns the NSView hosting the 3D preview so
    /// exports can match its aspect ratio and backdrop scale.
    @ObservationIgnored var frameCaptureViewProvider: (() -> NSView?)?

    var windowTitle: String {
        let base: String
        if let url = projectURL {
            base = url.deletingPathExtension().lastPathComponent
        } else {
            base = "Untitled"
        }
        return isDirty ? "\(base) •" : base // macOS uses •, spec says * – support both: title shows *
        // Spec: * in title if not saved yet. Use * for compatibility.
        // We'll expose both via computed for UI: titleWithStar
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

    var canSave: Bool { true }

    init() {
        // Capture initial clean snapshot so dirty compares correctly
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
            displayFileName: displayFileName
        )
        return doc
    }

    func applyDocument(_ doc: YomMockProjectDocument, displayImage: NSImage?) {
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
        zoom = doc.zoom

        // Rebuild timeline from checkpoints
        let newCheckpoints: [CameraCheckpoint] = doc.checkpoints.map { pc in
            let pose = OrbitPose(yaw: pc.yaw, pitch: pc.pitch, radius: pc.radius)
            let id = UUID(uuidString: pc.id) ?? UUID()
            return CameraCheckpoint(id: id, time: pc.time, pose: pose, zoom: pc.zoom, pan: pc.pan, lidAngle: pc.lidAngle)
        }
        // Ensure sorted
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

        lastSavedSnapshot = doc
        isDirty = false
        projectError = nil
    }

    func markDirty() {
        guard !isRestoring else { return }
        let current = makeDocument()
        // Display image pixel changes are not captured in document equality
        // (only relative path), so we rely on the caller to have set dirty
        // for image changes. Here we compare full document for other fields.
        if let last = lastSavedSnapshot, current == last {
            isDirty = false
        } else if lastSavedSnapshot == nil {
            // No saved snapshot yet (untitled). Any change from initial demo counts as dirty
            // Compare to initial document captured at init.
            if current == lastSavedSnapshot {
                isDirty = false
            } else {
                // Initial lastSavedSnapshot is demo; if current != demo, dirty
                isDirty = true
                // Keep lastSavedSnapshot for comparison; don't overwrite until save
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

    // MARK: - Save / Open / New

    func newProject() {
        if isDirty {
            let alert = NSAlert()
            alert.messageText = "Unsaved Changes"
            alert.informativeText = "You have unsaved changes. Save the project before creating a new one?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Save…")
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            let resp = alert.runModal()
            if resp == .alertFirstButtonReturn {
                saveProject()
                if isDirty { return } // save cancelled or failed
            } else if resp == .alertThirdButtonReturn {
                return
            }
        }
        isRestoring = true
        device = .iPhone
        lidAngle = MacBookLidRig.defaultOpenAngle
        selectedColor = .black
        customColor = Color(red: 0.78, green: 0.32, blue: 0.36)
        background = .white
        customBackground = Color.white
        zoom = 1
        timeline = CameraTimeline.demoFromDefaultFile()
        displayImage = nil
        displayFileName = nil
        projectURL = nil
        isRestoring = false
        lastSavedSnapshot = makeDocument()
        isDirty = false
        projectError = nil
    }

    func saveProject() {
        if let url = projectURL {
            performSave(to: url)
        } else {
            saveProjectAs()
        }
    }

    func saveProjectAs() {
        let panel = NSSavePanel()
        panel.title = "Save YomMock Project"
        panel.message = "Save all checkpoints, colors and screenshot into a project."
        let base = projectURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.nameFieldStringValue = "\(base).\(YomMockProject.pathExtension)"
        panel.allowedContentTypes = [.yomMockProject]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let finalURL = url.pathExtension.lowercased() == YomMockProject.pathExtension ? url : url.appendingPathExtension(YomMockProject.pathExtension)
        performSave(to: finalURL)
    }

    func openProject() {
        if isDirty {
            let alert = NSAlert()
            alert.messageText = "Unsaved Changes"
            alert.informativeText = "You have unsaved changes. Save the project before opening another?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Save…")
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            let resp = alert.runModal()
            if resp == .alertFirstButtonReturn {
                saveProject()
                if isDirty { return }
            } else if resp == .alertThirdButtonReturn {
                return
            }
        }
        let panel = NSOpenPanel()
        panel.title = "Open YomMock Project"
        panel.message = "Choose a YomMock project to restore."
        panel.allowedContentTypes = [.yomMockProject]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url)
    }

    func openProject(at url: URL) {
        do {
            let loaded = try YomMockProject.load(from: url)
            projectURL = url
            applyDocument(loaded.document, displayImage: loaded.displayImage)
            projectError = nil
        } catch {
            projectError = error.localizedDescription
            // Present error via alert? Store will show in UI if needed.
        }
    }

    // MARK: - Frame export

    /// Renders the current timeline state offscreen on the GPU (4K class, any
    /// aspect) and saves it as a PNG. No screen capture — works with the
    /// window minimized or on another Space.
    func exportCurrentFrame() {
        let previewPoints = previewPointSize()
        let inputs = makeSceneInputs()
        let state = timeline.evaluatedState()
        Task { @MainActor in
            do {
                let size = VideoExportOptions(resolution: .p2160).outputSize(
                    previewPoints: previewPoints, backingScale: 1)
                let key = "\(device.rawValue)-\(Int(size.width))x\(Int(size.height))"
                if stillRenderer == nil || stillRendererKey != key {
                    stillRenderer = try await OffscreenSceneRenderer(
                        outputSize: size, previewPointSize: previewPoints, inputs: inputs)
                    stillRendererKey = key
                } else if let stillRenderer {
                    await stillRenderer.update(inputs: inputs)
                }
                guard let renderer = stillRenderer else { return }
                let buffer = try await renderer.render(
                    orbit: state.orbit, zoom: state.zoom, pan: state.pan, lidAngle: state.lidAngle, deltaTime: 1.0 / 30)
                guard let image = renderer.makeCGImage(from: buffer) else {
                    projectError = "Could not create an image from the rendered frame."
                    return
                }
                presentFrameSavePanel(for: image)
            } catch {
                projectError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Snapshot of everything the offscreen renderer needs — safe to keep
    /// editing the project while an export runs.
    private func makeSceneInputs() -> OffscreenSceneRenderer.Inputs {
        let gradient = background.gradient(custom: customBackground)
        let top = NSColor(gradient.top).usingColorSpace(.sRGB) ?? .white
        let bottom = NSColor(gradient.bottom).usingColorSpace(.sRGB) ?? .white
        let displayCG = displayImage.flatMap { try? PhoneStyling.sRGBCGImage(from: $0) }
        return OffscreenSceneRenderer.Inputs(
            device: device,
            finish: selectedColor.finish(custom: customColor),
            displayImage: displayCG,
            backgroundTop: top,
            backgroundBottom: bottom
        )
    }

    private func previewPointSize() -> CGSize {
        frameCaptureViewProvider?()?.bounds.size ?? CGSize(width: 1280, height: 800)
    }

    private func presentFrameSavePanel(for image: CGImage) {
        let panel = NSSavePanel()
        panel.title = "Export Current Frame"
        panel.message = "Save a screenshot of the current frame as a PNG image."
        let base = projectURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.nameFieldStringValue = "\(base) Frame.png"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let finalURL = url.pathExtension.lowercased() == "png" ? url : url.appendingPathExtension("png")
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            projectError = "Could not encode the frame as PNG."
            return
        }
        do {
            try data.write(to: finalURL, options: .atomic)
            lastExportedFrameURL = finalURL
            showExportSuccess = true
            scheduleExportSuccessAutoDismiss()
        } catch {
            projectError = error.localizedDescription
        }
    }

    func showExportedFrameInFinder() {
        guard let url = lastExportedFrameURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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

    // MARK: - Video export helpers

    func exportVideo() {
        // Offscreen rendering needs no window/screen — go straight to options.
        showVideoOptions = true
    }

    func startVideoExport() {
        // Called from options sheet after user picks format/resolution — now ask for location
        let options = pendingVideoOptions
        let base = projectURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        let panel = NSSavePanel()
        panel.title = "Export Video"
        panel.message = "Choose where to save the timeline video as \(options.format.rawValue)."
        panel.nameFieldStringValue = "\(base).\(options.fileExtension)"
        panel.allowedContentTypes = options.format == .mp4_h264 ? [.mpeg4Movie] : [.quickTimeMovie]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }
        // Ensure extension matches chosen format (user may have typed custom name without ext)
        let finalURL: URL = {
            let ext = options.fileExtension.lowercased()
            if outputURL.pathExtension.lowercased() == ext { return outputURL }
            if outputURL.pathExtension.isEmpty { return outputURL.appendingPathExtension(ext) }
            return outputURL.deletingPathExtension().appendingPathExtension(ext)
        }()
        // Remember for next time
        pendingVideoExportURL = finalURL

        isExportingVideo = true
        videoExportProgress = 0
        videoExportError = nil
        showVideoSuccess = false
        showVideoOptions = false

        // Snapshot everything the export needs; the timeline + scene stay
        // fully editable while the GPU renders offscreen.
        let previewPoints = previewPointSize()
        let backingScale = frameCaptureViewProvider?()?.window?.backingScaleFactor ?? 2
        let inputs = makeSceneInputs()
        let timelineSnapshot = timeline

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
                    outputURL: finalURL,
                    onProgress: { p in self.videoExportProgress = p }
                )
                isExportingVideo = false
                lastExportedVideoURL = finalURL
                showVideoSuccess = true
                // Auto-hide after 5s (like image export)
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

    func showExportedVideoInFinder() {
        guard let url = lastExportedVideoURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func dismissVideoSuccess() { showVideoSuccess = false }

    private func performSave(to url: URL) {
        do {
            let doc = makeDocument()
            let saved = try YomMockProject.save(to: url, document: doc, displayImage: displayImage)
            projectURL = url
            lastSavedSnapshot = saved
            isDirty = false
            projectError = nil
        } catch {
            projectError = error.localizedDescription
        }
    }

    func handleSaveErrorDismiss() {
        projectError = nil
    }
}
