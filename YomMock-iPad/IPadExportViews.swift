//
//  IPadExportViews.swift
//  YomMock-iPad
//
//  Export UI for iPadOS: video options sheet, progress HUD, success toasts
//  with Share actions, and the UIActivityViewController bridge.
//

import SwiftUI

// MARK: - Share sheet bridge

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Video export options (touch)

struct IPadVideoExportOptionsView: View {
    @Bindable var store: YomMockStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Resolution") {
                    resolutionPicker
                }
                Section("Format") {
                    formatPicker
                }
                Section("Frame Rate") {
                    fpsPicker
                }
                Section {
                    outputSummary
                } footer: {
                    Text(
                        "Rendered offscreen on the GPU — resolutions above your screen are true renders, not upscaled captures. You can keep editing while it exports."
                    )
                }

                if h264TooLarge {
                    Label("H.264 supports up to 4K — choose HEVC or ProRes for 8K.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
            }
            .navigationTitle("Export Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.showVideoOptions = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        store.startVideoExportToTempFile()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var resolutionSelection: Binding<IPadVideoResolution> {
        Binding(
            get: {
                switch store.pendingVideoOptions.resolution {
                case .matchPreview: .matchPreview
                case .p720: .p720
                case .p1080: .p1080
                case .p1440: .p1440
                case .p2160: .p2160
                case .p4320: .p4320
                }
            },
            set: { store.pendingVideoOptions.resolution = $0.preset }
        )
    }

    /// Compact horizontal pickers sized for touch.
    private var resolutionPicker: some View {
        Picker("Resolution", selection: resolutionSelection) {
            ForEach(videoResolutions) { preset in
                Text(preset.label).tag(preset)
            }
        }
        .pickerStyle(.menu)
    }

    private var formatPicker: some View {
        Picker("Format", selection: $store.pendingVideoOptions.format) {
            ForEach(VideoExportFormat.allCases) { format in
                Text(format.rawValue).tag(format)
            }
        }
        .pickerStyle(.menu)
    }

    private var fpsPicker: some View {
        Picker("Frame Rate", selection: $store.pendingVideoOptions.fps) {
            Text("24 fps").tag(24)
            Text("30 fps").tag(30)
            Text("60 fps").tag(60)
        }
        .pickerStyle(.segmented)
    }

    private var outputSummary: some View {
        let out = store.pendingVideoOptions.outputSize(
            previewPoints: store.previewPointSizeProvider?() ?? CGSize(width: 1280, height: 800),
            backingScale: store.previewBackingScale()
        )
        return HStack(spacing: 8) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .foregroundStyle(.secondary)
            Text("\(Int(out.width)) × \(Int(out.height))")
                .monospacedDigit()
            Text("· \(store.timeline.totalFrames) frames · \(String(format: "%.1fs", store.timeline.duration))")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 14))
    }

    private var h264TooLarge: Bool {
        guard store.pendingVideoOptions.format == .mp4_h264 else { return false }
        let out = store.pendingVideoOptions.outputSize(
            previewPoints: store.previewPointSizeProvider?() ?? CGSize(width: 1280, height: 800),
            backingScale: store.previewBackingScale()
        )
        return out.width > 4096 || out.height > 4096
    }
}

/// Local mirror of the macOS-only `p4320` raw label handling so the menu
/// stays compact on iPad.
private enum IPadVideoResolution: String, CaseIterable, Identifiable {
    case matchPreview, p720, p1080, p1440, p2160, p4320

    var id: String { rawValue }

    var label: String {
        switch self {
        case .matchPreview: "Match Preview"
        case .p720: "720p"
        case .p1080: "1080p"
        case .p1440: "1440p"
        case .p2160: "4K"
        case .p4320: "8K"
        }
    }

    var preset: VideoResolutionPreset {
        switch self {
        case .matchPreview: .matchPreview
        case .p720: .p720
        case .p1080: .p1080
        case .p1440: .p1440
        case .p2160: .p2160
        case .p4320: .p4320
        }
    }
}

private let videoResolutions = IPadVideoResolution.allCases

// MARK: - Overlays (presented by IPadRootView consumers / store state)

struct IPadVideoProgressHUD: View {
    @Bindable var store: YomMockStore

    var body: some View {
        HStack(spacing: 14) {
            ProgressView(value: store.videoExportProgress)
                .progressViewStyle(.linear)
                .frame(width: 130)
            VStack(alignment: .leading, spacing: 2) {
                Text("Exporting video…")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(Int(store.videoExportProgress * 100))%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") {
                store.cancelVideoExport()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 380)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
    }
}

struct IPadVideoSuccessToast: View {
    @Bindable var store: YomMockStore
    @State private var sharePayload: SharePayload?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "film.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Video exported")
                    .font(.system(size: 15, weight: .semibold))
                Text(store.lastExportedVideoURL?.lastPathComponent ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button {
                if let url = store.lastExportedVideoURL {
                    sharePayload = SharePayload(items: [url])
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            Button {
                store.dismissVideoSuccess()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 420)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
        .sheet(item: $sharePayload) { payload in
            ActivityView(items: payload.items)
                .ignoresSafeArea()
        }
    }
}
