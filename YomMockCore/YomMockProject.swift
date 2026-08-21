//
//  YomMockProject.swift
//  YomMock
//
//  On-disk project package (`.yommock`) that keeps timeline + appearance
//  settings so a mock can be reopened later with everything restored.
//

import Foundation
import UniformTypeIdentifiers
import SwiftUI

extension UTType {
    static var yomMockProject: UTType {
        UTType(exportedAs: "app.yommock.project")
    }
}

/// Simple RGBA for Codable Color persistence.
struct ProjectColor: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(color: Color) {
        let comps = platformColor(color).studioRGBA
        self.r = Double(comps.red)
        self.g = Double(comps.green)
        self.b = Double(comps.blue)
        self.a = Double(comps.alpha)
    }

    init(platformColor: PlatformColor) {
        let c = platformColor.studioRGBA
        self.r = Double(c.red)
        self.g = Double(c.green)
        self.b = Double(c.blue)
        self.a = Double(c.alpha)
    }

    var color: Color {
        Color(
            platform: PlatformColor.studio(
                red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a)))
    }

    var resolvedPlatformColor: PlatformColor {
        PlatformColor.studio(
            red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }
}

/// One checkpoint persisted to disk.
struct ProjectCheckpoint: Codable, Equatable {
    var id: String // UUID string
    var time: Double
    var yaw: Float
    var pitch: Float
    var radius: Float
    var zoom: Float
    var panX: Float
    var panY: Float
    var panZ: Float
    var lidAngle: Float // MacBook lid open angle in degrees; default when absent

    init(id: UUID = UUID(), time: Double, yaw: Float, pitch: Float, radius: Float, zoom: Float, pan: SIMD3<Float> = .zero, lidAngle: Float = MacBookLidRig.defaultOpenAngle) {
        self.id = id.uuidString
        self.time = time
        self.yaw = yaw
        self.pitch = pitch
        self.radius = radius
        self.zoom = zoom
        self.panX = pan.x
        self.panY = pan.y
        self.panZ = pan.z
        self.lidAngle = lidAngle
    }

    // Backward compat: old files without pan/lid decode with defaults
    enum CodingKeys: String, CodingKey {
        case id, time, yaw, pitch, radius, zoom, panX, panY, panZ, lidAngle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        time = try c.decode(Double.self, forKey: .time)
        yaw = try c.decode(Float.self, forKey: .yaw)
        pitch = try c.decode(Float.self, forKey: .pitch)
        radius = try c.decode(Float.self, forKey: .radius)
        zoom = try c.decode(Float.self, forKey: .zoom)
        panX = try c.decodeIfPresent(Float.self, forKey: .panX) ?? 0
        panY = try c.decodeIfPresent(Float.self, forKey: .panY) ?? 0
        panZ = try c.decodeIfPresent(Float.self, forKey: .panZ) ?? 0
        lidAngle = try c.decodeIfPresent(Float.self, forKey: .lidAngle) ?? MacBookLidRig.defaultOpenAngle
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(time, forKey: .time)
        try c.encode(yaw, forKey: .yaw)
        try c.encode(pitch, forKey: .pitch)
        try c.encode(radius, forKey: .radius)
        try c.encode(zoom, forKey: .zoom)
        try c.encode(panX, forKey: .panX)
        try c.encode(panY, forKey: .panY)
        try c.encode(panZ, forKey: .panZ)
        try c.encode(lidAngle, forKey: .lidAngle)
    }

    var uuid: UUID { UUID(uuidString: id) ?? UUID() }
    var pan: SIMD3<Float> { SIMD3(panX, panY, panZ) }
}

/// Serializable edit document stored as `project.json` inside a `.yommock` package.
struct YomMockProjectDocument: Codable, Equatable {
    var version: Int
    var deviceRaw: String? // Device rawValue; nil in pre-device projects = iPhone
    var selectedColorRaw: String // iPhoneColor name
    var customColor: ProjectColor?
    var backgroundRaw: String // StudioBackground name
    var customBackground: ProjectColor?
    var zoom: Float
    var lidAngle: Float? // current MacBook lid angle; nil in older projects
    var timelineDuration: Double
    var timelineCurrentTime: Double
    var checkpoints: [ProjectCheckpoint]
    var selectedCheckpointID: String?
    var displayRelativePath: String? // e.g. "assets/display.png"
    var displayFileName: String?

