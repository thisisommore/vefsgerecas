//
//  YomMockStore+iPad.swift
//  YomMock-iPad
//
//  iPadOS-only flows: Files-app import (security-scoped copies), in-place
//  sandbox save, share-sheet exports.
//

import SwiftUI
import UniformTypeIdentifiers

extension YomMockStore {
    /// Imports a `.yommock` package from the Files app / another app into the
    /// app's own Documents directory and opens it. Copying sidesteps
    /// security-scoped access expiring between sessions.
    @discardableResult
    func importProject(from externalURL: URL) -> Bool {
        let scoped = externalURL.startAccessingSecurityScopedResource()
        defer { if scoped { externalURL.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let importsDir = docs.appendingPathComponent("Projects", isDirectory: true)
        try? fm.createDirectory(at: importsDir, withIntermediateDirectories: true)

        var name = externalURL.deletingPathExtension().lastPathComponent
        if name.isEmpty { name = "Imported" }
        var destination = importsDir.appendingPathComponent(name).appendingPathExtension("yommock")
        var counter = 2
        while fm.fileExists(atPath: destination.path) {
            destination = importsDir
                .appendingPathComponent("\(name) \(counter)")
                .appendingPathExtension("yommock")
            counter += 1
        }

        do {
            try fm.copyItem(at: externalURL, to: destination)
            openProject(at: destination)
            return true
        } catch {
            projectError = error.localizedDescription
            return false
        }
    }

    /// Saves to the project's current in-sandbox URL, or to Documents under
    /// the project name when untitled. Returns the saved URL.
    @discardableResult
    func saveProjectToSandbox() -> URL? {
        let url: URL
        if let existing = projectURL {
            url = existing
        } else {
            let fm = FileManager.default
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? fm.temporaryDirectory
            let projectsDir = docs.appendingPathComponent("Projects", isDirectory: true)
            try? fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
            url = projectsDir
                .appendingPathComponent(displayName == "Untitled" ? "Untitled" : displayName)
                .appendingPathExtension("yommock")
        }
        performSave(to: url)
        return projectError == nil ? url : nil
    }

    /// Saves the project under a new name inside Documents/Projects, updating
    /// `projectURL`/`displayName`. When the name changed and the previous
    /// file lives in the same Projects directory, the old file is removed.
    @discardableResult
    func saveProjectToSandboxAs(_ newName: String) -> URL? {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let projectsDir = docs.appendingPathComponent("Projects", isDirectory: true)
        try? fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        let url = projectsDir
            .appendingPathComponent(trimmed)
            .appendingPathExtension("yommock")
        let previousURL = projectURL
        performSave(to: url)
        guard projectError == nil else { return nil }
        if let previousURL, previousURL != url,
            previousURL.deletingLastPathComponent().standardizedFileURL
                == projectsDir.standardizedFileURL
        {
            try? fm.removeItem(at: previousURL)
        }
        return url
    }

    /// Renders the current frame offscreen at 4K class and writes it to a
    /// temporary PNG ready for the share sheet.
    func exportFrameForSharing() async throws -> URL {
        let data = try await renderFramePNGData()
        let base = displayName
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(base) Frame-\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension("png")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Starts a video export to a temporary file; the share sheet is shown
    /// through `lastExportedVideoURL` once it finishes.
    func startVideoExportToTempFile() {
        let options = pendingVideoOptions
        let base = displayName
        let ext = options.fileExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(base)-\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension(ext)
        pendingVideoExportURL = url
        runVideoExport(options: options, outputURL: url)
    }
}
