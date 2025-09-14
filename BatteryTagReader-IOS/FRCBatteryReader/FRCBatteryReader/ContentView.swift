//
//  ContentView.swift
//  FRCBatteryReader
//
//  Created by Nathan on 2025-09-13.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var nfc = NFCController()
    @EnvironmentObject var store: LogStore

    @State private var showLogs = false
    @State private var showStatusPicker = false
    @State private var pickedNote: NoteType = .normal

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button("Init New") { promptInitNew() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                Button("Mock Robot") { addUsage(d: 1) }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button("View Logs") { showLogs = true }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let p = nfc.payload {
                        labeled("Serial Number", p.sn)
                        labeled("First Use", formatUTCStringToLocal(p.fu))
                        labeled("Cycle Count", String(p.cc))
                        noteBadge(NoteType(rawValue: p.n) ?? .normal)

                        if !p.u.isEmpty {
                            Text("Usage Log:")
                                .font(.headline)
                                .padding(.top, 8)
                            ForEach(p.u.sorted { $0.i > $1.i }) { e in
                                usageRow(e)
                            }
                        }
                    } else {
                        Text("Hold battery to phone")
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 80)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Button("Charged") { addUsage(d: 2, incrementCycle: true) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                Button("Set Status") { showStatusPicker = true }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Battery Tag Reader")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Scan") { nfc.begin() }
            }
        }
        .sheet(isPresented: $showLogs) {
            LogsView()
        }
        .confirmationDialog("Select Note Type", isPresented: $showStatusPicker, titleVisibility: .visible) {
            ForEach(NoteType.allCases) { t in
                Button(t.title) { setStatus(t) }
            }
        }
        .onAppear { store.load() }
    }

    // MARK: - UI helpers
    func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body)
        }
    }

    @ViewBuilder
    func noteBadge(_ t: NoteType) -> some View {
        let bg: Color = {
            switch t {
            case .practice: return Color.yellow.opacity(0.5)
            case .scrap: return Color.red.opacity(0.7)
            case .other: return Color.blue.opacity(0.6)
            default: return .clear
            }
        }()
        Text("Note Type: \(t.title)")
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    func usageRow(_ e: UsageEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("#\(e.i): \(formatUTCStringToLocal(e.t))")
            Text("• Device: \((e.d == 2) ? "Charger" : "Robot")")
            Text("• Energy: \(e.e) kJ, Voltage: \(e.v)")
            Divider()
        }.font(.subheadline)
    }

    // MARK: - Actions
    func promptInitNew() {
        var controller: UIAlertController?
        controller = UIAlertController(title: "Enter Serial Number", message: nil, preferredStyle: .alert)
        controller?.addTextField { $0.placeholder = "Serial Number" }
        controller?.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        controller?.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            let sn = controller?.textFields?.first?.text ?? ""
            var p = BatteryPayload(sn: sn, fu: currentTimestampUTC(), cc: 0, n: 0, u: [])
            nfc.write(p) { raw in store.log(.write, raw: raw); nfc.payload = p }
        }))
        UIApplication.shared.keyWindowTop?.present(controller!, animated: true)
    }

    func addUsage(d: Int, incrementCycle: Bool = false) {
        guard var p = nfc.payload else { return }
        let maxId = p.u.map { $0.i }.max() ?? 0
        let entry = UsageEntry(i: maxId + 1, t: currentTimestampUTC(), d: d, e: 0, v: 0)
        p.u.append(entry)
        if p.u.count > MAX_RECORDS {
            p.u.removeFirst(p.u.count - MAX_RECORDS)
        }
        if incrementCycle { p.cc += 1 }
        nfc.write(p) { raw in store.log(.write, raw: raw); nfc.payload = p }
    }

    func setStatus(_ t: NoteType) {
        guard var p = nfc.payload else { return }
        p.n = t.rawValue
        nfc.write(p) { raw in store.log(.write, raw: raw); nfc.payload = p }
    }
}