    static let currentVersion = 3

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.version == rhs.version
            && lhs.deviceRaw == rhs.deviceRaw
            && lhs.selectedColorRaw == rhs.selectedColorRaw
            && lhs.customColor == rhs.customColor
            && lhs.backgroundRaw == rhs.backgroundRaw
            && lhs.customBackground == rhs.customBackground
            && lhs.zoom == rhs.zoom
            && lhs.lidAngle == rhs.lidAngle
            && lhs.timelineDuration == rhs.timelineDuration
            && lhs.timelineCurrentTime == rhs.timelineCurrentTime
            && lhs.checkpoints == rhs.checkpoints
            && lhs.selectedCheckpointID == rhs.selectedCheckpointID
            && lhs.displayRelativePath == rhs.displayRelativePath
            && lhs.displayFileName == rhs.displayFileName
    }
}

enum YomMockProject {
    static let pathExtension = "yommock"
    static let documentFileName = "project.json"
    static let assetsDirectoryName = "assets"
    static let displayFileName = "display.png"

    struct Loaded {
        let projectURL: URL
        let document: YomMockProjectDocument
        let displayImage: PlatformImage?
    }

    static func documentURL(in projectURL: URL) -> URL {
        projectURL.appendingPathComponent(documentFileName)
    }

    static func assetsDirectory(in projectURL: URL) -> URL {
        projectURL.appendingPathComponent(assetsDirectoryName, isDirectory: true)
    }

    static func displayURL(in projectURL: URL) -> URL {
        assetsDirectory(in: projectURL).appendingPathComponent(displayFileName)
    }

    static func load(from projectURL: URL) throws -> Loaded {
        let docURL = documentURL(in: projectURL)
        let data = try Data(contentsOf: docURL)
        let document = try JSONDecoder().decode(YomMockProjectDocument.self, from: data)

        var image: PlatformImage?
        if let rel = document.displayRelativePath {
            let url = projectURL.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: url.path) {
                image = PlatformImageLoader.image(contentsOf: url)
            }
        } else {
            // fallback to legacy location assets/display.png
            let fallback = displayURL(in: projectURL)
            if FileManager.default.fileExists(atPath: fallback.path) {
                image = PlatformImageLoader.image(contentsOf: fallback)
            }
        }
        return Loaded(projectURL: projectURL, document: document, displayImage: image)
    }

    /// Writes a self-contained project package at `projectURL`.
    @discardableResult
    static func save(
        to projectURL: URL,
        document: YomMockProjectDocument,
        displayImage: PlatformImage?
    ) throws -> YomMockProjectDocument {
        let fm = FileManager.default
        let tempURL = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension)

        let assetsDir = assetsDirectory(in: tempURL)
        try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        do {
            var saved = document
            saved.version = YomMockProjectDocument.currentVersion

            if let displayImage,
               let cg = PlatformImageLoader.cgImage(from: displayImage),
               let png = PlatformImageLoader.pngData(from: cg) {
                let dest = assetsDir.appendingPathComponent(displayFileName)
                try png.write(to: dest)
                saved.displayRelativePath = "\(assetsDirectoryName)/\(displayFileName)"
            } else {
                saved.displayRelativePath = nil
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(saved)
            try data.write(to: documentURL(in: tempURL))

            if fm.fileExists(atPath: projectURL.path) {
                try fm.removeItem(at: projectURL)
            }
            try fm.moveItem(at: tempURL, to: projectURL)

            return saved
        } catch {
            try? fm.removeItem(at: tempURL)
            throw error
        }
    }
}

enum YomMockProjectError: LocalizedError {
    case missingDocument
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingDocument: "This project is missing its document."
        case let .saveFailed(message): message
        }
    }
}

// MARK: - Helpers to map enums to raw strings

extension iPhoneColor {
    var rawValueForProject: String {
        switch self {
        case .lavender: "lavender"
        case .sage: "sage"
        case .mistBlue: "mistBlue"
        case .white: "white"
        case .black: "black"
        case .custom: "custom"
        }
    }

    static func from(projectRaw: String) -> iPhoneColor {
        switch projectRaw {
        case "lavender": return .lavender
        case "sage": return .sage
        case "mistBlue": return .mistBlue
        case "white": return .white
        case "black": return .black
        default: return .custom
        }
    }
}

extension StudioBackground {
    var rawValueForProject: String {
        switch self {
        case .white: "white"
        case .black: "black"
        case .lightGray: "lightGray"
        case .cream: "cream"
        case .slate: "slate"
        case .custom: "custom"
        }
    }

    static func from(projectRaw: String) -> StudioBackground {
        switch projectRaw {
        case "white": return .white
        case "black": return .black
        case "lightGray": return .lightGray
        case "cream": return .cream
        case "slate": return .slate
        default: return .custom
        }
    }
}
