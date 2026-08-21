//
//  PhoneStyling.swift
//  YomMock
//
//  Shared device materials / shadows / image conversion used by BOTH the
//  live RealityView preview and the offline RealityRenderer export path,
//  so exported frames match the preview exactly.
//

import AppKit
import RealityKit
import SwiftUI

enum PhoneStyling {

    // MARK: - Materials

    static func applyMaterials(to entity: Entity, device: Device = .iPhone, finish: PhoneFinish, displayTexture: TextureResource?, lidGlow: Float = 0, displayAverageColor: NSColor? = nil) {
        if var model = entity.components[ModelComponent.self] {
            let material = material(for: entity.name, device: device, finish: finish, displayTexture: displayTexture, lidGlow: lidGlow, displayAverageColor: displayAverageColor)
            model.materials = Array(repeating: material, count: max(model.materials.count, 1))
            entity.components.set(model)
        }
        for child in entity.children {
            applyMaterials(to: child, device: device, finish: finish, displayTexture: displayTexture, lidGlow: lidGlow, displayAverageColor: displayAverageColor)
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

    static func material(for name: String, device: Device = .iPhone, finish: PhoneFinish, displayTexture: TextureResource?, lidGlow: Float = 0, displayAverageColor: NSColor? = nil) -> any RealityKit.Material {
        switch device {
        case .iPhone:
            return phoneMaterial(for: name, finish: finish, displayTexture: displayTexture)
        case .macBookPro:
            return macMaterial(for: name, finish: finish, displayTexture: displayTexture, lidGlow: lidGlow, displayAverageColor: displayAverageColor)
        }
    }

    /// Emissive strengths for the MacBook screen spill (scaled by lidGlow).
    /// TEMP: vars for render tuning; make let once tuned.
    static var macGlowDeckNear: Float = 0.18
    static var macGlowDeckFar: Float = 0.10
    static var macGlowKeys: Float = 0.22
    static var macGlowLegends: Float = 1.2
    static var macGlowHinge: Float = 0.15

    /// MacBook Pro materials, keyed by the semantic mesh names baked into
    /// MacBookPro.usdc at conversion time (Base, Lid, Screen, Bezel, Keys…).
    /// `lidGlow` adds a cool-white emissive to the deck area, faking the
    /// screen spill when the lid is partly closed (MacBookLidRig.glowFactor).
    /// When `displayAverageColor` is provided, the spill is tinted to match
    /// the screenshot instead of the fixed cool-white.
    static func macMaterial(for name: String, finish: PhoneFinish, displayTexture: TextureResource?, lidGlow: Float = 0, displayAverageColor: NSColor? = nil) -> any RealityKit.Material {
        let glowColor = displayAverageColor ?? NSColor(calibratedRed: 0.72, green: 0.80, blue: 0.95, alpha: 1)
        switch name.lowercased() {
        case "screen":
            if let displayTexture {
                return screenMaterial(with: displayTexture)
            }
            // Powered-off LCD.
            return pbr(
                color: NSColor(calibratedWhite: 0.02, alpha: 1),
                metallic: 0,
                roughness: 0.05,
                specular: 1,
                clearcoat: 1,
                clearcoatRoughness: 0.02
            )
        case "bezel", "bezelchin":
            return pbr(
                color: NSColor(calibratedWhite: 0.02, alpha: 1),
                metallic: 0.1,
                roughness: 0.25,
                specular: 0.6
            )
        case "keys":
            return pbr(
                color: NSColor(calibratedWhite: 0.06, alpha: 1),
                metallic: 0,
                roughness: 0.5,
                specular: 0.3,
                emissive: glowColor,
                emissiveIntensity: macGlowKeys * lidGlow
            )
        case "keyboarddetail":
            // Keycap legends — light like backlit glyphs.
            return pbr(
                color: NSColor(calibratedWhite: 0.75, alpha: 1),
                metallic: 0,
                roughness: 0.5,
                specular: 0.3,
                emissive: glowColor,
                emissiveIntensity: macGlowLegends * lidGlow
            )
        case "lidinner":
            // Full-face glass panel over the Screen mesh. Transparent when a
            // screenshot is active, dark glass otherwise (like the iPhone's
            // cover glass over the textured screen plane).
            if displayTexture != nil {
                var material = PhysicallyBasedMaterial()
                material.baseColor = .init(tint: NSColor(white: 1, alpha: 0))
                material.metallic = .init(floatLiteral: 0)
                material.roughness = .init(floatLiteral: 0.02)
                material.specular = .init(floatLiteral: 1)
                material.clearcoat = .init(floatLiteral: 1)
                material.clearcoatRoughness = .init(floatLiteral: 0.02)
                material.blending = .transparent(opacity: 0.0)
                return material
            }
            return pbr(
                color: NSColor(calibratedRed: 0.03, green: 0.032, blue: 0.036, alpha: 1),
                metallic: 0,
                roughness: 0.028,
                specular: 1,
                clearcoat: 1,
                clearcoatRoughness: 0.02
            )
        case "hingevent", "port", "deckstrip", "baseinner":
            return pbr(
                color: NSColor(calibratedWhite: 0.03, alpha: 1),
                metallic: 0.1,
                roughness: 0.45,
                specular: 0.3,
                emissive: glowColor,
                emissiveIntensity: macGlowHinge * lidGlow
            )
        case "keyboarddeck":
            // Deck + trackpad around the keys — nearest to the screen.
            return pbr(
                color: finish.frame,
                metallic: 0.9,
                roughness: 0.32,
                specular: 1,
                anisotropy: 0.15,
                emissive: glowColor,
                emissiveIntensity: macGlowDeckNear * lidGlow
            )
        case "lid":
            // Lid back — faces away from the screen, no spill.
            return pbr(
                color: finish.frame,
                metallic: 0.9,
                roughness: 0.32,
                specular: 1,
                anisotropy: 0.15
            )
        case "logo":
            return pbr(
                color: NSColor(calibratedWhite: 0.8, alpha: 1),
                metallic: 1,
                roughness: 0.08,
                specular: 1
            )
        case "feet":
            return pbr(
                color: NSColor(calibratedWhite: 0.05, alpha: 1),
                metallic: 0,
                roughness: 0.6,
                specular: 0.2
            )
        default:
            // Base, BottomPlate — far from the screen, faint spill.
            return pbr(
                color: finish.frame,
                metallic: 0.9,
                roughness: 0.32,
                specular: 1,
                anisotropy: 0.15,
                emissive: glowColor,
                emissiveIntensity: macGlowDeckFar * lidGlow
            )
        }
    }

    static func phoneMaterial(for name: String, finish: PhoneFinish, displayTexture: TextureResource?) -> any RealityKit.Material {
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

    /// Average color of a CGImage by downscaling to 32×32 and averaging pixels.
    /// Used to tint the MacBook keyboard spill so it matches the screenshot.
    /// Filters near-white pixels and boosts saturation so light wallpapers still
    /// read as tinted rather than pure white.
    static func averageColor(from cgImage: CGImage) -> NSColor? {
        let sampleSize = 32
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var rawData = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        guard let context = CGContext(
            data: &rawData,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: sampleSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
        var r: UInt64 = 0, g: UInt64 = 0, b: UInt64 = 0, count: UInt64 = 0
        var rf: UInt64 = 0, gf: UInt64 = 0, bf: UInt64 = 0, countF: UInt64 = 0
        for i in stride(from: 0, to: rawData.count, by: 4) {
            let a = rawData[i + 3]
            guard a > 10 else { continue }
            let rr = rawData[i], gg = rawData[i+1], bb = rawData[i+2]
            r += UInt64(rr); g += UInt64(gg); b += UInt64(bb); count += 1
            // Filter near-white / very low saturation for vibrant average
            let rfN = CGFloat(rr)/255, gfN = CGFloat(gg)/255, bfN = CGFloat(bb)/255
            let mx = max(rfN, max(gfN, bfN)), mn = min(rfN, min(gfN, bfN))
            let delta = mx - mn
            let s: CGFloat = mx == 0 ? 0 : delta / mx
            let isWhite = mx > 0.94 && s < 0.12
            let isVeryLightGray = mx > 0.88 && s < 0.06
            if !isWhite && !isVeryLightGray {
                rf += UInt64(rr); gf += UInt64(gg); bf += UInt64(bb); countF += 1
            }
        }
        guard count > 0 else { return nil }
        // Prefer filtered average when enough colorful pixels remain ( >20% )
        let useFiltered = countF > count / 5 && countF > 0
        let fr = useFiltered ? rf : r
        let fg = useFiltered ? gf : g
        let fb = useFiltered ? bf : b
        let fc = useFiltered ? countF : count
        var color = NSColor(
            calibratedRed: CGFloat(fr) / CGFloat(fc) / 255.0,
            green: CGFloat(fg) / CGFloat(fc) / 255.0,
            blue: CGFloat(fb) / CGFloat(fc) / 255.0,
            alpha: 1
        )
        // Boost saturation / brightness so desaturated wallpapers still tint visibly.
        if let srgb = color.usingColorSpace(.sRGB) {
            var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
            srgb.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
            if s < 0.35 {
                s = min(s * 2.6 + 0.18, 0.85)
            } else if s < 0.6 {
                s = min(s * 1.35, 0.9)
            }
            br = max(br, 0.82)
            // For very desaturated originals (mac_home s~0.16) this moves 0.16 -> 0.60
            color = NSColor(hue: h, saturation: s, brightness: br, alpha: 1)
        }
        return color
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
