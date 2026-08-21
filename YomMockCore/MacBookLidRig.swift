//
//  MacBookLidRig.swift
//  YomMock
//
//  Runtime lid rig for the MacBook Pro model: regroups the lid meshes under
//  a pivot entity at the hinge so the lid can open/close. The screen "spill"
//  on the keyboard is done in the materials (emissive via glowFactor) rather
//  than a light — point/spot lights are ignored by RealityRenderer, and a
//  directional light throws a harsh specular blob on the aluminum deck,
//  unlike the soft glow of a real screen. Used identically in the live
//  preview and the offscreen renderer.
//

import RealityKit
import simd

#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class MacBookLidRig {
    /// As-modeled lid opening in degrees from the deck — the model is
    /// authored fully open; angles below this close the lid.
    nonisolated static let defaultOpenAngle: Float = 110
    static let minOpenAngle: Float = 0

    /// Hinge pivot in model space (before scene scaling), along the X axis.
    /// Center of the lid's hinge-edge band measured from MacBookPro.usdc
    /// (edge spans y 0.0707-0.1155, z -1.0694..-0.9966; z tuned so the closed
    /// lid sits flush with the base at both rear and front), so the lid's
    /// bottom edge stays planted on the hinge through the whole range and the
    /// screen lands flat on the deck when closed.
    static let hingePivot = SIMD3<Float>(0, 0.093, -1.017)

    /// Mesh names that make up the moving lid assembly (from MacBookPro.usdc).
    private static let lidMeshNames: Set<String> = ["Lid", "LidInner", "Screen", "Bezel", "BezelChin", "Logo"]

    private let assembly: Entity
    private var currentAngle: Float = MacBookLidRig.defaultOpenAngle

    /// Whether the display has content. When off, there is no screen glow.
    var displayOn: Bool = true

    /// Screen-spill strength 0...1: none when fully open, full below ~35°.
    /// Materials add emissive scaled by this (see PhoneStyling.macMaterial).
    var glowFactor: Float {
        guard displayOn else { return 0 }
        return simd_clamp((75 - currentAngle) / 40, 0, 1)
    }

    private init(assembly: Entity) {
        self.assembly = assembly
    }

    /// Finds the lid meshes and re-parents them under a new hinge-pivot
    /// entity. Returns nil for models without lid parts (e.g. the iPhone).
    static func install(on model: Entity) -> MacBookLidRig? {
        var lidEntities: [Entity] = []
        collectLidEntities(under: model, into: &lidEntities)
        guard lidEntities.count > 3, let parent = lidEntities[0].parent else { return nil }

        // Identity group at the same hierarchy level: world transforms of the
        // moved meshes are unchanged until the lid rotates.
        let assembly = Entity()
        assembly.name = "LidAssembly"
        parent.addChild(assembly)
        for entity in lidEntities {
            assembly.addChild(entity)
        }
        return MacBookLidRig(assembly: assembly)
    }

    /// Sets the lid opening in degrees (0 = closed, `defaultOpenAngle` = as modeled).
    func setLidAngle(_ degrees: Float) {
        currentAngle = min(max(degrees, Self.minOpenAngle), Self.defaultOpenAngle)
        let delta = (Self.defaultOpenAngle - currentAngle) * .pi / 180
        let rotation = simd_quatf(angle: delta, axis: SIMD3<Float>(1, 0, 0))
        let pivot = Self.hingePivot
        // Rotate about the hinge: translate pivot to origin, rotate, translate back.
        let matrix = Transform(translation: pivot).matrix
            * Transform(rotation: rotation).matrix
            * Transform(translation: -pivot).matrix
        assembly.transform = Transform(matrix: matrix)
    }

    private static func collectLidEntities(under entity: Entity, into result: inout [Entity]) {
        if lidMeshNames.contains(entity.name), entity.components.has(ModelComponent.self) {
            result.append(entity)
        }
        for child in entity.children {
            collectLidEntities(under: child, into: &result)
        }
    }
}
