//
//  LogStore.swift
//  FRCBatteryReader
//
//  Created by Nathan on 2025-09-13.
//

import Foundation

struct RawLogItem: Identifiable, Codable {
    enum Kind: String, Codable { case read, write }
    var id: UUID = UUID()
    var time: Date
    var type: Kind
    var dataRaw: String
}

final class LogStore: ObservableObject {
    @Published var rawLog: [RawLogItem] = []
    @Published var lastReadRaw: String? = nil

    private let logURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("RawLog.json")
    }()

    func log(_ kind: RawLogItem.Kind, raw: String) {
        if kind == .read, lastReadRaw == raw { return }
        lastReadRaw = raw
        rawLog.append(.init(time: .now, type: kind, dataRaw: raw))
        save()
    }

    func load() {
        do {
            let d = try Data(contentsOf: logURL)
            let arr = try JSONDecoder().decode([RawLogItem].self, from: d)
            self.rawLog = arr
            self.lastReadRaw = arr.last(where: { $0.type == .read })?.dataRaw
        } catch { }
    }

    func save() {
        do {
            let d = try JSONEncoder().encode(rawLog)
            try d.write(to: logURL, options: .atomic)
        } catch { print("log save error", error) }
    }

    func exportCSV() -> URL? {
        let url = logURL.deletingLastPathComponent().appendingPathComponent("BatteryLog.csv")
        var csv = "time,type,data\n"
        let fmt = ISO8601DateFormatter()
        for r in rawLog {
            let t = fmt.string(from: r.time)
            let line = "\(t),\(r.type.rawValue),\"\(r.dataRaw.replacingOccurrences(of: "\"", with: "\"\""))\"\n"
            csv.append(line)
        }
        do {
            try csv.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }
}
