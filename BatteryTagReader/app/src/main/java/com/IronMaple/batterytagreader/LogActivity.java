package com.IronMaple.batterytagreader;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import androidx.core.content.FileProvider;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileWriter;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

import android.util.TypedValue;
import androidx.core.content.ContextCompat;


public class LogActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(16, 16, 16, 16);
        setContentView(root);
// ===== Row 1: Exit / Pin / Unpin =====
        LinearLayout row1 = new LinearLayout(this);
        row1.setOrientation(LinearLayout.HORIZONTAL);
        row1.setGravity(Gravity.CENTER);
        row1.setPadding(0, 0, 0, 16);

        LinearLayout.LayoutParams btnParams = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);

        Button exitBtn = new Button(this);
        exitBtn.setText("Exit");
        exitBtn.setOnClickListener(v -> {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                stopLockTask();
            }
            finishAffinity(); // Optional: exit the app entirely
        });
        row1.addView(exitBtn, btnParams);

        Button pinBtn = new Button(this);
        pinBtn.setText("Pin");
        pinBtn.setOnClickListener(v -> {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                startLockTask();
            }
        });
        row1.addView(pinBtn, btnParams);

        Button unpinBtn = new Button(this);
        unpinBtn.setText("Unpin");
        unpinBtn.setOnClickListener(v -> {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                stopLockTask();
            }
        });
        row1.addView(unpinBtn, btnParams);

        root.addView(row1);

// ===== Row 2: Export JSON / Export CSV / Clear =====
        LinearLayout row2 = new LinearLayout(this);
        row2.setOrientation(LinearLayout.HORIZONTAL);
        row2.setGravity(Gravity.CENTER);
        row2.setPadding(0, 0, 0, 16);

        Button exportJson = new Button(this);
        exportJson.setText("Export JSON");
        exportJson.setOnClickListener(v -> exportFile("log.json", "application/json", true));
        row2.addView(exportJson, btnParams);

        Button exportCsv = new Button(this);
        exportCsv.setText("Export CSV");
        exportCsv.setOnClickListener(v -> exportFile("log.csv", "text/csv", false));
        row2.addView(exportCsv, btnParams);

        Button clear = new Button(this);
        clear.setText("Clear");
        clear.setOnClickListener(v -> {
            LogHelper.clearLog(this);
            recreate();
        });
        row2.addView(clear, btnParams);

        root.addView(row2);



        // Scrollable log entries
        ScrollView scroll = new ScrollView(this);
        LinearLayout logList = new LinearLayout(this);
        logList.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(logList);
        root.addView(scroll);

        JSONArray log = LogHelper.getLog(this);
        for (int i = 0; i < log.length(); i++) {
            JSONObject entry = log.optJSONObject(i);
            if (entry == null) continue;

            String info = String.format(Locale.US,
                    "[%s] %s\n\n%s",
                    entry.optString("time"),
                    entry.optString("type").toUpperCase(Locale.US),
                    formatJsonPretty(entry.optJSONObject("data"))
            );

            TextView tv = new TextView(this);
            tv.setText(info);
            tv.setTextSize(15f);
            tv.setPadding(24, 20, 24, 20);
            tv.setTextIsSelectable(true);

            // Dynamically resolve text color based on theme
            TypedValue tvColor = new TypedValue();
            getTheme().resolveAttribute(android.R.attr.textColorPrimary, tvColor, true);
            tv.setTextColor(ContextCompat.getColor(this, tvColor.resourceId));

            // Optional: use theme background
            TypedValue bgColor = new TypedValue();
            if (getTheme().resolveAttribute(android.R.attr.colorBackgroundFloating, bgColor, true)) {
                tv.setBackgroundColor(ContextCompat.getColor(this, bgColor.resourceId));
            }

            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
            );
            params.setMargins(0, 0, 0, 20);
            logList.addView(tv, params);
        }
    }

    private void exportFile(String filename, String mime, boolean asJson) {
        try {
            File file = new File(getCacheDir(), filename);
            FileWriter writer = new FileWriter(file);

            JSONArray log = LogHelper.getLog(this);
            if (asJson) {
                writer.write(log.toString(2));
            } else {
                writer.write("Time,Type,Data\n");
                for (int i = 0; i < log.length(); i++) {
                    JSONObject entry = log.getJSONObject(i);
                    String utcString = entry.optString("time", "");
                    String localTime = utcString;

                    try {
                        SimpleDateFormat utcFormat = new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US);
                        utcFormat.setTimeZone(TimeZone.getTimeZone("UTC"));

                        SimpleDateFormat localFormat = new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault());
                        localFormat.setTimeZone(TimeZone.getDefault());

                        Date parsedUtcDate = utcFormat.parse(utcString);
                        if (parsedUtcDate != null) {
                            localTime = localFormat.format(parsedUtcDate);
                        }
                    } catch (Exception e) {
                        e.printStackTrace();  // fallback to raw UTC string
                    }

                    String type = entry.optString("type", "");
                    String data = entry.optJSONObject("data").toString().replace("\"", "'");

                    writer.write(String.format("\"%s\",\"%s\",\"%s\"\n", localTime, type, data));
                }
            }

            writer.close();

            Intent share = new Intent(Intent.ACTION_SEND);
            share.setType(mime);
            share.putExtra(Intent.EXTRA_STREAM, FileProvider.getUriForFile(
                    this,
                    getPackageName() + ".provider",
                    file
            ));
            share.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            startActivity(Intent.createChooser(share, "Share log file"));

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private String formatJsonPretty(JSONObject obj) {
        try {
            return obj.toString(2);
        } catch (Exception e) {
            return obj.toString();
        }
    }
}
