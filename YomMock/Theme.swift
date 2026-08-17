//
//  Theme.swift
//  YomMock
//

import AppKit
import SwiftUI

extension Color {
    /// A color that resolves differently in light and dark appearance.
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark)
                : NSColor(light)
        })
    }

    /// Playhead knob fill that stays visible on the track in both modes.
    static let timelineKnob = Color.dynamic(
        light: Color(red: 0.953, green: 0.953, blue: 0.957),
        dark: Color(red: 0.145, green: 0.153, blue: 0.169)
    )
}

/// The backdrop behind the 3D phone in the preview. Colors are literal and
/// theme-independent, so `.white` stays white in any device appearance.
enum StudioBackground: Hashable, Identifiable {
    case white
    case black
    case lightGray
    case cream
    case slate
    case custom

    static let presets: [StudioBackground] = [.white, .black, .lightGray, .cream, .slate]

    var id: Self { self }

    var name: String {
        switch self {
        case .white: "White"
        case .black: "Black"
        case .lightGray: "Light Gray"
        case .cream: "Cream"
        case .slate: "Slate"
        case .custom: "Custom"
        }
    }

    var swatch: Color {
        switch self {
        case .white: .white
        case .black: Color(red: 0.04, green: 0.04, blue: 0.05)
        case .lightGray: Color(red: 0.90, green: 0.90, blue: 0.91)
        case .cream: Color(red: 0.95, green: 0.93, blue: 0.88)
        case .slate: Color(red: 0.82, green: 0.84, blue: 0.87)
        case .custom: .white
        }
    }

    /// Top and bottom colors of the vertical backdrop gradient for a given
    /// selection (slightly lighter at the top reads like soft studio light).
    func gradient(custom: Color) -> (top: Color, bottom: Color) {
        let base: Color
        switch self {
        case .custom:
            base = custom
        default:
            base = swatch
        }
        let nsBase = NSColor(base).usingColorSpace(.deviceRGB)
            ?? NSColor(calibratedWhite: 0.5, alpha: 1)
        let top = nsBase.blended(with: .white, amount: 0.12)
        let bottom = nsBase.blended(with: .black, amount: 0.05)
        return (Color(nsColor: top), Color(nsColor: bottom))
    }
}

extension NSColor {
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


