//
//  HelpOverlayView.swift
//  YomMockCore
//
//  Onboarding overlay: a scrollable guide of every gesture, shortcut and
//  timeline interaction. Platform-neutral — macOS presents it in a sheet,
//  iPadOS in a detented sheet from the top chrome.
//

import SwiftUI

struct HelpOverlayView: View {
    let sections: [HelpSection]
    var onClose: () -> Void

    init(sections: [HelpSection], onClose: @escaping () -> Void) {
        self.sections = sections
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("YomMock Guide")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close guide")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(sections) { section in
                        sectionView(section)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
#if canImport(AppKit)
        .frame(width: 440, height: 540)
#endif
    }

    private func sectionView(_ section: HelpSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(section.title, systemImage: section.systemImage)
                .font(.system(size: 12, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(section.items) { item in
                    itemRow(item)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
    }

    private func itemRow(_ item: HelpItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(item.input)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.primary.opacity(0.07))
                )
                .overlay {
                    Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .lineLimit(1)

            Text(item.detail)
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
