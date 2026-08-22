//
//  IPadTimelineBar.swift
//  YomMock-iPad
//
//  Touch-first timeline card: big transport controls, a tall scrub track
//  with drag-to-retime checkpoint diamonds, and a prominent Save Checkpoint
//  action. Everything is ≥44 pt for finger use.
//

import SwiftUI

struct IPadTimelineBar: View {
    @Bindable var timeline: CameraTimeline
    var cameraAvailable: Bool
    var onSaveCheckpoint: () -> Void
    var onEdited: () -> Void

    @State private var draggingCheckpointID: UUID?
    @State private var scrubbing = false

    var body: some View {
        VStack(spacing: 10) {
            controlsRow
            track
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: timeline.isPlaying)
        .background(
            // Hardware keyboard: spacebar toggles play/pause.
            Button(action: timeline.togglePlay) { EmptyView() }
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .disabled(timeline.checkpoints.count < 2 && !timeline.isPlaying)
        )
    }

    // MARK: - Controls row

    private var controlsRow: some View {
        HStack(spacing: 14) {
            Button(action: timeline.goToStart) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .foregroundStyle(.primary.opacity(0.75))
            .disabled(timeline.currentTime == 0 && !timeline.isPlaying)

            Button(action: timeline.togglePlay) {
                Image(systemName: timeline.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.14), in: Circle())
                    .contentShape(Circle())
            }
            .disabled(timeline.checkpoints.count < 2 && !timeline.isPlaying)

            timeReadout

            Spacer(minLength: 8)

            saveCheckpointButton

            if let checkpoint = timeline.checkpointAtPlayhead, timeline.checkpoints.count > 1 {
                Button {
                    timeline.deleteCheckpoint(id: checkpoint.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .foregroundStyle(.red.opacity(0.85))
                .disabled(timeline.isPlaying)
            }

            lengthStepper
        }
    }

    private var timeReadout: some View {
        HStack(spacing: 5) {
            Text(timeline.formatted(timeline.currentTime))
                .monospacedDigit()
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text("/")
                .foregroundStyle(.tertiary)
            Text(timeline.formatted(timeline.duration))
                .monospacedDigit()
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text("·")
                .foregroundStyle(.tertiary)
            Text("f\(timeline.currentFrame)")
                .monospacedDigit()
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
    }

    private var saveCheckpointButton: some View {
        Button(action: onSaveCheckpoint) {
            Label(
                timeline.checkpointAtPlayhead == nil ? "Save Checkpoint" : "Update Checkpoint",
                systemImage: "diamond.fill"
            )
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .buttonStyle(.borderedProminent)
        .clipShape(Capsule())
        .disabled(!cameraAvailable || timeline.isPlaying)
    }

    private var lengthStepper: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                TextField(
                    "Duration",
                    value: durationBinding,
                    format: .number.precision(.fractionLength(0...2))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(width: 42)
                Text("s")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .disabled(timeline.isPlaying)

            Menu {
                ForEach([4, 6, 8, 12, 20, 30, 60], id: \.self) { seconds in
                    Button("\(seconds)s") {
                        timeline.setDuration(TimeInterval(seconds))
                    }
                    .disabled(seconds < Int(timeline.minDuration) || timeline.isPlaying)
                }
            } label: {
                Image(systemName: "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .disabled(timeline.isPlaying)
        }
        .accessibilityLabel("Timeline length")
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { timeline.duration },
            set: { timeline.setDuration($0) }
        )
    }

    // MARK: - Track

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.primary.opacity(0.06))
                    .overlay(alignment: .leading) {
                        // Progress fill up to the playhead.
                        Capsule()
                            .fill(Color.accentColor.opacity(scrubbing ? 0.22 : 0.14))
                            .frame(width: max(0, x(for: timeline.currentTime, width: width)))
                            .padding(2)
                    }
                    .contentShape(Rectangle())
                    .gesture(scrubGesture(width: width))

                tickMarks(width: width)

                ForEach(timeline.checkpoints) { checkpoint in
                    diamond(for: checkpoint, width: width, height: height)
                }

                playhead(width: width, height: height)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 52)
    }

