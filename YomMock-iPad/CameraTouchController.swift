//
//  CameraTouchController.swift
//  YomMock-iPad
//
//  Native UIGestureRecognizer layer over the RealityView so the viewport
//  gets true direct-manipulation feel:
//    • one-finger drag  → orbit the turntable
//    • two-finger drag  → pan the device
//    • pinch            → dolly zoom (1:1 with fingers)
//    • double tap       → reset pan
//  All recognizers run simultaneously, matching pro camera apps.
//

import SwiftUI
import UIKit

struct CameraTouchController: UIViewRepresentable {
    var gesturesEnabled: Bool
    var onOrbit: (SIMD2<Float>) -> Void
    var onPan: (SIMD2<Float>) -> Void
    var onPinchZoom: (Float) -> Void
    var onDoubleTap: () -> Void
    /// Reports the viewport point size + display scale for pixel-exact exports.
    var onViewportChange: (CGSize, CGFloat) -> Void = { _, _ in }

    func makeUIView(context: Context) -> GestureView {
        let view = GestureView()
        view.backgroundColor = .clear

        let orbit = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleOrbit(_:)))
        orbit.minimumNumberOfTouches = 1
        orbit.maximumNumberOfTouches = 1
        orbit.delegate = context.coordinator

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = context.coordinator

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator

        view.addGestureRecognizer(orbit)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(doubleTap)
        return view
    }

    func updateUIView(_ view: GestureView, context: Context) {
        context.coordinator.parent = self
        view.onLayout = { [coordinator = context.coordinator] size, scale in
            coordinator.parent.onViewportChange(size, scale)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CameraTouchController
        private var lastOrbit: CGPoint = .zero
        private var lastPan: CGPoint = .zero
        private var lastScale: CGFloat = 1

        init(parent: CameraTouchController) { self.parent = parent }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        @objc func handleOrbit(_ g: UIPanGestureRecognizer) {
            guard parent.gesturesEnabled else { return }
            switch g.state {
            case .began:
                lastOrbit = g.translation(in: g.view)
            case .changed:
                let t = g.translation(in: g.view)
                // AppKit drag events report deltas with inverted sign relative
                // to UIPan; negate so sensitivity matches the Mac app.
                let dx = Float(-(t.x - lastOrbit.x))
                let dy = Float(-(t.y - lastOrbit.y))
                lastOrbit = t
                if dx != 0 || dy != 0 { parent.onOrbit(SIMD2(dx, dy)) }
            default:
                break
            }
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard parent.gesturesEnabled else { return }
            switch g.state {
            case .began:
                lastPan = g.translation(in: g.view)
            case .changed:
                let t = g.translation(in: g.view)
                let dx = Float(-(t.x - lastPan.x))
                let dy = Float(-(t.y - lastPan.y))
                lastPan = t
                if dx != 0 || dy != 0 { parent.onPan(SIMD2(dx, dy)) }
            default:
                break
            }
        }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard parent.gesturesEnabled else { return }
            switch g.state {
            case .began:
                lastScale = 1
            case .changed:
                let factor = Float(g.scale / lastScale)
                lastScale = g.scale
                if factor > 0 { parent.onPinchZoom(factor) }
            default:
                break
            }
        }

        @objc func handleDoubleTap(_ g: UITapGestureRecognizer) {
            guard parent.gesturesEnabled, g.state == .ended else { return }
            parent.onDoubleTap()
        }
    }

    /// Clear hit-testing surface over the preview. Touches pass through to
    /// nothing beneath — it owns all viewport gestures.
    final class GestureView: UIView {
        var onLayout: ((CGSize, CGFloat) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layoutSubviews() {
            super.layoutSubviews()
            let scale = max(traitCollection.displayScale, 1)
            onLayout?(bounds.size, scale)
        }
    }
}
