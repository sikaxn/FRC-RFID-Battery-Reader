//
//  LogsView.swift
//  FRCBatteryReader
//
//  Created by Nathan on 2025-09-13.
//

import SwiftUI
import UIKit

struct LogsView: View {
    @EnvironmentObject var store: LogStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store.rawLog.sorted { $0.time > $1.time }) { r in
                VStack(alignment: .leading, spacing: 6) {
                    Text(r.type.rawValue.uppercased()).font(.headline)
                    Text(r.time.formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(r.dataRaw)
                        .font(.system(.footnote, design: .monospaced))
                }
            }
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Export CSV") {
                        if let url = store.exportCSV() {
                            let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                            UIApplication.shared.keyWindowTop?.present(av, animated: true)
                        }
                    }
                }
            }
        }
    }
}
