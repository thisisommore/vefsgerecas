//
//  Theme.swift
//  YomMockCore
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

extension Color {
    /// A color that resolves differently in light and dark appearance.
    static func dynamic(light: Color, dark: Color) -> Color {
        #if canImport(AppKit)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark)
                : NSColor(light)
        })
        #else
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #endif
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
    case image

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
        case .image: "Image"
        }
    }

    var swatch: Color {
        switch self {
        case .white: .white
        case .black: Color(red: 0, green: 0, blue: 0)
        case .lightGray: Color(red: 0.90, green: 0.90, blue: 0.91)
        case .cream: Color(red: 0.95, green: 0.93, blue: 0.88)
        case .slate: Color(red: 0.82, green: 0.84, blue: 0.87)
        case .custom: .white
        case .image: .white
        }
    }

    /// Top and bottom colors of the vertical backdrop gradient for a given
    /// selection. With `glow` the top is slightly lighter (soft studio
    /// light); without it the backdrop is the flat, exact swatch color.
    /// `.image` has no gradient — callers render the image instead; the
    /// gradient here is only a fallback when the image is missing.
    func gradient(custom: Color, glow: Bool = true) -> (top: Color, bottom: Color) {
        let base: Color
        switch self {
        case .custom, .image:
            base = custom
        default:
            base = swatch
        }
        guard glow else { return (base, base) }
        let nsBase = platformColor(base)
        let top = nsBase.blended(with: PlatformColor.studioWhite(1), amount: 0.12)
        let bottom = nsBase.blended(with: PlatformColor.studioWhite(0), amount: 0.05)
        return (Color(platform: top), Color(platform: bottom))
    }
}

