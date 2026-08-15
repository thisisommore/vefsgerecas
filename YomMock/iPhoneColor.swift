//
//  iPhoneColor.swift
//  YomMock
//

import AppKit
import SwiftUI

enum iPhoneColor: Hashable, Identifiable {
    case lavender
    case sage
    case mistBlue
    case white
    case black
    case custom

    static let presets: [iPhoneColor] = [.lavender, .sage, .mistBlue, .white, .black]

    var id: Self { self }

    var name: String {
        switch self {
        case .lavender: "Lavender"
        case .sage: "Sage"
        case .mistBlue: "Mist Blue"
        case .white: "White"
        case .black: "Black"
        case .custom: "Custom"
        }
    }

    var swatch: Color {
        switch self {
        case .lavender: Color(red: 0.78, green: 0.72, blue: 0.82)
        case .sage: Color(red: 0.70, green: 0.75, blue: 0.64)
        case .mistBlue: Color(red: 0.66, green: 0.77, blue: 0.84)
        case .white: Color(red: 0.94, green: 0.93, blue: 0.91)
        case .black: Color(red: 0.13, green: 0.13, blue: 0.14)
        case .custom: .clear
        }
    }

    func finish(custom: Color) -> PhoneFinish {
        switch self {
        case .lavender:
            return PhoneFinish.coloredGlass(
                back: NSColor(calibratedRed: 0.70, green: 0.64, blue: 0.74, alpha: 1),
                frame: NSColor(calibratedRed: 0.56, green: 0.50, blue: 0.62, alpha: 1)
            )
        case .sage:
            return PhoneFinish.coloredGlass(
                back: NSColor(calibratedRed: 0.60, green: 0.66, blue: 0.54, alpha: 1),
                frame: NSColor(calibratedRed: 0.48, green: 0.54, blue: 0.43, alpha: 1)
            )
        case .mistBlue:
            return PhoneFinish.coloredGlass(
                back: NSColor(calibratedRed: 0.56, green: 0.68, blue: 0.76, alpha: 1),
                frame: NSColor(calibratedRed: 0.44, green: 0.56, blue: 0.66, alpha: 1)
            )
        case .white:
            return PhoneFinish.coloredGlass(
                back: NSColor(calibratedRed: 0.92, green: 0.91, blue: 0.88, alpha: 1),
                frame: NSColor(calibratedRed: 0.82, green: 0.82, blue: 0.80, alpha: 1),
                metallic: 0.16,
                roughness: 0.14
            )
        case .black:
            return PhoneFinish.coloredGlass(
                back: NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.08, alpha: 1),
                frame: NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.17, alpha: 1),
                metallic: 0.38,
                roughness: 0.11,
                clearcoat: 1
            )
        case .custom:
            let back = NSColor(custom).usingColorSpace(.deviceRGB)
                ?? NSColor(calibratedWhite: 0.5, alpha: 1)
            return PhoneFinish.coloredGlass(
                back: back,
                frame: back.blended(with: .black, amount: 0.22)
            )
        }
    }
}

struct PhoneFinish {
    let back: NSColor
    let frame: NSColor
    let backMetallic: Float
    let backRoughness: Float
    let backClearcoat: Float

    static func coloredGlass(
        back: NSColor,
        frame: NSColor,
        metallic: Float = 0.22,
        roughness: Float = 0.16,
        clearcoat: Float = 0.9
    ) -> PhoneFinish {
        PhoneFinish(
            back: back,
            frame: frame,
            backMetallic: metallic,
            backRoughness: roughness,
            backClearcoat: clearcoat
        )
    }
}

private extension NSColor {
    func blended(with other: NSColor, amount: CGFloat) -> NSColor {
        let lhs = usingColorSpace(.deviceRGB) ?? self
        let rhs = other.usingColorSpace(.deviceRGB) ?? other
        return NSColor(
            calibratedRed: lhs.redComponent + (rhs.redComponent - lhs.redComponent) * amount,
            green: lhs.greenComponent + (rhs.greenComponent - lhs.greenComponent) * amount,
            blue: lhs.blueComponent + (rhs.blueComponent - lhs.blueComponent) * amount,
            alpha: 1
        )
    }
}
