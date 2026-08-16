//
//  TimelineBar.swift
//  YomMock
//

import SwiftUI

struct TimelineBar: View {
    @Bindable var timeline: CameraTimeline
    var cameraAvailable: Bool
    var onAddZoomRange: () -> Void
    var onAddOrbitRange: () -> Void
    var onUpdateZoomFromScene: () -> Void
    var onUpdateOrbitFromScene: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                playbackControls
                timeReadout
                Spacer(minLength: 12)
                durationControls
            }

            RangeLane(
                title: "ZOOM",
                tint: .accentColor,
                coordinateSpaceName: "zoomLane",
                showsKnob: true,
                ranges: timeline.zoomRanges,
                duration: timeline.duration,
                currentTime: timeline.currentTime,
                selection: timeline.selectedZoomRangeID,
                controlsDisabled: !cameraAvailable || timeline.isPlaying,
                label: { String(format: "%.2gx", $0.zoom) },
                onAdd: onAddZoomRange,
                onSelect: { range in
                    timeline.selectedZoomRangeID = range.id
                    timeline.selectedOrbitRangeID = nil
                    timeline.seek(to: range.start)
                },
                onChange: { timeline.updateZoomRange($0) },
                onRemove: { timeline.removeZoomRange(id: $0) },
                onUpdateFromScene: onUpdateZoomFromScene,
                onSeek: scrub
            )

            RangeLane(
                title: "CAMERA",
                tint: .timelineCamera,
                coordinateSpaceName: "orbitLane",
                showsKnob: false,
                ranges: timeline.orbitRanges,
                duration: timeline.duration,
                currentTime: timeline.currentTime,
                selection: timeline.selectedOrbitRangeID,
                controlsDisabled: !cameraAvailable || timeline.isPlaying,
                label: { orbitLabel($0.pose) },
                onAdd: onAddOrbitRange,
                onSelect: { range in
                    timeline.selectedOrbitRangeID = range.id
                    timeline.selectedZoomRangeID = nil
                    timeline.seek(to: range.start)
                },
                onChange: { timeline.updateOrbitRange($0) },
                onRemove: { timeline.removeOrbitRange(id: $0) },
                onUpdateFromScene: onUpdateOrbitFromScene,
                onSeek: scrub
            )

            if timeline.zoomRanges.isEmpty && timeline.orbitRanges.isEmpty {
                Text("Orbit or zoom the scene, then tap + on a track to add a range at the playhead.")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardShadow()
    }

    private var playbackControls: some View {
        HStack(spacing: 6) {
            Button(action: timeline.goToStart) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(TimelineIconButtonStyle())
            .help("Go to start")
            .disabled(timeline.currentTime == 0 && !timeline.isPlaying)

            Button(action: timeline.togglePlay) {
                Image(systemName: timeline.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 28)
            }
            .buttonStyle(TimelineIconButtonStyle())
            .help(timeline.isPlaying ? "Pause" : "Play")
        }
    }

    private var timeReadout: some View {
        HStack(spacing: 6) {
            Text(timeline.formatted(timeline.currentTime))
                .monospacedDigit()
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("/")
                .foregroundStyle(.primary.opacity(0.35))
            Text(timeline.formatted(timeline.duration))
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(0.55))
            Text("·")
                .foregroundStyle(.primary.opacity(0.35))
            Text("f\(timeline.currentFrame)")
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(0.5))
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.primary.opacity(0.8))
    }

    private var durationControls: some View {
        HStack(spacing: 4) {
            Text("Length")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.5))
            Button {
                timeline.setDuration(timeline.duration - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(TimelineIconButtonStyle())
            .disabled(timeline.duration <= timeline.minDuration || timeline.isPlaying)

            TextField(
                "Duration",
                value: durationBinding,
                format: .number.precision(.fractionLength(0...2))
            )
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(width: 42)
            .disabled(timeline.isPlaying)

            Text("s")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.5))

            Button {
                timeline.setDuration(timeline.duration + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(TimelineIconButtonStyle())
            .disabled(timeline.duration >= CameraTimeline.maxDuration || timeline.isPlaying)
        }
        .help("Timeline length")
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { timeline.duration },
            set: { timeline.setDuration($0) }
        )
    }

    private func scrub(to time: TimeInterval) {
        if timeline.isPlaying {
            timeline.isPlaying = false
        }
        timeline.seek(to: time)
    }

    private func orbitLabel(_ pose: OrbitPose) -> String {
        let degrees = Int((Double(pose.yaw) * 180 / .pi).rounded())
        let normalized = ((degrees % 360) + 360) % 360
        return "\(normalized)°"
    }
}

