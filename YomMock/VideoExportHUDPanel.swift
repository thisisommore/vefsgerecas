//
//  VideoExportHUDPanel.swift
//  YomMock
//
//  Detached HUD for video export — shown in its own NSPanel so
//  SCContentFilter(desktopIndependentWindow: mainWindow) captures
//  only the preview without dim/HUD. WindowServer composites the
//  panel above the main window on-screen, but the ScreenCaptureKit
//  capture of the main window excludes it.
//

import AppKit
import SwiftUI

/// The HUD content shown in the detached panel.
/// Mirrors ContentView.VideoExportProgressHUD but is shared so the
/// panel and any future callers use identical visuals.
struct DetachedVideoExportHUDView: View {
    var progress: Double
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .scaleEffect(0.8)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Exporting video…")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 360)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
    }
}

@MainActor
final class VideoExportHUDPanelController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<DetachedVideoExportHUDView>?
    private weak var parentWindow: NSWindow?
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?

    func show(parentWindow: NSWindow, progress: Double, onCancel: @escaping () -> Void) {
        self.parentWindow = parentWindow

        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 72),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            p.level = .floating
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = false
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isMovable = false
            p.becomesKeyOnlyIfNeeded = true
            p.animationBehavior = .none
            // Ensure panel does not appear in Dock / window cycle
            p.isExcludedFromWindowsMenu = true
            self.panel = p
        }

        let view = DetachedVideoExportHUDView(progress: progress, onCancel: onCancel)
        if let hv = hostingView {
            hv.rootView = view
        } else {
            let hv = NSHostingView(rootView: view)
            // Let SwiftUI size the view; panel will be resized to fit
            self.hostingView = hv
            panel?.contentView = hv
        }

        // Size panel to HUD intrinsic size
        if let hv = hostingView {
            // Use fittingSize to get SwiftUI ideal size
            let fitting = hv.fittingSize
            let w = max(360, min(400, fitting.width > 0 ? fitting.width : 360))
            let h = max(58, fitting.height > 0 ? fitting.height : 58)
            panel?.setContentSize(NSSize(width: w, height: h))
        }

        reposition()
        if let panel, !panel.isVisible {
            panel.orderFrontRegardless()
        }

        installObservers(for: parentWindow)
    }

    func update(progress: Double, onCancel: @escaping () -> Void) {
        guard let hv = hostingView else { return }
        hv.rootView = DetachedVideoExportHUDView(progress: progress, onCancel: onCancel)
        // Keep centered if parent moved; also ensure panel stays visible
        if let panel, !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        removeObservers()
        panel?.orderOut(nil)
        // Don't destroy panel — reuse for next export
        parentWindow = nil
    }

    private func reposition() {
        guard let panel, let parent = parentWindow else { return }
        let parentFrame = parent.frame
        let panelSize = panel.frame.size
        // Center over parent window
        let x = parentFrame.origin.x + (parentFrame.width - panelSize.width) / 2
        let y = parentFrame.origin.y + (parentFrame.height - panelSize.height) / 2
        // Clamp to screen visible frame so HUD never off-screen
        let visible = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? parentFrame
        var origin = NSPoint(x: x, y: y)
        origin.x = max(visible.minX, min(origin.x, visible.maxX - panelSize.width))
        origin.y = max(visible.minY, min(origin.y, visible.maxY - panelSize.height))
        panel.setFrameOrigin(origin)
    }

    private func installObservers(for parent: NSWindow) {
        removeObservers()
        let center = NotificationCenter.default
        moveObserver = center.addObserver(forName: NSWindow.didMoveNotification, object: parent, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
        resizeObserver = center.addObserver(forName: NSWindow.didResizeNotification, object: parent, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
        closeObserver = center.addObserver(forName: NSWindow.willCloseNotification, object: parent, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        if let o = moveObserver { center.removeObserver(o); moveObserver = nil }
        if let o = resizeObserver { center.removeObserver(o); resizeObserver = nil }
        if let o = closeObserver { center.removeObserver(o); closeObserver = nil }
    }

    deinit {
        // MainActor isolation — deinit not isolated, so best-effort
        // Actual removal happens in hide() on MainActor.
    }
}
