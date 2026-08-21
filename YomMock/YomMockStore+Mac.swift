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
    /// saves it as a PNG after asking for a location.
    func exportCurrentFrame() {
        Task { @MainActor in
            do {
                let data = try await renderFramePNGData()
                presentFrameSavePanel(for: data)
            } catch {
                projectError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func presentFrameSavePanel(for data: Data) {
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
        do {
            try data.write(to: finalURL, options: .atomic)
            presentExportedFile(frameURL: finalURL)
        } catch {
            projectError = error.localizedDescription
        }
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
