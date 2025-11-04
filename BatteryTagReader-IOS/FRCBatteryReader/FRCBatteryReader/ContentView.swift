//
//  ContentView.swift
//  FRCBatteryReader
//

import SwiftUI
import UIKit
import Foundation
import Combine
struct ContentView: View {
    @EnvironmentObject var nfc: NFCController
    @EnvironmentObject var store: LogStore

    @State private var showLogs = false
    @State private var showStatusPicker = false

    // New state variables for init new sheet
    @State private var showInitSheet = false
    @AppStorage("initMode") private var initMode = 0
    @State private var manualSN = ""
    @AppStorage("teamNumber") private var teamNumber = ""
    @AppStorage("batteryType") private var batteryType = 0 // 0: New, 1: Old, 2: Special
    @State private var batteryID = ""

    var body: some View {
        VStack(spacing: 12) {
            // Top actions
            HStack(spacing: 8) {
                Button("Init New") {
                    nfc.canWriteTag = false
                    showInitSheet = true
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                Button("Set Status") {
                    nfc.canWriteTag = false
                    if nfc.payload != nil { showStatusPicker = true }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                Button("Mock Robot") {
                    nfc.canWriteTag = false
                    addUsage(d: 1)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let p = nfc.payload {
                        labeled(Text("Serial Number"), Text(p.sn))
                        labeled(Text("First Use"), Text(formatUTCStringToLocal(p.fu)))
                        labeled(Text("Cycle Count"), Text("\(p.cc)"))
                        noteBadge(NoteType(rawValue: p.n) ?? .normal)

                        if !p.u.isEmpty {
                            Text("Usage Log:")
                                .font(.headline)
                                .padding(.top, 8)

                            // Legend
                            HStack(spacing: 12) {
                                legendDot(.green, title: String(localized: "legend_robot"))
                                legendDot(.orange, title: String(localized: "legend_charger"))
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
                Button("Charged") {
                    addUsage(d: 2, incrementCycle: true)
                    nfc.canWriteTag = false
                }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .frame(maxWidth: .infinity)
                // Write Tag (red) - appears only when canWriteTag is true and nfc.payload != nil
                if nfc.canWriteTag, nfc.payload != nil {
                    Button("Write Tag") {
                        if let payload = nfc.payload {
                            nfc.canWriteTag = false
                            nfc.write(payload) { raw in
                                store.log(.write, raw: raw)
                                SoundHelper.shared.play(note: NoteType(rawValue: payload.n) ?? .normal)
                            }
                        } else {
                            nfc.canWriteTag = false
                            nfc.begin()
                        }
                    }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .frame(maxWidth: .infinity)
                }
                // Scan (blue)
                Button("Scan") {
                    nfc.canWriteTag = false
                    nfc.begin()
                }
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: { shareBatteryJSON() }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share")
                Button("View Logs") { showLogs = true }
            }
        }
        .sheet(isPresented: $showLogs) {
            LogsView(onSimulateScan: { json in
                if let payload = parseDemoJSON(json) {
                    // Do not log demo; just load it like a real scan result
                    nfc.payload = payload
                    nfc.canWriteTag = false
                    // Play chime for demo loads as well
                    SoundHelper.shared.play(note: NoteType(rawValue: payload.n) ?? .normal)
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
        .sheet(isPresented: $showInitSheet) {
            VStack(spacing: 16) {
                Picker("Mode", selection: $initMode) {
                    Text("Manual").tag(0)
                    Text("BEST Scheme").tag(1)
                }
                .pickerStyle(.segmented)

                if initMode == 0 {
                    TextField("Serial Number (ASCII, max 8)", text: $manualSN)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: manualSN) { _, newValue in
                            manualSN = String(newValue.prefix(8).filter { $0.isASCII })
                        }
                } else {
                    // Show Team Number for all modes except manual
                    TextField("Team Number (max 5 digits)", text: $teamNumber)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: teamNumber) { _, newValue in
                            teamNumber = String(newValue.prefix(5).filter { $0.isNumber })
                        }
                    Picker("Battery Type", selection: $batteryType) {
                        Text("New").tag(0)
                        Text("Old").tag(1)
                        Text("Special").tag(2)
                    }
                    .pickerStyle(.segmented)
                    if batteryType == 0 {
                        TextField("Battery ID (000–899)", text: $batteryID)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: batteryID) { _, newValue in
                                let maxLen = 3
                                batteryID = String(newValue.prefix(maxLen).filter { $0.isNumber })
                            }
                    } else if batteryType == 1 {
                        TextField("Battery ID (00–98)", text: $batteryID)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: batteryID) { _, newValue in
                                let maxLen = 2
                                batteryID = String(newValue.prefix(maxLen).filter { $0.isNumber })
                            }
                    } else if batteryType == 2 {
                        Text("Special: Serial Number will end in 999.")
                            .foregroundColor(.secondary)
                    }
                    Text("BEST Battery ID Format: tttttnnn — team padded to 5, nnn = 000–899 (New), 00–98 (Old), 999 (Special). Reserved 900–999.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // Live preview area
                let preview = generatePreview()
                if preview == "Illegal input" {
                    Text("Illegal input")
                        .font(.headline)
                        .foregroundColor(.red)
                } else if let preview = preview {
                    Text("Preview: \(preview)")
                        .font(.headline)
                        .foregroundColor(.primary)
                } else {
                    Text("Incomplete data — preview unavailable")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Button("Cancel") { showInitSheet = false }
                    Spacer()
                    Button("OK") { confirmInit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(generatePreview() == nil || generatePreview() == "Illegal input")
                }
            }
            .padding()
            .presentationDetents([.medium])
        }
        .onAppear {
            nfc.onReadRaw = { raw in
                // Always log the raw payload.
                store.log(.read, raw: raw)
                // Play chime on every successful read, even if the note hasn't changed.
                if let data = raw.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let n = obj["n"] as? Int {
                    SoundHelper.shared.play(note: NoteType(rawValue: n) ?? .normal)
                } else if let p = nfc.payload {
                    // Fallback: if parsing fails, use the last payload in memory.
                    SoundHelper.shared.play(for: p)
                }
                // Reset canWriteTag after scanning a new tag
                nfc.canWriteTag = false
            }
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

    func labeled(_ title: Text, _ value: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title.font(.caption).foregroundStyle(.secondary)
            value.font(.body)
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

    /*
    // Original UIAlertController-based promptInitNew implementation commented out for reference
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
    */

    func confirmInit() {
        guard let sn = generatePreview() else { return }
        var p = BatteryPayload(sn: sn, fu: currentTimestampUTC(), cc: 0, n: 0, u: [])
        if p.u.count > MAX_RECORDS { p.u = Array(p.u.suffix(MAX_RECORDS)) }
        nfc.write(p) { raw in
            store.log(.write, raw: raw)
            nfc.payload = p
            nfc.canWriteTag = false
        }
        showInitSheet = false
    }

    // Helper function for live preview and confirmInit
    func generatePreview() -> String? {
        if initMode == 0 {
            guard !manualSN.isEmpty else { return nil }
            return manualSN
        }
        // Team number validation
        guard teamNumber.count > 0 else { return nil }
        guard let team = Int(teamNumber) else { return "Illegal input" }
        let teamStr = String(team)
        let paddedTeam = teamStr + String(repeating: "-", count: max(0, 5 - teamStr.count))
        switch batteryType {
        case 0: // New
            guard batteryID.count > 0 else { return nil }
            guard let id = Int(batteryID) else { return "Illegal input" }
            guard (0...899).contains(id) else { return "Illegal input" }
            return paddedTeam + String(format: "%03d", id)
        case 1: // Old
            guard batteryID.count > 0 else { return nil }
            guard let id = Int(batteryID) else { return "Illegal input" }
            guard (0...98).contains(id) else { return "Illegal input" }
            return paddedTeam + String(format: "9%02d", id)
        case 2: // Special
            return paddedTeam + "999"
        default:
            return nil
        }
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
            nfc.canWriteTag = false
        }
    }

    // MARK: - Share functionality
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var showShareAlert = false

    func shareBatteryJSON() {
        // Determine which JSON to use: current payload or demo payload
        guard let payload = nfc.payload else {
            // Show alert if no tag loaded
            let ac = UIAlertController(title: "No tag loaded", message: "Scan a battery tag first.", preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            UIApplication.shared.keyWindowTop?.present(ac, animated: true)
            return
        }
        // Convert payload to JSON dictionary
        let dict: [String: Any] = [
            "sn": payload.sn,
            "fu": payload.fu,
            "cc": payload.cc,
            "n": payload.n,
            "usage": payload.u.map { e in
                [
                    "id": e.i,
                    "t": e.t,
                    "d": e.d,
                    "e": e.e,
                    "v": e.v
                ]
            }
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
            let fileManager = FileManager.default
            let tmpDir = fileManager.temporaryDirectory
            let fileName = "\(payload.sn).BEST.json"
            let fileURL = tmpDir.appendingPathComponent(fileName)
            try data.write(to: fileURL)
            // Present share sheet
            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.windows.first?.rootViewController {
                root.present(activityVC, animated: true)
            }
        } catch {
            let ac = UIAlertController(title: "Export failed", message: "Could not export battery JSON.", preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            UIApplication.shared.keyWindowTop?.present(ac, animated: true)
        }
    }

    // MARK: - Import functionality
    /// Load a JSON file from a URL, parse, update NFC payload, log and chime.
    func handleIncomingJSON(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            guard let jsonStr = String(data: data, encoding: .utf8) else { return }

            if let payload = parseDemoJSON(jsonStr) {
                // Update current NFC payload
                nfc.payload = payload
                // Log the imported data
                store.log(.read, raw: jsonStr)
                // Play the appropriate chime
                SoundHelper.shared.play(note: NoteType(rawValue: payload.n) ?? .normal)
                // Allow writing this imported tag
                nfc.canWriteTag = true
            } else {
                print("Invalid battery JSON structure.")
            }
        } catch {
            print("Failed to open JSON from URL: \(error)")
        }
    }

    // Write imported JSON data to NFC tag
    func writeTagFromImportedJSON() {
        guard let payload = nfc.payload else { return }
        nfc.write(payload) { raw in
            store.log(.write, raw: raw)
            SoundHelper.shared.play(note: NoteType(rawValue: payload.n) ?? .normal)
            nfc.canWriteTag = false
        }
    }
}
