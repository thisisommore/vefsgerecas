//
//  YomMockTests.swift
//  YomMockTests
//
//  Created by Om More on 14/08/26.
//

import Testing
import simd
@testable import YomMock

struct CameraTimelineTests {
    @Test @MainActor func startsWithOneDefaultCheckpoint() {
        let timeline = CameraTimeline()
        #expect(timeline.checkpoints.count == 1)
        #expect(timeline.checkpoints[0].time == 0)
        #expect(timeline.checkpoints[0].pose == .default)
        #expect(timeline.duration == 12)
        #expect(timeline.currentFrame == 1)
        #expect(abs(timeline.checkpoints[0].pose.zoom - 1) < 0.0001)
    }

    @Test func poseKeepsRotationAndZoom() {
        let start = CameraPose(position: SIMD3<Float>(0.15, 0.045, 0.30), zoom: 1)
        #expect(almostEqual(start.position, SIMD3<Float>(0.15, 0.045, 0.30)))

        let rotated = CameraPose(
            yaw: start.yaw + 1.2,
            pitch: start.pitch + 0.3,
            radius: start.radius,
            zoom: 2.4
        )
        let mid = start.interpolated(to: rotated, t: 0.5)
        #expect(abs(mid.yaw - (start.yaw + 0.6)) < 0.0001)
        #expect(abs(mid.pitch - (start.pitch + 0.15)) < 0.0001)
        #expect(abs(mid.zoom - 1.7) < 0.0001)
        #expect(abs(mid.radius - start.radius) < 0.0001)
    }

    @Test @MainActor func evaluatesSavedCheckpointAndMidpoint() {
        let timeline = CameraTimeline()
        let end = CameraPose(position: SIMD3<Float>(0, 0.05, -0.3), zoom: 2)
        timeline.upsert(pose: end, at: 12)

        #expect(timeline.checkpoints.count == 2)
        #expect(almostEqual(timeline.evaluatedPose(at: 0).position, CameraPose.default.position))
        #expect(abs(timeline.evaluatedPose(at: 0).zoom - 1) < 0.0001)
        #expect(almostEqual(timeline.evaluatedPose(at: 12).position, end.position))
        #expect(abs(timeline.evaluatedPose(at: 12).zoom - 2) < 0.0001)

        let mid = timeline.evaluatedPose(at: 6)
        let expected = CameraPose.default.interpolated(to: end, t: 0.5)
        #expect(almostEqual(mid.position, expected.position))
        #expect(abs(mid.zoom - expected.zoom) < 0.0001)
        #expect(abs(mid.yaw - expected.yaw) < 0.0001)
        #expect(abs(mid.pitch - expected.pitch) < 0.0001)
    }

    @Test @MainActor func upsertReplacesNearbyCheckpoint() {
        let timeline = CameraTimeline()
        let first = CameraPose(position: SIMD3<Float>(0.2, 0.1, 0.2), zoom: 1.2)
        let second = CameraPose(position: SIMD3<Float>(0.3, 0.1, 0.1), zoom: 1.4)
        timeline.upsert(pose: first, at: 4)
        timeline.upsert(pose: second, at: 4 + 1 / 60)

        #expect(timeline.checkpoints.count == 2)
        #expect(almostEqual(timeline.checkpoints[1].pose.position, second.position))
        #expect(abs(timeline.checkpoints[1].pose.zoom - 1.4) < 0.0001)
    }

    @Test @MainActor func keepsAtLeastOneCheckpoint() {
        let timeline = CameraTimeline()
        let only = timeline.checkpoints[0]
        timeline.deleteCheckpoint(id: only.id)
        #expect(timeline.checkpoints.count == 1)
    }

    @Test func interpolatesYawAlongTheShortArc() {
        let start = Spherical(radius: 1, yaw: 3, pitch: 0)
        let end = Spherical(radius: 1, yaw: -3, pitch: 0)
        let mid = start.interpolated(to: end, t: 0.5)
        #expect(abs(mid.yaw) > 3)
    }

    @Test @MainActor func playRestartsAtTheEnd() {
        let timeline = CameraTimeline()
        timeline.upsert(pose: .default, at: 12)
        timeline.seek(to: 12)
        timeline.togglePlay()
        #expect(timeline.currentTime == 0)
        #expect(timeline.isPlaying)
    }

    @Test @MainActor func durationCannotShrinkPastLastCheckpoint() {
        let timeline = CameraTimeline()
        timeline.upsert(pose: .default, at: 8)
        timeline.setDuration(3)
        #expect(timeline.duration == 8)
    }

    @Test @MainActor func seedsStartPoseOnlyWhileStillDefault() {
        let timeline = CameraTimeline()
        let live = CameraPose(position: SIMD3<Float>(0.4, 0.1, 0.8), zoom: 1)
        timeline.seedStartPoseIfDefault(live)
        #expect(almostEqual(timeline.checkpoints[0].pose.position, live.position))

        let later = CameraPose(position: SIMD3<Float>(0.1, 0.2, 0.1), zoom: 1.5)
        timeline.seedStartPoseIfDefault(later)
        #expect(almostEqual(timeline.checkpoints[0].pose.position, live.position))
    }
}

private func almostEqual(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>, epsilon: Float = 0.0001) -> Bool {
    simd_length(lhs - rhs) < epsilon
}
