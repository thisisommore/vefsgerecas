//
//  PlatformCompat.swift
//  YomMockCore
//
//  Thin cross-platform layer so the shared core compiles for both the
//  macOS app and the native iPadOS target. AppKit types are aliased on
//  macOS; UIKit equivalents on iOS.
//

import CoreGraphics
import Foundation
import SwiftUI

#if canImport(AppKit)
import AppKit

typealias PlatformImage = NSImage
typealias PlatformColor = NSColor

#else
import UIKit

typealias PlatformImage = UIImage
typealias PlatformColor = UIColor

#endif

// MARK: - Color helpers

extension PlatformColor {
    /// sRGB color from 0...1 components on every platform.
    static func studio(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1)
        -> PlatformColor
    {
        #if canImport(AppKit)
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        #else
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
        #endif
    }

    /// RGBA components in extended sRGB.
    var studioRGBA: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(AppKit)
        (usingColorSpace(.deviceRGB) ?? self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return (r, g, b, a)
    }

    var studioHueBrightness: (hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        #if canImport(AppKit)
        (usingColorSpace(.deviceRGB) ?? self).getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        #else
        getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        #endif
        return (h, s, br, a)
    }

    static func studio(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat = 1)
        -> PlatformColor
    {
        #if canImport(AppKit)
        return NSColor(
            calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
        #else
        return UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
        #endif
    }

    func blended(with other: PlatformColor, amount: CGFloat) -> PlatformColor {
        let lhs = studioRGBA
        let rhs = other.studioRGBA
        return PlatformColor.studio(
            red: lhs.red + (rhs.red - lhs.red) * amount,
            green: lhs.green + (rhs.green - lhs.green) * amount,
            blue: lhs.blue + (rhs.blue - lhs.blue) * amount
        )
    }

    /// White by "calibrated" brightness 0...1.
    static func studioWhite(_ level: CGFloat, alpha: CGFloat = 1) -> PlatformColor {
        studio(red: level, green: level, blue: level, alpha: alpha)
    }
}

/// SwiftUI Color -> platform color.
func platformColor(_ color: Color) -> PlatformColor {
    #if canImport(AppKit)
    return NSColor(color)
    #else
    return UIColor(color)
    #endif
}

extension Color {
    /// Platform color -> SwiftUI Color.
    init(platform color: PlatformColor) {
        #if canImport(AppKit)
        self.init(nsColor: color)
        #else
        self.init(uiColor: color)
        #endif
    }
}

// MARK: - Image helpers

enum PlatformImageLoader {
    /// Loads a decodable image from a file URL.
    static func image(contentsOf url: URL) -> PlatformImage? {
        #if canImport(AppKit)
        return NSImage(contentsOf: url)
        #else
        // UIImage(contentsOfFile:) misses scale info for some formats but is
        // fine for display textures (we always work from the CGImage).
        return UIImage(contentsOfFile: url.path)
        #endif
    }

    /// Decodes an image from raw data (PNG/JPEG/HEIC...).
    static func image(data: Data) -> PlatformImage? {
        #if canImport(AppKit)
        return NSImage(data: data)
        #else
        return UIImage(data: data)
        #endif
    }

    /// Best-effort CGImage for any platform image.
    static func cgImage(from image: PlatformImage) -> CGImage? {
        #if canImport(AppKit)
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #else
        if let cg = image.cgImage { return cg }
        // CIImage-backed images (rare) — render through a context.
        if let ci = image.ciImage {
            let context = CIContext(options: nil)
            return context.createCGImage(ci, from: ci.extent)
        }
        return nil
        #endif
    }

    /// PNG-encoded data for a CGImage (ImageIO works on every platform).
    static func pngData(from cgImage: CGImage) -> Data? {
        let out = NSMutableData()
        guard
            let dest = CGImageDestinationCreateWithData(
                out as CFMutableData, "public.png" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
