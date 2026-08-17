//
//  YomMockTests.swift
//  YomMockTests
//
//  Created by Om More on 14/08/26.
//

import Foundation
import Testing
import simd
@testable import YomMock

struct CameraTimelineTests {
    @Test @MainActor func startsWithDefaultCheckpoint() {
        let timeline = CameraTimeline()
        #expect(timeline.checkpoints.count == 1)
        #expect(timeline.checkpoints[0].time == 0)
        #expect(timeline.checkpoints[0].pose == .default)
        #expect(timeline.checkpoints[0].zoom == 1)
        #expect(timeline.duration == 12)
        #expect(timeline.currentFrame == 1)
        let state = timeline.evaluatedState()
        #expect(state.zoom == 1)
        #expect(state.orbit == .default)
    }

    @Test @MainActor func saveInsertsSortedCheckpointAndSelectsIt() {
        let timeline = CameraTimeline()
        let late = timeline.saveCheckpoint(
            at: 8, pose: .default, zoom: 2)
        let early = timeline.saveCheckpoint(
            at: 2, pose: .default, zoom: 1.5)

        #expect(late.id != early.id)
        #expect(timeline.checkpoints.count == 3)
        #expect(timeline.checkpoints.map(\.time) == timeline.checkpoints.map(\.time).sorted())
        #expect(timeline.selectedCheckpointID == early.id)
    }

    @Test @MainActor func saveUpdatesExistingCheckpointAtSameTime() {
        let timeline = CameraTimeline()
        let first = timeline.saveCheckpoint(at: 2, pose: .default, zoom: 1.5)
        let updated = timeline.saveCheckpoint(at: 2, pose: .default, zoom: 4)

        #expect(first.id == updated.id)
        #expect(timeline.checkpoints.count == 2)
        #expect(abs(timeline.checkpoints[1].zoom - 4) < 0.000_1)
        #expect(timeline.checkpointAtPlayhead != nil)  // playhead at 0 has default checkpoint
        #expect(timeline.checkpointAtPlayhead?.time == 0)
        timeline.seek(to: 1)
        #expect(timeline.checkpointAtPlayhead == nil)  // no checkpoint at 1
    }

    @Test @MainActor func saveClampsIntoDuration() {
        let timeline = CameraTimeline()
        timeline.saveCheckpoint(at: -5, pose: .default, zoom: 2)
        timeline.saveCheckpoint(at: 99, pose: .default, zoom: 3)

        #expect(timeline.checkpoints[0].time == 0)
        #expect(timeline.checkpoints.last?.time == 12)
    }

    @Test @MainActor func checkpointAtPlayheadMatchesWithinFrame() {
        let timeline = CameraTimeline()
        timeline.saveCheckpoint(at: 4.1, pose: .default, zoom: 2)
        timeline.seek(to: 4.1)
        #expect(timeline.checkpointAtPlayhead != nil)
        #expect(abs((timeline.checkpointAtPlayhead?.time ?? -1) - 4.1) < CameraTimeline.snapTolerance)

        timeline.seek(to: 5)
        #expect(timeline.checkpointAtPlayhead == nil)
    }

    @Test @MainActor func deletesCheckpointButKeepsOne() {
        let timeline = CameraTimeline()
        let a = timeline.saveCheckpoint(at: 2, pose: .default, zoom: 2)
        let b = timeline.saveCheckpoint(at: 6, pose: .default, zoom: 3)

        timeline.deleteCheckpoint(id: a.id)
        #expect(timeline.checkpoints.map(\.id).contains(b.id))
        #expect(!timeline.checkpoints.map(\.id).contains(a.id))

        // The initial checkpoint can't be removed below one total.
        timeline.deleteCheckpoint(id: b.id)
        timeline.deleteCheckpoint(id: b.id)
        #expect(timeline.checkpoints.count == 1)
    }

    @Test @MainActor func evaluatedStateInterpolatesBetweenCheckpoints() {
        let timeline = CameraTimeline()
        let base = OrbitPose(yaw: radians(0), pitch: 0, radius: 1)
        let target = OrbitPose(yaw: radians(20), pitch: 0.2, radius: 1.4)
        timeline.saveCheckpoint(at: 0, pose: base, zoom: 1)
        timeline.saveCheckpoint(at: 4, pose: target, zoom: 3)

        let start = timeline.evaluatedState(at: 0)
        #expect(start.orbit.yaw == 0)
        #expect(abs(start.zoom - 1) < 0.000_1)

        let end = timeline.evaluatedState(at: 4)
        #expect(abs(end.orbit.yaw - radians(20)) < 0.000_1)
        #expect(abs(end.zoom - 3) < 0.000_1)

        let mid = timeline.evaluatedState(at: 2)
        let eased = CameraTimeline.easeInOut(0.5)
        #expect(abs(angleDelta(mid.orbit.yaw, base.yaw + (target.yaw - base.yaw) * eased)) < 0.000_1)
        #expect(abs(mid.zoom - (1 + (3 - 1) * eased)) < 0.000_1)
    }

