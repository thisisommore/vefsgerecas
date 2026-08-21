//
//  IPadInspectorPanel.swift
//  YomMock-iPad
//
//  Trailing sidebar with touch-sized styling controls: device, lid angle,
//  finish swatches, display screenshot and backdrop.
//

import PhotosUI
import SwiftUI

struct IPadInspectorPanel: View {
    @Bindable var store: YomMockStore
    @Binding var displayStatus: String?
    var onPickFromFiles: () -> Void

    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                deviceSection

                if store.device == .macBookPro {
                    lidSection
                }

                finishSection
                displaySection
                backdropSection
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.bar)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                    let image = PlatformImageLoader.image(data: data)
                {
                    store.displayFileName = "Photo Library"
                    store.displayImage = image
                }
                photoItem = nil
            }
        }
    }

    // MARK: - Sections

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("DEVICE", subtitle: "Model")

            Picker("Model", selection: $store.device) {
                ForEach(Device.allCases) { device in
                    Label(device.name, systemImage: device == .iPhone ? "iphone" : "laptopcomputer")
                        .tag(device)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var lidSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("LID", subtitle: "Opening angle")

            HStack(spacing: 12) {
                Slider(
                    value: $store.lidAngle,
                    in: MacBookLidRig.minOpenAngle...MacBookLidRig.defaultOpenAngle
                )
                Text("\(Int(store.lidAngle.rounded()))°")
                    .monospacedDigit()
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
        }
    }

    private var finishSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("FINISH", subtitle: store.selectedColor.name)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 5),
                spacing: 14
            ) {
                ForEach(iPhoneColor.presets) { color in
                    SwatchCircle(
                        fill: color.swatch,
                        name: color.name,
                        isSelected: store.selectedColor == color,
                        checkmarkLight: true
                    ) {
                        store.selectedColor = color
                    }
                }
                SwatchCircle(
                    fill: store.customColor,
                    name: "Custom",
                    isSelected: store.selectedColor == .custom,
                    checkmarkLight: false,
                    showsRainbowRing: true
                ) {
                    store.selectedColor = .custom
                }
            }

            ColorPicker("Custom finish", selection: $store.customColor, supportsOpacity: false)
                .font(.system(size: 15, weight: .medium))
                .onChange(of: store.customColor) { _, _ in
                    store.selectedColor = .custom
                }
        }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("DISPLAY", subtitle: "Screenshot")

            if let image = store.displayImage {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.primary.opacity(0.05))
                        Image(platformImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(8)
                    }
                    .frame(maxWidth: .infinity)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                    Text(store.displayFileName ?? "Screenshot")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 10) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Change", systemImage: "photo")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                        }

                        Button {
                            onPickFromFiles()
                        } label: {
                            Label("Files", systemImage: "folder")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }

                        Spacer()

                        Button(role: .destructive) {
                            store.displayImage = nil
                            store.displayFileName = nil
                            displayStatus = nil
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 38, height: 38)
                                .background(Color.red.opacity(0.1), in: Circle())
                        }
                    }
                }
            } else {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 26))
                            .foregroundStyle(.secondary)
                        Text("Choose Screenshot")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Photos or Files")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                Color.primary.opacity(0.14),
                                style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                            )
                    }
                }
                .buttonStyle(.plain)
            }

            if let displayStatus {
                Text(displayStatus)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var backdropSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("BACKDROP", subtitle: store.background.name)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 5),
                spacing: 14
            ) {
                ForEach(StudioBackground.presets) { preset in
                    SwatchCircle(
                        fill: preset.swatch,
                        name: preset.name,
                        isSelected: store.background == preset,
                        checkmarkLight: preset != .white
                    ) {
                        store.background = preset
                    }
                }
                SwatchCircle(
                    fill: store.customBackground,
                    name: "Custom",
                    isSelected: store.background == .custom,
                    checkmarkLight: false,
                    showsRainbowRing: true
                ) {
                    store.background = .custom
                }
            }

            ColorPicker("Custom backdrop", selection: $store.customBackground, supportsOpacity: false)
                .font(.system(size: 15, weight: .medium))
                .onChange(of: store.customBackground) { _, _ in
                    store.background = .custom
                }
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.system(size: 16, weight: .semibold))
        }
    }
}

// MARK: - Swatch circle (44 pt touch target)

private struct SwatchCircle: View {
    let fill: Color
    let name: String
    let isSelected: Bool
    var checkmarkLight: Bool = false
    var showsRainbowRing: Bool = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                Circle()
                    .fill(fill)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                    }
                    .overlay {
                        if showsRainbowRing {
                            Circle()
                                .strokeBorder(
                                    AngularGradient(
                                        colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                        center: .center
                                    ),
                                    lineWidth: isSelected ? 0 : 2
                                )
                        }
                    }
                    .overlay {
                        if isSelected {
                            Circle().strokeBorder(Color.accentColor, lineWidth: 2.5).frame(width: 46, height: 46)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(checkmarkLight ? Color.white : Color.black.opacity(0.65))
                                .shadow(color: .black.opacity(0.3), radius: 1)
                        }
                    }
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(TouchDownStyle())
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct TouchDownStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Platform image helper

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(AppKit)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}
