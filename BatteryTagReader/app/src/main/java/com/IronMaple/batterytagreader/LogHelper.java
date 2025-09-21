package com.IronMaple.batterytagreader;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

public class LogHelper {

    private static final String PREF_NAME = "BatteryTagLog";
    private static final String LOG_KEY = "log_data";
    private static final String LAST_LOGGED_KEY = "last_logged_raw";

    /**
     * Save a new log entry in SharedPreferences, avoiding duplicates.
     */
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

    // ------------------------------------------------------------------------
    // DEMO JSON GENERATION (iOS-aligned)
    // ------------------------------------------------------------------------

    /**
     * Generate a demo JSON string simulating a battery tag.
     * Shape matches iOS:
     * {
     *   "sn": "DEMO-XYZ",
     *   "fu": "YYMMDDHHMM"   // past within last year
     *   "n": 0..2,           // avoid 3 in demo
     *   "cycle": 1..10,
     *   "number": startNumber (1..20),
     *   "usage": [
     *     { "id": number+i, "t":"YYMMDDHHMM" (future, strictly increasing),
     *       "d":1|2 (no two 2's in a row), "e":10..500, "v":7..14 }
     *   ] // 2..5
     * }
     */
    public static String generateDemoJson() {
        try {
            // Top-level values
            String sn = makeDemoSN(); // "DEMO-%03d"
            String fu = makeRandomFUwithinLastYearYYMMDDHHMM(); // past within last year
            int startNumber = randBetween(1, 20);
            int recordCount = randBetween(2, 5);

            // Usage array: strictly increasing FUTURE timestamps (from today 00:00),
            // and ensure no two chargers (d=2) consecutively.
            JSONArray u = new JSONArray(); // << Android expects "u"
            TimeZone tz = TimeZone.getTimeZone("America/Toronto");
            SimpleDateFormat yymmddhhmm = new SimpleDateFormat("yyMMddHHmm", Locale.US);
            yymmddhhmm.setTimeZone(tz);

            long now = System.currentTimeMillis();
            long startOfToday = startOfDayMillis(now, tz);
            long last = startOfToday; // begin at today's 00:00, then bump forward

            int lastD = 0;
            for (int idx = 0; idx < recordCount; idx++) {
                // Advance by at least 1 day + random minutes
                int advanceDays = randBetween(1, 20);
                int advanceMinutes = randBetween(0, (24 * 60) - 1);
                long candidate = addDaysMinutes(last, advanceDays, advanceMinutes);

                // Ensure strictly increasing
                if (candidate <= last) candidate = last + 60_000L;
                last = candidate;

                // d: 1 = robot, 2 = charger; avoid two 2's in a row
                int dVal = randBetween(1, 2);
                if (lastD == 2 && dVal == 2) dVal = 1;
                lastD = dVal;

                JSONObject e = new JSONObject();
                e.put("i", startNumber + idx);          // << Android expects "i"
                e.put("t", yymmddhhmm.format(new Date(last)));
                e.put("d", dVal);
                e.put("e", randBetween(10, 500));
                e.put("v", randBetween(7, 14));

                u.put(e);
            }

            // Final object with Android-expected keys
            JSONObject root = new JSONObject();
            root.put("sn", sn);
            root.put("fu", fu);
            root.put("n", randBetween(0, 2));   // 0..2 (avoid 3 for demo)
            root.put("cc", randBetween(1, 10)); // << Android expects "cc"
            root.put("u", u);                   // << Android expects "u"

            return root.toString();
        } catch (Exception e) {
            e.printStackTrace();
            return "{}";
        }
    }


    // ------------------------------------------------------------------------
    // Helper functions
    // ------------------------------------------------------------------------

    private static String makeDemoSN() {
        int n = randBetween(0, 999);
        return String.format(Locale.US, "DEMO-%03d", n);
    }

    private static int randBetween(int a, int b) {
        return a + (int) Math.floor(Math.random() * (b - a + 1));
    }

    /** Random past time within the last year, formatted YYMMDDHHMM in America/Toronto. */
    private static String makeRandomFUwithinLastYearYYMMDDHHMM() {
        try {
            TimeZone tz = TimeZone.getTimeZone("America/Toronto");
            SimpleDateFormat fmt = new SimpleDateFormat("yyMMddHHmm", Locale.US);
            fmt.setTimeZone(tz);

            long now = System.currentTimeMillis();
            // subtract 0..364 days and 0..(24*60-1) minutes
            int backDays = randBetween(0, 364);
            int backMinutes = randBetween(0, (24 * 60) - 1);
            long ts = addDaysMinutes(now, -backDays, -backMinutes);

            return fmt.format(new Date(ts));
        } catch (Exception e) {
            return new SimpleDateFormat("yyMMddHHmm", Locale.US).format(new Date());
        }
    }

    /** Add days and minutes to a timestamp in ms. */
    private static long addDaysMinutes(long baseMs, int days, int minutes) {
        return baseMs + days * 24L * 60L * 60L * 1000L + minutes * 60L * 1000L;
    }

    /** Start of day (00:00) in given time zone. */
    private static long startOfDayMillis(long epochMs, TimeZone tz) {
        java.util.Calendar c = java.util.Calendar.getInstance(tz, Locale.US);
        c.setTimeInMillis(epochMs);
        c.set(java.util.Calendar.HOUR_OF_DAY, 0);
        c.set(java.util.Calendar.MINUTE, 0);
        c.set(java.util.Calendar.SECOND, 0);
        c.set(java.util.Calendar.MILLISECOND, 0);
        return c.getTimeInMillis();
    }

    // ------------------------------------------------------------------------
    // (Optional) Legacy helpers kept for compatibility; not used by demo:
    // ------------------------------------------------------------------------

    @SuppressWarnings("unused")
    private static String randomYYMMDDHHMM(boolean avoidToday, boolean allowFuture) {
        try {
            long now = System.currentTimeMillis();
            long ninetyDaysMs = 90L * 24 * 60 * 60 * 1000;
            long offset = (long) randBetween(-(int) (ninetyDaysMs / 1000), (int) (ninetyDaysMs / 1000)) * 1000L;

            if (!allowFuture && offset > 0) offset = -offset; // force past

            long ts = now + offset;
            SimpleDateFormat fmt = new SimpleDateFormat("yyMMddHHmm", Locale.US);

            String today = fmt.format(new Date(now));
            String candidate = fmt.format(new Date(ts));

            if (avoidToday && candidate.equals(today)) {
                ts += 24L * 60 * 60 * 1000; // push by 1 day
                candidate = fmt.format(new Date(ts));
            }
            return candidate;
        } catch (Exception e) {
            return new SimpleDateFormat("yyMMddHHmm", Locale.US).format(new Date());
        }
    }

    @SuppressWarnings("unused")
    private static String randomSerial() {
        int style = randBetween(0, 2);
        switch (style) {
            case 0:
                return String.format(Locale.US, "%04d-%03d", randBetween(1, 9999), randBetween(1, 999));
            case 1:
                return String.format(Locale.US, "%d----%03d", randBetween(1, 9), randBetween(1, 999));
            default:
                return String.format(Locale.US, "%04d%04d", randBetween(1, 9999), randBetween(1, 9999));
        }
    }
}
