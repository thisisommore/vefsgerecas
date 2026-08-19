//
//  PhoneStyling.swift
//  YomMock
//
//  Shared phone materials / shadows / image conversion used by BOTH the
//  live RealityView preview and the offline RealityRenderer export path,
//  so exported frames match the preview exactly.
//

import AppKit
import RealityKit
import SwiftUI

enum PhoneStyling {

    // MARK: - Materials

    static func applyMaterials(to entity: Entity, finish: PhoneFinish, displayTexture: TextureResource?) {
        if var model = entity.components[ModelComponent.self] {
            let material = material(for: entity.name, finish: finish, displayTexture: displayTexture)
            model.materials = Array(repeating: material, count: max(model.materials.count, 1))
            entity.components.set(model)
        }
        for child in entity.children {
            applyMaterials(to: child, finish: finish, displayTexture: displayTexture)
        }
    }

    static func applyGroundingShadows(to entity: Entity) {
        if entity.components.has(ModelComponent.self) {
            entity.components.set(
                GroundingShadowComponent(castsShadow: true, receivesShadow: false))
        }
        for child in entity.children {
            applyGroundingShadows(to: child)
        }
    }

    static func material(for name: String, finish: PhoneFinish, displayTexture: TextureResource?) -> any RealityKit.Material {
        let key = name.lowercased()

        if key.contains("screen") && !key.contains("glass") && !key.contains("edge") {
            if let displayTexture {
                return screenMaterial(with: displayTexture)
            }
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
        // The cover glass sits directly in front of the LCD (Mesh_013_Glass_Screen).
        // When a screenshot is active it must be transparent, otherwise the opaque
        // dark glass hides the textured 043_Screen plane behind it.
        if key.contains("glass_screen") {
            if displayTexture != nil {
                var material = PhysicallyBasedMaterial()
                material.baseColor = .init(tint: NSColor(white: 1, alpha: 0))
                material.metallic = .init(floatLiteral: 0)
                material.roughness = .init(floatLiteral: 0.015)
                material.specular = .init(floatLiteral: 1)
                material.clearcoat = .init(floatLiteral: 1)
                material.clearcoatRoughness = .init(floatLiteral: 0.015)
                material.blending = .transparent(opacity: 0.0)
                return material
            }
            // No screenshot — keep the original dark glass so the off-screen looks correct.
            return pbr(
                color: NSColor(calibratedRed: 0.03, green: 0.032, blue: 0.036, alpha: 1),
                metallic: 0,
                roughness: 0.028,
                specular: 1,
                clearcoat: 1,
                clearcoatRoughness: 0.02
            )
        }
        if key.contains("glass_back")
            || key.contains("glass_rough")
            || key.contains("matte")
            || (key.contains("back") && !key.contains("antenna"))
        {
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

    static func pbr(
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

    static func screenMaterial(with texture: TextureResource) -> any RealityKit.Material {
        // Unlit shows the texture 1:1 — no IBL tint, no ACES washout, no double exposure.
        // Keeps high-res screenshots sharp and color-accurate.
        // applyPostProcessToneMap = false prevents HDR washout (macOS 15+).
        if #available(macOS 15.0, *) {
            var material = UnlitMaterial(color: .white, applyPostProcessToneMap: false)
            material.color = .init(tint: .white, texture: .init(texture))
            return material
        } else {
            var material = UnlitMaterial(color: .white)
            material.color = .init(tint: .white, texture: .init(texture))
            return material
        }
    }

    // MARK: - Display screenshot

    /// Builds the sRGB display texture used for the phone screen.
    static func displayTexture(from image: NSImage) async throws -> TextureResource {
        let cgImage = try sRGBCGImage(from: image)
        return try await TextureResource(
            image: cgImage,
            withName: "DisplayScreenshot",
            options: TextureResource.CreateOptions(
                semantic: .color,
                compression: .none,
                mipmapsMode: .allocateAndGenerateAll
            )
        )
    }

    /// Prefer a CGImage already in sRGB to keep colors 1:1.
    static func sRGBCGImage(from nsImage: NSImage) throws -> CGImage {
        var rect = NSRect(origin: .zero, size: nsImage.size)
        if let cg = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            if let cs = cg.colorSpace, cs.name == CGColorSpace.sRGB { return cg }
            // Convert to sRGB if needed so RealityKit's .color semantic doesn't shift hues.
            if let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
               let ctx = CGContext(
                 data: nil, width: cg.width, height: cg.height,
                 bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
               )
            {
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                if let converted = ctx.makeImage() { return converted }
            }
            return cg
        }
        guard let tiff = nsImage.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let cg = rep.cgImage
        else {
            throw CocoaError(
                .fileReadCorruptFile,
                userInfo: [NSLocalizedDescriptionKey: "Could not convert image to CGImage."])
        }
        return cg
    }
}
