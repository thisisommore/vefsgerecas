//
//  HelpCatalog.swift
//  YomMockCore
//
//  Data for the onboarding/help overlay: every gesture, shortcut and
//  timeline interaction, split per platform. Presentation lives in
//  HelpOverlayView; platform apps pick their catalog.
//

import Foundation

struct HelpItem: Identifiable, Sendable {
    /// The input: a gesture name or key combo (rendered as a key cap).
    let input: String
    /// What the input does.
    let detail: String
    /// Optional SF Symbol hint shown next to the row.
    var icon: String? = nil

    var id: String { input + detail }
}

struct HelpSection: Identifiable, Sendable {
    let title: String
    let systemImage: String
    let items: [HelpItem]

    var id: String { title }
}

enum HelpCatalog {
    /// macOS: mouse/trackpad + WASD camera controls, timeline, shortcuts.
    static let mac: [HelpSection] = [
        HelpSection(title: "Camera", systemImage: "rotate.3d", items: [
            HelpItem(input: "Drag", detail: "Orbit around the device", icon: "arrow.trianglehead.2.clockwise.rotate.90"),
            HelpItem(input: "⇧ Drag", detail: "Pan the device within the frame"),
            HelpItem(input: "Scroll", detail: "Dolly zoom in and out"),
            HelpItem(input: "W / S", detail: "Zoom in / zoom out"),
            HelpItem(input: "A / D", detail: "Rotate left / rotate right"),
        ]),
        HelpSection(title: "Timeline", systemImage: "film", items: [
            HelpItem(input: "Drag playhead", detail: "Scrub the camera animation"),
            HelpItem(input: "Save Checkpoint", detail: "Store the current camera at the playhead", icon: "plus.square"),
            HelpItem(input: "Click a diamond", detail: "Jump to that checkpoint"),
            HelpItem(input: "Drag a diamond", detail: "Retime the checkpoint"),
            HelpItem(input: "Trash", detail: "Delete the selected checkpoint", icon: "trash"),
        ]),
        HelpSection(title: "Documents", systemImage: "doc", items: [
            HelpItem(input: "⌘N", detail: "New project"),
            HelpItem(input: "⌘S", detail: "Save project"),
            HelpItem(input: "⇧⌘S", detail: "Save project as…"),
            HelpItem(input: "⌘O", detail: "Open project…"),
        ]),
        HelpSection(title: "Export", systemImage: "square.and.arrow.up", items: [
            HelpItem(input: "⇧⌘E", detail: "Export current frame (PNG / WebP)"),
            HelpItem(input: "⇧⌘⌥E", detail: "Export video"),
            HelpItem(input: "Pro", detail: "Exporting requires YomMock Pro", icon: "crown"),
        ]),
    ]

    /// iPadOS: direct-manipulation touch gestures, timeline, chrome.
    static let iPad: [HelpSection] = [
        HelpSection(title: "Stage Gestures", systemImage: "hand.draw", items: [
            HelpItem(input: "1-finger drag", detail: "Orbit around the device", icon: "arrow.trianglehead.2.clockwise.rotate.90"),
            HelpItem(input: "2-finger drag", detail: "Pan the device within the frame"),
            HelpItem(input: "Pinch", detail: "Dolly zoom in and out"),
            HelpItem(input: "Double-tap", detail: "Reset pan to center"),
        ]),
        HelpSection(title: "Timeline", systemImage: "film", items: [
            HelpItem(input: "Drag playhead", detail: "Scrub the camera animation"),
            HelpItem(input: "Save Checkpoint", detail: "Store the current camera at the playhead", icon: "plus.square"),
            HelpItem(input: "Tap a diamond", detail: "Jump to that checkpoint"),
            HelpItem(input: "Drag a diamond", detail: "Retime the checkpoint"),
            HelpItem(input: "Trash", detail: "Delete the selected checkpoint", icon: "trash"),
        ]),
        HelpSection(title: "Documents", systemImage: "doc", items: [
            HelpItem(input: "Document menu", detail: "New, Open, Save, Rename and Share projects"),
        ]),
        HelpSection(title: "Export", systemImage: "square.and.arrow.up", items: [
            HelpItem(input: "Share Frame…", detail: "Export a still as PNG or WebP"),
            HelpItem(input: "Export Video…", detail: "Render the timeline to a movie"),
            HelpItem(input: "Pro", detail: "Exporting requires YomMock Pro", icon: "crown"),
        ]),
    ]
}
