//
//  InspectorPanel.swift
//  YomMock
//
//  Right-hand panel — phone finish options.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct InspectorPanel: View {
    @Bindable var store: YomMockStore
    @Binding var displayStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().opacity(0)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DeviceInspectorPanel(device: $store.device)

                    if store.device == .macBookPro {
                        Divider()

                        LidInspectorPanel(lidAngle: $store.lidAngle)
                    }

                    Divider()

                    CameraInspectorPanel(camera: $store.camera)

                    Divider()

                    PhoneInspectorPanel(
                        selectedColor: $store.selectedColor,
                        customColor: $store.customColor
                    )

                    Divider()

                    DisplayInspectorPanel(
                        store: store,
                        displayStatus: $displayStatus
                    )

                    Divider()

                    BackdropInspectorPanel(
                        background: $store.background,
                        customBackground: $store.customBackground,
                        backgroundGlow: $store.backgroundGlow
                    )
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .leading) {
            Divider()
        }
    }
}

// MARK: - Device

private struct DeviceInspectorPanel: View {
    @Binding var device: Device

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            inspectorHeader(title: "DEVICE", subtitle: "Model")

            Picker("Model", selection: $device) {
                ForEach(Device.allCases) { device in
                    Text(device.name).tag(device)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

// MARK: - Lid (MacBook)

private struct LidInspectorPanel: View {
    @Binding var lidAngle: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            inspectorHeader(title: "LID", subtitle: "Opening angle")

            HStack(spacing: 8) {
                Slider(
                    value: $lidAngle,
                    in: MacBookLidRig.minOpenAngle...MacBookLidRig.defaultOpenAngle
                )
                .controlSize(.small)
                Text("\(Int(lidAngle.rounded()))°")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }
}

// MARK: - Camera

private struct CameraInspectorPanel: View {
    @Binding var camera: StudioCameraSettings

    private var focalLengthBinding: Binding<Float> {
        Binding(
            get: { camera.focalLength },
            set: { camera.setFocalLength($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            inspectorHeader(title: "CAMERA", subtitle: "Studio lens")

            HStack(spacing: 8) {
                Text("FOCAL")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: 36, alignment: .leading)
                Slider(value: focalLengthBinding, in: StudioCameraSettings.minFocalLength...StudioCameraSettings.maxFocalLength)
                    .controlSize(.small)
                Text("\(Int(camera.focalLength.rounded()))mm")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            .help("Equivalent focal length — \(Int(camera.fieldOfView.rounded()))° field of view")

            HStack(spacing: 8) {
                Text("FOV")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: 36, alignment: .leading)
                Slider(
                    value: $camera.fieldOfView,
                    in: StudioCameraSettings.minFieldOfView...StudioCameraSettings.maxFieldOfView
                )
                .controlSize(.small)
                Text("\(Int(camera.fieldOfView.rounded()))°")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }
}

// MARK: - Phone

private struct PhoneInspectorPanel: View {
    @Binding var selectedColor: iPhoneColor
    @Binding var customColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            inspectorHeader(title: "PHONE", subtitle: "Finish")

            HStack(spacing: 8) {
                ForEach(iPhoneColor.presets) { color in
                    PhoneColorCircle(
                        color: color,
                        isSelected: selectedColor == color
                    ) {
                        selectedColor = color
                    }
                }
            }

            HStack(spacing: 16) {
                ColorPicker("Custom", selection: $customColor, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: customColor) { _, _ in
                        selectedColor = .custom
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(
                        selectedColor == .custom
                            ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        selectedColor == .custom
                            ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.06),
                        lineWidth: 1)
            }
            .onTapGesture { selectedColor = .custom }
        }
    }
}

private struct BackdropInspectorPanel: View {
    @Binding var background: StudioBackground
    @Binding var customBackground: Color
    @Binding var backgroundGlow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            inspectorHeader(title: "BACKDROP", subtitle: "Background")

            HStack(spacing: 8) {
                ForEach(StudioBackground.presets) { color in
                    BackdropCircle(
                        color: color,
                        isSelected: background == color
                    ) {
                        background = color
                    }
                }
            }

            HStack(spacing: 16) {
                ColorPicker("Custom", selection: $customBackground, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: customBackground) { _, _ in
                        background = .custom
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(
                        background == .custom
                            ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        background == .custom
                            ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.06),
                        lineWidth: 1)
            }
            .onTapGesture { background = .custom }

            Toggle(isOn: $backgroundGlow) {
                Text("Background glow")
                    .font(.system(size: 11, weight: .medium))
            }
            .toggleStyle(.checkbox)
            .help("Soft radial highlight in the middle of the backdrop")
        }
    }
}

// MARK: - Display (Screenshot / Screen Recording)

private struct DisplayInspectorPanel: View {
    @Bindable var store: YomMockStore
    @Binding var displayStatus: String?
    @State private var isDropTargeted = false

    private var isVideoActive: Bool { store.displayVideo != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            inspectorHeader(
                title: "DISPLAY",
                subtitle: isVideoActive ? "Screen Recording" : "Screenshot")

            if let image = store.displayImage {
                VStack(alignment: .leading, spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.04))
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(6)
                        if isVideoActive {
                            Label("Recording", systemImage: "play.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(4)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { chooseFile() }
                    .help(isVideoActive ? "Click to change screen recording" : "Click to change screenshot")

                    HStack(spacing: 6) {
                        Image(systemName: isVideoActive ? "video.fill" : "photo")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(store.displayFileName ?? (isVideoActive ? "Screen recording" : "Screenshot"))
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }

                    HStack(spacing: 6) {
                        Button("Remove", role: .destructive, action: removeImage)
                            .buttonStyle(TimelineTextButtonStyle())
                        Spacer()
                    }
                }
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.03))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                }
            } else {
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                isDropTargeted
                                    ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isDropTargeted ? Color.accentColor : Color.primary.opacity(0.12),
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                        VStack(spacing: 4) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(.secondary)
                            Text("Drop screenshot or recording")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("MP4 / MOV screen recordings play live")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 12)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { chooseFile() }
                    .onDrop(
                        of: [.fileURL, .image], isTargeted: $isDropTargeted, perform: handleDrop
                    )
                    .help("Click to choose image or drop file")

