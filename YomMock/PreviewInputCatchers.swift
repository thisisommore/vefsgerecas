//
//  PreviewInputCatchers.swift
//  YomMock
//

import AppKit
import SwiftUI

/// Observes scroll-wheel / trackpad scroll without intercepting orbit drags.
struct ScrollZoomCatcher: NSViewRepresentable {
    var onScroll: (NSEvent) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onScroll = onScroll
    }

    final class MonitorView: NSView {
        var onScroll: ((NSEvent) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installMonitor()
        }

        deinit {
            removeMonitor()
        }

        private func installMonitor() {
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                [weak self] event in
                guard let self, event.window === self.window else { return event }
                let location = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(location) else { return event }
                self.onScroll?(event)
                return nil
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

/// Shift + drag pans and drag without shift orbits.
/// Owns all orbit + pan so PhoneScene is single source of truth.
struct CameraPanCatcher: NSViewRepresentable {
    var onPan: (SIMD2<Float>) -> Void
    var onOrbit: (SIMD2<Float>) -> Void

    func makeNSView(context: Context) -> PanMonitorView {
        let view = PanMonitorView()
        view.onPan = onPan
        view.onOrbit = onOrbit
        return view
    }

    func updateNSView(_ view: PanMonitorView, context: Context) {
        view.onPan = onPan
        view.onOrbit = onOrbit
    }

    final class PanMonitorView: NSView {
        var onPan: ((SIMD2<Float>) -> Void)?
        var onOrbit: ((SIMD2<Float>) -> Void)?
        private var flagsMonitor: Any?
        private var dragMonitor: Any?
        private var isShiftHeld = false
        private var isDraggingInside = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installMonitors()
        }

        deinit {
            removeMonitors()
        }

        private func installMonitors() {
            removeMonitors()
            guard window != nil else { return }
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self else { return event }
                self.isShiftHeld = event.modifierFlags.contains(.shift)
                return event
            }
            dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let location = self.convert(event.locationInWindow, from: nil)
                switch event.type {
                case .leftMouseDown:
                    isDraggingInside = bounds.contains(location)
                    return event
                case .leftMouseUp:
                    isDraggingInside = false
                    return event
                case .leftMouseDragged:
                    let shift = event.modifierFlags.contains(.shift)
                    isShiftHeld = shift
                    let dx = Float(event.deltaX)
                    let dy = Float(event.deltaY)
                    if (isDraggingInside || bounds.contains(location)) && shift {
                        onPan?(SIMD2<Float>(dx, dy))
                        return nil
                    } else if isDraggingInside || bounds.contains(location) {
                        onOrbit?(SIMD2<Float>(dx, dy))
                        return nil
                    }
                    return event
                default:
                    return event
                }
            }
        }

        private func removeMonitors() {
            if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
            if let m = dragMonitor { NSEvent.removeMonitor(m); dragMonitor = nil }
        }
    }
}

/// W/S dolly zoom + A/D yaw orbit — keyboard camera controls.
struct WASDZoomCatcher: NSViewRepresentable {
    var onZoomIn: () -> Void
    var onZoomOut: () -> Void
    var onRotateLeft: () -> Void
    var onRotateRight: () -> Void

    func makeNSView(context: Context) -> KeyMonitorView {
        let view = KeyMonitorView()
        view.onZoomIn = onZoomIn
        view.onZoomOut = onZoomOut
        view.onRotateLeft = onRotateLeft
        view.onRotateRight = onRotateRight
        return view
    }

    func updateNSView(_ view: KeyMonitorView, context: Context) {
        view.onZoomIn = onZoomIn
        view.onZoomOut = onZoomOut
        view.onRotateLeft = onRotateLeft
        view.onRotateRight = onRotateRight
    }

    final class KeyMonitorView: NSView {
        var onZoomIn: (() -> Void)?
        var onZoomOut: (() -> Void)?
        var onRotateLeft: (() -> Void)?
        var onRotateRight: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installMonitor()
        }

        deinit { removeMonitor() }

        private func installMonitor() {
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                // Don't steal typing in text fields
                if let fr = window.firstResponder as? NSText, fr is NSTextView { return event }
                guard let chars = event.charactersIgnoringModifiers?.lowercased() else { return event }
                switch chars {
                case "w": self.onZoomIn?(); return nil
                case "s": self.onZoomOut?(); return nil
                case "a": self.onRotateLeft?(); return nil
                case "d": self.onRotateRight?(); return nil
                default: return event
                }
            }
        }

        private func removeMonitor() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        }
    }
}

/// Holds a weak reference to the preview's NSView so "Export Current Frame"
/// can locate the region to capture without keeping the view alive.
final class PreviewViewBox {
    weak var view: NSView?
}

/// Invisible anchor that fills the preview area and reports its NSView,
/// giving FrameCapture an exact on-screen rect for the 3D frame.
struct FrameCaptureAnchor: NSViewRepresentable {
    var resolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { resolve(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { resolve(nsView) }
    }
}
