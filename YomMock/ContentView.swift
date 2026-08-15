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

    var body: some View {
        ZStack {
            RealityView { content in
                content.camera = .virtual

                if let environment = try? studioEnvironment() {
                    content.environment = .skybox(environment)
                }

                addStudioLights(to: &content)

                guard let url = Bundle.main.url(forResource: "iPhone17", withExtension: "usdz") else {
                    status = "iPhone17.usdz is missing from the app bundle"
                    return
                }

                do {
                    let phone = try await Entity(contentsOf: url)
                    frame(phone, targetSize: 0.16)
                    applyPhoneMaterials(to: phone)

                    if let environment = try? studioEnvironment() {
                        let ibl = Entity()
                        ibl.name = "IBL"
                        ibl.components.set(
                            ImageBasedLightComponent(source: .single(environment), intensityExponent: 0.35)
                        )
                        content.add(ibl)
                        applyIBLReceiver(to: phone, ibl: ibl)
                    }

                    content.add(phone)
                    content.cameraTarget = phone
                } catch {
                    status = error.localizedDescription
                }
            }
            .realityViewCameraControls(.orbit)
            .ignoresSafeArea()

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

    private func applyPhoneMaterials(to entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            let material = material(for: entity.name)
            model.materials = Array(repeating: material, count: max(model.materials.count, 1))
            entity.components.set(model)
        }
        for child in entity.children {
            applyPhoneMaterials(to: child)
        }
    }

    private func applyIBLReceiver(to entity: Entity, ibl: Entity) {
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
        for child in entity.children {
            applyIBLReceiver(to: child, ibl: ibl)
        }
    }

    private func material(for name: String) -> PhysicallyBasedMaterial {
        let key = name.lowercased()

        if key.contains("screen") && !key.contains("glass") && !key.contains("edge") {
            return pbr(
                color: NSColor(calibratedWhite: 0.03, alpha: 1),
                metallic: 0,
                roughness: 0.03,
                specular: 1,
                clearcoat: 1,
                clearcoatRoughness: 0.02
            )
        }
        if key.contains("glass_rough") || key.contains("matte") {
            return pbr(
                color: NSColor(calibratedRed: 0.07, green: 0.075, blue: 0.08, alpha: 1),
                metallic: 0,
                roughness: 0.32,
                specular: 0.85,
                clearcoat: 0.35,
                clearcoatRoughness: 0.25
            )
        }
        if key.contains("glass") {
            return pbr(
                color: NSColor(calibratedRed: 0.04, green: 0.045, blue: 0.05, alpha: 1),
                metallic: 0,
                roughness: 0.045,
                specular: 1,
                clearcoat: 1,
                clearcoatRoughness: 0.04
            )
        }
        if key.contains("lens") {
            return pbr(
                color: NSColor(calibratedWhite: 0.02, alpha: 1),
                metallic: 0,
                roughness: 0.02,
                specular: 1,
                clearcoat: 1,
                clearcoatRoughness: 0.02
            )
        }
        if key.contains("flash") {
            return pbr(
                color: NSColor(calibratedWhite: 0.92, alpha: 1),
                metallic: 0,
                roughness: 0.28,
                specular: 0.7
            )
        }
        if key.contains("logo") {
            return pbr(
                color: NSColor(calibratedWhite: 0.72, alpha: 1),
                metallic: 1,
                roughness: 0.12,
                specular: 1
            )
        }
        if key.contains("antenna") {
            return pbr(
                color: NSColor(calibratedRed: 0.22, green: 0.23, blue: 0.24, alpha: 1),
                metallic: 0.85,
                roughness: 0.28
            )
        }
        if key.contains("plastic") || key.contains("black") || key.contains("mic") {
            return pbr(
                color: NSColor(calibratedWhite: 0.05, alpha: 1),
                metallic: 0,
                roughness: 0.38,
                specular: 0.35
            )
        }
        if key.contains("edge") || key.contains("back") || key.contains("gray") {
            return pbr(
                color: NSColor(calibratedRed: 0.42, green: 0.43, blue: 0.45, alpha: 1),
                metallic: 1,
                roughness: 0.16,
                specular: 1
            )
        }

        return pbr(
            color: NSColor(calibratedRed: 0.38, green: 0.39, blue: 0.41, alpha: 1),
            metallic: 1,
            roughness: 0.18,
            specular: 1
        )
    }

    private func pbr(
        color: NSColor,
        metallic: Float,
        roughness: Float,
        specular: Float = 0.5,
        clearcoat: Float = 0,
        clearcoatRoughness: Float = 0.1
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.metallic = .init(floatLiteral: metallic)
        material.roughness = .init(floatLiteral: roughness)
        material.specular = .init(floatLiteral: specular)
        material.clearcoat = .init(floatLiteral: clearcoat)
        material.clearcoatRoughness = .init(floatLiteral: clearcoatRoughness)
        return material
    }

    private func addStudioLights(to content: inout RealityViewCameraContent) {
        let key = DirectionalLight()
        key.light.color = .white
        key.light.intensity = 1800
        key.shadow = DirectionalLightComponent.Shadow()
        key.look(at: .zero, from: [0.35, 0.55, 0.45], relativeTo: nil)
        content.add(key)

        let fill = DirectionalLight()
        fill.light.color = NSColor(calibratedRed: 0.82, green: 0.88, blue: 1.0, alpha: 1)
        fill.light.intensity = 500
        fill.look(at: .zero, from: [-0.55, 0.18, 0.28], relativeTo: nil)
        content.add(fill)

        let rim = DirectionalLight()
        rim.light.color = NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.82, alpha: 1)
        rim.light.intensity = 700
        rim.look(at: .zero, from: [0.08, 0.28, -0.55], relativeTo: nil)
        content.add(rim)
    }

    private func studioEnvironment() throws -> EnvironmentResource {
        let width = 1024
        let height = 512
        let w = CGFloat(width)
        let h = CGFloat(height)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        context.setFillColor(NSColor(calibratedWhite: 0.07, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Floor is darker so the phone reads against the studio.
        context.setFillColor(NSColor(calibratedWhite: 0.04, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.28))

        // Ceiling wash.
        context.setFillColor(NSColor(calibratedWhite: 0.16, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: h * 0.78, width: w, height: h * 0.22))

        func softbox(_ rect: CGRect, color: NSColor) {
            context.setFillColor(color.cgColor)
            context.fill(rect.insetBy(dx: 2, dy: 2))
        }

        // Key window, camera-left.
        softbox(CGRect(x: w * 0.08, y: h * 0.38, width: w * 0.16, height: h * 0.34),
                color: NSColor(calibratedWhite: 1, alpha: 1))
        // Cool fill window, camera-right.
        softbox(CGRect(x: w * 0.72, y: h * 0.40, width: w * 0.14, height: h * 0.28),
                color: NSColor(calibratedRed: 0.75, green: 0.86, blue: 1.0, alpha: 1))
        // Warm overhead strip.
        softbox(CGRect(x: w * 0.28, y: h * 0.86, width: w * 0.44, height: h * 0.08),
                color: NSColor(calibratedRed: 1.0, green: 0.94, blue: 0.84, alpha: 1))
        // Rim panel behind the subject.
        softbox(CGRect(x: w * 0.44, y: h * 0.34, width: w * 0.08, height: h * 0.22),
                color: NSColor(calibratedWhite: 0.85, alpha: 1))

        guard let image = context.makeImage() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try EnvironmentResource(equirectangular: image)
    }
}

#Preview {
    ContentView()
}
