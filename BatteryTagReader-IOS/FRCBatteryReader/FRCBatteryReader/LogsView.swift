//
//  LogsView.swift
//  FRCBatteryReader
//

import SwiftUI
import UIKit

struct LogsView: View {
    @EnvironmentObject var store: LogStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showClearConfirm: Bool = false
    @State private var clearCountdown: Int = 3
    var onSimulateScan: ((String) -> Void)? = nil

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
                        loadDemoTapped()
                    } label: {
                        Label("Load Demo", systemImage: "wand.and.stars")
                    }
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

                    Menu {
                        Button("Get Help") {
                            if let url = URL(string: "https://studenttechsupport.com/support") {
                                openURL(url)
                            }
                        }
                        Button("Privacy Policy") {
                            if let url = URL(string: "https://studenttechsupport.com/privacy") {
                                openURL(url)
                            }
                        }
                    } label: {
                        Label("Support", systemImage: "info.circle")
                    }

                    Button(role: .destructive) {
                        startClearConfirm()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .disabled(store.items.isEmpty)
                }
            }
            .sheet(isPresented: $showClearConfirm) {
                VStack(spacing: 16) {
                    Text("Delete All Logs?")
                        .font(.headline)
                        .padding(.top, 12)
                    Text("This cannot be undone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button("Cancel") {
                            showClearConfirm = false
                        }
                        .buttonStyle(.bordered)

                        Button("Yes" + (clearCountdown > 0 ? " (\(clearCountdown))" : "")) {
                            store.clear()
                            showClearConfirm = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(clearCountdown > 0)
                    }
                    .padding(.bottom, 12)
                }
                .padding()
                .onAppear { clearCountdown = 3 }
                .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                    if showClearConfirm && clearCountdown > 0 { clearCountdown -= 1 }
                }
                .presentationDetents([.height(180)])
            }
        }
    }

    private func startClearConfirm() {
        clearCountdown = 3
        showClearConfirm = true
    }

    // MARK: - Demo Loader
    private func loadDemoTapped() {
        // Build a full demo payload and simulate a scan in the main window.
        let sn = makeDemoSN()
        let fu = makeRandomFUwithinLastYearYYMMDDHHMM()
        let json = makeDemoJSON(sn: sn, fu: fu)

        // Notify parent/host if provided
        onSimulateScan?(json)

        // Also broadcast a notification for any global listeners (e.g., ContentView)
        NotificationCenter.default.post(name: .mockScanJSON, object: json)

        // Close the Logs view
        dismiss()
    }

    private func makeDemoSN() -> String {
        let n = Int.random(in: 0...999)
        return String(format: "DEMO-%03d", n)
    }

    private func makeRandomFUwithinLastYearYYMMDDHHMM() -> String {
        var comps = DateComponents()
        comps.day = -Int.random(in: 0..<365)
        comps.minute = -Int.random(in: 0..<(24*60))
        let cal = Calendar.current
        let base = Date()
        let randomDate = cal.date(byAdding: comps, to: base) ?? base

        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "America/Toronto")
        fmt.dateFormat = "yyMMddHHmm" // YYMMDDHHMM
        return fmt.string(from: randomDate)
    }

    private func makeDemoJSON(sn: String, fu: String) -> String {
        // Choose a starting number in 1...20 and a small number of usage records
        let startNumber = Int.random(in: 1...20)
        let recordCount = Int.random(in: 2...5)

        // Generate usage records with incrementing ids and random times within last year
        var usage: [[String: Any]] = []
        //let cal = Calendar.current
        //let now = Date()
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "America/Toronto")
        fmt.dateFormat = "yyMMddHHmm" // YYMMDDHHMM

        // Build strictly increasing FUTURE timestamps (no "today"), random notes,
        // and ensure no two charger entries (d = 2) are consecutive

        usage.removeAll(keepingCapacity: true)

        let currentdate = Date()
        var lastDate = Calendar.current.startOfDay(for: currentdate) // today @ 00:00
        var lastD = 0
        for i in 0..<recordCount {
            // Advance by at least 1 day to guarantee future (and strictly increasing),
            // then add a random minute offset. Keep within ~1 year horizon.
            let advanceDays = Int.random(in: 1...20)
            let advanceMinutes = Int.random(in: 0..<(24*60))
            if let dayBump = Calendar.current.date(byAdding: .day, value: advanceDays, to: lastDate),
               let finalDate = Calendar.current.date(byAdding: .minute, value: advanceMinutes, to: dayBump) {
                lastDate = finalDate
            }
            let t = fmt.string(from: lastDate)

            // Random device type, but avoid consecutive chargers (d = 2)
            var dVal = Int.random(in: 1...2)
            if lastD == 2 && dVal == 2 { dVal = 1 }
            lastD = dVal

            let eVal = Int.random(in: 10...500)
            let vVal = Int.random(in: 7...14)

            usage.append([
                "id": startNumber + i,
                "t": t,
                "d": dVal,              // 1 = robot, 2 = charger
                "e": eVal,              // energy units
                "v": vVal               // voltage-ish integer
            ])
        }

        let dict: [String: Any] = [
            "sn": sn,
            "fu": fu,
            "n": Int.random(in: 0...2), // 0=normal, 1=practice only, 2=scrap (avoid 3=other for demo)
            "cycle": Int.random(in: 1...10),
            "number": startNumber,
            "usage": usage
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{\"sn\":\"\(sn)\",\"fu\":\"\(fu)\",\"note\":\"Demo battery\",\"cycle\":1,\"number\":\(startNumber)}"
    }

    private func delete(at offsets: IndexSet) {
        store.delete(at: offsets)
    }
}

extension Notification.Name {
    static let mockScanJSON = Notification.Name("MockScanJSON")
}
