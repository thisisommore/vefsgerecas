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

    var body: some Scene {
        WindowGroup {
            IPadRootView(store: store)
                .onOpenURL { url in
                    store.importProject(from: url)
                }
        }
    }
}
