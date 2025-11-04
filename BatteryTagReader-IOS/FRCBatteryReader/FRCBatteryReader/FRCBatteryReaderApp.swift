//
//  FRCBatteryReaderApp.swift
//  FRCBatteryReader
//

import SwiftUI

@main
struct FRCBatteryReaderApp: App {
    @StateObject private var store = LogStore()
    @StateObject private var nfc = NFCController()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
                    .environmentObject(store)
                    .environmentObject(nfc)
                    .onOpenURL { url in
                        handleIncomingJSON(url)
                    }
            }
        }
    }

    private func handleIncomingJSON(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            guard let jsonStr = String(data: data, encoding: .utf8) else { return }
            if let payload = ContentView().parseDemoJSON(jsonStr) {
                nfc.payload = payload
                store.log(.read, raw: jsonStr)
                SoundHelper.shared.play(note: NoteType(rawValue: payload.n) ?? .normal)
                DispatchQueue.main.async {
                    self.nfc.canWriteTag = true
                }
            } else {
                print("Invalid battery JSON structure.")
            }
        } catch {
            print("Failed to open JSON from URL: \(error)")
        }
    }
}
