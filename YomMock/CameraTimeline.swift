//
//  CameraTimeline.swift
//  YomMock
//

import Foundation
import Observation
import simd

nonisolated struct OrbitPose: Equatable, Sendable {
    var yaw: Float
    var pitch: Float
    var radius: Float

    static let `default` = OrbitPose(position: SIMD3<Float>(2.10, 0.63, 4.20))

    init(yaw: Float, pitch: Float, radius: Float) {
        self.yaw = yaw
        self.pitch = simd_clamp(pitch, -.pi / 2 + 0.18, .pi / 2 - 0.18)
        self.radius = max(radius, 0.000_1)
    }

    init(position: SIMD3<Float>) {
        let spherical = Spherical(position)
        self.init(yaw: spherical.yaw, pitch: spherical.pitch, radius: spherical.radius)
    }

    var position: SIMD3<Float> {
        Spherical(radius: radius, yaw: yaw, pitch: pitch).cartesian
    }

    func interpolated(to other: OrbitPose, t: Float) -> OrbitPose {
        let clamped = simd_clamp(t, 0, 1)
        return OrbitPose(
            yaw: Spherical.lerpAngle(yaw, other.yaw, clamped),
            pitch: pitch + (other.pitch - pitch) * clamped,
            radius: radius + (other.radius - radius) * clamped
        )
    }
}

/// A single moment in the timeline capturing both the camera orbit and the
/// zoom. The timeline animates from one checkpoint to the next, interpolating
/// orbit and zoom together.
nonisolated struct CameraCheckpoint: Identifiable, Equatable, Sendable {
    let id: UUID
    var time: TimeInterval
    var pose: OrbitPose
    var zoom: Float

    init(id: UUID = UUID(), time: TimeInterval, pose: OrbitPose, zoom: Float) {
        self.id = id
        self.time = time
        self.pose = pose
        self.zoom = zoom
    }
}

@MainActor
@Observable
final class CameraTimeline {
    nonisolated static let fps: Double = 30
    nonisolated static let maxDuration: TimeInterval = 120
    nonisolated static let defaultDuration: TimeInterval = 12
    nonisolated static let snapTolerance: TimeInterval = 1 / fps

    var duration: TimeInterval
    var currentTime: TimeInterval = 0
    var isPlaying = false
    private(set) var checkpoints: [CameraCheckpoint]
    var selectedCheckpointID: UUID?

    init(duration: TimeInterval = CameraTimeline.defaultDuration) {
        self.duration = duration
        self.checkpoints = [CameraCheckpoint(time: 0, pose: .default, zoom: 1)]
    }

    /// Demo timeline — bottom → top → side orbit, smoothly eased.
    /// Used as the default in the app; tests still use the single-checkpoint init.
    static var demo: CameraTimeline {
        let t = CameraTimeline(duration: defaultDuration)
        t.checkpoints = [
            CameraCheckpoint(time: 0, pose: OrbitPose(yaw: 0.40, pitch: -0.48, radius: 4.2), zoom: 1.45),
            CameraCheckpoint(time: 4, pose: OrbitPose(yaw: 0.55, pitch: 0.52, radius: 5.0), zoom: 1.08),
            CameraCheckpoint(time: 8, pose: OrbitPose(yaw: 1.75, pitch: 0.18, radius: 4.6), zoom: 1.0),
            CameraCheckpoint(time: 12, pose: OrbitPose(yaw: -0.55, pitch: 0.12, radius: 4.85), zoom: 0.98),
        ]
        t.selectedCheckpointID = t.checkpoints.first?.id
        return t
    }

    var minDuration: TimeInterval {
        max(1, checkpoints.map(\.time).max() ?? 0)
    }

    var currentFrame: Int {
        Int((currentTime * Self.fps).rounded(.down)) + 1
    }

    var totalFrames: Int {
        max(1, Int((duration * Self.fps).rounded(.down)))
    }

    /// The checkpoint exactly under the playhead (within a frame), if any.
    var checkpointAtPlayhead: CameraCheckpoint? {
        checkpoints.first { abs($0.time - currentTime) <= Self.snapTolerance }
    }

    var selectedCheckpoint: CameraCheckpoint? {
        checkpoints.first { $0.id == selectedCheckpointID }
    }

    func formatted(_ time: TimeInterval) -> String {
        String(format: "%.2fs", time)
    }

    func seek(to time: TimeInterval) {
        currentTime = min(max(time, 0), duration)
    }

    func goToStart() {
        isPlaying = false
        currentTime = 0
    }

    func togglePlay() {
        if isPlaying {
            isPlaying = false
            return
        }
        if currentTime >= duration - 0.000_5 {
            currentTime = 0
        }
        isPlaying = true
    }

    func advance(by dt: TimeInterval) {
        guard isPlaying else { return }
        currentTime = min(max(currentTime + dt, 0), duration)
        if currentTime >= duration {
            isPlaying = false
        }
    }

