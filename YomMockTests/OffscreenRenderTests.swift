//
//  OffscreenRenderTests.swift
//  YomMockTests
//
//  Renders real frames with the offscreen RealityRenderer pipeline and
//  writes PNGs to /tmp for visual verification. Also checks determinism
//  (same state → identical pixels) and resolution independence.
//

import AppKit
import Foundation
import RealityKit
import SwiftUI
import Testing
import simd
@testable import YomMock

struct OffscreenRenderTests {

    private func makeInputs(device: Device = .iPhone, withDisplay: Bool) -> OffscreenSceneRenderer.Inputs {
        var displayCG: CGImage?
        let name = device.defaultDisplayImageName
        if withDisplay,
           let url = Bundle.main.url(forResource: name, withExtension: nil),
           let img = NSImage(contentsOf: url) {
            displayCG = try? PhoneStyling.sRGBCGImage(from: img)
        }
        let gradient = StudioBackground.white.gradient(custom: .white)
        return OffscreenSceneRenderer.Inputs(
            device: device,
            finish: iPhoneColor.mistBlue.finish(custom: .white),
            displayImage: displayCG,
            backgroundTop: NSColor(gradient.top),
            backgroundBottom: NSColor(gradient.bottom)
        )
    }

    private func savePNG(_ image: CGImage, name: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(name).png")
        let rep = NSBitmapImageRep(cgImage: image)
        let data = rep.representation(using: .png, properties: [:])
        try data?.write(to: url)
        return url
    }

    /// Samples the pixel at a normalized position (0...1, top-left origin)
    /// via NSBitmapImageRep (handles any CGImage backing store).
    private func pixel(_ image: CGImage, x: CGFloat, y: CGFloat) -> (Int, Int, Int) {
        let rep = NSBitmapImageRep(cgImage: image)
        let px = min(max(Int(x * CGFloat(rep.pixelsWide)), 0), rep.pixelsWide - 1)
        let py = min(max(Int(y * CGFloat(rep.pixelsHigh)), 0), rep.pixelsHigh - 1)
        guard let color = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) else { return (-1, -1, -1) }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// Average absolute difference between two same-size images (0 = identical).
    private func meanDifference(_ a: CGImage, _ b: CGImage) -> Double {
        guard a.width == b.width, a.height == b.height else { return .infinity }
        guard let da = a.dataProvider?.data, let db = b.dataProvider?.data else { return .infinity }
        let ba = CFDataGetBytePtr(da)!
        let bb = CFDataGetBytePtr(db)!
        let count = CFDataGetLength(da)
        guard count == CFDataGetLength(db), count > 0 else { return .infinity }
        var sum: Int64 = 0
        // Sample every 4093rd byte to keep it fast.
        var i = 0
        while i < count {
            sum += Int64(abs(Int(ba[i]) - Int(bb[i])))
            i += 4093
        }
        return Double(sum) / Double(count / 4093 + 1)
    }

    @Test @MainActor
    func renders4KFrameWithPhoneAndBackdrop() async throws {
        let renderer = try await OffscreenSceneRenderer(
            outputSize: CGSize(width: 3840, height: 2160),
            previewPointSize: CGSize(width: 960, height: 540),
            inputs: makeInputs(withDisplay: true)
        )
        let state = (OrbitPose.default, Float(1.45), SIMD3<Float>.zero)
        let buffer = try await renderer.render(
            orbit: state.0, zoom: state.1, pan: state.2, deltaTime: 1.0 / 30)
        #expect(CVPixelBufferGetWidth(buffer) == 3840)
        #expect(CVPixelBufferGetHeight(buffer) == 2160)

        let image = try #require(renderer.makeCGImage(from: buffer))
        #expect(image.width == 3840)
        #expect(image.height == 2160)
        let url = try savePNG(image, name: "yommock_offscreen_4k")
        print("wrote \(url.path)")

        // Backdrop: top and bottom edges differ (vertical gradient), non-black.
        let top = pixel(image, x: 0.05, y: 0.02)
        let bottom = pixel(image, x: 0.05, y: 0.98)
        #expect(top != bottom, "Expected vertical gradient backdrop")
        #expect(top.0 + top.1 + top.2 > 200, "Backdrop should be bright (white studio)")

        // Phone present: center pixel differs strongly from edge backdrop.
        let center = pixel(image, x: 0.5, y: 0.5)
        let edge = pixel(image, x: 0.03, y: 0.5)
        #expect(center != edge, "Center should contain the phone, not backdrop")
    }

    @Test @MainActor
    func rendersTimelinePosesAt1080p() async throws {
        let renderer = try await OffscreenSceneRenderer(
            outputSize: CGSize(width: 1920, height: 1080),
            previewPointSize: CGSize(width: 960, height: 540),
            inputs: makeInputs(withDisplay: true)
        )
        let timeline = CameraTimeline.demo
        let times: [TimeInterval] = [0, timeline.duration * 0.5, timeline.duration * 0.999]
        var images: [CGImage] = []
        for (index, t) in times.enumerated() {
            let state = timeline.evaluatedState(at: t)
            let buffer = try await renderer.render(
                orbit: state.orbit, zoom: state.zoom, pan: state.pan, deltaTime: 1.0 / 30)
            let image = try #require(renderer.makeCGImage(from: buffer))
            images.append(image)
            let url = try savePNG(image, name: "yommock_offscreen_1080p_t\(index)")
            print("wrote \(url.path)")
        }
        // Distinct timeline poses must produce distinct frames.
        #expect(meanDifference(images[0], images[1]) > 1)
        #expect(meanDifference(images[1], images[2]) > 1)
    }

