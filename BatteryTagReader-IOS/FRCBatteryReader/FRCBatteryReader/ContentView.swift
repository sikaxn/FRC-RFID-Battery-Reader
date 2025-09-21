//
//  ContentView.swift
//  FRCBatteryReader
//

import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var nfc = NFCController()
    @EnvironmentObject var store: LogStore

    @State private var showLogs = false
    @State private var showStatusPicker = false

    var body: some View {
        VStack(spacing: 12) {
            // Top actions
            HStack(spacing: 8) {
                Button("Init New") { promptInitNew() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                Button("Set Status") {
                    if nfc.payload != nil { showStatusPicker = true }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                Button("Mock Robot") { addUsage(d: 1) }
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

                            // Legend
                            HStack(spacing: 12) {
                                legendDot(.green, title: "Robot")
                                legendDot(.orange, title: "Charger")
                            }.padding(.bottom, 2)

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
                // Charged (orange)
                Button("Charged") { addUsage(d: 2, incrementCycle: true) }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .frame(maxWidth: .infinity)
                // Scan (blue)
                Button("Scan") { nfc.begin() }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Battery Tag Reader")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("View Logs") { showLogs = true }
            }
        }
        .sheet(isPresented: $showLogs) {
            LogsView(onSimulateScan: { json in
                if let payload = parseDemoJSON(json) {
                    // Do not log demo; just load it like a real scan result
                    nfc.payload = payload
                }
                showLogs = false
            })
            .environmentObject(store)
        }
        .confirmationDialog("Select Note Type",
                            isPresented: $showStatusPicker,
                            titleVisibility: .visible) {
            ForEach(NoteType.allCases) { t in
                Button(t.title) { setStatus(t) }
            }
        }
        .onAppear {
            nfc.onReadRaw = { raw in store.log(.read, raw: raw) }
            store.load()
        }
    }

    // MARK: - Small UI bits

    func legendDot(_ color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body)
        }
    }

    @ViewBuilder
    func noteBadge(_ t: NoteType) -> some View {
        let base: Color = {
            switch t {
            case .practice: return .yellow
            case .scrap: return .red
            case .other: return .blue
            default: return .clear
            }
        }()
        let bg = base.opacity(t == .normal ? 0 : 0.22)
        let stroke = base.opacity(t == .normal ? 0 : 0.9)
        HStack(spacing: 6) {
            if t != .normal {
                Circle().fill(stroke).frame(width: 8, height: 8)
            }
            Text("Note Type: \(t.title)")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(bg))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(stroke, lineWidth: t == .normal ? 0 : 1))
    }

    func usageRow(_ e: UsageEntry) -> some View {
        let stripe = (e.d == 2) ? Color.orange : Color.green
        let dateText = isAllZeroTimestamp(e.t) ? "Date not available" : formatUTCStringToLocal(e.t)
        return HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(stripe)
                .frame(width: 5)
                .cornerRadius(2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("#\(e.i)").font(.headline)
                    Spacer()
                    Text(dateText).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Label((e.d == 2) ? "Charger" : "Robot",
                          systemImage: (e.d == 2) ? "bolt.fill" : "gearshape.2.fill")
                        .font(.footnote)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(((e.d == 2) ? Color.orange : Color.green).opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("E: \(e.e) kJ").font(.footnote)
                    Text("V: \(e.v)").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(stripe.opacity(0.25), lineWidth: 1))
    }

    // MARK: - Actions

    /// Parse demo JSON generated from LogsView into BatteryPayload
    func parseDemoJSON(_ raw: String) -> BatteryPayload? {
        guard let data = raw.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        guard let sn = obj["sn"] as? String else { return nil }
        let fu = (obj["fu"] as? String) ?? "0000000000"
        let cycle = (obj["cycle"] as? Int) ?? (obj["cc"] as? Int) ?? 0
        let noteType = (obj["n"] as? Int) ?? 0

        var usage: [UsageEntry] = []
        if let arr = obj["usage"] as? [[String: Any]] {
            for e in arr {
                let i = (e["id"] as? Int) ?? 0
                let t = (e["t"] as? String) ?? "0000000000"
                let d = (e["d"] as? Int) ?? 1 // 1 robot, 2 charger (default robot)
                let en = (e["e"] as? Int) ?? 0
                let v = (e["v"] as? Int) ?? 0
                usage.append(UsageEntry(i: i, t: t, d: d, e: en, v: v))
            }
        }
        // Cap to MAX_RECORDS if defined
        if usage.count > MAX_RECORDS { usage = Array(usage.suffix(MAX_RECORDS)) }

        return BatteryPayload(sn: sn, fu: fu, cc: cycle, n: noteType, u: usage)
    }

    func promptInitNew() {
        var controller: UIAlertController?
        controller = UIAlertController(title: "Enter Serial Number", message: nil, preferredStyle: .alert)
        controller?.addTextField { tf in
            tf.placeholder = "Serial Number"
            tf.autocapitalizationType = .allCharacters
            tf.clearButtonMode = .whileEditing
        }
        controller?.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        controller?.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            let sn = controller?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var p = BatteryPayload(sn: sn, fu: currentTimestampUTC(), cc: 0, n: 0, u: [])
            // Cap to 13 just in case
            if p.u.count > MAX_RECORDS { p.u = Array(p.u.suffix(MAX_RECORDS)) }
            controller?.dismiss(animated: true) {
                nfc.write(p) { raw in
                    store.log(.write, raw: raw)
                    nfc.payload = p
                }
            }
        }))
        UIApplication.shared.keyWindowTop?.present(controller!, animated: true)
    }

    func addUsage(d: Int, incrementCycle: Bool = false) {
        guard var p = nfc.payload else {
            let ac = UIAlertController(title: "No tag loaded", message: "Scan a battery tag first.", preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            UIApplication.shared.keyWindowTop?.present(ac, animated: true)
            return
        }
        let maxId = p.u.map { $0.i }.max() ?? 0
        let entry = UsageEntry(i: maxId + 1, t: currentTimestampUTC(), d: d, e: 0, v: 0)
        p.u.append(entry)
        if p.u.count > MAX_RECORDS { p.u.removeFirst(p.u.count - MAX_RECORDS) }
        if incrementCycle { p.cc += 1 }

        nfc.write(p) { raw in
            store.log(.write, raw: raw)
            nfc.payload = p
        }
    }

    func setStatus(_ t: NoteType) {
        guard var p = nfc.payload else {
            let ac = UIAlertController(title: "No tag loaded", message: "Scan a battery tag first.", preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            UIApplication.shared.keyWindowTop?.present(ac, animated: true)
            return
        }
        p.n = t.rawValue
        nfc.write(p) { raw in
            store.log(.write, raw: raw)
            nfc.payload = p
        }
    }
}
