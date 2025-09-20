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

/// Current timestamp in **UTC** as numeric **YYMMDDHHMM** (all digits).
func currentTimestampUTC() -> String {
    let tzUTC = TimeZone(secondsFromGMT: 0)!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tzUTC
    let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
    let yy = (c.year ?? 2000) % 100
    let mo = c.month ?? 0
    let dd = c.day ?? 0
    let hh = c.hour ?? 0
    let mm = c.minute ?? 0
    return String(format: "%02d%02d%02d%02d%02d", yy, mo, dd, hh, mm)
}

/// Render either our numeric **YYMMDDHHMM** or legacy ISO string into local user time.
/// If value represents all zeros, returns "Date not available".
func formatUTCStringToLocal(_ s: String) -> String {
    if isAllZeroTimestamp(s) { return "Date not available" }

    // Prefer numeric YYMMDDHHMM (interpreted as UTC) → local display
    if let d = parseYYMMDDHHMMAsUTC(s) {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = .current
        f.timeZone = .current
        return f.string(from: d)
    }

    // Fallback: legacy ISO-8601 parsing
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso.date(from: s) {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = .current
        return f.string(from: d)
    }
    let isoNoFrac = ISO8601DateFormatter()
    if let d2 = isoNoFrac.date(from: s) {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d2)
    }

    return s
}

/// Heuristic: treat strings of all '0' (optionally with separators) as unavailable.
func isAllZeroTimestamp(_ s: String) -> Bool {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    // Exact numeric all-zero (e.g., "0000000000")
    if trimmed.allSatisfy({ $0 == "0" }) { return true }
    // Generic: if the string contains only digits and separators, and all digits are zero
    let digits = trimmed.compactMap { $0.isNumber ? $0 : nil }
    if digits.isEmpty { return false }
    return digits.allSatisfy { $0 == "0" }
}

/// Parse numeric YYMMDDHHMM as **UTC** date; returns nil if format invalid.
private func parseYYMMDDHHMMAsUTC(_ s: String) -> Date? {
    let chars = Array(s)
    guard chars.count == 10, chars.allSatisfy({ $0.isNumber }) else { return nil }
    guard let yy = Int(String(chars[0...1])),
          let mo = Int(String(chars[2...3])),
          let dd = Int(String(chars[4...5])),
          let hh = Int(String(chars[6...7])),
          let mm = Int(String(chars[8...9])) else { return nil }
    var comps = DateComponents()
    comps.timeZone = TimeZone(secondsFromGMT: 0)
    comps.year = 2000 + yy
    comps.month = mo
    comps.day = dd
    comps.hour = hh
    comps.minute = mm
    return Calendar(identifier: .gregorian).date(from: comps)
}
