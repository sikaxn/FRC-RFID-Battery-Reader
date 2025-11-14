//
//  BatteryHtmlGenerator.swift
//  FRCBatteryReader
//

import Foundation

struct BatteryHtmlGenerator {

    // MARK: - Public API

    static func generateHTML(from p: BatteryPayload) -> String {
        let sn = p.sn
        let fu = fmtTime(p.fu)
        let cc = p.cc
        let n = p.n

        let note: String
        switch n {
        case 1: note = "Practice"
        case 2: note = "Scrap"
        case 3: note = "Other"
        default: note = "Normal"
        }

        let usage = p.u

        var totalReads = 0
        var totalCharges = 0
        for ent in usage {
            switch ent.d {
            case 1: totalReads += 1
            case 2: totalCharges += 1
            default: break
            }
        }
        let totalRecords = usage.count

        let now = formatNow()

        var html = ""
        html.append("<!DOCTYPE html>\n<html lang='en'><head>\n")
        html.append("<meta charset='utf-8' />\n")
        html.append("<title>Battery Report — ")
        html.append(esc(sn))
        html.append("</title>\n")
        html.append("<meta name='viewport' content='width=device-width, initial-scale=1' />\n")
        html.append("<style>\n")
        html.append("  :root { --fg:#000; --muted:#222; --line:#000; --bg:#fff; }\n")
        html.append("  * { box-sizing:border-box; }\n")
        html.append("  html, body { background:var(--bg); color:var(--fg); }\n")
        html.append("  body { margin:24px; font:12px/1.35 system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif; }\n")
        html.append("  h1 { margin:0 0 6px; font-size:16px; font-weight:700; }\n")
        html.append("  h2 { margin:14px 0 6px; font-size:13px; font-weight:700; }\n")
        html.append("  .grid { display:grid; grid-template-columns:160px 1fr 120px 1fr; gap:6px 10px; padding:8px; border:1px solid var(--line); }\n")
        html.append("  .k { color:var(--muted); text-align:right; }\n")
        html.append("  .code { font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; }\n")
        html.append("  table { width:100%; border-collapse:collapse; }\n")
        html.append("  th,td { border-top:1px solid var(--line); padding:4px 6px; vertical-align:top; }\n")
        html.append("  thead th { text-align:left; border-top:none; font-size:11px; font-weight:700; }\n")
        html.append("  .num { text-align:right; font-variant-numeric:tabular-nums; }\n")
        html.append("  .muted { color:#444; }\n")
        html.append("  .foot { margin-top:8px; font-size:11px; color:#111; }\n")
        html.append("  .charger-row { background:#000; color:#fff; }\n")
        html.append("  @page { size: letter; margin: 0.5in; }\n")
        html.append("  @media print { body { margin:0; } * { -webkit-print-color-adjust: exact; print-color-adjust: exact; } }\n")
        html.append("</style>\n")
        // NOTE: intentionally NOT adding the auto-print script from Android
        html.append("</head>\n<body>\n")
        html.append("<h1>Battery Report</h1>\n")
        html.append("<div class='grid'>\n")
        html.append("  <div class='k'>Serial Number (sn):</div><div class='code'>")
        html.append(esc(sn))
        html.append("</div>\n")
        html.append("  <div class='k'>First Use (fu):</div><div>")
        html.append(esc(fu))
        html.append("</div>\n")
        html.append("  <div class='k'>Cycle Count (cc):</div><div class='code'>")
        html.append(String(cc))
        html.append("</div>\n")
        html.append("  <div class='k'>Note (n):</div><div class='code'>")
        html.append(String(n))
        html.append(" — ")
        html.append(esc(note))
        html.append("</div>\n")
        html.append("</div>\n\n")

        html.append("<h2>Usage</h2>\n<table>\n<thead>\n<tr>\n")
        html.append("<th style='width:48px'>#</th>\n<th style='width:160px'>Time</th>\n<th style='width:110px'>Device</th>\n")
        html.append("<th class='num' style='width:90px'>e</th>\n<th class='num' style='width:90px'>v</th>\n")
        html.append("</tr>\n</thead>\n<tbody>\n")
        html.append(renderUsageRows(usage, maxRows: 36))
        html.append("\n</tbody>\n</table>\n\n")

        html.append("<h2>Stats</h2>\n<div class='grid' style='grid-template-columns:160px 1fr 160px 1fr;'>\n")
        html.append("  <div class='k'>Robot records:</div><div class='code'>")
        html.append(String(totalReads))
        html.append("</div>\n")
        html.append("  <div class='k'>Charger records:</div><div class='code'>")
        html.append(String(totalCharges))
        html.append("</div>\n")
        html.append("  <div class='k'>Total records (u):</div><div class='code'>")
        html.append(String(totalRecords))
        html.append("</div>\n")
        html.append("  <div class='k'>Generated:</div><div>")
        html.append(esc(now))
        html.append("</div>\n")
        html.append("</div>\n\n")

        html.append("<div class='foot'>This report only represents the data currently stored on the NFC tag.</div>\n")
        html.append("</body></html>")

        return html
    }

