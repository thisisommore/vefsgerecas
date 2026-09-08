//
//  YomMockApp.swift
//  YomMock
//
//  Menu-bar–only project save/restore (like viewio).
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

private struct YomMockStoreFocusedKey: FocusedValueKey {
    typealias Value = YomMockStore
}

private struct ToggleGesturesGuideFocusedKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var yomMockStore: YomMockStore? {
        get { self[YomMockStoreFocusedKey.self] }
        set { self[YomMockStoreFocusedKey.self] = newValue }
    }

    var toggleGesturesGuide: (() -> Void)? {
        get { self[ToggleGesturesGuideFocusedKey.self] }
        set { self[ToggleGesturesGuideFocusedKey.self] = newValue }
    }
}

final class YomMockAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Find the active window's guard via the shared registry.
        // For single-window we delegate to the focused store's guard if any.
        // YomMockRegistry handles multi-window.
        return MainActor.assumeIsolated {
            YomMockRegistry.shared.handleApplicationShouldTerminate()
        }
    }
}

// Simple registry so AppDelegate can find dirty windows (mirrors ViewioSessionRegistry).
@MainActor
final class YomMockRegistry {
    static let shared = YomMockRegistry()
    private final class Entry {
        weak var store: YomMockStore?
        weak var guardObj: UnsavedChangesGuard?
    }
    private var entries: [ObjectIdentifier: Entry] = [:]

    func register(store: YomMockStore, guardObj: UnsavedChangesGuard) {
        let id = ObjectIdentifier(store)
        let e = Entry()
        e.store = store
        e.guardObj = guardObj
        entries[id] = e
    }

    func unregister(store: YomMockStore) {
        entries.removeValue(forKey: ObjectIdentifier(store))
    }

    func handleApplicationShouldTerminate() -> NSApplication.TerminateReply {
        for e in entries.values {
            if let g = e.guardObj, g.isDirty {
                return g.handleApplicationShouldTerminate()
            }
            // Fallback: check store dirty directly
            if let s = e.store, s.isDirty {
                // If guard not installed yet, still block
                // Create a temporary guard handling via alert will be shown by the window's guard.
                // For now, block quit and let window's guard show alert.
                if let g = e.guardObj {
                    return g.handleApplicationShouldTerminate()
                }
                // No guard: still cancel and let UI handle
                return .terminateCancel
            }
        }
        return .terminateNow
    }
}

private struct YomMockWindowRoot: View {
    @State var store = YomMockStore()
    @StateObject private var unsavedGuard = UnsavedChangesGuard()
    @Environment(\.openWindow) private var openWindow
    @State private var recoveryOffer: RecoveryStore.Pending?

    var body: some View {
        ContentView(store: store)
            .environmentObject(unsavedGuard)
            .focusedSceneValue(\.yomMockStore, store)
            .task {
                checkForRecoverableSession()
            }
            .alert(
                "Recover Unsaved Session?",
                isPresented: Binding(
                    get: { recoveryOffer != nil },
                    set: { if !$0 { recoveryOffer = nil } }
                )
            ) {
                Button("Recover") {
                    if let pending = recoveryOffer {
                        store.restoreRecovery(pending)
                    }
                    recoveryOffer = nil
                }
                Button("Discard", role: .destructive) {
                    if let pending = recoveryOffer {
                        RecoveryStore.remove(id: pending.id)
                    }
                    recoveryOffer = nil
                }
            } message: {
                Text(
                    "YomMock quit unexpectedly with unsaved changes. The last autosave can be restored."
                )
            }
            .onAppear {
                unsavedGuard.onDiscard = { [weak store] in
                    store?.markClean()
                }
                YomMockRegistry.shared.register(store: store, guardObj: unsavedGuard)
                // Sync guard dirty with store
                unsavedGuard.updateDirty(store.isDirty)
            }
            .onChange(of: store.isDirty) { _, dirty in
                unsavedGuard.updateDirty(dirty)
            }
            .onDisappear {
                YomMockRegistry.shared.unregister(store: store)
            }
            // Install window-close guard
            .background(WindowCloseGuardInstaller(guardObject: unsavedGuard))
            .alert("Unsaved Changes", isPresented: $unsavedGuard.showsAlert) {
                Button("Cancel", role: .cancel) { unsavedGuard.cancel() }
                Button("Discard", role: .destructive) { unsavedGuard.discard() }
                Button("Save…") {
                    store.saveProject()
                    // After save, if now clean, retry pending action
                    if !store.isDirty {
                        unsavedGuard.discard() // will perform pending quit/close without extra prompt
                    } else {
                        unsavedGuard.cancel()
                    }
                }
            } message: {
                Text("You have unsaved changes. Save the project before quitting?")
            }
    }

    /// Offers the most recent crash-recovery snapshot once per window.
    private func checkForRecoverableSession() {
        guard recoveryOffer == nil, !store.isDirty else { return }
        recoveryOffer = RecoveryStore.pending()
    }
}

@main
struct YomMockApp: App {
    @NSApplicationDelegateAdaptor(YomMockAppDelegate.self) private var appDelegate
    @FocusedValue(\.yomMockStore) private var focusedStore
    @FocusedValue(\.toggleGesturesGuide) private var toggleGesturesGuide
    @Environment(\.openWindow) private var openWindow
    @State private var subscriptions = SubscriptionManager.shared

    init() {
        SubscriptionManager.configure()
        SubscriptionManager.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            YomMockWindowRoot()
        }
        .defaultSize(width: 960, height: 720)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    focusedStore?.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!(focusedStore?.canUndo ?? false))

                Button("Redo") {
                    focusedStore?.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(focusedStore?.canRedo ?? false))
            }

            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    focusedStore?.newProject()
                }
                .keyboardShortcut("n")
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save Project") {
                    focusedStore?.saveProject()
                }
                .keyboardShortcut("s")
                .disabled(focusedStore == nil)

                Button("Save Project As…") {
                    focusedStore?.saveProjectAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(focusedStore == nil)

                Divider()

                Button("Open Project…") {
                    focusedStore?.openProjectWithPrompt()
                }
                .keyboardShortcut("o")
                .disabled(focusedStore == nil)

                Divider()

                Button {
                    focusedStore?.exportFrame()
                } label: {
                    if subscriptions.isPro {
                        Text("Export Current Frame…")
                    } else {
                        Label("Get Pro to Export Frame…", systemImage: "crown")
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(focusedStore == nil)

                Button {
                    focusedStore?.exportVideo()
                } label: {
                    if subscriptions.isPro {
                        Text("Export Video…")
                    } else {
                        Label("Get Pro to Export Video…", systemImage: "crown")
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift, .option])
                .disabled(focusedStore == nil)
            }

            CommandGroup(after: .appSettings) {
                Button("YomMock Pro…") {
                    openWindow(id: "yommock-pro")
                }
            }

            CommandGroup(after: .help) {
                Button("Gestures & Shortcuts") {
                    toggleGesturesGuide?()
                }
                .keyboardShortcut("/")
                .disabled(toggleGesturesGuide == nil)
            }
        }

        Window("YomMock Pro", id: "yommock-pro") {
            SubscriptionSettingsView()
                .frame(minWidth: 460, minHeight: 420)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 440)

        Settings {
            SubscriptionSettingsView()
        }
    }
}
