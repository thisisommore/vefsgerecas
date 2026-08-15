//
//  ContentView.swift
//  YomMock
//
//  Created by Om More on 14/08/26.
//

import AppKit
import RealityKit
import SwiftUI

struct ContentView: View {
    @State private var status: String?
    @State private var selectedColor: iPhoneColor = .black
    @State private var customColor = Color(red: 0.78, green: 0.32, blue: 0.36)
    @State private var scene = PhoneScene()

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color(red: 0.99, green: 0.99, blue: 0.995),
                    Color(red: 0.88, green: 0.88, blue: 0.90)
                ],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 16,
                endRadius: 640
            )
            .ignoresSafeArea()

            RealityView { content in
                content.camera = .virtual
                content.environment = .default

                let camera = PerspectiveCamera()
                camera.camera.fieldOfViewInDegrees = 34
                camera.look(at: .zero, from: [0.15, 0.045, 0.30], relativeTo: nil)
                content.add(camera)

                guard let url = Bundle.main.url(forResource: "iPhone17", withExtension: "usdz") else {
                    status = "iPhone17.usdz is missing from the app bundle"
                    return
                }

                do {
                    let phone = try await Entity(contentsOf: url)
                    phone.name = "iPhone"
                    frame(phone, targetSize: 0.16)
                    applyPhoneMaterials(to: phone, finish: selectedColor.finish(custom: customColor))
                    applyGroundingShadows(to: phone)

                    let ibl = Entity()
                    ibl.name = "IBL"
                    if let environment = try? await StudioEnvironment.resource() {
                        ibl.components.set(
                            ImageBasedLightComponent(source: .single(environment), intensityExponent: 0.15)
                        )
                    }
                    content.add(ibl)
                    applyIBLReceiver(to: phone, ibl: ibl)

                    let floor = studioFloor(under: phone)
                    applyIBLReceiver(to: floor, ibl: ibl)
                    content.add(floor)

                    scene.phone = phone
                    content.add(phone)
                    content.cameraTarget = phone
                } catch {
                    status = error.localizedDescription
                }
            } update: { _ in
                guard let phone = scene.phone else { return }
                applyPhoneMaterials(to: phone, finish: selectedColor.finish(custom: customColor))
            }
            .realityViewCameraControls(.orbit)
            .ignoresSafeArea()

            VStack {
                Spacer()
                PhoneColorPicker(selection: $selectedColor, customColor: $customColor)
                    .padding(.bottom, 28)
            }

            if let status {
                Text(status)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
    }

    private func frame(_ entity: Entity, targetSize: Float) {
        let bounds = entity.visualBounds(relativeTo: nil)
        let maxDim = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        guard maxDim > 0 else { return }
        let scale = targetSize / maxDim
        entity.scale = SIMD3(repeating: scale)
        entity.position = -bounds.center * scale
    }

    private func applyPhoneMaterials(to entity: Entity, finish: PhoneFinish) {
        if var model = entity.components[ModelComponent.self] {
            let material = material(for: entity.name, finish: finish)
            model.materials = Array(repeating: material, count: max(model.materials.count, 1))
            entity.components.set(model)
        }
        for child in entity.children {
            applyPhoneMaterials(to: child, finish: finish)
        }
    }

    private func applyIBLReceiver(to entity: Entity, ibl: Entity) {
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
        for child in entity.children {
            applyIBLReceiver(to: child, ibl: ibl)
        }
    }

    private func applyGroundingShadows(to entity: Entity) {
        if entity.components.has(ModelComponent.self) {
            entity.components.set(GroundingShadowComponent(castsShadow: true, receivesShadow: false))
        }
        for child in entity.children {
            applyGroundingShadows(to: child)
        }
    }

    private func studioFloor(under phone: Entity) -> ModelEntity {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: NSColor(calibratedWhite: 0.94, alpha: 1))
        material.metallic = .init(floatLiteral: 0)
        material.roughness = .init(floatLiteral: 0.58)
        material.specular = .init(floatLiteral: 0.45)

        let floor = ModelEntity(
            mesh: .generatePlane(width: 4, depth: 4),
            materials: [material]
        )
        floor.name = "StudioFloor"
        let bounds = phone.visualBounds(relativeTo: nil)
        floor.position = [0, bounds.min.y - 0.0004, 0]
        floor.components.set(GroundingShadowComponent(castsShadow: false, receivesShadow: true))
        return floor
    }

    private func material(for name: String, finish: PhoneFinish) -> PhysicallyBasedMaterial {
        let key = name.lowercased()

        if key.contains("screen") && !key.contains("glass") && !key.contains("edge") {
            return pbr(
                color: NSColor(calibratedWhite: 0.015, alpha: 1),
                metallic: 0,
                roughness: 0.018,
                specular: 1,
                clearcoat: 1,
                clearcoatRoughness: 0.012
            )
        }
        if key.contains("screen_edge") || (key.contains("screen") && key.contains("edge")) {
            return pbr(
                color: NSColor(calibratedWhite: 0.025, alpha: 1),
                metallic: 0.08,
                roughness: 0.22,
                specular: 0.55
            )
        }
        if key.contains("glass_back")
            || key.contains("glass_rough")
            || key.contains("matte")
            || (key.contains("back") && !key.contains("antenna")) {
            let roughBack = key.contains("glass_rough") || key.contains("matte")
            return pbr(
                color: finish.back,
                metallic: roughBack ? max(finish.backMetallic - 0.06, 0.08) : finish.backMetallic,
                roughness: roughBack ? max(finish.backRoughness, 0.32) : finish.backRoughness,
                specular: 1,
                clearcoat: roughBack ? 0.4 : finish.backClearcoat,
                clearcoatRoughness: roughBack ? 0.26 : 0.028
            )
        }
        if key.contains("glass") {
            return pbr(
                color: NSColor(calibratedRed: 0.03, green: 0.032, blue: 0.036, alpha: 1),
                metallic: 0,
                roughness: 0.028,
                specular: 1,
                clearcoat: 1,
                clearcoatRoughness: 0.02
            )
        }
        if key.contains("lens") {
            return pbr(
                color: NSColor(calibratedWhite: 0.012, alpha: 1),
                metallic: 0.04,
                roughness: 0.012,
                specular: 1,
                clearcoat: 1,
                clearcoatRoughness: 0.01
            )
        }
        if key.contains("flash") {
            return pbr(
                color: NSColor(calibratedRed: 0.94, green: 0.93, blue: 0.88, alpha: 1),
                metallic: 0,
                roughness: 0.3,
                specular: 0.68,
                emissive: NSColor(calibratedRed: 0.95, green: 0.93, blue: 0.86, alpha: 1),
                emissiveIntensity: 0.12
            )
        }
        if key.contains("logo") {
            return pbr(
                color: NSColor(calibratedWhite: 0.66, alpha: 1),
                metallic: 1,
                roughness: 0.16,
                specular: 1,
                anisotropy: 0.28
            )
        }
        if key.contains("antenna") {
            return pbr(
                color: NSColor(calibratedRed: 0.18, green: 0.185, blue: 0.195, alpha: 1),
                metallic: 0.72,
                roughness: 0.3
            )
        }
        if key.contains("plastic") || key.contains("black") || key.contains("mic") {
            return pbr(
                color: NSColor(calibratedWhite: 0.035, alpha: 1),
                metallic: 0,
                roughness: 0.4,
                specular: 0.28
            )
        }
        if key.contains("edge") || key.contains("gray") {
            return pbr(
                color: finish.frame,
                metallic: 1,
                roughness: 0.2,
                specular: 1,
                clearcoat: 0.18,
                clearcoatRoughness: 0.12,
                anisotropy: 0.3
            )
        }

        return pbr(
            color: finish.frame,
            metallic: 1,
            roughness: 0.22,
            specular: 1,
            anisotropy: 0.26
        )
    }

    private func pbr(
        color: NSColor,
        metallic: Float,
        roughness: Float,
        specular: Float = 0.5,
        clearcoat: Float = 0,
        clearcoatRoughness: Float = 0.1,
        anisotropy: Float = 0,
        emissive: NSColor? = nil,
        emissiveIntensity: Float = 0
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.metallic = .init(floatLiteral: metallic)
        material.roughness = .init(floatLiteral: roughness)
        material.specular = .init(floatLiteral: specular)
        material.clearcoat = .init(floatLiteral: clearcoat)
        material.clearcoatRoughness = .init(floatLiteral: clearcoatRoughness)
        if anisotropy > 0 {
            material.anisotropyLevel = .init(floatLiteral: anisotropy)
            material.anisotropyAngle = .init(floatLiteral: 0.25)
        }
        if let emissive, emissiveIntensity > 0 {
            material.emissiveColor = .init(color: emissive)
            material.emissiveIntensity = emissiveIntensity
        }
        return material
    }
}

