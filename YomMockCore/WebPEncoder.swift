//
//  WebPEncoder.swift
//  YomMockCore
//
//  Real WebP encoding via libwebp (SDWebImage/libwebp-Xcode SPM package).
//  Apple's ImageIO decodes WebP but has no WebP destination, so encoding
//  goes through libwebp directly.

import Accelerate
import CoreGraphics
import Foundation
import libwebp

enum WebPEncoder {
    /// Encodes a CGImage as WebP.
    /// - Parameters:
    ///   - lossy: `false` uses lossless VP8L; `true` uses lossy VP8 at
    ///     `quality` (0...1).
    static func encode(_ cgImage: CGImage, lossy: Bool, quality: Double) -> Data? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0,
            let pixels = straightRGBA(from: cgImage)
        else { return nil }
        defer { pixels.baseAddress?.deallocate() }

        var output: UnsafeMutablePointer<UInt8>?
        let size = pixels.baseAddress.map { base -> Int in
            if lossy {
                return WebPEncodeRGBA(
                    base, Int32(width), Int32(height), Int32(width * 4),
                    Float(min(max(quality, 0), 1) * 100), &output)
            }
            return WebPEncodeLosslessRGBA(
                base, Int32(width), Int32(height), Int32(width * 4), &output)
        } ?? 0
        guard size > 0, let output else { return nil }
        defer { WebPFree(output) }
        return Data(bytes: output, count: size)
    }

    /// Straight (non-premultiplied) RGBA8888 pixels, as libwebp expects.
    /// Caller owns the returned buffer (`deallocate()` when done).
    private static func straightRGBA(from cgImage: CGImage) -> UnsafeMutableBufferPointer<UInt8>? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        let count = bytesPerRow * height
        let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        // RGBA byte order in memory = byteOrder32Big + alphaLast.
        guard
            let context = CGContext(
                data: pixels, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            pixels.deallocate()
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        // CoreGraphics draws premultiplied; libwebp wants straight alpha.
        var buffer = vImage_Buffer(
            data: pixels, height: vImagePixelCount(height),
            width: vImagePixelCount(width), rowBytes: bytesPerRow)
        let straight = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        var outBuffer = vImage_Buffer(
            data: straight, height: vImagePixelCount(height),
            width: vImagePixelCount(width), rowBytes: bytesPerRow)
        guard
            vImageUnpremultiplyData_RGBA8888(&buffer, &outBuffer, vImage_Flags(kvImageNoFlags))
                == kvImageNoError
        else {
            pixels.deallocate()
            straight.deallocate()
            return nil
        }
        pixels.deallocate()
        return UnsafeMutableBufferPointer(start: straight, count: count)
    }
}
