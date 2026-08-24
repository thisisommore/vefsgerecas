//
//  PhoneScene.swift
//  YomMock
//

import Foundation
import RealityKit
import simd

#if canImport(AppKit)
import AppKit
#endif

enum StudioSceneError: LocalizedError {
    case modelMissing(String)

    var errorDescription: String? {
        switch self {
        case .modelMissing(let name):
            return "\(name) missing from bundle."
        }
    }
}

/// Controller for the live 3D preview: camera orbit/zoom/pan state and the
/// device model + studio lighting installation.
@MainActor
final class PhoneScene {
    static let minZoom: Float = 0.06
    static let maxZoom: Float = 21

    var camera: Entity?
    var phone: Entity?
    var floor: Entity?
    var lidRig: MacBookLidRig?
    var orbitPose = OrbitPose.default
    var zoom: Float = 1
    var baseScale: Float = 1
    var modelCenter = SIMD3<Float>.zero
    var panOffset = SIMD3<Float>.zero
    var hasUserInteracted = false
    /// Virtual studio camera settings (FOV/focal length, DoF styling).
    var cameraSettings = StudioCameraSettings()

    /// Loads the device model, applies materials, installs the lid rig and
    /// studio IBL. Throws on failure — the caller surfaces the error.
    /// Loads the device model, applies materials, installs the lid rig and
    /// studio IBL. Throws on failure — the caller surfaces the error.
    func makeStudioEntities(styling: DeviceStyling, lidAngle: Float) async throws -> (model: Entity, ibl: Entity) {
        guard let url = Bundle.main.url(
            forResource: styling.device.modelResource,
            withExtension: styling.device.modelExtension
        ) else {
            throw StudioSceneError.modelMissing(
                "\(styling.device.modelResource).\(styling.device.modelExtension)")
        }

        let model = try await Entity(contentsOf: url)
        model.name = styling.device.modelResource
        self.phone = model
        framePhone(model, targetSize: styling.device.frameTargetSize)
        PhoneStyling.liftKeyboardLegends(on: model)
        PhoneStyling.applyMaterials(to: model, styling: styling)
        PhoneStyling.applyGroundingShadows(to: model)

        if styling.device == .macBookPro {
            lidRig = MacBookLidRig.install(on: model)
            lidRig?.displayOn = styling.displayTexture != nil
            lidRig?.setLidAngle(lidAngle)
            if styling.displayTexture != nil {
                var restyled = styling
                restyled.lidGlow = lidRig?.glowFactor ?? 0
                PhoneStyling.applyMaterials(to: model, styling: restyled)
            }
        } else {
            lidRig = nil
        }

        let ibl = Entity()
        ibl.name = "IBL"
        let environment = try await StudioEnvironment.resource()
        ibl.components.set(
            ImageBasedLightComponent(source: .single(environment), intensityExponent: -3.0))
        applyIBLReceiver(to: model, ibl: ibl)

        return (model, ibl)
    }

    private func applyIBLReceiver(to entity: Entity, ibl: Entity) {
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
        for child in entity.children {
            applyIBLReceiver(to: child, ibl: ibl)
        }
    }

    func applyLidAngle(_ angle: Float) {
        lidRig?.setLidAngle(angle)
    }

    /// Applies studio camera settings (focal length / field of view) to the
    /// live camera, preserving the current pose.
    func applyCameraSettings(_ settings: StudioCameraSettings) {
        guard settings != cameraSettings else { return }
        cameraSettings = settings
        applyCamera(from: orbitPose.position)
    }

    func apply(orbit: OrbitPose, zoom: Float, pan: SIMD3<Float> = .zero) {
        orbitPose = orbit
        self.zoom = zoom
        panOffset = pan
        applyCamera(from: orbit.position)
        applyZoom()
    }

    func applyWithCurrentPan(orbit: OrbitPose, zoom: Float) {
        apply(orbit: orbit, zoom: zoom, pan: panOffset)
    }

    func syncPoseFromCamera(zoom: Float) {
        guard let camera else { return }
        let position = camera.position(relativeTo: nil)
        guard simd_length(position) > 1e-4 else { return }
        orbitPose = OrbitPose(position: position)
        self.zoom = zoom
    }

