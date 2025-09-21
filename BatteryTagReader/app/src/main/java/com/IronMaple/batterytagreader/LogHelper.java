package com.IronMaple.batterytagreader;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class LogHelper {

    private static final String PREF_NAME = "BatteryTagLog";
    private static final String LOG_KEY = "log_data";
    private static JSONObject lastLogged = null;
    private static final String LAST_LOGGED_KEY = "last_logged_raw";


    public static void log(Context context, String type, JSONObject data) {
        if (data == null) return;

        String raw = data.toString();

        SharedPreferences prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        String lastRaw = prefs.getString(LAST_LOGGED_KEY, null);
        if (raw.equals(lastRaw)) return;  // skip duplicate

        try {
            JSONArray log = new JSONArray(prefs.getString(LOG_KEY, "[]"));

            JSONObject entry = new JSONObject();
            SimpleDateFormat utcFormat = new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US);
            utcFormat.setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
            entry.put("time", utcFormat.format(new Date()));

            entry.put("type", type);
            entry.put("data", data);

            log.put(entry);

            prefs.edit()
                    .putString(LOG_KEY, log.toString())
                    .putString(LAST_LOGGED_KEY, raw)
                    .apply();
        } catch (Exception ignored) {}
    }

    public static JSONArray getLog(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        try {
            return new JSONArray(prefs.getString(LOG_KEY, "[]"));
        } catch (Exception e) {
            return new JSONArray();
        }
    }

    public static void clearLog(Context context) {
        context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit().remove(LOG_KEY).apply();
    }
    public static String getLastLoggedRaw(Context context) {
        return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getString(LAST_LOGGED_KEY, null);
    }

}

    // --- Demo JSON generation utilities for MainActivity ---
    public static String generateDemoJson() {
        try {
            JSONObject root = new JSONObject();
            // Serial number
            root.put("sn", randomSerial());
            // Firmware update version (random 1-3 digits)
            root.put("fu", randBetween(1, 999));
            // Cycle count (random 0-400)
            root.put("cc", randBetween(0, 400));
            // Name (randomly "Main", "Backup", "Test", etc.)
            String[] names = {"Main", "Backup", "Test", "Spare", "Alpha", "Beta"};
            root.put("n", names[randBetween(0, names.length - 1)]);

            // Generate u array
            JSONArray uArr = new JSONArray();
            int numEntries = randBetween(5, 13);
            int lastD = -1;
            for (int i = 1; i <= numEntries; i++) {
                JSONObject entry = new JSONObject();
                entry.put("i", i);
                entry.put("t", randomTimestamp());
                // d: 1 (robot) or 2 (charger), but no two charger in a row
                int d;
                if (lastD == 2) {
                    d = 1;
                } else {
                    d = randBetween(1, 2);
                }
                entry.put("d", d);
                lastD = d;
                entry.put("e", randBetween(10, 500));
                entry.put("v", randBetween(7, 14));
                uArr.put(entry);
            }
            root.put("u", uArr);
            return root.toString();
        } catch (Exception e) {
            return "{}";
        }
    }

    // Helper: random int between min and max, inclusive
    private static int randBetween(int min, int max) {
        return min + (int) (Math.random() * ((max - min) + 1));
    }

    // Helper: generate plausible timestamp string "yyMMddHHmm", not today, within +/-90 days
    private static String randomTimestamp() {
        try {
            long now = System.currentTimeMillis();
            // ±90 days in ms
            long ninetyDays = 90L * 24 * 60 * 60 * 1000;
            long offset = (long) randBetween((int) -ninetyDays, (int) ninetyDays);
            long ts = now + offset;
            SimpleDateFormat fmt = new SimpleDateFormat("yyMMddHHmm", Locale.US);
            String today = fmt.format(new Date(now));
            String candidate = fmt.format(new Date(ts));
            // Avoid today
            if (candidate.equals(today)) {
                // Add or subtract a day
                ts += 24 * 60 * 60 * 1000 * (offset >= 0 ? 1 : -1);
                candidate = fmt.format(new Date(ts));
            }
            return candidate;
        } catch (Exception e) {
            return "2301011200";
        }
    }

    // Helper: generate plausible serial string
    private static String randomSerial() {
        int style = randBetween(0, 2);
        switch (style) {
            case 0:
                // "1234-001"
                return String.format("%04d-%03d", randBetween(1, 9999), randBetween(1, 999));
            case 1:
                // "1----001"
                return String.format("%d----%03d", randBetween(1, 9), randBetween(1, 999));
            default:
                // "12345001"
                return String.format("%04d%04d", randBetween(1, 9999), randBetween(1, 9999));
        }
    }
