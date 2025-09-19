//
//  LogStore.swift
//  FRCBatteryReader
//

import Foundation

enum LogKind: String, Codable {
    case read, write
}

struct RawLogItem: Codable, Identifiable {
    let id: UUID
    let when: Date
    let kind: LogKind
    let raw: String
}

final class LogStore: ObservableObject {
    @Published private(set) var items: [RawLogItem] = []

    private let key = "FRCBatteryReader.Logs"

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([RawLogItem].self, from: data) {
            items = decoded.sorted { $0.when > $1.when }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func log(_ kind: LogKind, raw: String) {
        let entry = RawLogItem(id: UUID(), when: Date(), kind: kind, raw: raw)
        items.insert(entry, at: 0)
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }
}
