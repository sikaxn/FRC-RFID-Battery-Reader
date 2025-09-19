//
//  Models.swift
//  FRCBatteryReader
//

import Foundation

// Max entries to store on the tag (Android parity)
let MAX_RECORDS = 13

struct UsageEntry: Codable, Identifiable {
    // We keep original field 'i' but also expose Identifiable
    var i: Int
    var t: String  // UTC timestamp, ISO 8601-like or "0000..." sentinel
    var d: Int     // device: 1=robot, 2=charger
    var e: Int     // energy (kJ)
    var v: Int     // voltage

    var id: Int { i }
}

struct BatteryPayload: Codable {
    var sn: String         // serial number
    var fu: String         // first use timestamp UTC
    var cc: Int            // cycle count
    var n: Int             // note type raw
    var u: [UsageEntry]    // usage entries
}

enum NoteType: Int, CaseIterable, Identifiable, Codable {
    case normal = 0
    case practice = 1
    case scrap = 2
    case other = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .normal:   return "Normal"
        case .practice: return "Practice"
        case .scrap:    return "Scrap"
        case .other:    return "Other"
        }
    }
}

// MARK: - Time helpers

func currentTimestampUTC() -> String {
    let df = ISO8601DateFormatter()
    df.timeZone = TimeZone(secondsFromGMT: 0)
    df.formatOptions = [.withInternetDateTime, .withFractionalSeconds] // compact, stable
    return df.string(from: Date())
}

// “0000…“ handling + pretty local rendering
func formatUTCStringToLocal(_ s: String) -> String {
    if isAllZeroTimestamp(s) { return "Date not available" }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso.date(from: s) {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = .current
        return f.string(from: d)
    }

    // Try without fractional seconds
    let isoNoFrac = ISO8601DateFormatter()
    if let d2 = isoNoFrac.date(from: s) {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d2)
    }

    return s
}

func isAllZeroTimestamp(_ s: String) -> Bool {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    for ch in trimmed { if ch != "0" && ch != ":" && ch != "-" && ch != " " && ch != "T" && ch != "Z" { return false } }
    // if nothing but 0s and separators
    return trimmed.replacingOccurrences(of: "0", with: "").trimmingCharacters(in: .whitespacesAndNewlines).count < 6
}