    @Test @MainActor func evaluatedStateHoldsOutsideOuterKeyframes() {
        let timeline = CameraTimeline()
        let early = OrbitPose(yaw: radians(10), pitch: 0, radius: 1)
        let late = OrbitPose(yaw: radians(40), pitch: 0.1, radius: 1.3)
        timeline.saveCheckpoint(at: 2, pose: early, zoom: 2)
        timeline.saveCheckpoint(at: 6, pose: late, zoom: 4)

        let before = timeline.evaluatedState(at: 0)
        // With default checkpoint at 0, before holds default, not early
        #expect(before.orbit == .default)
        #expect(abs(before.zoom - 1) < 0.000_1)

        let between = timeline.evaluatedState(at: 1)
        // Between default (0) and early (2) interpolates, not exactly early
        #expect(between.orbit.yaw != early.yaw)

        let after = timeline.evaluatedState(at: 12)
        #expect(after.orbit.yaw == late.yaw)
        #expect(abs(after.zoom - 4) < 0.000_1)

        // Also verify that with only early/late (no default), before holds early
        let clean = CameraTimeline()
        clean.checkpoints = []
        clean.saveCheckpoint(at: 2, pose: early, zoom: 2)
        clean.saveCheckpoint(at: 6, pose: late, zoom: 4)
        let cleanBefore = clean.evaluatedState(at: 0)
        #expect(cleanBefore.orbit.yaw == early.yaw)
    }

    @Test @MainActor func updateSelectedCheckpointEditsOnlyThatKey() {
        let timeline = CameraTimeline()
        let first = timeline.saveCheckpoint(at: 2, pose: .default, zoom: 2)
        timeline.saveCheckpoint(at: 6, pose: .default, zoom: 3)

        timeline.selectedCheckpointID = first.id
        timeline.updateSelectedCheckpoint(zoom: 5)
        #expect(abs(timeline.checkpoints[1].zoom - 5) < 0.000_1)
        #expect(abs(timeline.checkpoints[2].zoom - 3) < 0.000_1)

        let pose = OrbitPose(yaw: 0.4, pitch: 0.05, radius: 0.7)
        timeline.updateSelectedCheckpoint(pose: pose)
        #expect(timeline.checkpoints[1].pose == pose)
        #expect(timeline.checkpoints[2].pose == .default)
    }

    @Test @MainActor func selectSeeksToCheckpointTime() {
        let timeline = CameraTimeline()
        let checkpoint = timeline.saveCheckpoint(at: 7, pose: .default, zoom: 2)
        timeline.select(checkpoint)
        #expect(abs(timeline.currentTime - 7) < 0.000_1)
        #expect(timeline.selectedCheckpointID == checkpoint.id)
    }

    @Test @MainActor func seedBasePoseFreezesAtFirstCheckpoint() {
        let timeline = CameraTimeline()
        let live = OrbitPose(position: SIMD3<Float>(0.4, 0.1, 0.8))
        timeline.seedBasePoseIfDefault(live)
        #expect(timeline.checkpoints[0].pose == live)

        timeline.saveCheckpoint(at: 3, pose: live, zoom: 2)
        let later = OrbitPose(position: SIMD3<Float>(0.1, 0.2, 0.1))
        timeline.seedBasePoseIfDefault(later)
        #expect(timeline.checkpoints[0].pose == live)
    }

    @Test @MainActor func durationCannotShrinkPastLatestCheckpoint() {
        let timeline = CameraTimeline()
        timeline.saveCheckpoint(at: 8, pose: .default, zoom: 2)

        timeline.setDuration(3)
        #expect(abs(timeline.duration - 8) < 0.000_1)
        #expect(abs(timeline.minDuration - 8) < 0.000_1)
    }

    @Test @MainActor func removeClearsSelection() {
        let timeline = CameraTimeline()
        let checkpoint = timeline.saveCheckpoint(at: 2, pose: .default, zoom: 2)
        #expect(timeline.selectedCheckpointID == checkpoint.id)

        timeline.deleteCheckpoint(id: checkpoint.id)
        #expect(timeline.selectedCheckpointID == nil)
    }

    @Test func orbitPoseKeepsRotation() {
        let start = OrbitPose(position: SIMD3<Float>(0.15, 0.045, 0.30))
        #expect(almostEqual(start.position, SIMD3<Float>(0.15, 0.045, 0.30)))

        let rotated = OrbitPose(
            yaw: start.yaw + 1.2,
            pitch: start.pitch + 0.3,
            radius: start.radius
        )
        let mid = start.interpolated(to: rotated, t: 0.5)
        #expect(abs(mid.yaw - (start.yaw + 0.6)) < 0.000_1)
        #expect(abs(mid.pitch - (start.pitch + 0.15)) < 0.000_1)
        #expect(abs(mid.radius - start.radius) < 0.000_1)
    }

    @Test func interpolatesYawAlongTheShortArc() {
        let start = Spherical(radius: 1, yaw: 3, pitch: 0)
        let end = Spherical(radius: 1, yaw: -3, pitch: 0)
        let mid = start.interpolated(to: end, t: 0.5)
        #expect(abs(mid.yaw) > 3)
    }

    @Test @MainActor func playRestartsAtTheEnd() {
        let timeline = CameraTimeline()
        timeline.seek(to: 12)
        timeline.togglePlay()
        #expect(timeline.currentTime == 0)
        #expect(timeline.isPlaying)
    }
}

private func radians(_ degrees: Float) -> Float {
    degrees * .pi / 180
}

private func angleDelta(_ lhs: Float, _ rhs: Float) -> Float {
    var delta = lhs - rhs
    if delta > .pi { delta -= 2 * .pi }
    if delta < -.pi { delta += 2 * .pi }
    return delta
}

private func almostEqual(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>, epsilon: Float = 0.0001) -> Bool {
    simd_length(lhs - rhs) < epsilon
}