    func rotateYaw(by delta: Float) {
        syncPoseFromCamera(zoom: zoom)
        hasUserInteracted = true
        orbitPose = OrbitPose(yaw: orbitPose.yaw + delta, pitch: orbitPose.pitch, radius: orbitPose.radius)
        applyCamera(from: orbitPose.position)
    }

    func orbit(by delta: SIMD2<Float>) {
        hasUserInteracted = true
        orbitPose = OrbitPose(
            yaw: orbitPose.yaw - delta.x * 0.005,
            pitch: orbitPose.pitch - delta.y * 0.005,
            radius: orbitPose.radius
        )
        applyCamera(from: orbitPose.position)
    }

    /// Pan by moving the phone in the camera's right/up plane. Keeps the
    /// RealityKit orbit target at the origin, so the built-in `.orbit`
    /// controls don't snap back after shift-drag.
    func pan(by delta: SIMD2<Float>) {
        guard let camera, phone != nil else { return }
        let t = camera.transformMatrix(relativeTo: nil)
        let right = SIMD3<Float>(t.columns.0.x, t.columns.0.y, t.columns.0.z)
        let up = SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z)
        let distance = max(simd_length(orbitPose.position), 0.5)
        let factor = distance * 0.0012 / max(zoom, 0.1)
        // X inverted per feedback, Y kept as original (reverted).
        panOffset -= right * delta.x * factor
        panOffset += up * delta.y * factor
        positionPhone()
    }

    func resetPan() {
        panOffset = .zero
        applyCamera(from: orbitPose.position)
        applyZoom()
    }

    func captureOrbitPose() -> OrbitPose {
        orbitPose
    }

    /// Scales and centers the phone so it fits the studio framing.
    func framePhone(_ entity: Entity, targetSize: Float) {
        let bounds = entity.visualBounds(relativeTo: nil)
        let maxDim = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        guard maxDim > 0 else { return }
        baseScale = targetSize / maxDim
        modelCenter = bounds.center
        applyZoom()
    }

#if canImport(AppKit)
    /// Scroll-wheel zoom step (macOS only — iPad uses pinch gestures).
    static func adjustedZoom(from zoom: Float, event: NSEvent) -> Float {
        guard event.momentumPhase.isEmpty else { return zoom }
        let raw = Float(event.scrollingDeltaY)
        guard abs(raw) > 0.01 else { return zoom }
        let units = event.hasPreciseScrollingDeltas ? raw / 50 : raw
        let step = min(max(units, -1), 1)
        return min(max(zoom * exp(step * 0.04), minZoom), maxZoom)
    }
#endif

    private func positionPhone() {
        guard let phone else { return }
        let scale = baseScale * zoom
        guard scale > 0 else { return }
        phone.scale = SIMD3(repeating: scale)
        phone.position = -modelCenter * scale + panOffset
        if let floor {
            let bounds = phone.visualBounds(relativeTo: nil)
            floor.position = [0, bounds.min.y - 0.0004, 0]
        }
    }

    private func applyCamera(from position: SIMD3<Float>) {
        guard let camera else { return }
        if var perspective = camera.components[PerspectiveCameraComponent.self],
            abs(perspective.fieldOfViewInDegrees - cameraSettings.fieldOfView) > 0.01
        {
            perspective.fieldOfViewInDegrees = cameraSettings.fieldOfView
            camera.components.set(perspective)
        }
        // Keep a stable up when near the pole to avoid 180° roll.
        let pitch = orbitPose.pitch
        if abs(pitch) > 1.30 {
            let forward = normalize(SIMD3<Float>.zero - position)
            let worldUp: SIMD3<Float> = [0, 1, 0]
            let right = normalize(cross(forward, worldUp))
            let up = cross(right, forward)
            var m = matrix_identity_float4x4
            m.columns.0 = SIMD4<Float>(right.x, right.y, right.z, 0)
            m.columns.1 = SIMD4<Float>(up.x, up.y, up.z, 0)
            m.columns.2 = SIMD4<Float>(-forward.x, -forward.y, -forward.z, 0)
            m.columns.3 = SIMD4<Float>(position.x, position.y, position.z, 1)
            camera.setTransformMatrix(m, relativeTo: nil)
        } else {
            camera.look(at: .zero, from: position, relativeTo: nil)
        }
    }

    func applyZoom() {
        positionPhone()
    }
}
