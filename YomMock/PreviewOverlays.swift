//
//  PreviewOverlays.swift
//  YomMock
//

import SwiftUI

/// Configurable studio backdrop behind the 3D scene. Defaults to white,
/// independent of the device appearance theme.
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
/// on every frame — ContentView must not read `currentTime` in its body.
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

struct ExportSuccessToast: View {
    @Bindable var store: YomMockStore

    var body: some View {
        let fileName = store.lastExportedFrameURL?.lastPathComponent ?? "Frame.png"
        let folderName = store.lastExportedFrameURL?.deletingLastPathComponent().lastPathComponent ?? ""
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 32, height: 32)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Frame exported")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(fileName)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !folderName.isEmpty {
                    Text(folderName)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button {
                    store.showExportedFrameInFinder()
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.accentColor)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.dismissExportSuccess()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 420)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
    }
}

struct VideoExportProgressHUD: View {
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

struct VideoExportSuccessToast: View {
    @Bindable var store: YomMockStore
    var body: some View {
        let fileName = store.lastExportedVideoURL?.lastPathComponent ?? "Video"
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.08)).frame(width: 32, height: 32)
                Image(systemName: "film.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Video exported")
                    .font(.system(size: 13, weight: .semibold))
                Text(fileName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                store.showExportedVideoInFinder()
            } label: {
                Label("Show in Finder", systemImage: "folder")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.accentColor)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { store.dismissVideoSuccess() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 420)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
    }
}
