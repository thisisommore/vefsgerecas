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

    /// Studio backdrop: a bright cyclorama in light mode and a deep gray
    /// studio in dark mode, so the phone is never on a flat black void.
    static let studioTop = Color.dynamic(
        light: Color(red: 0.957, green: 0.957, blue: 0.965),
        dark: Color(red: 0.216, green: 0.227, blue: 0.255)
    )
    static let studioBottom = Color.dynamic(
        light: Color(red: 0.886, green: 0.894, blue: 0.914),
        dark: Color(red: 0.114, green: 0.122, blue: 0.137)
    )
    static let studioGlow = Color.dynamic(
        light: .white.opacity(0.5),
        dark: .white.opacity(0.05)
    )

    /// Playhead knob fill that stays visible on the track in both modes.
    static let timelineKnob = Color.dynamic(
        light: Color(red: 0.953, green: 0.953, blue: 0.957),
        dark: Color(red: 0.145, green: 0.153, blue: 0.169)
    )
}

private struct CardShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.shadow(
            color: .black.opacity(colorScheme == .dark ? 0.5 : 0.15),
            radius: 16,
            y: 6
        )
    }
}

extension View {
    /// Soft card shadow that stays visible on dark backgrounds too.
    func cardShadow() -> some View {
        modifier(CardShadow())
    }
}
