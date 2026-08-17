//
//  TimelineBar.swift
//  YomMock
//

import SwiftUI

struct TimelineBar: View {
    @Bindable var timeline: CameraTimeline
    var cameraAvailable: Bool
    var onSaveCheckpoint: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("TIMELINE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.75)
                    .foregroundStyle(.secondary)

                Spacer()

                playbackControls
                timeReadout
                Spacer(minLength: 12)

                saveCheckpointControls

                durationControls
            }
            .padding(.horizontal, 16)
            .frame(height: 31)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                checkpointTrack

                Text(
                    timeline.checkpoints.count < 2
                        ? "Orbit and zoom the scene, move the playhead, then save a checkpoint. The camera animates between checkpoints."
                        : "The camera animates between checkpoints. Save a new one to add it to the timeline."
                )
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)

            Spacer(minLength: 0)
        }
        .background(Color(nsColor: .controlBackgroundColor))
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
            .disabled(timeline.checkpoints.count < 2 && !timeline.isPlaying)
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

    private var saveCheckpointControls: some View {
        HStack(spacing: 8) {
            Button(action: onSaveCheckpoint) {
                Label(
                    timeline.checkpointAtPlayhead == nil ? "Save Checkpoint" : "Update Checkpoint",
                    systemImage: "diamond.fill"
                )
                .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(TimelineTextButtonStyle())
            .disabled(!cameraAvailable || timeline.isPlaying)
            .help("Store the current camera orbit and zoom at the playhead")

            if let checkpoint = timeline.checkpointAtPlayhead, timeline.checkpoints.count > 1 {
                Button {
                    timeline.deleteCheckpoint(id: checkpoint.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(TimelineIconButtonStyle())
                .help("Delete checkpoint")
                .disabled(timeline.isPlaying)
            }
        }
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

    private var checkpointTrack: some View {
        TimelineCheckpointTrack(timeline: timeline)
            .frame(height: 26)
    }
}

/// A single draft track showing checkpoint diamonds and the playhead. Clicking
/// a diamond selects/seeks to it; dragging or clicking the background scrubs.
private struct TimelineCheckpointTrack: View {
    @Bindable var timeline: CameraTimeline

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.primary.opacity(0.05))
                    .contentShape(Rectangle())
                    .gesture(seekGesture(width: width))

                tickMarks(width: width)

                ForEach(timeline.checkpoints) { checkpoint in
                    TimelineDiamond()
                        .fill(
                            checkpoint.id == timeline.selectedCheckpointID
                                ? Color.accentColor
                                : .primary.opacity(0.55)
                        )
                        .frame(width: 11, height: 11)
                        .position(
                            x: x(for: checkpoint.time, width: width),
                            y: height / 2
                        )
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                        .help(timeline.formatted(checkpoint.time))
                        .onTapGesture {
                            timeline.select(checkpoint)
                        }
                }

                playhead(width: width, height: height)
            }
        }
    }

    private func playhead(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 1.5, height: height)
            Circle()
                .fill(Color.timelineKnob)
                .overlay {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                }
                .frame(width: 12, height: 12)
                .offset(x: 5.25, y: -13)
        }
        .offset(x: x(for: timeline.currentTime, width: width))
        .allowsHitTesting(false)
    }

    private func tickMarks(width: CGFloat) -> some View {
        ForEach(secondMarks(width: width), id: \.self) { mark in
            Capsule()
                .fill(.primary.opacity(0.14))
                .frame(width: 1, height: mark.isMajor ? 8 : 5)
                .position(x: mark.x, y: 20)
        }
        .allowsHitTesting(false)
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard width > 0 else { return }
                if timeline.isPlaying {
                    timeline.isPlaying = false
                }
                timeline.seek(to: Double(value.location.x / width) * timeline.duration)
            }
    }

    private func x(for time: TimeInterval, width: CGFloat) -> CGFloat {
        guard timeline.duration > 0 else { return 0 }
        return CGFloat(time / timeline.duration) * width
    }

    private func secondMarks(width: CGFloat) -> [TickMark] {
        let seconds = Int(timeline.duration.rounded(.down))
        guard seconds > 0, width > 0 else { return [] }
        let step = seconds > 30 ? 5 : 1
        return stride(from: 0, through: seconds, by: step).map { second in
            TickMark(
                x: x(for: TimeInterval(second), width: width),
                isMajor: second % (step * 2 == 0 ? max(step, 2) : step) == 0
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
