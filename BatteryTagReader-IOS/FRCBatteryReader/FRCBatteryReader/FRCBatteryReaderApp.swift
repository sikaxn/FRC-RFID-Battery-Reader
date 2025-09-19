//
//  FRCBatteryReaderApp.swift
//  FRCBatteryReader
//

import SwiftUI

@main
struct FRCBatteryReaderApp: App {
    @StateObject private var store = LogStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
                    .environmentObject(store)
            }
        }
    }
}
