//
//  PreviewOverlays.swift
//  YomMock
//
//  macOS-only export toasts. StudioBackdrop and TimelinePlaybackDriver live
//  in YomMockCore so both platforms share them.
//

import SwiftUI

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
