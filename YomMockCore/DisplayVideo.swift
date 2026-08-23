//
//  DisplayVideo.swift
//  YomMockCore
//
//  A user-dropped screen recording used as the device display content
//  (instead of a static screenshot). One controller owns:
//    - a muted AVQueuePlayer + RealityKit VideoMaterial for the live preview,
//      driven BY THE TIMELINE — it starts when the camera animation starts,
//      pauses with it, and freezes on its final frame if it is shorter than
//      the timeline. It never autoplays on its own.
//    - an AVAssetImageGenerator that extracts exact frames for the offscreen
//      still and video export pipelines (clamped at the clip end).
//

import AVFoundation
import CoreGraphics
import CoreTransferable
import RealityKit
import UniformTypeIdentifiers

enum DisplayVideoError: LocalizedError {
    case unreadable
    case noVideoTrack

    var errorDescription: String? {
        switch self {
        case .unreadable: "Could not read the video file."
        case .noVideoTrack: "The dropped file has no playable video track."
        }
    }
}

@MainActor
final class DisplayVideoController: Equatable {
    static func == (lhs: DisplayVideoController, rhs: DisplayVideoController) -> Bool {
        lhs === rhs
    }

    let url: URL
    let asset: AVAsset
    /// Clip duration in seconds (> 0 for a usable recording).
    let duration: Double

    /// Muted player driving `material`. Never autoplays — the timeline
    /// playback driver starts/pauses/resumes it (see YomMockStore).
    let player: AVQueuePlayer
    let material: VideoMaterial

    private let imageGenerator: AVAssetImageGenerator

    /// Loads metadata and prepares the preview player. Throws when the file
    /// can't be played as video (callers surface the message).
    init(url: URL) async throws {
        self.url = url
        let asset = AVURLAsset(url: url)
        self.asset = asset

        guard (try? await asset.load(.isPlayable)) == true else {
            throw DisplayVideoError.unreadable
        }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else { throw DisplayVideoError.noVideoTrack }
        let seconds = try await asset.load(.duration).seconds
        guard seconds.isFinite, seconds > 0 else { throw DisplayVideoError.unreadable }
        self.duration = seconds

        let item = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer()
        player.isMuted = true
        // Freeze on the last frame when the recording is shorter than the
        // timeline instead of advancing past the item.
        player.actionAtItemEnd = .none
        self.player = player
        player.insert(item, after: nil)
        self.material = VideoMaterial(avPlayer: player)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Exact frames so exports are deterministic.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        self.imageGenerator = generator
    }

    func play() { player.play() }
    func pause() { player.pause() }

    /// Whether playback ran through (or was scrubbed to) the end of the clip.
    var isAtEnd: Bool {
        player.currentTime().seconds >= duration - 0.01
    }

    /// Seeks back to the first frame and plays — used when the timeline
    /// (re)starts from the top.
    func restart() {
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    /// Resumes from the paused position — used when the timeline continues
    /// from mid-animation.
    func resume() {
        guard !isAtEnd else { return }
        player.play()
    }

    /// Moves to the exact frame at `time` (seconds) and stays paused — used
    /// for playhead scrubbing and for attaching mid-timeline.
    func scrub(to time: Double) {
        pause()
        guard duration > 0 else { return }
        var t = min(max(time, 0), duration)
        if t >= duration { t = duration - 0.001 } // hold the last frame
        player.seek(
            to: CMTime(seconds: t, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero)
    }

    /// Current preview playback position clamped into [0, duration).
    var currentPlaybackTime: Double {
        let t = player.currentTime().seconds
        guard t.isFinite, t > 0 else { return 0 }
        return min(t, duration)
    }

    /// Exact decoded frame at `time` (seconds, clamped into the clip — times
    /// past the end hold the last frame, matching preview behavior).
    /// Falls back to nil on decode failure — callers keep the poster image.
    func frame(at time: Double) async -> CGImage? {
        guard duration > 0 else { return nil }
        var t = min(max(time, 0), duration)
        if t >= duration { t = duration - 0.001 }
        do {
            let result = try await imageGenerator.image(
                at: CMTime(seconds: t, preferredTimescale: 600))
            return result.image
        } catch {
            return nil
        }
    }

    /// First frame — used as the poster/thumbnail for the project package.
    func posterFrame() async -> CGImage? {
        await frame(at: 0)
    }
}

extension UTType {
    /// True when the URL looks like a playable movie (mov/mp4/m4v…).
    static func isDisplayVideo(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .mpeg4Movie)
    }
}

/// Transferable box so `PhotosPickerItem.loadTransferable` can hand us a
/// dropped/selected video file. Importing copies the file into the app's
/// temporary directory, so access survives the picker's security scope.
struct ImportedMovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty
                ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ImportedMovieFile(url: destination)
        }
    }
}
