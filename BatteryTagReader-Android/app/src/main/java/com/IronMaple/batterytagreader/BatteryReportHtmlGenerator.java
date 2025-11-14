package com.IronMaple.batterytagreader;

import org.json.*;
import java.text.*;
import java.util.*;

public class BatteryReportHtmlGenerator {

    private static String fmtTime(String t) {
        if (t == null || t.equals("0000000000")) return "Date not available";
        try {
            Date d = new SimpleDateFormat("yyMMddHHmm", Locale.US).parse(t);
            return new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(d);
        } catch (Exception e) {
            return t;
        }
    }

    private static String esc(String s) {
        if (s == null) return "";
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }

    private static String renderUsageRows(JSONArray usage, int maxRows) throws JSONException {
        StringBuilder parts = new StringBuilder();
        List<JSONObject> rows = new ArrayList<>();

        // sort by i descending
        for (int i = 0; i < usage.length(); i++) rows.add(usage.getJSONObject(i));
        rows.sort((a, b) -> Integer.compare(b.optInt("i", 0), a.optInt("i", 0)));

        int extra = 0;
        if (rows.size() > maxRows) {
            extra = rows.size() - maxRows;
            rows = rows.subList(0, maxRows);
        }

        for (JSONObject ent : rows) {
            int i = ent.optInt("i", 0);
            String t = fmtTime(ent.optString("t", ""));
            int d = ent.optInt("d", 0);            String device = (d == 1) ? "Robot" : (d == 2) ? "Charger" : "Unknown";
            int e = ent.optInt("e", 0);
            int v = ent.optInt("v", 0);
            String rowClass = (d == 2) ? " class='charger-row'" : "";
            parts.append("<tr").append(rowClass).append(">")
                    .append("<td class='num'>").append(i).append("</td>")
                    .append("<td>").append(esc(t)).append("</td>")
                    .append("<td>").append(esc(device)).append("</td>")
                    .append("<td class='num'>").append(e).append("</td>")
                    .append("<td class='num'>").append(v).append("</td>")
                    .append("</tr>");
        }

        if (rows.isEmpty()) {
            parts.append("<tr><td colspan='5' class='muted'>No usage records.</td></tr>");
        }
        if (extra > 0) {
            parts.append("<tr><td colspan='5' class='muted'>(+")
                    .append(extra).append(" more not shown)</td></tr>");
        }
        return parts.toString();
    }

    public static String generateHtml(JSONObject doc) throws JSONException {
        String sn = doc.optString("sn", "");
        String fu = fmtTime(doc.optString("fu", "0000000000"));
        int cc = doc.optInt("cc", 0);
        int n = doc.optInt("n", 0);
        String note;
        switch (n) {
            case 1:
                note = "Practice";
                break;
            case 2:
                note = "Scrap";
                break;
            case 3:
                note = "Other";
                break;
            default:
                note = "Normal";
                break;
        }


        JSONArray usage = doc.optJSONArray("u");
        if (usage == null) usage = new JSONArray();

        int totalReads = 0, totalCharges = 0;
        for (int i = 0; i < usage.length(); i++) {
            int d = usage.getJSONObject(i).optInt("d", 0);
            if (d == 1) totalReads++;
            else if (d == 2) totalCharges++;
        }
        int totalRecords = usage.length();
        String now = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(new Date());

        // --- Build full HTML identical to battery_print.py ---
        StringBuilder html = new StringBuilder();
        html.append("<!DOCTYPE html>\n<html lang='en'><head>\n")
                .append("<meta charset='utf-8' />\n")
                .append("<title>Battery Report — ").append(esc(sn)).append("</title>\n")
                .append("<meta name='viewport' content='width=device-width, initial-scale=1' />\n")
                .append("<style>\n")
                .append("  :root { --fg:#000; --muted:#222; --line:#000; --bg:#fff; }\n")
                .append("  * { box-sizing:border-box; }\n")
                .append("  html, body { background:var(--bg); color:var(--fg); }\n")
                .append("  body { margin:24px; font:12px/1.35 system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif; }\n")
                .append("  h1 { margin:0 0 6px; font-size:16px; font-weight:700; }\n")
                .append("  h2 { margin:14px 0 6px; font-size:13px; font-weight:700; }\n")
                .append("  .grid { display:grid; grid-template-columns:160px 1fr 120px 1fr; gap:6px 10px; padding:8px; border:1px solid var(--line); }\n")
                .append("  .k { color:var(--muted); text-align:right; }\n")
                .append("  .code { font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; }\n")
                .append("  table { width:100%; border-collapse:collapse; }\n")
                .append("  th,td { border-top:1px solid var(--line); padding:4px 6px; vertical-align:top; }\n")
                .append("  thead th { text-align:left; border-top:none; font-size:11px; font-weight:700; }\n")
                .append("  .num { text-align:right; font-variant-numeric:tabular-nums; }\n")
                .append("  .muted { color:#444; }\n")
                .append("  .foot { margin-top:8px; font-size:11px; color:#111; }\n")
                .append("  .charger-row { background:#000; color:#fff; }\n")
                .append("  @page { size: letter; margin: 0.5in; }\n")
                .append("  @media print { body { margin:0; } * { -webkit-print-color-adjust: exact; print-color-adjust: exact; } }\n")
                .append("</style>\n")
                .append("<script>window.addEventListener('load',function(){setTimeout(function(){window.print();},100);});</script>\n")
                .append("</head>\n<body>\n")
                .append("<h1>Battery Report</h1>\n")
                .append("<div class='grid'>\n")
                .append("  <div class='k'>Serial Number (sn):</div><div class='code'>").append(esc(sn)).append("</div>\n")
                .append("  <div class='k'>First Use (fu):</div><div>").append(esc(fu)).append("</div>\n")
                .append("  <div class='k'>Cycle Count (cc):</div><div class='code'>").append(cc).append("</div>\n")
                .append("  <div class='k'>Note (n):</div><div class='code'>").append(n).append(" — ").append(esc(note)).append("</div>\n")
                .append("</div>\n\n")
                .append("<h2>Usage</h2>\n<table>\n<thead>\n<tr>\n")
                .append("<th style='width:48px'>#</th>\n<th style='width:160px'>Time</th>\n<th style='width:110px'>Device</th>\n")
                .append("<th class='num' style='width:90px'>e</th>\n<th class='num' style='width:90px'>v</th>\n")
                .append("</tr>\n</thead>\n<tbody>\n")
                .append(renderUsageRows(usage, 36))
                .append("\n</tbody>\n</table>\n\n")
                .append("<h2>Stats</h2>\n<div class='grid' style='grid-template-columns:160px 1fr 160px 1fr;'>\n")
                .append("  <div class='k'>Robot records:</div><div class='code'>").append(totalReads).append("</div>\n")
                .append("  <div class='k'>Charger records:</div><div class='code'>").append(totalCharges).append("</div>\n")
                .append("  <div class='k'>Total records (u):</div><div class='code'>").append(totalRecords).append("</div>\n")
                .append("  <div class='k'>Generated:</div><div>").append(esc(now)).append("</div>\n")
                .append("</div>\n\n")
                .append("<div class='foot'>This report only represents the data currently stored on the NFC tag.</div>\n")
                .append("</body></html>");

        return html.toString();
    }
}
