//
//  PreviewOverlays.swift
//  YomMockCore
//
//  Shared preview helpers: studio backdrop and the playback driver that
//  advances the timeline without invalidating the RealityView each frame.
//

import SwiftUI

/// Configurable studio backdrop behind the 3D scene. Colors are literal and
/// theme-independent, so `.white` stays white in any device appearance.
struct StudioBackdrop: View {
    var background: StudioBackground
    var customColor: Color

    var body: some View {
        let colors = background.gradient(custom: customColor)
        return ZStack {
            LinearGradient(
                colors: [colors.top, colors.bottom],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [colors.top.opacity(0.4), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 560
            )
        }
        .ignoresSafeArea()
    }
}

/// Drives playhead ticks and pose apply without invalidating the RealityView
/// on every frame — editor views must not read `currentTime` in their body.
struct TimelinePlaybackDriver: View {
    @Bindable var timeline: CameraTimeline
    var apply: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: timeline.currentTime) { _, _ in
                if !timeline.isPlaying {
                    apply()
                }
            }
            .onChange(of: timeline.isPlaying) { _, playing in
                if playing {
                    apply()
                }
            }
            .onAppear {
                apply()
            }
            .task(id: timeline.isPlaying) {
                guard timeline.isPlaying else { return }
                var last = CACurrentMediaTime()
                while !Task.isCancelled, timeline.isPlaying {
                    let now = CACurrentMediaTime()
                    timeline.advance(by: now - last)
                    last = now
                    apply()
                    try? await Task.sleep(for: .milliseconds(8))
                }
            }
    }
}