private struct RangeLane<R: TimelineRange>: View {
    let title: String
    let tint: Color
    let coordinateSpaceName: String
    let showsKnob: Bool
    let ranges: [R]
    let duration: TimeInterval
    let currentTime: TimeInterval
    let selection: UUID?
    let controlsDisabled: Bool
    let label: (R) -> String
    let onAdd: () -> Void
    let onSelect: (R) -> Void
    let onChange: (R) -> Void
    let onRemove: (UUID) -> Void
    let onUpdateFromScene: () -> Void
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.75)
                    .foregroundStyle(.secondary)

                Spacer()

                if let selection {
                    Button(action: onUpdateFromScene) {
                        Label("Update", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(TimelineTextButtonStyle())
                    .help("Capture the current scene into the selected range")
                    .disabled(controlsDisabled)

                    Button {
                        onRemove(selection)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(TimelineIconButtonStyle())
                    .help("Delete selected range")
                    .disabled(controlsDisabled)
                }

                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(TimelineIconButtonStyle())
                .help("Add a range at the playhead")
                .disabled(controlsDisabled)
            }

            GeometryReader { geo in
                let width = geo.size.width

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.primary.opacity(0.05))
                        .contentShape(Rectangle())
                        .gesture(seekGesture(width: width))

                    tickMarks(width: width)

                    ForEach(ranges) { range in
                        let bounds = neighborBounds(for: range)
                        RangeBlock(
                            range: range,
                            duration: duration,
                            trackWidth: width,
                            lowerBound: bounds.lower,
                            upperBound: bounds.upper,
                            tint: tint,
                            isSelected: selection == range.id,
                            label: label(range),
                            coordinateSpaceName: coordinateSpaceName,
                            onChange: onChange,
                            onSelect: { onSelect(range) },
                            onRemove: { onRemove(range.id) }
                        )
                    }

                    playhead(width: width, height: geo.size.height)
                }
            }
            .frame(height: 26)
            .coordinateSpace(name: coordinateSpaceName)
            .accessibilityLabel("\(title.lowercased()) track")
        }
    }

    private func playhead(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 1.5, height: height)
            .overlay(alignment: .top) {
                if showsKnob {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .offset(y: -3)
                }
            }
            .offset(x: width * CGFloat(currentTime / max(duration, 0.001)))
            .allowsHitTesting(false)
    }

    private func tickMarks(width: CGFloat) -> some View {
        ForEach(secondMarks(width: width), id: \.self) { mark in
            Capsule()
                .fill(.primary.opacity(0.14))
                .frame(width: 1, height: mark.isMajor ? 8 : 5)
                .offset(x: mark.x)
        }
        .allowsHitTesting(false)
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard width > 0 else { return }
                onSeek(Double(value.location.x / width) * duration)
            }
    }

    private func neighborBounds(for range: R) -> (lower: TimeInterval, upper: TimeInterval) {
        let others = ranges.filter { $0.id != range.id }
        let lower = others.filter { $0.start <= range.start }.map(\.end).max() ?? 0
        let upper = others.filter { $0.start > range.start }.map(\.start).min() ?? duration
        return (lower, upper)
    }

    private func secondMarks(width: CGFloat) -> [TickMark] {
        let seconds = Int(duration.rounded(.down))
        guard seconds > 0, width > 0 else { return [] }
        let step = seconds > 30 ? 5 : 1
        return stride(from: 0, through: seconds, by: step).map { second in
            TickMark(
                x: CGFloat(TimeInterval(second) / duration) * width,
                isMajor: second % (step * 2 == 0 ? max(step, 2) : step) == 0
            )
        }
    }
}

