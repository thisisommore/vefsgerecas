//
//  RecoveryStore.swift
//  YomMockCore
//
//  Crash-recovery autosave: periodically writes the in-progress session to
//  a sandbox directory (never touching the user's project file), and offers
//  to restore it on the next launch. One recovery slot per editor session
//  (window on macOS, scene on iPadOS).
//

import Foundation

/// Everything needed to restore an unsaved session.
struct RecoveryPayload: Codable, Equatable {
    /// When the snapshot was written.
    var savedAt: Date
    /// The project file this session edits, if it has been saved before.
    /// Restore points ⌘S at this URL.
    var projectURL: URL?
    /// Best-effort: the temporary file backing an active screen recording.
    /// May be gone after a reboot — the poster image is the fallback.
    var displayVideoURL: URL?
    /// The full serializable edit state.
    var document: YomMockProjectDocument
}

enum RecoveryStoreError: LocalizedError {
    case encodeFailed

    var errorDescription: String? { "Could not write the autosave snapshot." }
}

@MainActor
enum RecoveryStore {
    private static let documentFileName = "recovery.json"
    private static let displayFileName = "display.png"

    /// Test hook — redirects the storage directory.
    nonisolated(unsafe) static var directoryOverride: URL?

    /// Container-scoped, so the same path works sandboxed on macOS and iPadOS.
    static func directory() -> URL {
        if let directoryOverride { return directoryOverride }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("YomMockRecovery", isDirectory: true)
    }

    private static func slotURL(_ id: UUID) -> URL {
        directory().appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Writes a recovery snapshot for the given session slot. Best-effort by
    /// design — callers swallow failures; autosave must never interrupt work.
    static func write(
        id: UUID, payload: RecoveryPayload, displayImage: PlatformImage?,
        backgroundImage: PlatformImage? = nil
    ) {
        let fm = FileManager.default
        let slot = slotURL(id)
        let assets = slot.appendingPathComponent(YomMockProject.assetsDirectoryName, isDirectory: true)
        do {
            try fm.createDirectory(at: assets, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            try data.write(to: slot.appendingPathComponent(documentFileName), options: .atomic)

            if let displayImage,
                let cg = PlatformImageLoader.cgImage(from: displayImage),
                let png = PlatformImageLoader.pngData(from: cg)
            {
                try png.write(
                    to: assets.appendingPathComponent(YomMockProject.displayFileName),
                    options: .atomic)
            } else {
                try? fm.removeItem(at: assets.appendingPathComponent(YomMockProject.displayFileName))
            }

            if let backgroundImage,
                let cg = PlatformImageLoader.cgImage(from: backgroundImage),
                let png = PlatformImageLoader.pngData(from: cg)
            {
                try png.write(
                    to: assets.appendingPathComponent(YomMockProject.backgroundFileName),
                    options: .atomic)
            } else {
                try? fm.removeItem(at: assets.appendingPathComponent(YomMockProject.backgroundFileName))
            }
        } catch {
            // Best effort — drop a half-written slot so it never restores.
            try? fm.removeItem(at: slot)
        }
    }

    struct Pending {
        let id: UUID
        let payload: RecoveryPayload
        let displayImage: PlatformImage?
        let backgroundImage: PlatformImage?
    }

    /// The most recent recoverable session, if any.
    static func pending() -> Pending? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory(), includingPropertiesForKeys: [.contentModificationDateKey])
        else { return nil }
        let slots = entries
            .filter { $0.hasDirectoryPath }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
        for slot in slots {
            guard let id = UUID(uuidString: slot.lastPathComponent),
                let pending = read(slot: slot, id: id)
            else { continue }
            return pending
        }
        return nil
    }

    private static func read(slot: URL, id: UUID) -> Pending? {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard
            let data = try? Data(contentsOf: slot.appendingPathComponent(documentFileName)),
            let payload = try? decoder.decode(RecoveryPayload.self, from: data)
        else {
            // Unreadable slot — drop it so it doesn't block future recoveries.
            try? fm.removeItem(at: slot)
            return nil
        }
        let displayURL = slot
            .appendingPathComponent(YomMockProject.assetsDirectoryName, isDirectory: true)
            .appendingPathComponent(YomMockProject.displayFileName)
        let displayImage = fm.fileExists(atPath: displayURL.path)
            ? PlatformImageLoader.image(contentsOf: displayURL)
            : nil
        let backgroundURL = slot
            .appendingPathComponent(YomMockProject.assetsDirectoryName, isDirectory: true)
            .appendingPathComponent(YomMockProject.backgroundFileName)
        let backgroundImage = fm.fileExists(atPath: backgroundURL.path)
            ? PlatformImageLoader.image(contentsOf: backgroundURL)
            : nil
        return Pending(id: id, payload: payload, displayImage: displayImage, backgroundImage: backgroundImage)
    }

    /// Deletes the slot once the session is saved, discarded or restored.
    static func remove(id: UUID) {
        try? FileManager.default.removeItem(at: slotURL(id))
    }
}
