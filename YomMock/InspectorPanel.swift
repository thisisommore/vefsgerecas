//
//  InspectorPanel.swift
//  YomMock
//
//  Right-hand options panel. Tabs: "Phone" for the phone finish, and "Shot"
//  for the selected camera checkpoint (orbit + zoom).
//

import SwiftUI

enum InspectorTab: String, CaseIterable, Identifiable {
    case phone
    case shot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phone: "Phone"
        case .shot: "Shot"
        }
    }

    var systemImage: String {
        switch self {
        case .phone: "iphone"
        case .shot: "camera"
        }
    }
}

struct InspectorPanel: View {
    @Binding var selectedColor: iPhoneColor
    @Binding var customColor: Color
    @Binding var zoom: Float
    @Binding var selectedTab: InspectorTab

    var cameraAvailable: Bool
    var timeline: CameraTimeline
    var onCapture: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorTabBar(selection: $selectedTab)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedTab {
                    case .phone:
                        PhoneInspectorPanel(
                            selectedColor: $selectedColor,
                            customColor: $customColor
                        )
                    case .shot:
                        ShotInspectorPanel(
                            zoom: $zoom,
                            timeline: timeline,
                            cameraAvailable: cameraAvailable,
                            onCapture: onCapture
                        )
                    }
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

private struct InspectorTabBar: View {
    @Binding var selection: InspectorTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(InspectorTab.allCases) { tab in
                InspectorTabButton(
                    tab: tab,
                    isSelected: selection == tab
                ) {
                    selection = tab
                }
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        }
    }
}

private struct InspectorTabButton: View {
    let tab: InspectorTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(height: 14)
                Text(tab.title)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.55))
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
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

// MARK: - Shot (selected checkpoint)

private struct ShotInspectorPanel: View {
    @Binding var zoom: Float
    var timeline: CameraTimeline
    var cameraAvailable: Bool
    var onCapture: () -> Void

    private var selected: CameraCheckpoint? {
        timeline.selectedCheckpoint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            inspectorHeader(title: "SHOT", subtitle: "Selected checkpoint")

            if let checkpoint = selected {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Checkpoint \(timeline.formatted(checkpoint.time))")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("Orbit and zoom held at this moment")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 12) {
                    LabeledContent("Yaw") {
                        Text(angleLabel(checkpoint.pose.yaw))
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .font(.caption)
                    LabeledContent("Pitch") {
                        Text(angleLabel(checkpoint.pose.pitch))
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .font(.caption)
                    LabeledContent("Dist.") {
                        Text(String(format: "%.2f", checkpoint.pose.radius))
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .font(.caption)
                }

                HStack {
                    Text("Zoom")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2gx", checkpoint.zoom))
                        .font(.system(size: 12, design: .monospaced))
                }

                Slider(
                    value: Binding(
                        get: { Double(checkpoint.zoom) },
                        set: { timeline.updateSelectedCheckpoint(zoom: Float($0)) }
                    ),
                    in: 1...Double(PhoneScene.maxZoom),
                    step: 0.05
                )
                .tint(.accentColor)
                .disabled(!cameraAvailable || timeline.isPlaying)

                Button(action: onCapture) {
                    Label(
                        "Capture current camera",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!cameraAvailable || timeline.isPlaying)
                .help("Store the current scene orbit and zoom into this checkpoint")

                Divider()

                Text("Orbit and zoom the scene, place the playhead on a checkpoint, then Save Checkpoint captures a new keyframe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No checkpoint selected. Click a diamond on the timeline to edit that checkpoint.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Text("The camera animates between checkpoints, easing orbit and zoom together.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func angleLabel(_ radians: Float) -> String {
        let degrees = Int((Double(radians) * 180 / .pi).rounded())
        let normalized = ((degrees % 360) + 360) % 360
        return "\(normalized)°"
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