    @Test @MainActor
    func displayImageChangesScreenPixels() async throws {
        let size = CGSize(width: 1280, height: 720)
        let points = CGSize(width: 960, height: 540)
        let withImage = try await OffscreenSceneRenderer(
            outputSize: size, previewPointSize: points, inputs: makeInputs(withDisplay: true))
        let withoutImage = try await OffscreenSceneRenderer(
            outputSize: size, previewPointSize: points, inputs: makeInputs(withDisplay: false))
        // Front-facing pose so the screen faces the camera.
        let pose = OrbitPose(yaw: 0.0, pitch: 0.15, radius: 4.2)
        let a = try await withImage.render(orbit: pose, zoom: 1.45, pan: .zero, deltaTime: 1.0 / 30)
        let b = try await withoutImage.render(orbit: pose, zoom: 1.45, pan: .zero, deltaTime: 1.0 / 30)
        let imgA = try #require(withImage.makeCGImage(from: a))
        let imgB = try #require(withoutImage.makeCGImage(from: b))
        #expect(meanDifference(imgA, imgB) > 0.5, "Display screenshot should change screen pixels")
    }

    // TEMP debug — lid angle + screen light tuning. Remove after visual verification.
    @Test @MainActor
    func zzLidAngleDumps() async throws {
        let renderer = try await OffscreenSceneRenderer(
            outputSize: CGSize(width: 960, height: 540),
            previewPointSize: CGSize(width: 960, height: 540),
            inputs: makeInputs(device: .macBookPro, withDisplay: true))
        let hero = OrbitPose(yaw: 0.6, pitch: 0.5, radius: 4.2)
        let side = OrbitPose(yaw: .pi / 2, pitch: 0.1, radius: 4.2)

        func dump(_ tag: String, _ pose: OrbitPose, _ angle: Float) async throws {
            let buffer = try await renderer.render(
                orbit: pose, zoom: 1.45, pan: .zero, lidAngle: angle, deltaTime: 1.0 / 30)
            let img = try #require(renderer.makeCGImage(from: buffer))
            let small = NSImage(size: NSSize(width: 480, height: 270))
            small.lockFocus()
            NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
                .draw(in: NSRect(x: 0, y: 0, width: 480, height: 270))
            small.unlockFocus()
            if let jpeg = small.tiffRepresentation
                .flatMap({ NSBitmapImageRep(data: $0) })?
                .representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                print("B64-\(tag):" + jpeg.base64EncodedString())
            }
        }

        // Screen-spill (emissive glow) across the lid range.
        for angle in [Float(55), 45, 35, 15] {
            try await dump("GLOW-\(Int(angle))", hero, angle)
        }
        try await dump("GLOW-35-SIDE", side, 35)
    }

    @Test @MainActor
    func rendersMacBookFrameWithDefaultScreenshot() async throws {
        let size = CGSize(width: 1920, height: 1080)
        let points = CGSize(width: 960, height: 540)
        let withImage = try await OffscreenSceneRenderer(
            outputSize: size, previewPointSize: points, inputs: makeInputs(device: .macBookPro, withDisplay: true))
        let withoutImage = try await OffscreenSceneRenderer(
            outputSize: size, previewPointSize: points, inputs: makeInputs(device: .macBookPro, withDisplay: false))
        // Front-facing pose so the laptop screen faces the camera.
        let pose = OrbitPose(yaw: 0.0, pitch: 0.15, radius: 4.2)
        let a = try await withImage.render(orbit: pose, zoom: 1.45, pan: .zero, deltaTime: 1.0 / 30)
        let b = try await withoutImage.render(orbit: pose, zoom: 1.45, pan: .zero, deltaTime: 1.0 / 30)
        let imgA = try #require(withImage.makeCGImage(from: a))
        let imgB = try #require(withoutImage.makeCGImage(from: b))
        #expect(meanDifference(imgA, imgB) > 0.5, "MacBook screen should show the screenshot")
        let url = try savePNG(imgA, name: "yommock_offscreen_macbook")
        print("wrote \(url.path)")
    }

    @Test @MainActor
    func sameStateRendersIdenticalPixels() async throws {
        let renderer = try await OffscreenSceneRenderer(
            outputSize: CGSize(width: 1280, height: 720),
            previewPointSize: CGSize(width: 960, height: 540),
            inputs: makeInputs(withDisplay: false)
        )
        let pose = OrbitPose(yaw: 0.5, pitch: 0.3, radius: 4.5)
        var images: [CGImage] = []
        for _ in 0..<2 {
            let buffer = try await renderer.render(
                orbit: pose, zoom: 1.2, pan: .zero, deltaTime: 1.0 / 30)
            images.append(try #require(renderer.makeCGImage(from: buffer)))
        }
        let diff = meanDifference(images[0], images[1])
        #expect(diff == 0, "Expected deterministic render, mean diff \(diff)")
    }
}