private final class PhoneScene {
    var phone: Entity?
}

private struct PhoneColorPicker: View {
    @Binding var selection: iPhoneColor
    @Binding var customColor: Color

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ForEach(iPhoneColor.presets) { color in
                    Button {
                        selection = color
                    } label: {
                        Circle()
                            .fill(color.swatch)
                            .frame(width: 22, height: 22)
                            .overlay {
                                Circle()
                                    .strokeBorder(.black.opacity(0.3), lineWidth: 1)
                            }
                            .overlay {
                                if selection == color {
                                    Circle()
                                        .strokeBorder(.black.opacity(0.75), lineWidth: 2)
                                        .padding(-4)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(color.name)
                    .accessibilityLabel(color.name)
                    .accessibilityAddTraits(selection == color ? .isSelected : [])
                }

                Rectangle()
                    .fill(.black.opacity(0.2))
                    .frame(width: 1, height: 18)

                ColorPicker("Custom color", selection: $customColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28, height: 28)
                    .overlay {
                        if selection == .custom {
                            Circle()
                                .strokeBorder(.black.opacity(0.75), lineWidth: 2)
                                .padding(-4)
                                .allowsHitTesting(false)
                        }
                    }
                    .help("Custom")
                    .onChange(of: customColor) { _, _ in
                        selection = .custom
                    }
            }

            Text(selection.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.black.opacity(0.7))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
    }
}

#Preview {
    ContentView()
}