private struct RangeBlock<R: TimelineRange>: View {
    let range: R
    let duration: TimeInterval
    let trackWidth: CGFloat
    let lowerBound: TimeInterval
    let upperBound: TimeInterval
    let tint: Color
    let isSelected: Bool
    let label: String
    let coordinateSpaceName: String
    let onChange: (R) -> Void
    let onSelect: () -> Void
    let onRemove: () -> Void

    /// What the block's single drag is doing, decided once from where the drag
    /// started. One gesture (instead of separate move + edge-resize gestures)
    /// avoids mid-drag gesture re-competition when model updates re-render the
    /// block — that race made the block flip between moving and resizing.
    private enum DragKind {
        case move, resizeLeading, resizeTrailing
    }

    /// Range captured when the current drag began (the drag's anchor).
    @State private var dragAnchor: R?
    @State private var dragKind: DragKind?
    /// Live geometry while dragging. Rendering from local state (instead of
    /// the model's echoed value) keeps the block glued to the pointer and
    /// immune to update timing during the drag.
    @State private var dragRange: R?

    private var displayed: R { dragRange ?? range }

    private var x: CGFloat {
        trackWidth * CGFloat(displayed.start / max(duration, 0.001))
    }

    private var width: CGFloat {
        max(24, trackWidth * CGFloat((displayed.end - displayed.start) / max(duration, 0.001)))
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(tint.opacity(0.2))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isSelected ? tint : tint.opacity(0.65), lineWidth: isSelected ? 2 : 1.25)
            }
            .overlay(alignment: .center) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint)
                    .opacity(width > 44 ? 1 : 0)
            }
            .frame(width: width, height: 22)
            .overlay(alignment: .leading) {
                rangeHandle
                    .padding(.leading, 3)
            }
            .overlay(alignment: .trailing) {
                HStack(spacing: 3) {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.borderless)
                    .opacity(width > 58 ? 1 : 0)

                    rangeHandle
                }
                .padding(.trailing, 3)
            }
            .gesture(dragGesture)
            .onTapGesture(perform: onSelect)
            .offset(x: x)
            .help("Drag to move the range. Drag its edges to resize.")
    }

    private var rangeHandle: some View {
        Capsule()
            .fill(tint)
            .frame(width: 4, height: 14)
    }

    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                guard trackWidth > 1 else { return }
                let anchor: R
                let kind: DragKind
                if let dragAnchor, let dragKind {
                    anchor = dragAnchor
                    kind = dragKind
                } else {
                    anchor = range
                    // startLocation is in track space; subtract the block's
                    // offset to get the press point in block-local terms.
                    kind = Self.classifyDrag(startX: value.startLocation.x - x, width: width)
                    dragAnchor = anchor
                    dragKind = kind
                }
                let delta = Double(value.translation.width / trackWidth) * duration
                let minLength = CameraTimeline.minimumRangeLength
                var updated = anchor
                switch kind {
                case .move:
                    let length = anchor.end - anchor.start
                    let start = min(max(anchor.start + delta, lowerBound), max(lowerBound, upperBound - length))
                    updated.start = start
                    updated.end = start + length
                case .resizeLeading:
                    updated.start = min(max(anchor.start + delta, lowerBound), anchor.end - minLength)
                case .resizeTrailing:
                    updated.end = max(min(anchor.end + delta, upperBound), anchor.start + minLength)
                }
                dragRange = updated
                onChange(updated)
            }
            .onEnded { _ in
                // The model already holds the last onChanged value, so dropping
                // the local override just hands rendering back to it.
                dragAnchor = nil
                dragKind = nil
                dragRange = nil
            }
    }

    /// Strips near the edge handles resize the range; the middle moves it.
    private static func classifyDrag(startX: CGFloat, width: CGFloat) -> DragKind {
        let handleZone = min(12, width * 0.35)
        if startX <= handleZone { return .resizeLeading }
        if startX >= width - handleZone { return .resizeTrailing }
        return .move
    }
}

private struct TickMark: Hashable {
    var x: CGFloat
    var isMajor: Bool
}

private struct TimelineIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary.opacity(configuration.isPressed ? 0.45 : 0.8))
            .background(.primary.opacity(configuration.isPressed ? 0.1 : 0.06), in: Capsule())
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
