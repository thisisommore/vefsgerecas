//
//  CameraTimeline.swift
//  YomMock
//

import Foundation
import Observation
import simd

nonisolated struct CameraPose: Equatable, Sendable {
    var yaw: Float
    var pitch: Float
    var radius: Float
    var zoom: Float

    static let `default` = CameraPose(
        position: SIMD3<Float>(0.15, 0.045, 0.30),
        zoom: 1
    )

    init(yaw: Float, pitch: Float, radius: Float, zoom: Float) {
        self.yaw = yaw
        self.pitch = simd_clamp(pitch, -.pi / 2 + 0.02, .pi / 2 - 0.02)
        self.radius = max(radius, 0.000_1)
        self.zoom = zoom
    }

    init(position: SIMD3<Float>, zoom: Float) {
        let spherical = Spherical(position)
        self.init(yaw: spherical.yaw, pitch: spherical.pitch, radius: spherical.radius, zoom: zoom)
    }

    var position: SIMD3<Float> {
        Spherical(radius: radius, yaw: yaw, pitch: pitch).cartesian
    }

    func interpolated(to other: CameraPose, t: Float) -> CameraPose {
        let clamped = simd_clamp(t, 0, 1)
        return CameraPose(
            yaw: Spherical.lerpAngle(yaw, other.yaw, clamped),
            pitch: pitch + (other.pitch - pitch) * clamped,
            radius: radius + (other.radius - radius) * clamped,
            zoom: zoom + (other.zoom - zoom) * clamped
        )
    }

    func orbiting(by translation: CGSize) -> CameraPose {
        CameraPose(
            yaw: yaw - Float(translation.width) * 0.008,
            pitch: pitch + Float(translation.height) * 0.008,
            radius: radius,
            zoom: zoom
        )
    }

    func withZoom(_ zoom: Float) -> CameraPose {
        CameraPose(yaw: yaw, pitch: pitch, radius: radius, zoom: zoom)
    }
}

nonisolated struct CameraCheckpoint: Identifiable, Equatable, Sendable {
    let id: UUID
    var time: TimeInterval
    var pose: CameraPose

    init(id: UUID = UUID(), time: TimeInterval, pose: CameraPose) {
        self.id = id
        self.time = time
        self.pose = pose
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

    init(
        duration: TimeInterval = CameraTimeline.defaultDuration,
        defaultPose: CameraPose = .default
    ) {
        self.duration = duration
        self.checkpoints = [CameraCheckpoint(time: 0, pose: defaultPose)]
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

    var checkpointAtPlayhead: CameraCheckpoint? {
        checkpoints.first { abs($0.time - currentTime) <= Self.snapTolerance }
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

    @discardableResult
    func upsert(pose: CameraPose, at time: TimeInterval) -> CameraCheckpoint {
        let t = min(max(time, 0), duration)
        if let index = checkpoints.firstIndex(where: { abs($0.time - t) <= Self.snapTolerance }) {
            checkpoints[index].time = t
            checkpoints[index].pose = pose
            return checkpoints[index]
        }
        let checkpoint = CameraCheckpoint(time: t, pose: pose)
        checkpoints.append(checkpoint)
        checkpoints.sort { $0.time < $1.time }
        return checkpoint
    }

    func deleteCheckpoint(id: UUID) {
        guard checkpoints.count > 1 else { return }
        checkpoints.removeAll { $0.id == id }
    }

    func seedStartPoseIfDefault(_ pose: CameraPose) {
        guard
            checkpoints.count == 1,
            let index = checkpoints.firstIndex(where: { $0.time == 0 }),
            checkpoints[index].pose == .default,
            pose != .default
        else { return }
        checkpoints[index].pose = pose
    }

    func evaluatedPose(at time: TimeInterval? = nil) -> CameraPose {
        let t = time ?? currentTime
        let keys = checkpoints.sorted { $0.time < $1.time }
        guard let first = keys.first else { return .default }
        if t <= first.time { return first.pose }
        guard let last = keys.last else { return first.pose }
        if t >= last.time { return last.pose }

        guard
            let nextIndex = keys.firstIndex(where: { $0.time >= t }),
            nextIndex > 0
        else {
            return last.pose
        }

        let start = keys[nextIndex - 1]
        let end = keys[nextIndex]
        let span = end.time - start.time
        let raw = span > 0 ? (t - start.time) / span : 1
        return start.pose.interpolated(to: end.pose, t: Self.easeInOut(Float(raw)))
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
        self.pitch = simd_clamp(pitch, -.pi / 2 + 0.01, .pi / 2 - 0.01)
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
        return start + delta * t
    }
}
