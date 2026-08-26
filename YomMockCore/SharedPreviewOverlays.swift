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
    /// Soft radial highlight in the middle of the backdrop (user-toggleable).
    var glow: Bool = true

    var body: some View {
        let colors = background.gradient(custom: customColor, glow: glow)
        return ZStack {
            LinearGradient(
                colors: [colors.top, colors.bottom],
                startPoint: .top,
                endPoint: .bottom
            )
            if glow {
                RadialGradient(
                    colors: [colors.top.opacity(0.4), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 560
                )
            }
        }
        .ignoresSafeArea()
    }
}

/// Drives playhead ticks and pose apply without invalidating the RealityView
/// on every frame — editor views must not read `currentTime` in their body.
struct TimelinePlaybackDriver: View {
    @Bindable var timeline: CameraTimeline
    var apply: () -> Void
    /// Timeline play/pause transitions — used to start/pause the display
    /// screen recording in lockstep with the camera animation.
    var onPlayStateChanged: (Bool) -> Void = { _ in }
    /// Playhead moved while paused (scrub/seek) — parks the recording on
    /// the matching frame.
    var onScrubbed: () -> Void = {}

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: timeline.currentTime) { _, _ in
                if !timeline.isPlaying {
                    apply()
                    onScrubbed()
                }
            }
            .onChange(of: timeline.isPlaying) { _, playing in
                onPlayStateChanged(playing)
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
