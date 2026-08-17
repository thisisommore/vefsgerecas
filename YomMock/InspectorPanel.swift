//
//  InspectorPanel.swift
//  YomMock
//
//  Right-hand panel — phone finish options.
//

import SwiftUI

struct InspectorPanel: View {
    @Binding var selectedColor: iPhoneColor
    @Binding var customColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().opacity(0)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PhoneInspectorPanel(
                        selectedColor: $selectedColor,
                        customColor: $customColor
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