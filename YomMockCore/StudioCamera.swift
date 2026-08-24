//
//  StudioCamera.swift
//  YomMockCore
//
//  Virtual studio camera settings: equivalent focal length linked to the
//  camera's field of view. Persisted per project.
//

import Foundation
import simd

/// Photography-style framing control for the virtual studio camera.
///
/// `fieldOfView` is the source of truth; the equivalent focal length is
/// derived against a 24mm full-frame film height (matching RealityKit's
/// vertical field-of-view orientation).
nonisolated struct StudioCameraSettings: Equatable, Codable, Sendable {
    /// Vertical field of view in degrees.
    var fieldOfView: Float

    static let minFieldOfView: Float = 10
    static let maxFieldOfView: Float = 90
    /// Half the 24mm full-frame film height used for the focal-length math.
    static let sensorHalfHeight: Float = 12
    static let minFocalLength: Float = 12
    static let maxFocalLength: Float = 70

    /// Matches the previous fixed 60° studio camera.
    static let `default` = StudioCameraSettings(fieldOfView: 60)

    init(fieldOfView: Float = StudioCameraSettings.default.fieldOfView) {
        self.fieldOfView = Self.clampFieldOfView(fieldOfView)
    }

    // Backward compat: files written before this field existed decode with
    // studio defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        fieldOfView = Self.clampFieldOfView(
            try c.decodeIfPresent(Float.self, forKey: .fieldOfView) ?? fieldOfView)
    }

    static func clampFieldOfView(_ value: Float) -> Float {
        min(max(value, minFieldOfView), maxFieldOfView)
    }

    /// 35mm-equivalent focal length: f = 12mm / tan(fov/2).
    var focalLength: Float {
        Self.sensorHalfHeight / tan(fieldOfView * .pi / 360)
    }

    /// Sets the field of view from a focal length in millimetres.
    mutating func setFocalLength(_ mm: Float) {
        let clamped = min(max(mm, Self.minFocalLength), Self.maxFocalLength)
        fieldOfView = Self.clampFieldOfView(2 * atan2(Self.sensorHalfHeight, clamped) * 180 / .pi)
    }
}
