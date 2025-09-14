//
//  Models.swift
//  FRCBatteryReader
//
//  Created by Nathan on 2025-09-13.
//

import Foundation

struct UsageEntry: Identifiable, Codable {
    var id: Int { i }
    var i: Int
    var t: String // "yyMMddHHmm" UTC
    var d: Int    // 1=robot, 2=charger
    var e: Int    // energy kJ
    var v: Int    // voltage (scaled)
}

struct BatteryPayload: Codable {
    var sn: String
    var fu: String // first use UTC
    var cc: Int
    var n: Int     // note type 0..3
    var u: [UsageEntry]
}

enum NoteType: Int, CaseIterable, Identifiable {
    case normal = 0, practice = 1, scrap = 2, other = 3
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .normal: return "Normal"
        case .practice: return "Practice Only"
        case .scrap: return "Scrap"
        case .other: return "Other"
        }
    }
}

func currentTimestampUTC() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyMMddHHmm"
    f.timeZone = .init(abbreviation: "UTC")
    return f.string(from: Date())
}

func formatUTCStringToLocal(_ raw: String) -> String {
    let src = DateFormatter()
    src.dateFormat = "yyMMddHHmm"
    src.timeZone = .init(abbreviation: "UTC")
    let dst = DateFormatter()
    dst.dateFormat = "yyyy-MM-dd HH:mm"
    dst.timeZone = .current
    if let d = src.date(from: raw) {
        return dst.string(from: d)
    } else {
        return raw
    }
}

let MAX_RECORDS = 14