    private func diamond(for checkpoint: CameraCheckpoint, width: CGFloat, height: CGFloat)
        -> some View
    {
        let isSelected = checkpoint.id == timeline.selectedCheckpointID
        let isDragging = draggingCheckpointID == checkpoint.id

        return TimelineDiamond()
            .fill(isSelected || isDragging ? Color.accentColor : .primary.opacity(0.55))
            .frame(width: 16, height: 16)
            .scaleEffect(isDragging ? 1.25 : 1)
            .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle().inset(by: -14))
            .position(x: x(for: checkpoint.time, width: width), y: height / 2)
            .onTapGesture {
                timeline.select(checkpoint)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .gesture(retimeGesture(for: checkpoint, width: width))
    }

    private func retimeGesture(for checkpoint: CameraCheckpoint, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !timeline.isPlaying, draggingCheckpointID == nil || draggingCheckpointID == checkpoint.id else { return }
                if draggingCheckpointID == nil {
                    draggingCheckpointID = checkpoint.id
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                let dt = Double(value.translation.width / max(width, 1)) * timeline.duration
                let sorted = timeline.checkpoints.sorted { $0.time < $1.time }
                guard let index = sorted.firstIndex(where: { $0.id == checkpoint.id }) else { return }
                let lower = index > 0 ? sorted[index - 1].time + CameraTimeline.snapTolerance * 2 : 0
                let upper =
                    index < sorted.count - 1
                    ? sorted[index + 1].time - CameraTimeline.snapTolerance * 2 : timeline.duration
                timeline.moveCheckpoint(id: checkpoint.id, to: min(max(checkpoint.time + dt, lower), upper))
            }
            .onEnded { _ in
                if draggingCheckpointID != nil {
                    timeline.finishReorder()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                draggingCheckpointID = nil
                onEdited()
            }
    }

    private func playhead(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor)
                .frame(width: 2.5, height: height)
            Circle()
                .fill(Color.timelineKnob)
                .overlay {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 2.5)
                }
                .frame(width: 16, height: 16)
                .offset(y: -8)
        }
        .shadow(color: Color.accentColor.opacity(0.35), radius: 4, y: 1)
        .offset(x: x(for: timeline.currentTime, width: width) - 1.25)
    }

    private func tickMarks(width: CGFloat) -> some View {
        ForEach(secondMarks(width: width), id: \.self) { mark in
            VStack(spacing: 3) {
                Capsule()
                    .fill(.primary.opacity(mark.isMajor ? 0.28 : 0.16))
                    .frame(width: mark.isMajor ? 1.5 : 1, height: mark.isMajor ? 10 : 6)
                if mark.isMajor {
                    Text("\(mark.second)s")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary.opacity(0.45))
                }
            }
            .position(x: mark.x, y: 12)
            .allowsHitTesting(false)
        }
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard width > 0 else { return }
                if !scrubbing {
                    scrubbing = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                if timeline.isPlaying {
                    timeline.isPlaying = false
                }
                let fraction = value.location.x / width
                timeline.seek(to: Double(fraction) * timeline.duration)
            }
            .onEnded { _ in scrubbing = false }
    }

    private func x(for time: TimeInterval, width: CGFloat) -> CGFloat {
        guard timeline.duration > 0 else { return 0 }
        return CGFloat(time / timeline.duration) * width
    }

    private func secondMarks(width: CGFloat) -> [TickMark] {
        let seconds = Int(timeline.duration.rounded(.down))
        guard seconds > 0, width > 0 else { return [] }
        let step = seconds > 30 ? 5 : (seconds > 12 ? 2 : 1)
        return stride(from: 0, through: seconds, by: step).map { second in
            TickMark(
                x: x(for: TimeInterval(second), width: width),
                second: second,
                isMajor: second % (step * 2) == 0
            )
        }
    }
}

private struct TimelineDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        }
    }
}

private struct TickMark: Hashable {
    var x: CGFloat
    var second: Int
    var isMajor: Bool
}
