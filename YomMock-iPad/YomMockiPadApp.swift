//
//  YomMockiPadApp.swift
//  YomMock-iPad
//
//  Native iPadOS entry point.
//

import SwiftUI

@main
struct YomMockiPadApp: App {
    @State private var store = YomMockStore()

    init() {
        SubscriptionManager.configure()
        SubscriptionManager.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            IPadRootView(store: store)
        }
    }
}
