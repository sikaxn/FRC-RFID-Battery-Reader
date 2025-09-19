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
