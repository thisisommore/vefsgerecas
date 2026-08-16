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
        self.pitch = simd_clamp(pitch, -.pi / 2 + 0.02, .pi / 2 - 0.02)
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

nonisolated protocol TimelineRange: Identifiable, Equatable, Sendable where ID == UUID {
    var start: TimeInterval { get set }
    var end: TimeInterval { get set }
}

extension TimelineRange {
    var length: TimeInterval { end - start }
}

nonisolated struct ZoomRange: TimelineRange {
    let id: UUID
    var start: TimeInterval
    var end: TimeInterval
    var zoom: Float

    init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, zoom: Float) {
        self.id = id
        self.start = start
        self.end = end
        self.zoom = zoom
    }
}

nonisolated struct OrbitRange: TimelineRange {
    let id: UUID
    var start: TimeInterval
    var end: TimeInterval
    var pose: OrbitPose

    init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, pose: OrbitPose) {
        self.id = id
        self.start = start
        self.end = end
        self.pose = pose
    }
}

@MainActor
@Observable
final class CameraTimeline {
    nonisolated static let fps: Double = 30
    nonisolated static let maxDuration: TimeInterval = 120
    nonisolated static let defaultDuration: TimeInterval = 12
    nonisolated static let minimumRangeLength: TimeInterval = 0.25
    nonisolated static let defaultRangeLength: TimeInterval = 2.5
    nonisolated static let maximumTransition: TimeInterval = 0.6

    var duration: TimeInterval
    var currentTime: TimeInterval = 0
    var isPlaying = false
    private(set) var zoomRanges: [ZoomRange] = []
    private(set) var orbitRanges: [OrbitRange] = []
    private(set) var basePose: OrbitPose = .default
    var selectedZoomRangeID: UUID?
    var selectedOrbitRangeID: UUID?

    init(duration: TimeInterval = CameraTimeline.defaultDuration) {
        self.duration = duration
    }

    var minDuration: TimeInterval {
        let lastZoomEnd = zoomRanges.map(\.end).max() ?? 0
        let lastOrbitEnd = orbitRanges.map(\.end).max() ?? 0
        return max(1, lastZoomEnd, lastOrbitEnd)
    }

    var currentFrame: Int {
        Int((currentTime * Self.fps).rounded(.down)) + 1
    }