    func setDuration(_ newDuration: TimeInterval) {
        let clamped = min(max(newDuration, minDuration), Self.maxDuration)
        duration = clamped
        currentTime = min(currentTime, duration)
    }

    /// Save the given orbit + zoom at the playhead, updating an existing
    /// checkpoint at that time or inserting a new one.
    @discardableResult
    func saveCheckpoint(at time: TimeInterval, pose: OrbitPose, zoom: Float) -> CameraCheckpoint {
        let t = min(max(time, 0), duration)
        if let index = checkpoints.firstIndex(where: { abs($0.time - t) <= Self.snapTolerance }) {
            checkpoints[index].time = t
            checkpoints[index].pose = pose
            checkpoints[index].zoom = zoom
            selectedCheckpointID = checkpoints[index].id
            return checkpoints[index]
        }
        let checkpoint = CameraCheckpoint(time: t, pose: pose, zoom: zoom)
        checkpoints.append(checkpoint)
        checkpoints.sort { $0.time < $1.time }
        selectedCheckpointID = checkpoint.id
        return checkpoint
    }

    func updateSelectedCheckpoint(pose: OrbitPose? = nil, zoom: Float? = nil) {
        guard
            let id = selectedCheckpointID,
            let index = checkpoints.firstIndex(where: { $0.id == id })
        else { return }
        if let pose { checkpoints[index].pose = pose }
        if let zoom { checkpoints[index].zoom = zoom }
    }

    func deleteCheckpoint(id: UUID) {
        guard checkpoints.count > 1 else { return }
        checkpoints.removeAll { $0.id == id }
        if selectedCheckpointID == id {
            selectedCheckpointID = nil
        }
    }

    func select(_ checkpoint: CameraCheckpoint) {
        selectedCheckpointID = checkpoint.id
        seek(to: checkpoint.time)
    }

    /// Keep a studio-default pose in the first checkpoint until the user
    /// takes over the camera by orbiting.
    func seedBasePoseIfDefault(_ pose: OrbitPose) {
        guard
            checkpoints.count == 1,
            checkpoints[0].time == 0,
            checkpoints[0].pose == .default,
            pose != .default
        else { return }
        checkpoints[0].pose = pose
    }

    /// Interpolated orbit + zoom at a time, eased between adjacent checkpoints.
    func evaluatedState(at time: TimeInterval? = nil) -> (orbit: OrbitPose, zoom: Float) {
        let t = time ?? currentTime
        let keys = checkpoints.sorted { $0.time < $1.time }
        guard let first = keys.first else {
            return (.default, 1)
        }
        // Before/beyond the outer keyframes, hold the nearest value.
        if t <= first.time { return (first.pose, first.zoom) }
        guard let last = keys.last else { return (first.pose, first.zoom) }
        if t >= last.time { return (last.pose, last.zoom) }

        guard
            let nextIndex = keys.firstIndex(where: { $0.time >= t }),
            nextIndex > 0
        else {
            return (last.pose, last.zoom)
        }

        let start = keys[nextIndex - 1]
        let end = keys[nextIndex]
        let span = end.time - start.time
        let raw = span > 0 ? (t - start.time) / span : 1
        let eased = Self.easeInOut(Float(raw))
        return (
            start.pose.interpolated(to: end.pose, t: eased),
            start.zoom + (end.zoom - start.zoom) * eased
        )
    }

    static func easeInOut(_ t: Float) -> Float {
        let clamped = simd_clamp(t, 0, 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}

nonisolated struct Spherical: Equatable {
    var radius: Float
    var yaw: Float
    var pitch: Float

    init(radius: Float, yaw: Float, pitch: Float) {
        self.radius = max(radius, 0.000_1)
        self.yaw = yaw
        self.pitch = simd_clamp(pitch, -.pi / 2 + 0.18, .pi / 2 - 0.18)
    }

    init(_ position: SIMD3<Float>) {
        let radius = max(simd_length(position), 0.000_1)
        self.init(
            radius: radius,
            yaw: atan2(position.x, position.z),
            pitch: asin(simd_clamp(position.y / radius, -1, 1))
        )
    }

    var cartesian: SIMD3<Float> {
        SIMD3(
            radius * sin(yaw) * cos(pitch),
            radius * sin(pitch),
            radius * cos(yaw) * cos(pitch)
        )
    }

    func interpolated(to other: Spherical, t: Float) -> Spherical {
        Spherical(
            radius: radius + (other.radius - radius) * t,
            yaw: Self.lerpAngle(yaw, other.yaw, t),
            pitch: pitch + (other.pitch - pitch) * t
        )
    }

    static func lerpAngle(_ start: Float, _ end: Float, _ t: Float) -> Float {
        var delta = end - start
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        var result = start + delta * t
        while result > .pi { result -= 2 * .pi }
        while result < -.pi { result += 2 * .pi }
        return result
    }
}
