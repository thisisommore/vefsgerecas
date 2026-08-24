//
//  AutosaveTests.swift
//  YomMockTests
//

import CoreGraphics
import Foundation
import Testing
@testable import YomMock

@MainActor
struct AutosaveTests {
    /// Isolates each test's recovery storage.
    private func makeIsolatedRecoveryDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YomMockAutosaveTests-\(UUID().uuidString)", isDirectory: true)
        RecoveryStore.directoryOverride = dir
        return dir
    }

    @Test func recoveryRoundTripRestoresDocumentAndImage() throws {
        let dir = makeIsolatedRecoveryDirectory()
        defer {
            try? FileManager.default.removeItem(at: dir)
            RecoveryStore.directoryOverride = nil
        }

        var doc = YomMockProjectDocument(
            version: YomMockProjectDocument.currentVersion,
            deviceRaw: Device.macBookPro.rawValue,
            selectedColorRaw: "black",
            customColor: nil,
            backgroundRaw: "slate",
            customBackground: nil,
            zoom: 1.2,
            lidAngle: 90,
            timelineDuration: 8,
            timelineCurrentTime: 0,
            checkpoints: [ProjectCheckpoint(time: 0, yaw: 0, pitch: 0.015, radius: 4.2, zoom: 1)],
            selectedCheckpointID: nil,
            displayRelativePath: nil,
            displayFileName: nil
        )
        doc.camera = StudioCameraSettings(fieldOfView: 42)

        let image = PlatformImageLoader.image(data: PlatformImageLoader.pngData(
            from: makeSolidCGImage())!)
        let id = UUID()
        RecoveryStore.write(
            id: id,
            payload: RecoveryPayload(
                savedAt: Date(), projectURL: nil, displayVideoURL: nil, document: doc),
            displayImage: image)

        let pending = RecoveryStore.pending()
        #expect(pending != nil)
        #expect(pending?.id == id)
        #expect(pending?.payload.document.deviceRaw == Device.macBookPro.rawValue)
        #expect(pending?.payload.document.camera?.fieldOfView == 42)
        #expect(pending?.displayImage != nil)

        RecoveryStore.remove(id: id)
        #expect(RecoveryStore.pending() == nil)
    }

    @Test func dirtyStoreWritesAndCleanStoreClearsRecovery() throws {
        let dir = makeIsolatedRecoveryDirectory()
        defer {
            try? FileManager.default.removeItem(at: dir)
            RecoveryStore.directoryOverride = nil
        }

        let store = YomMockStore()
        store.device = .macBookPro
        store.markDirty()
        store.writeRecoverySnapshotNow()

        let pending = RecoveryStore.pending()
        #expect(pending?.payload.document.deviceRaw == Device.macBookPro.rawValue)

        // Saving must clear the recovery slot — the work is on disk now.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("autosave-test-\(UUID().uuidString)")
            .appendingPathExtension("yommock")
        defer { try? FileManager.default.removeItem(at: url) }
        store.performSave(to: url)
        #expect(RecoveryStore.pending() == nil)
    }

    @Test func restoreRecoveryAppliesStateAndFlagsDirty() {
        let dir = makeIsolatedRecoveryDirectory()
        defer {
            try? FileManager.default.removeItem(at: dir)
            RecoveryStore.directoryOverride = nil
        }

        let store = YomMockStore()
        store.device = .macBookPro
        store.camera.setFocalLength(24)
        store.markDirty()
        store.writeRecoverySnapshotNow()
        let pending = RecoveryStore.pending()
        #expect(pending != nil)

        let fresh = YomMockStore()
        #expect(fresh.device == .iPhone)
        fresh.restoreRecovery(pending!)

        #expect(fresh.device == .macBookPro)
        #expect(abs(fresh.camera.focalLength - 24) < 0.01)
        #expect(fresh.isDirty)  // recovered work is unsaved
        // Restoring consumed the slot.
        #expect(RecoveryStore.pending() == nil)
    }

    @Test func resetAndOpenClearRecoverySlot() {
        let dir = makeIsolatedRecoveryDirectory()
        defer {
            try? FileManager.default.removeItem(at: dir)
            RecoveryStore.directoryOverride = nil
        }

        let store = YomMockStore()
        store.device = .macBookPro
        store.markDirty()
        store.writeRecoverySnapshotNow()
        #expect(RecoveryStore.pending() != nil)

        store.resetToNewProject()
        #expect(RecoveryStore.pending() == nil)
    }
}

/// 8×8 red image for display-content round trips.
nonisolated func makeSolidCGImage() -> CGImage {
    let width = 8, height = 8
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}
