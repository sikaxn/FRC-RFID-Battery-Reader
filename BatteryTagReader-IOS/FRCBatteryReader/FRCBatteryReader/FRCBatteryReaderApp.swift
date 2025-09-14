//
//  FRCBatteryReaderApp.swift
//  FRCBatteryReader
//
//  Created by Nathan on 2025-09-13.
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
