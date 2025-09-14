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
            // Top actions
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

            // Content
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
                            HStack(spacing: 12) {
                                HStack(spacing: 6) {
                                    Circle().fill(Color.green).frame(width: 8, height: 8)
                                    Text("Robot").font(.caption).foregroundStyle(.secondary)
                                }
                                HStack(spacing: 6) {
                                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                                    Text("Charger").font(.caption).foregroundStyle(.secondary)
                                }
                            }
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
        // Bottom actions
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Button("Charged") { addUsage(d: 2, incrementCycle: true) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                Button("Set Status") {
                    if nfc.payload != nil { showStatusPicker = true }
                }
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
        .confirmationDialog("Select Note Type",
                            isPresented: $showStatusPicker,
                            titleVisibility: .visible) {
            ForEach(NoteType.allCases) { t in
                Button(t.title) { setStatus(t) }
            }
        }
        .onAppear {
            // hook read logging and load persisted logs
            nfc.onReadRaw = { raw in store.log(.read, raw: raw) }
            store.load()
        }
    }

    // MARK: - Color helpers (Android-like colors)
    private func deviceColor(_ d: Int) -> Color {
        // 1 = robot (green), 2 = charger (orange)
        return (d == 2) ? Color.orange : Color.green
    }

    private func noteColor(_ t: NoteType) -> Color {
        switch t {
        case .practice: return .yellow
        case .scrap: return .red
        case .other: return .blue
        default: return .clear
        }
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
        let bg = noteColor(t).opacity(t == .normal ? 0.0 : 0.22)
        let stroke = noteColor(t).opacity(t == .normal ? 0.0 : 0.9)
        HStack(spacing: 6) {
            if t != .normal {
                Circle().fill(stroke).frame(width: 8, height: 8)
            }
            Text("Note Type: \(t.title)")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(stroke, lineWidth: t == .normal ? 0 : 1)
        )
    }

    func usageRow(_ e: UsageEntry) -> some View {
        let stripe = deviceColor(e.d)
        return HStack(alignment: .top, spacing: 10) {
            // Leading colored stripe
            Rectangle()
                .fill(stripe)
                .frame(width: 5)
                .cornerRadius(2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("#\(e.i)")
                        .font(.headline)
                    Spacer()
                    let isAllZeros = e.t.trimmingCharacters(in: .whitespacesAndNewlines).allSatisfy { $0 == "0" }
                    Text(isAllZeros ? "Date not available" : formatUTCStringToLocal(e.t))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Label((e.d == 2) ? "Charger" : "Robot", systemImage: (e.d == 2) ? "bolt.fill" : "gearshape.2.fill")
                        .font(.footnote)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(deviceColor(e.d).opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("E: \(e.e) kJ")
                        .font(.footnote)
                    Text("V: \(e.v)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(stripe.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Actions (write-safe sequencing)
    func promptInitNew() {
        var controller: UIAlertController?
        controller = UIAlertController(title: "Enter Serial Number", message: nil, preferredStyle: .alert)
        controller?.addTextField { $0.placeholder = "Serial Number" }
        controller?.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        controller?.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            let sn = controller?.textFields?.first?.text ?? ""
            let p = BatteryPayload(sn: sn, fu: currentTimestampUTC(), cc: 0, n: 0, u: [])

            controller?.dismiss(animated: true) {
                DispatchQueue.main.async {
                    nfc.write(p) { raw in
                        store.log(.write, raw: raw)
                        nfc.payload = p
                    }
                }
            }
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

        DispatchQueue.main.async {
            nfc.write(p) { raw in
                store.log(.write, raw: raw)
                nfc.payload = p
            }
        }
    }

    func setStatus(_ t: NoteType) {
        guard var p = nfc.payload else { return }
        p.n = t.rawValue

        DispatchQueue.main.async {
            nfc.write(p) { raw in
                store.log(.write, raw: raw)
                nfc.payload = p
            }
        }
    }
}
