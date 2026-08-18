//
//  VideoExportOptionsView.swift
//  YomMock
//
//  Sheet for Export Video — choose res downscale + format + fps
//

import SwiftUI
import AppKit

struct VideoExportOptionsView: View {
    @Bindable var store: YomMockStore
    @State private var nativeSize: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Video")
                .font(.system(size: 15, weight: .semibold))
            Text("Render the timeline to video. Preview will play through once.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

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
            if nativeSize.width > 0 {
                let out = store.pendingVideoOptions.outputSize(for: nativeSize)
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("\(Int(nativeSize.width))×\(Int(nativeSize.height)) → \(Int(out.width))×\(Int(out.height))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("· \(store.timeline.totalFrames) frames · \(String(format: "%.1fs", store.timeline.duration))")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 2)
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
            if let view = store.frameCaptureViewProvider?(), let window = view.window,
               let native = FrameCapture.nativePixelSize(for: view, window: window) {
                nativeSize = native
            }
        }
    }
}
