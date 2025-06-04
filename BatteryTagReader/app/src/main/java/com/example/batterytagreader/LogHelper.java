package com.example.batterytagreader;

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

    public static void log(Context context, String type, JSONObject data) {
        if (data == null || data.toString().equals(lastLogged != null ? lastLogged.toString() : "")) return;
        lastLogged = data;

        try {
            SharedPreferences prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
            JSONArray log = new JSONArray(prefs.getString(LOG_KEY, "[]"));

            JSONObject entry = new JSONObject();
            entry.put("time", new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(new Date()));
            entry.put("type", type);
            entry.put("data", data);

            log.put(entry);
            prefs.edit().putString(LOG_KEY, log.toString()).apply();
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
    public static String getLastLoggedRaw() {
        return lastLogged != null ? lastLogged.toString() : "";
    }

}
