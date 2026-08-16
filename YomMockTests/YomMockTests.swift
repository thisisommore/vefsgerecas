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
    @Test @MainActor func startsEmptyWithDefaultDuration() {
        let timeline = CameraTimeline()
        #expect(timeline.zoomRanges.isEmpty)
        #expect(timeline.orbitRanges.isEmpty)
        #expect(timeline.basePose == .default)
        #expect(timeline.duration == 12)
        #expect(timeline.currentFrame == 1)
        #expect(timeline.evaluatedZoom() == 1)
        #expect(timeline.evaluatedOrbit() == .default)
    }

    @Test @MainActor func addCreatesSortedRangeWithDefaultSpan() {
        let timeline = CameraTimeline()
        let late = timeline.addZoomRange(at: 8, zoom: 2)
        let early = timeline.addZoomRange(at: 2, zoom: 1.5)

        #expect(late != nil)
        #expect(early != nil)
        #expect(timeline.zoomRanges.map(\.start) == timeline.zoomRanges.map(\.start).sorted())
        #expect(abs(timeline.zoomRanges[0].length - CameraTimeline.defaultRangeLength) < 0.000_1)
        #expect(timeline.selectedZoomRangeID == early?.id)
    }

    @Test @MainActor func addClampsIntoDuration() {
        let timeline = CameraTimeline()
        let leading = timeline.addZoomRange(at: 0, zoom: 2)
        let trailing = timeline.addOrbitRange(at: 12, pose: .default)

        #expect(leading != nil)
        #expect(trailing != nil)
        #expect(leading?.start == 0)
        #expect(abs((leading?.end ?? 0) - CameraTimeline.defaultRangeLength) < 0.000_1)
        #expect(trailing?.end == 12)
        #expect(abs((trailing?.start ?? 0) - (12 - CameraTimeline.defaultRangeLength)) < 0.000_1)
    }

    @Test @MainActor func addRefusesPlayheadInsideExistingRange() {
        let timeline = CameraTimeline()
        let first = timeline.addZoomRange(at: 6, zoom: 2)
        #expect(first != nil)

        let mid = (first!.start + first!.end) / 2
        #expect(timeline.addZoomRange(at: mid, zoom: 3) == nil)
        #expect(timeline.zoomRanges.count == 1)
    }

    @Test @MainActor func updateClampsToBoundsAndMinimumLength() {
        let timeline = CameraTimeline()
        guard var range = timeline.addZoomRange(at: 6, zoom: 2) else {
            Issue.record("expected a zoom range")
            return
        }

        range.start = -2
        range.end = 20
        timeline.updateZoomRange(range)
        #expect(timeline.zoomRanges[0].start == 0)
        #expect(timeline.zoomRanges[0].end == 12)

        range = timeline.zoomRanges[0]
        range.end = range.start + 0.05
        timeline.updateZoomRange(range)
        #expect(abs(timeline.zoomRanges[0].length - CameraTimeline.minimumRangeLength) < 0.000_1)
    }

    @Test @MainActor func updateBlocksNeighborOverlapOnMoveAndResize() {
        let timeline = CameraTimeline()
        guard var left = timeline.addZoomRange(at: 2, zoom: 2),
              var right = timeline.addZoomRange(at: 8, zoom: 3)
        else {
            Issue.record("expected two zoom ranges")
            return
        }

        let leftEndBeforeMove = left.end
        let rightStart = right.start
        left.start = right.start
        left.end = left.start + leftEndBeforeMove - timeline.zoomRanges[0].start
        timeline.updateZoomRange(left)
        #expect(timeline.zoomRanges[0].end <= rightStart + 0.000_1)

        left = timeline.zoomRanges[0]
        left.end = rightStart + 2
        timeline.updateZoomRange(left)
        #expect(timeline.zoomRanges[0].end <= rightStart + 0.000_1)

        right = timeline.zoomRanges[1]
        let leftEnd = timeline.zoomRanges[0].end
        right.start = leftEnd - 2
        timeline.updateZoomRange(right)
        #expect(timeline.zoomRanges[1].start >= leftEnd - 0.000_1)
    }

    @Test @MainActor func evaluatedZoomRampsHoldsAndReturnsToOne() {
        let timeline = CameraTimeline()
        let amount: Float = 3
        guard let range = timeline.addZoomRange(at: 6, zoom: amount) else {
            Issue.record("expected a zoom range")
            return
        }

        let transition = expectedTransition(length: range.length)
        let entryMid = range.start + transition / 2
        let exitMid = range.end - transition / 2
        let hold = (range.start + range.end) / 2
        let easedMid = CameraTimeline.easeInOut(0.5)
        let midValue = 1 + (amount - 1) * easedMid

        #expect(abs(timeline.evaluatedZoom(at: 0) - 1) < 0.000_1)
        #expect(abs(timeline.evaluatedZoom(at: range.start - 0.01) - 1) < 0.000_1)
        #expect(abs(timeline.evaluatedZoom(at: entryMid) - midValue) < 0.000_1)
        #expect(abs(timeline.evaluatedZoom(at: hold) - amount) < 0.000_1)
        #expect(abs(timeline.evaluatedZoom(at: exitMid) - midValue) < 0.000_1)
        #expect(abs(timeline.evaluatedZoom(at: range.end + 0.01) - 1) < 0.000_1)
    }

    @Test @MainActor func evaluatedZoomPinnedAtZeroIsFullAmount() {
        let timeline = CameraTimeline()
        guard let range = timeline.addZoomRange(at: 0, zoom: 2.5) else {
            Issue.record("expected a zoom range")
            return
        }

        #expect(range.start == 0)
        #expect(abs(timeline.evaluatedZoom(at: 0) - 2.5) < 0.000_1)
        #expect(abs(timeline.evaluatedZoom(at: 0.05) - 2.5) < 0.000_1)
    }

    @Test @MainActor func evaluatedOrbitUsesShortArcAndHoldsPose() {
        let timeline = CameraTimeline()
        let base = OrbitPose(yaw: radians(350), pitch: 0, radius: 1)
        let target = OrbitPose(yaw: radians(10), pitch: 0.2, radius: 1.4)
        timeline.seedBasePoseIfDefault(base)

        guard let range = timeline.addOrbitRange(at: 6, pose: target) else {
            Issue.record("expected an orbit range")
            return
        }

        let transition = expectedTransition(length: range.length)
        let entryMid = range.start + transition / 2
        let hold = (range.start + range.end) / 2
        let mid = timeline.evaluatedOrbit(at: entryMid)
        let expectedMid = base.interpolated(to: target, t: CameraTimeline.easeInOut(0.5))

        #expect(timeline.evaluatedOrbit(at: 0) == base)
        #expect(abs(angleDelta(mid.yaw, expectedMid.yaw)) < 0.000_1)
        #expect(abs(mid.pitch - expectedMid.pitch) < 0.000_1)
        #expect(abs(angleDelta(mid.yaw, 0)) < 0.05)
        #expect(abs(angleDelta(mid.yaw, .pi)) > 1)
        #expect(timeline.evaluatedOrbit(at: hold) == target)
    }

    @Test @MainActor func seedBasePoseFreezesAfterFirstOrbitRange() {
        let timeline = CameraTimeline()
        let live = OrbitPose(position: SIMD3<Float>(0.4, 0.1, 0.8))
        timeline.seedBasePoseIfDefault(live)
        #expect(almostEqual(timeline.basePose.position, live.position))

        let later = OrbitPose(position: SIMD3<Float>(0.1, 0.2, 0.1))
        timeline.seedBasePoseIfDefault(later)
        #expect(almostEqual(timeline.basePose.position, later.position))

        #expect(timeline.addOrbitRange(at: 3, pose: later) != nil)
        timeline.seedBasePoseIfDefault(.default)
        #expect(almostEqual(timeline.basePose.position, later.position))
    }

    @Test @MainActor func durationCannotShrinkPastLatestRangeEnd() {
        let timeline = CameraTimeline()
        guard var range = timeline.addZoomRange(at: 6, zoom: 2) else {
            Issue.record("expected a zoom range")
            return
        }
        range.end = 8
        timeline.updateZoomRange(range)

        timeline.setDuration(3)
        #expect(abs(timeline.duration - 8) < 0.000_1)
        #expect(abs(timeline.minDuration - 8) < 0.000_1)
    }

    @Test @MainActor func removeClearsSelection() {
        let timeline = CameraTimeline()
        guard let range = timeline.addZoomRange(at: 2, zoom: 2) else {
            Issue.record("expected a zoom range")
            return
        }

        #expect(timeline.selectedZoomRangeID == range.id)
        timeline.removeZoomRange(id: range.id)
        #expect(timeline.selectedZoomRangeID == nil)
        #expect(timeline.zoomRanges.isEmpty)
    }

    @Test @MainActor func updateFromSceneReplacesSelectedRangeValueOnly() {
        let timeline = CameraTimeline()
        guard let first = timeline.addZoomRange(at: 2, zoom: 2),
              timeline.addZoomRange(at: 8, zoom: 3) != nil
        else {
            Issue.record("expected two zoom ranges")
            return
        }

        timeline.selectedZoomRangeID = first.id
        timeline.updateSelectedZoom(5)
        #expect(abs(timeline.zoomRanges[0].zoom - 5) < 0.000_1)
        #expect(abs(timeline.zoomRanges[1].zoom - 3) < 0.000_1)

        let pose = OrbitPose(yaw: 1, pitch: 0.1, radius: 0.5)
        let other = OrbitPose(yaw: -1, pitch: -0.1, radius: 0.8)
        guard let orbit = timeline.addOrbitRange(at: 2, pose: pose),
              timeline.addOrbitRange(at: 8, pose: other) != nil
        else {
            Issue.record("expected two orbit ranges")
            return
        }
        timeline.selectedOrbitRangeID = orbit.id
        let updated = OrbitPose(yaw: 0.4, pitch: 0.05, radius: 0.7)
        timeline.updateSelectedOrbit(updated)
        #expect(timeline.orbitRanges[0].pose == updated)
        #expect(timeline.orbitRanges[1].pose == other)
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

private func expectedTransition(length: TimeInterval) -> TimeInterval {
    min(CameraTimeline.maximumTransition, max(0.12, length / 2.4))
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
