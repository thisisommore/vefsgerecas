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
    @Binding var selectedColor: iPhoneColor
    @Binding var customColor: Color
    @Binding var background: StudioBackground
    @Binding var customBackground: Color
    @Binding var displayImage: NSImage?
    @Binding var displayFileName: String?
    @Binding var displayStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().opacity(0)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PhoneInspectorPanel(
                        selectedColor: $selectedColor,
                        customColor: $customColor
                    )

                    Divider()

                    DisplayInspectorPanel(
                        displayImage: $displayImage,
                        displayFileName: $displayFileName,
                        displayStatus: $displayStatus
                    )

                    Divider()

                    BackdropInspectorPanel(
                        background: $background,
                        customBackground: $customBackground
                    )
                }
                .padding(16)
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

// MARK: - Phone

private struct PhoneInspectorPanel: View {
    @Binding var selectedColor: iPhoneColor
    @Binding var customColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            inspectorHeader(title: "PHONE", subtitle: "Finish & color")

            Text("Choose the phone finish. The frame and glass update live in the preview.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            sectionLabel("Presets")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 72), spacing: 8)],
                spacing: 8
            ) {
                ForEach(iPhoneColor.presets) { color in
                    PhoneColorCard(
                        color: color,
                        isSelected: selectedColor == color
                    ) {
                        selectedColor = color
                    }
                }
            }

            sectionLabel("Custom")
            HStack(spacing: 10) {
                ColorPicker("Custom color", selection: $customColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28, height: 28)
                    .onChange(of: customColor) { _, _ in
                        selectedColor = .custom
                    }
                Text("Pick any color")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedColor == .custom
                          ? Color.accentColor.opacity(0.12)
                          : Color.primary.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selectedColor == .custom
                                  ? Color.accentColor.opacity(0.8)
                                  : Color.primary.opacity(0.06),
                                  lineWidth: 1)
            }
            .onTapGesture {
                selectedColor = .custom
            }
        }
    }
}

private struct BackdropInspectorPanel: View {
    @Binding var background: StudioBackground
    @Binding var customBackground: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            inspectorHeader(title: "BACKDROP", subtitle: "Preview background")

            Text("The color behind the phone in the preview. White is the default and stays white regardless of the device theme.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            sectionLabel("Presets")
            HStack(spacing: 8) {
                ForEach(StudioBackground.presets) { color in
                    BackdropSwatch(
                        color: color,
                        isSelected: background == color
                    ) {
                        background = color
                    }
                }
            }

            sectionLabel("Custom")
            HStack(spacing: 10) {
                ColorPicker("Custom backdrop", selection: $customBackground, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28, height: 28)
                    .onChange(of: customBackground) { _, _ in
                        background = .custom
                    }
                Text("Pick a color")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(background == .custom
                          ? Color.accentColor.opacity(0.12)
                          : Color.primary.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(background == .custom
                                  ? Color.accentColor.opacity(0.8)
                                  : Color.primary.opacity(0.06),
                                  lineWidth: 1)
            }
            .onTapGesture {
                background = .custom
            }
        }
    }
}

// MARK: - Display (Screenshot)

private struct DisplayInspectorPanel: View {
    @Binding var displayImage: NSImage?
    @Binding var displayFileName: String?
    @Binding var displayStatus: String?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            inspectorHeader(title: "DISPLAY", subtitle: "Screenshot")

            Text("Add an image to the phone's screen. It maps to the display and updates live. Drop a file here, on the preview, or choose one.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let image = displayImage {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.04))
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(8)
                    }
                    .frame(maxWidth: .infinity)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(displayFileName ?? "Screenshot")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Button("Choose Different…", action: chooseImage)
                            .buttonStyle(TimelineTextButtonStyle())
                        Button("Remove", role: .destructive, action: removeImage)
                            .buttonStyle(TimelineTextButtonStyle())
                        Spacer()
                    }

                    Button(action: pasteFromClipboard) {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.03))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                }
            } else {
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isDropTargeted ? Color.accentColor : Color.primary.opacity(0.12),
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                        VStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(.secondary)
                            Text("Drop screenshot here")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("PNG, JPEG, HEIC, TIFF")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 16)
                    }
                    .frame(maxWidth: .infinity)
                    .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted, perform: handleDrop)

                    HStack(spacing: 8) {
                        Button {
                            chooseImage()
                        } label: {
                            Label("Choose Image…", systemImage: "photo.badge.plus")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(TimelineTextButtonStyle())

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
            || NSPasteboard.general.canReadItem(withDataConformingToTypes: [UTType.image.identifier, UTType.fileURL.identifier, UTType.png.identifier])
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .png, .jpeg, .heic, .heif, .tiff, .bmp, .gif, .webP
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose an image for the phone display"
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            if let image = NSImage(contentsOf: url) {
                displayFileName = url.lastPathComponent
                displayImage = image
                displayStatus = nil
            } else {
                displayStatus = "Could not load image at \(url.lastPathComponent)."
            }
        }
    }

    private func removeImage() {
        displayImage = nil
        displayFileName = nil
        displayStatus = nil
    }

    private func pasteFromClipboard() {
        let pb = NSPasteboard.general
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first
        {
            displayFileName = "Pasted image"
            displayImage = image
            displayStatus = nil
            return
        }
        if let data = pb.data(forType: .tiff) ?? pb.data(forType: .png),
           let image = NSImage(data: data)
        {
            displayFileName = "Pasted image"
            displayImage = image
            displayStatus = nil
            return
        }
        displayStatus = "No image found on clipboard."
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let str = item as? String {
                    url = URL(string: str)
                } else if let u = item as? URL {
                    url = u
                }
                guard let url, let image = NSImage(contentsOf: url) else {
                    Task { @MainActor in displayStatus = "Could not load dropped file." }
                    return
                }
                Task { @MainActor in
                    displayFileName = url.lastPathComponent
                    displayImage = image
                    displayStatus = nil
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
                    displayFileName = "Dropped image"
                    displayImage = image
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

private struct BackdropSwatch: View {
    let color: StudioBackground
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.swatch)
                    .frame(height: 40)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.primary.opacity(0.2), lineWidth: 1)
                    }
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(checkmarkColor)
                        }
                    }

                Text(color.name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                                  lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .help(color.name)
    }

    private var checkmarkColor: Color {
        switch color {
        case .white: .black.opacity(0.6)
        case .black: .white.opacity(0.9)
        default: .black.opacity(0.6)
        }
    }
}

private struct PhoneColorCard: View {
    let color: iPhoneColor
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(nsColor: .controlBackgroundColor),
                                    Color.primary.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Circle()
                        .fill(color.swatch)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Circle()
                                .strokeBorder(.primary.opacity(0.25), lineWidth: 1)
                        }
                }
                .frame(height: 52)

                Text(color.name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                                  lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .help(color.name)
    }
}

// MARK: - Shared helpers

private func inspectorHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.75)
            .foregroundStyle(.secondary)
        Text(subtitle)
            .font(.system(size: 14, weight: .semibold))
    }
}

private func sectionLabel(_ title: String) -> some View {
    Text(title.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .tracking(0.7)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
}