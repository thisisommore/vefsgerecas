//
//  StudioCameraTests.swift
//  YomMockTests
//

import Foundation
import Testing
@testable import YomMock

struct StudioCameraSettingsTests {
    @Test func defaultMatchesLegacyFixedFov() {
        let camera = StudioCameraSettings.default
        #expect(abs(camera.fieldOfView - 60) < 0.01)
    }

    @Test func focalLengthAndFieldOfViewRoundTrip() {
        var camera = StudioCameraSettings()
        for focal: Float in [12, 18, 24, 35, 50, 70] {
            camera.setFocalLength(focal)
            #expect(abs(camera.focalLength - focal) < 0.01)
            #expect(camera.fieldOfView >= StudioCameraSettings.minFieldOfView)
            #expect(camera.fieldOfView <= StudioCameraSettings.maxFieldOfView)
        }
    }

    @Test func setFocalLengthClampsToRange() {
        var camera = StudioCameraSettings()
        camera.setFocalLength(1)
        #expect(camera.focalLength >= StudioCameraSettings.minFocalLength - 0.01)
        camera.setFocalLength(500)
        #expect(camera.focalLength <= StudioCameraSettings.maxFocalLength + 0.01)
    }

    @Test func initClampsOutOfRangeValues() {
        let camera = StudioCameraSettings(fieldOfView: 500)
        #expect(camera.fieldOfView == StudioCameraSettings.maxFieldOfView)
    }

    @Test func decodingLegacyJSONUsesDefaults() throws {
        // A document written before camera settings existed.
        let json = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(StudioCameraSettings.self, from: json)
        #expect(decoded == .default)
    }

    @Test func decodingIgnoresRemovedLegacyKeys() throws {
        // Projects saved with the earlier aperture/focus/DoF fields still decode.
        let json = Data(
            #"{"aperture":5.6,"fieldOfView":45,"focusDistance":7.2,"isDepthOfFieldEnabled":true}"#
                .utf8)
        let decoded = try JSONDecoder().decode(StudioCameraSettings.self, from: json)
        #expect(abs(decoded.fieldOfView - 45) < 0.01)
    }

    @Test func codableRoundTripPreservesValues() throws {
        let original = StudioCameraSettings(fieldOfView: 34)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StudioCameraSettings.self, from: data)
        #expect(decoded == original)
    }
}
