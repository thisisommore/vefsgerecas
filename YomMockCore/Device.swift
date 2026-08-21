//
//  Device.swift
//  YomMock
//
//  The hardware being mocked. Drives which bundled model + default
//  screenshot load, and how materials are styled.
//

import Foundation

enum Device: String, CaseIterable, Identifiable {
    case iPhone
    case macBookPro

    var id: String { rawValue }

    var name: String {
        switch self {
        case .iPhone: "iPhone 17"
        case .macBookPro: "MacBook Pro"
        }
    }

    /// Bundled model resource (iPhone17.usdz / MacBookPro.usdc).
    var modelResource: String {
        switch self {
        case .iPhone: "iPhone17"
        case .macBookPro: "MacBookPro"
        }
    }

    var modelExtension: String {
        switch self {
        case .iPhone: "usdz"
        case .macBookPro: "usdc"
        }
    }

    /// Bundled screenshot shown on the display until the user overrides it.
    var defaultDisplayImageName: String {
        switch self {
        case .iPhone: "iphone_home.jpg"
        case .macBookPro: "mac_home.jpg"
        }
    }

    /// Studio framing target (normalized max dimension). The open MacBook
    /// lid makes it much taller in frame than the iPhone, so it frames smaller.
    var frameTargetSize: Float {
        switch self {
        case .iPhone: 0.05
        case .macBookPro: 0.034
        }
    }
}
