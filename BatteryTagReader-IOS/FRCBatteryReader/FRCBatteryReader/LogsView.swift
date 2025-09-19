//
//  LogsView.swift
//  FRCBatteryReader
//

import SwiftUI
import UIKit

struct LogsView: View {
    @EnvironmentObject var store: LogStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if store.items.isEmpty {
                    Text("No logs yet").foregroundStyle(.secondary)
                } else {
                    ForEach(store.items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.kind == .read ? "READ" : "WRITE")
                                    .font(.caption).bold()
                                    .padding(.vertical, 2).padding(.horizontal, 6)
                                    .background(item.kind == .read ? Color.blue.opacity(0.15) : Color.green.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Spacer()
                                Text(item.when, style: .time)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text(item.raw)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 6)
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        let json = store.exportJSONString()
                        // Present share sheet with the JSON text
                        let av = UIActivityViewController(activityItems: [json], applicationActivities: nil)
                        if let top = UIApplication.shared.keyWindowTop {
                            top.present(av, animated: true)
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.items.isEmpty)

                    Button(role: .destructive) {
                        store.clear()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .disabled(store.items.isEmpty)
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        store.delete(at: offsets)
    }
}
