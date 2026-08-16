//
//  TimelineBar.swift
//  YomMock
//

import SwiftUI

struct TimelineBar: View {
    @Bindable var timeline: CameraTimeline
    var cameraAvailable: Bool
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                playbackControls
                timeReadout
                Spacer(minLength: 12)
                checkpointButtons
                durationControls
            }

            TimelineTrack(timeline: timeline)

            if timeline.checkpoints.count < 2 {
                Text("Move the playhead, orbit and zoom yourself, then save a checkpoint.")
                    .font(.system(size: 11))
                    .foregroundStyle(.black.opacity(0.45))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
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
                .foregroundStyle(.black.opacity(0.35))
            Text(timeline.formatted(timeline.duration))
                .monospacedDigit()
                .foregroundStyle(.black.opacity(0.55))
            Text("·")
                .foregroundStyle(.black.opacity(0.3))
            Text("f\(timeline.currentFrame)")
                .monospacedDigit()
                .foregroundStyle(.black.opacity(0.45))
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.black.opacity(0.75))
    }

    private var checkpointButtons: some View {
        HStack(spacing: 8) {
            Button(action: onSave) {
                Label(
                    timeline.checkpointAtPlayhead == nil ? "Save Checkpoint" : "Update Checkpoint",
                    systemImage: "diamond.fill"
                )
                .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(TimelineTextButtonStyle())
            .disabled(!cameraAvailable || timeline.isPlaying)
            .help("Store the current camera at this time")

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
                .foregroundStyle(.black.opacity(0.45))
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
                .foregroundStyle(.black.opacity(0.45))

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
}

private struct TimelineTrack: View {
    @Bindable var timeline: CameraTimeline

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.12))
                    .frame(height: 4)

                Capsule()
                    .fill(.black.opacity(0.32))
                    .frame(width: max(4, x(for: timeline.currentTime, width: width)), height: 4)

                ForEach(secondMarks(width: width), id: \.self) { mark in
                    Capsule()
                        .fill(.black.opacity(0.18))
                        .frame(width: 1, height: mark.isMajor ? 8 : 5)
                        .position(x: mark.x, y: height / 2 + 8)
                }

                ForEach(timeline.checkpoints) { checkpoint in
                    TimelineDiamond()
                        .fill(Color.black.opacity(0.78))
                        .frame(width: 10, height: 10)
                        .position(x: x(for: checkpoint.time, width: width), y: height / 2)
                        .help(timeline.formatted(checkpoint.time))
                        .onTapGesture {
                            timeline.seek(to: checkpoint.time)
                        }
                }

                Circle()
                    .fill(.white)
                    .overlay {
                        Circle().strokeBorder(.black.opacity(0.28), lineWidth: 1)
                    }
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .position(x: x(for: timeline.currentTime, width: width), y: height / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(seekGesture(width: width))
        }
        .frame(height: 28)
        .accessibilityLabel("Timeline")
        .accessibilityValue(timeline.formatted(timeline.currentTime))
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

private struct TickMark: Hashable {
    var x: CGFloat
    var isMajor: Bool
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

private struct TimelineIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black.opacity(configuration.isPressed ? 0.45 : 0.75))
            .background(.black.opacity(configuration.isPressed ? 0.08 : 0.05), in: Capsule())
    }
}

private struct TimelineTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(.black.opacity(configuration.isPressed ? 0.45 : 0.78))
            .background(.black.opacity(configuration.isPressed ? 0.08 : 0.05), in: Capsule())
    }
}
