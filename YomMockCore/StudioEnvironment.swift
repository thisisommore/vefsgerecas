//
//  StudioEnvironment.swift
//  YomMock
//

import CoreGraphics
import Foundation
import RealityKit
import simd

enum StudioEnvironment {
    static func resource() async throws -> EnvironmentResource {
        let image = try renderHDRI()
        do {
            #if os(macOS)
            let samplingQuality = TextureResource.SamplingQuality.veryHigh
            let cubeQuality = TextureResource.SamplingQuality.veryHigh
            #else
            // iOS exposes a reduced sampling-quality set.
            let samplingQuality = TextureResource.SamplingQuality.normal
            let cubeQuality = TextureResource.SamplingQuality.normal
            #endif
            let cube = try await TextureResource(
                cubeFromEquirectangular: image,
                named: "StudioHDRI",
                quality: cubeQuality,
                faceSize: 512,
                options: TextureResource.CreateOptions(
                    semantic: .hdrColor,
                    compression: .none,
                    mipmapsMode: .allocateAndGenerateAll
                )
            )
            return try await EnvironmentResource(
                cube: cube,
                options: EnvironmentResource.CreateOptions(
                    samplingQuality: samplingQuality,
                    specularCubeDimension: 512,
                    compression: .none
                )
            )
        } catch {
            return try await EnvironmentResource(equirectangular: image, withName: "StudioHDRI")
        }
    }

    /// Linear-space HDR studio. Room stays dim so the rectangular
    /// windows read as hot highlights on glass and metal.
    private static func renderHDRI() throws -> CGImage {
        let width = 2048
        let height = 1024
        var pixels = [Float](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            let v = (Float(y) + 0.5) / Float(height)
            for x in 0..<width {
                let u = (Float(x) + 0.5) / Float(width)
                let color = sample(u: u, v: v)
                let i = (y * width + x) * 4
                pixels[i + 0] = color.x
                pixels[i + 1] = color.y
                pixels[i + 2] = color.z
                pixels[i + 3] = 1
            }
        }

        return try makeHDRImage(pixels: pixels, width: width, height: height)
    }

    private static func sample(u: Float, v: Float) -> SIMD3<Float> {
        // v = 0 at +Y, 1 at -Y.
        let ceiling = smoothstep(0.42, 0.0, v)
        let floor = smoothstep(0.58, 1.0, v)
        let walls = 1 - max(ceiling, floor)

        var color = SIMD3<Float>(repeating: 0.52) * walls
        color += SIMD3<Float>(repeating: 0.78) * ceiling
        color += SIMD3<Float>(0.40, 0.40, 0.405) * floor

        // Large key window, camera-left / slightly above the horizon.
        color += SIMD3<Float>(repeating: 22) * window(
            u: u, v: v, center: SIMD2(0.34, 0.36), half: SIMD2(0.11, 0.16), edge: 0.035
        )
        // Cool fill window, camera-right.
        color += SIMD3<Float>(0.72, 0.84, 1.0) * 6.5 * window(
            u: u, v: v, center: SIMD2(0.70, 0.40), half: SIMD2(0.08, 0.12), edge: 0.04
        )
        // Warm overhead strip.
        color += SIMD3<Float>(1.0, 0.93, 0.82) * 9 * window(
            u: u, v: v, center: SIMD2(0.50, 0.09), half: SIMD2(0.28, 0.045), edge: 0.03
        )
        // Rim panel behind the subject.
        color += SIMD3<Float>(1.0, 0.97, 0.92) * 10 * window(
            u: u, v: v, center: SIMD2(0.04, 0.38), half: SIMD2(0.055, 0.14), edge: 0.03
        )
        // Thin vertical kicker for the aluminum rail.
        color += SIMD3<Float>(repeating: 7.5) * window(
            u: u, v: v, center: SIMD2(0.22, 0.42), half: SIMD2(0.018, 0.20), edge: 0.012
        )
        // Floor bounce card.
        color += SIMD3<Float>(1.0, 0.96, 0.90) * 2.8 * window(
            u: u, v: v, center: SIMD2(0.50, 0.84), half: SIMD2(0.22, 0.08), edge: 0.06
        )
        // Small highlights for the camera glass.
        color += SIMD3<Float>(repeating: 14) * window(
            u: u, v: v, center: SIMD2(0.46, 0.30), half: SIMD2(0.025, 0.04), edge: 0.018
        )

        return color
    }

    private static func window(
        u: Float,
        v: Float,
        center: SIMD2<Float>,
        half: SIMD2<Float>,
        edge: Float
    ) -> Float {
        let du = abs(wrapDelta(u - center.x))
        let dv = abs(v - center.y)
        return smoothstep(half.x + edge, half.x, du) * smoothstep(half.y + edge, half.y, dv)
    }

    private static func wrapDelta(_ delta: Float) -> Float {
        var value = delta
        if value > 0.5 { value -= 1 }
        if value < -0.5 { value += 1 }
        return value
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = simd_clamp((x - edge0) / (edge1 - edge0), 0, 1)
        return t * t * (3 - 2 * t)
    }

    private static func makeHDRImage(pixels: [Float], width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGBitmapInfo.floatComponents.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.noneSkipLast.rawValue
        )
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard
            let provider = CGDataProvider(data: data as CFData),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 32,
                bitsPerPixel: 128,
                bytesPerRow: width * 16,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return image
    }
}