    var totalFrames: Int {
        max(1, Int((duration * Self.fps).rounded(.down)))
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
        let next = min(max(currentTime + dt, 0), duration)
        if next != currentTime {
            currentTime = next
        }
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
    func addZoomRange(at time: TimeInterval, zoom: Float) -> ZoomRange? {
        guard let span = insertionSpan(at: time, in: zoomRanges) else { return nil }
        let range = ZoomRange(start: span.lowerBound, end: span.upperBound, zoom: zoom)
        zoomRanges.append(range)
        zoomRanges.sort { $0.start < $1.start }
        selectedZoomRangeID = range.id
        return range
    }

    @discardableResult
    func addOrbitRange(at time: TimeInterval, pose: OrbitPose) -> OrbitRange? {
        guard let span = insertionSpan(at: time, in: orbitRanges) else { return nil }
        let range = OrbitRange(start: span.lowerBound, end: span.upperBound, pose: pose)
        orbitRanges.append(range)
        orbitRanges.sort { $0.start < $1.start }
        selectedOrbitRangeID = range.id
        return range
    }

    func updateZoomRange(_ updated: ZoomRange) {
        guard zoomRanges.contains(where: { $0.id == updated.id }) else { return }
        zoomRanges = zoomRanges.map { $0.id == updated.id ? clamped(updated, in: zoomRanges) : $0 }
        zoomRanges.sort { $0.start < $1.start }
    }

    func updateOrbitRange(_ updated: OrbitRange) {
        guard orbitRanges.contains(where: { $0.id == updated.id }) else { return }
        orbitRanges = orbitRanges.map {
            $0.id == updated.id ? clamped(updated, in: orbitRanges) : $0
        }
        orbitRanges.sort { $0.start < $1.start }
    }

    func removeZoomRange(id: UUID) {
        zoomRanges.removeAll { $0.id == id }
        if selectedZoomRangeID == id {
            selectedZoomRangeID = nil
        }
    }

    func removeOrbitRange(id: UUID) {
        orbitRanges.removeAll { $0.id == id }
        if selectedOrbitRangeID == id {
            selectedOrbitRangeID = nil
        }
    }

    func updateSelectedZoom(_ zoom: Float) {
        guard
            let id = selectedZoomRangeID,
            let index = zoomRanges.firstIndex(where: { $0.id == id })
        else { return }
        zoomRanges[index].zoom = zoom
    }

    func updateSelectedOrbit(_ pose: OrbitPose) {
        guard
            let id = selectedOrbitRangeID,
            let index = orbitRanges.firstIndex(where: { $0.id == id })
        else { return }
        orbitRanges[index].pose = pose
    }

    func seedBasePoseIfDefault(_ pose: OrbitPose) {
        guard orbitRanges.isEmpty, pose != basePose else { return }
        basePose = pose
    }

    func evaluatedZoom(at time: TimeInterval? = nil) -> Float {
        let t = time ?? currentTime
        guard let range = zoomRanges.first(where: { t >= $0.start && t <= $0.end }) else {
            return 1
        }
        let progress = rangeEnvelope(at: t, start: range.start, end: range.end)
        if progress <= 0 { return 1 }
        if progress >= 1 { return range.zoom }
        return 1 + (range.zoom - 1) * progress
    }

    func evaluatedOrbit(at time: TimeInterval? = nil) -> OrbitPose {
        let t = time ?? currentTime
        guard let range = orbitRanges.first(where: { t >= $0.start && t <= $0.end }) else {
            return basePose
        }
        let progress = rangeEnvelope(at: t, start: range.start, end: range.end)
        if progress <= 0 { return basePose }
        if progress >= 1 { return range.pose }
        return basePose.interpolated(to: range.pose, t: progress)
    }

    func evaluatedState(at time: TimeInterval? = nil) -> (orbit: OrbitPose, zoom: Float) {
        let t = time ?? currentTime
        return (evaluatedOrbit(at: t), evaluatedZoom(at: t))
    }

    /// 0 at the base value, 1 fully inside the range, with eased ramps at both
    /// ends. Ranges pinned to a timeline edge hold full value from that edge.
    private func rangeEnvelope(at t: TimeInterval, start: TimeInterval, end: TimeInterval) -> Float
    {
        let length = max(0.001, end - start)
        let transition = min(Self.maximumTransition, max(0.12, length / 2.4))
        let entry = start <= 0.001 ? TimeInterval.zero : transition
        let exit = end >= duration - 0.001 ? TimeInterval.zero : transition
        let relative = t - start
        if entry > 0, relative < entry {
            return Self.easeInOut(Float(relative / entry))
        }
        if exit > 0, relative > length - exit {
            return Self.easeInOut(Float((length - relative) / exit))
        }
        return 1
    }

    private func insertionSpan<R: TimelineRange>(
        at time: TimeInterval,
        in ranges: [R]
    ) -> ClosedRange<TimeInterval>? {
        let t = min(max(time, 0), duration)
        // A playhead strictly inside another range has no legal gap.
        if ranges.contains(where: { t > $0.start && t < $0.end }) {
            return nil
        }
        let lower = ranges.filter { $0.end <= t }.map(\.end).max() ?? 0
        let upper = ranges.filter { $0.start >= t }.map(\.start).min() ?? duration
        let gap = upper - lower
        guard gap >= Self.minimumRangeLength else { return nil }
        let length = min(Self.defaultRangeLength, gap)
        let start = min(max(t - length / 2, lower), upper - length)
        return start...(start + length)
    }

    private func clamped<R: TimelineRange>(_ updated: R, in ranges: [R]) -> R {
        guard let current = ranges.first(where: { $0.id == updated.id }) else { return updated }
        let minLength = Self.minimumRangeLength
        let others = ranges.filter { $0.id != updated.id }
        let lowerBound = others.filter { $0.start <= current.start }.map(\.end).max() ?? 0
        let upperBound = others.filter { $0.start > current.start }.map(\.start).min() ?? duration
        guard upperBound - lowerBound >= minLength else { return current }

        var result = updated
        if abs(updated.length - current.length) < 0.000_1 {
            let start = min(
                max(updated.start, lowerBound), max(lowerBound, upperBound - current.length))
            result.start = start
            result.end = start + current.length
        } else {
            let start = min(max(updated.start, lowerBound), upperBound - minLength)
            let end = min(max(updated.end, start + minLength), upperBound)
            result.start = start
            result.end = end
        }
        return result
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
        var result = start + delta * t
        while result > .pi { result -= 2 * .pi }
        while result < -.pi { result += 2 * .pi }
        return result
    }
}
