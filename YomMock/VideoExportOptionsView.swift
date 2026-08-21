//
//  VideoExportOptionsView.swift
//  YomMock
//
//  Sheet for Export Video — choose resolution + format + fps
//

import SwiftUI
import AppKit

struct VideoExportOptionsView: View {
    @Bindable var store: YomMockStore
    @State private var previewPoints: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Video")
                .font(.system(size: 15, weight: .semibold))
            Text("Rendered offscreen on the GPU — resolutions above your screen size are true renders, not upscaled captures. You can keep using the app while it exports.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Resolution")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Picker("", selection: $store.pendingVideoOptions.resolution) {
                        ForEach(VideoResolutionPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                GridRow {
                    Text("Format")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $store.pendingVideoOptions.format) {
                        ForEach(VideoExportFormat.allCases) { fmt in
                            Text(fmt.rawValue).tag(fmt)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                GridRow {
                    Text("Frame Rate")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $store.pendingVideoOptions.fps) {
                        Text("24 fps").tag(24)
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            // Live preview of output size
            if previewPoints.width > 0 {
                let out = store.pendingVideoOptions.outputSize(
                    previewPoints: previewPoints,
                    backingScale: 1
                )
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("\(Int(out.width))×\(Int(out.height)) output")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("· \(store.timeline.totalFrames) frames · \(String(format: "%.1fs", store.timeline.duration))")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 2)
            }

            // Warn when the codec can't handle the chosen resolution
            if previewPoints.width > 0 {
                let out = store.pendingVideoOptions.outputSize(
                    previewPoints: previewPoints,
                    backingScale: 1
                )
                if store.pendingVideoOptions.format == .mp4_h264,
                   out.width > 4096 || out.height > 4096 {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.yellow)
                        Text("H.264 supports up to 4K — choose HEVC or ProRes for 8K.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Shows extension that will be used (chosen format first, so no mismatch)
            HStack(spacing: 6) {
                Image(systemName: "doc.badge.ellipsis")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("Will save as .\(store.pendingVideoOptions.fileExtension) (\(store.pendingVideoOptions.format.rawValue))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Cancel") {
                    store.showVideoOptions = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Next…") {
                    store.startVideoExport()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .help("Choose file location next")
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            if let size = store.previewPointSizeProvider?() {
                previewPoints = size
            }
        }
    }
}