    // MARK: - Helpers (match Java behavior)

    /// Equivalent to Java fmtTime():
    /// - Input format: "yyMMddHHmm"
    /// - Output format: "yyyy-MM-dd HH:mm" in *local* time
    /// - "0000000000" → "Date not available"
    private static func fmtTime(_ t: String?) -> String {
        guard let t = t, t != "0000000000" else {
            return "Date not available"
        }
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyMMddHHmm"
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        // default timeZone = current (local), which is what we want

        let outFmt = DateFormatter()
        outFmt.dateFormat = "yyyy-MM-dd HH:mm"
        outFmt.locale = Locale(identifier: "en_US_POSIX")
        outFmt.timeZone = .current

        if let d = inFmt.date(from: t) {
            return outFmt.string(from: d)
        } else {
            // Same as Java: on parse error, just return original string
            return t
        }
    }

    /// Escape &, <, > like Java esc()
    private static func esc(_ s: String) -> String {
        var result = s
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        return result
    }

    /// Render usage rows identical to Java renderUsageRows()
    private static func renderUsageRows(_ usage: [UsageEntry], maxRows: Int) -> String {
        var parts = ""

        // sort by i descending
        var rows = usage.sorted { $0.i > $1.i }

        var extra = 0
        if rows.count > maxRows {
            extra = rows.count - maxRows
            rows = Array(rows.prefix(maxRows))
        }

        for ent in rows {
            let i = ent.i
            let t = fmtTime(ent.t)
            let d = ent.d
            let device: String
            if d == 1 { device = "Robot" }
            else if d == 2 { device = "Charger" }
            else { device = "Unknown" }

            let e = ent.e
            let v = ent.v
            let rowClass = (d == 2) ? " class='charger-row'" : ""

            parts.append("<tr")
            parts.append(rowClass)
            parts.append(">")
            parts.append("<td class='num'>")
            parts.append(String(i))
            parts.append("</td>")
            parts.append("<td>")
            parts.append(esc(t))
            parts.append("</td>")
            parts.append("<td>")
            parts.append(esc(device))
            parts.append("</td>")
            parts.append("<td class='num'>")
            parts.append(String(e))
            parts.append("</td>")
            parts.append("<td class='num'>")
            parts.append(String(v))
            parts.append("</td>")
            parts.append("</tr>")
        }

        if rows.isEmpty {
            parts.append("<tr><td colspan='5' class='muted'>No usage records.</td></tr>")
        }
        if extra > 0 {
            parts.append("<tr><td colspan='5' class='muted'>(+")
            parts.append(String(extra))
            parts.append(" more not shown)</td></tr>")
        }

        return parts
    }

    /// "Generated" timestamp: "yyyy-MM-dd HH:mm:ss" local, matching Java
    private static func formatNow() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        return df.string(from: Date())
    }
}
