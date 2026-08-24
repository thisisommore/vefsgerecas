//
//  UndoRedoTests.swift
//  YomMockTests
//

import Foundation
import Testing
@testable import YomMock

@MainActor
struct UndoRedoTests {
    @Test func markDirtyWithoutChangeDoesNotRecord() {
        let store = YomMockStore()
        store.markDirty()
        #expect(!store.canUndo)
        #expect(!store.canRedo)
    }

    @Test func undoRestoresPreviousDeviceAndRedoReapplies() {
        let store = YomMockStore()
        #expect(store.device == .iPhone)

        store.device = .macBookPro
        store.markDirty()
        #expect(store.canUndo)

        store.undo()
        #expect(store.device == .iPhone)
        #expect(store.canRedo)

        store.redo()
        #expect(store.device == .macBookPro)
        #expect(!store.canRedo)
        #expect(store.canUndo)
    }

    @Test func rapidMarksCoalesceIntoSingleStep() {
        let store = YomMockStore()
        let original = store.lidAngle

        store.lidAngle = 40
        store.markDirty()
        store.lidAngle = 55
        store.markDirty()  // within the coalesce window → same step
        store.lidAngle = 70
        store.markDirty()

        #expect(store.canUndo)
        store.undo()
        #expect(abs(store.lidAngle - original) < 0.001)
        #expect(!store.canUndo)  // everything was one step
    }

    @Test func undoRestoresCheckpointDeletion() {
        let store = YomMockStore()
        let countBefore = store.timeline.checkpoints.count

        store.timeline.checkpoints.removeLast()
        store.markDirty()
        #expect(store.timeline.checkpoints.count == countBefore - 1)

        store.undo()
        #expect(store.timeline.checkpoints.count == countBefore)
    }

    @Test func undoRestoresCameraSettings() {
        let store = YomMockStore()
        store.camera.setFocalLength(24)
        store.markDirty()

        store.undo()
        #expect(abs(store.camera.focalLength - StudioCameraSettings.default.focalLength) < 0.01)
    }

    @Test func undoAfterUndoReappliesInOrder() {
        // Force distinct steps — the default 0.6s window would merge the
        // two rapid edits into one.
        YomMockStore.undoCoalesceWindow = 0
        defer { YomMockStore.undoCoalesceWindow = 0.6 }
        let store = YomMockStore()
        store.device = .macBookPro
        store.markDirty()
        store.background = .slate
        store.markDirty()

        store.undo()
        #expect(store.background == .white)
        #expect(store.device == .macBookPro)  // device edit still applied

        store.undo()
        #expect(store.device == .iPhone)

        store.redo()
        store.redo()
        #expect(store.device == .macBookPro)
        #expect(store.background == .slate)
    }

    @Test func resetClearsHistory() {
        let store = YomMockStore()
        store.device = .macBookPro
        store.markDirty()
        #expect(store.canUndo)

        store.resetToNewProject()
        #expect(!store.canUndo)
        #expect(!store.canRedo)
    }

    @Test func newEditAfterUndoClearsRedoBranch() {
        YomMockStore.undoCoalesceWindow = 0
        defer { YomMockStore.undoCoalesceWindow = 0.6 }
        let store = YomMockStore()
        store.device = .macBookPro
        store.markDirty()
        store.undo()

        #expect(store.canRedo)
        store.background = .slate
        store.markDirty()
        #expect(!store.canRedo)
    }

    @Test func undoDoesNotMarkProjectClean() {
        let store = YomMockStore()
        store.device = .macBookPro
        store.markDirty()
        #expect(store.isDirty)

        store.undo()
        // Undoing back to the saved state may clean; but undoing a saved
        // edit must re-dirty. Simulate: save, edit, undo.
        store.markClean()
        #expect(!store.isDirty)

        store.device = .macBookPro
        store.markDirty()
        #expect(store.isDirty)

        store.undo()
        #expect(!store.isDirty)  // back to the saved state
    }
}
