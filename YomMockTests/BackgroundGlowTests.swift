//
//  BackgroundGlowTests.swift
//  YomMockTests
//
//  The backdrop's soft radial highlight is user-toggleable; the choice is
//  persisted in the project document, undoable, and defaults to on for
//  projects saved before the setting existed.
//

import Foundation
import SwiftUI
import Testing
@testable import YomMock

@MainActor
struct BackgroundGlowTests {
    @Test func defaultsToOn() {
        let store = YomMockStore()
        #expect(store.backgroundGlow)
        #expect(store.makeDocument().backgroundGlow == true)
    }

    @Test func documentRoundTripPreservesToggle() {
        let store = YomMockStore()
        store.backgroundGlow = false
        let doc = store.makeDocument()
        #expect(doc.backgroundGlow == false)

        store.backgroundGlow = true
        store.applyDocument(doc, displayImage: nil)
        #expect(store.backgroundGlow == false)
    }

    @Test func legacyDocumentWithoutGlowDecodesAsOn() throws {
        let store = YomMockStore()
        var doc = store.makeDocument()
        doc.backgroundGlow = nil // simulates a pre-glow project file
        store.backgroundGlow = false
        store.applyDocument(doc, displayImage: nil)
        #expect(store.backgroundGlow)
    }

    @Test func toggleIsUndoable() {
        let store = YomMockStore()
        store.backgroundGlow = false
        store.markDirty()
        #expect(store.canUndo)

        store.undo()
        #expect(store.backgroundGlow)

        store.redo()
        #expect(!store.backgroundGlow)
    }

    @Test func sceneInputsCarryGlowFlag() {
        let store = YomMockStore()
        #expect(store.makeSceneInputs().backgroundGlow)
        store.backgroundGlow = false
        #expect(!store.makeSceneInputs().backgroundGlow)
    }

    @Test func glowOffGivesFlatExactSwatchColor() {
        // Black with glow off must be pure black, not lifted gray.
        let flat = StudioBackground.black.gradient(custom: .white, glow: false)
        for color in [flat.top, flat.bottom] {
            let rgba = platformColor(color).studioRGBA
            #expect(rgba.red == 0)
            #expect(rgba.green == 0)
            #expect(rgba.blue == 0)
        }

        // Glow on keeps the soft studio lift at the top.
        let lit = StudioBackground.black.gradient(custom: .white, glow: true)
        #expect(platformColor(lit.top).studioRGBA.red > 0.05)
    }
}
