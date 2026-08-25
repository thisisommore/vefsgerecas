//
//  WebPTests.swift
//  YomMockTests
//
//  WebP display-image support: encoding produces a real WebP container and
//  decoding round-trips through PlatformImageLoader (ImageIO fallback path).
//

import CoreGraphics
import Foundation
import Testing
@testable import YomMock

struct WebPTests {
    @Test func webPEncodeProducesWebPContainer() throws {
        let data = try #require(PlatformImageLoader.webPData(from: makeSolidCGImage()))
        // RIFF container: "RIFF" <size> "WEBP"
        #expect(data.count > 12)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: data.dropFirst(8).prefix(4), as: UTF8.self) == "WEBP")
    }

    @Test func webPRoundTripPreservesDimensions() throws {
        let source = makeSolidCGImage()
        let data = try #require(PlatformImageLoader.webPData(from: source))
        let decoded = try #require(PlatformImageLoader.image(data: data))
        let cg = try #require(PlatformImageLoader.cgImage(from: decoded))
        #expect(cg.width == source.width)
        #expect(cg.height == source.height)
    }

    @Test func webPLoadsFromFileURL() throws {
        let source = makeSolidCGImage()
        let data = try #require(PlatformImageLoader.webPData(from: source))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("YomMockWebPTests-\(UUID().uuidString)")
            .appendingPathExtension("webp")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoded = try #require(PlatformImageLoader.image(contentsOf: url))
        let cg = try #require(PlatformImageLoader.cgImage(from: decoded))
        #expect(cg.width == source.width)
        #expect(cg.height == source.height)
    }
}
