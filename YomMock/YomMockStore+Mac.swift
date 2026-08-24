//
//  YomMockStore+Mac.swift
//  YomMock
//
//  macOS-only flows: NSSavePanel/NSOpenPanel document management, frame
//  export to disk and Finder reveal.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension YomMockStore {
    // MARK: - New project (with unsaved-changes prompt)

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
        resetToNewProject()
    }

    // MARK: - Save / Open

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

    func openProjectWithPrompt() {
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

    // MARK: - Frame export

    /// Renders the current timeline state offscreen on the GPU (4K class) and
    /// saves it after asking for a location. Transparent background removes the studio gradient.
    func exportCurrentFrame() {
        guard requireProForExport() else { return }
        // Capture pending options at call time
        let format = pendingFrameFormat
        let transparent = pendingFrameTransparent
        Task { @MainActor in
            do {
                let data = try await renderFrameData(format: format, transparentBackground: transparent)
                presentFrameSavePanel(for: data, format: format)
            } catch {
                projectError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Direct export for accessory preview or tests
    func exportCurrentFrame(format: FrameExportFormat, transparentBackground: Bool) {
        pendingFrameFormat = format
        pendingFrameTransparent = transparentBackground
        exportCurrentFrame()
    }

    private func presentFrameSavePanel(for data: Data, format: FrameExportFormat) {
        let panel = NSSavePanel()
        panel.title = "Export Current Frame"
        panel.message = format == .webp
            ? "Save a transparent WebP or PNG of the current frame."
            : "Save a screenshot of the current frame."
        let base = projectURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.nameFieldStringValue = "\(base) Frame.\(format.fileExtension)"
        if format == .png {
            panel.allowedContentTypes = [.png]
        } else {
            panel.allowedContentTypes = [UTType("org.webmproject.webp") ?? .png, .png]
            if let webp = UTType("org.webmproject.webp") {
                panel.allowedContentTypes = [webp, .png]
            }
        }
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        // Accessory for format + transparency — lightweight custom view
        // Note: keep panel accessory simple to avoid AppKit lifecycle issues; user can also change via Inspector toggle.
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let ext = format.fileExtension.lowercased()
        let finalURL: URL = {
            if url.pathExtension.lowercased() == ext { return url }
            if url.pathExtension.lowercased() == "png" || url.pathExtension.lowercased() == "webp" {
                return url.deletingPathExtension().appendingPathExtension(ext)
            }
            if url.pathExtension.isEmpty { return url.appendingPathExtension(ext) }
            return url.deletingPathExtension().appendingPathExtension(ext)
        }()
        do {
            try data.write(to: finalURL, options: .atomic)
            presentExportedFile(frameURL: finalURL)
        } catch {
            projectError = error.localizedDescription
        }
    }

    private func presentFrameSavePanel(for data: Data) {
        presentFrameSavePanel(for: data, format: pendingFrameFormat)
    }

    func showExportedFrameInFinder() {
        guard let url = lastExportedFrameURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func showExportedVideoInFinder() {
        guard let url = lastExportedVideoURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Video export destination

    /// Asks for a location, then kicks off the offscreen GPU render.
    func startVideoExport() {
        guard requireProForExport() else { return }
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
        let finalURL: URL = {
            let ext = options.fileExtension.lowercased()
            if outputURL.pathExtension.lowercased() == ext { return outputURL }
            if outputURL.pathExtension.isEmpty { return outputURL.appendingPathExtension(ext) }
            return outputURL.deletingPathExtension().appendingPathExtension(ext)
        }()
        pendingVideoExportURL = finalURL
        runVideoExport(options: options, outputURL: finalURL)
    }
}
