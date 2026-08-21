//
//  iPhoneColor.swift
//  YomMock
//

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
                back: .studio(red: 0.68, green: 0.61, blue: 0.73),
                frame: .studio(red: 0.52, green: 0.46, blue: 0.58)
            )
        case .sage:
            return PhoneFinish.coloredGlass(
                back: .studio(red: 0.57, green: 0.64, blue: 0.51),
                frame: .studio(red: 0.44, green: 0.50, blue: 0.40)
            )
        case .mistBlue:
            return PhoneFinish.coloredGlass(
                back: .studio(red: 0.52, green: 0.65, blue: 0.74),
                frame: .studio(red: 0.40, green: 0.52, blue: 0.62)
            )
        case .white:
            return PhoneFinish.coloredGlass(
                back: .studio(red: 0.93, green: 0.92, blue: 0.89),
                frame: .studio(red: 0.80, green: 0.80, blue: 0.78),
                metallic: 0.10,
                roughness: 0.12,
                clearcoat: 0.95
            )
        case .black:
            return PhoneFinish.coloredGlass(
                back: .studio(red: 0.035, green: 0.035, blue: 0.04),
                frame: .studio(red: 0.10, green: 0.10, blue: 0.11),
                metallic: 0.48,
                roughness: 0.07,
                clearcoat: 1
            )
        case .custom:
            let back = platformColor(custom)
            return PhoneFinish.coloredGlass(
                back: back,
                frame: back.blended(with: .black, amount: 0.24)
            )
        }
    }
}

struct PhoneFinish {
    let back: PlatformColor
    let frame: PlatformColor
    let backMetallic: Float
    let backRoughness: Float
    let backClearcoat: Float

    static func coloredGlass(
        back: PlatformColor,
        frame: PlatformColor,
        metallic: Float = 0.18,
        roughness: Float = 0.10,
        clearcoat: Float = 1
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