                    HStack(spacing: 8) {
                        Button(action: pasteFromClipboard) {
                            Label("Paste", systemImage: "doc.on.clipboard")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(TimelineTextButtonStyle())
                        .disabled(!canPasteImage)

                        Spacer()
                    }
                }
            }

            if let displayStatus {
                Text(displayStatus)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var canPasteImage: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
            || NSPasteboard.general.canReadItem(withDataConformingToTypes: [
                UTType.image.identifier, UTType.fileURL.identifier, UTType.png.identifier,
                UTType.webP.identifier,
            ])
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .png, .jpeg, .heic, .heif, .tiff, .bmp, .gif, .webP,
            .movie, .mpeg4Movie, .quickTimeMovie,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a screenshot or a screen recording for the display"
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            if UTType.isDisplayVideo(url) {
                Task { @MainActor in
                    await store.setDisplayVideo(at: url)
                    if store.projectError != nil {
                        displayStatus = store.projectError
                        store.handleSaveErrorDismiss()
                    } else {
                        displayStatus = nil
                    }
                }
            } else if let image = NSImage(contentsOf: url) {
                store.setStaticDisplay(image, fileName: url.lastPathComponent)
                displayStatus = nil
            } else {
                displayStatus = "Could not load file at \(url.lastPathComponent)."
            }
        }
    }

    private func removeImage() {
        store.setStaticDisplay(nil, fileName: nil)
        displayStatus = nil
    }

    private func pasteFromClipboard() {
        let pb = NSPasteboard.general
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
            let image = images.first
        {
            store.setStaticDisplay(image, fileName: "Pasted image")
            displayStatus = nil
            return
        }
        if let data = pb.data(forType: .tiff) ?? pb.data(forType: .png)
            ?? pb.data(forType: NSPasteboard.PasteboardType(UTType.webP.identifier)),
            let image = PlatformImageLoader.image(data: data)
        {
            store.setStaticDisplay(image, fileName: "Pasted image")
            displayStatus = nil
            return
        }
        displayStatus = "No image found on clipboard."
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
                item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let str = item as? String {
                    url = URL(string: str)
                } else if let u = item as? URL {
                    url = u
                }
                guard let url else { return }
                Task { @MainActor in
                    if UTType.isDisplayVideo(url) {
                        await store.setDisplayVideo(at: url)
                        if store.projectError != nil {
                            displayStatus = store.projectError
                            store.handleSaveErrorDismiss()
                        } else {
                            displayStatus = nil
                        }
                    } else if let image = PlatformImageLoader.image(contentsOf: url) {
                        store.setStaticDisplay(image, fileName: url.lastPathComponent)
                        displayStatus = nil
                    } else {
                        displayStatus = "Could not load dropped file."
                    }
                }
            }
            return true
        }
        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else {
                    Task { @MainActor in displayStatus = "Could not load dropped image." }
                    return
                }
                Task { @MainActor in
                    store.setStaticDisplay(image, fileName: "Dropped image")
                    displayStatus = nil
                }
            }
            return true
        }
        return false
    }
}

private struct TimelineTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(.primary.opacity(configuration.isPressed ? 0.45 : 0.85))
            .background(.primary.opacity(configuration.isPressed ? 0.1 : 0.06), in: Capsule())
    }
}

private struct BackdropCircle: View {
    let color: StudioBackground
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Circle()
                .fill(color.swatch)
                .frame(width: 26, height: 26)
                .overlay { Circle().strokeBorder(.primary.opacity(0.22), lineWidth: 1) }
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(
                                color == .black
                                    ? Color.white.opacity(0.9) : Color.black.opacity(0.6))
                    }
                }
        }
        .buttonStyle(.plain)
        .help(color.name)
    }
}

private struct PhoneColorCircle: View {
    let color: iPhoneColor
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Circle()
                .fill(color.swatch)
                .frame(width: 26, height: 26)
                .overlay { Circle().strokeBorder(.primary.opacity(0.22), lineWidth: 1) }
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(color.name)
    }
}

// MARK: - Shared helpers

private func inspectorHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(.secondary)
        Text(subtitle)
            .font(.system(size: 12, weight: .semibold))
    }
}

private func sectionLabel(_ title: String) -> some View {
    Text(title.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .tracking(0.7)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
}
