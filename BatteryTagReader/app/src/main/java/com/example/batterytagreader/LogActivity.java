package com.example.batterytagreader;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import androidx.core.content.FileProvider;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileWriter;
import java.util.Locale;

public class LogActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(16, 16, 16, 16);
        setContentView(root);

        // Top buttons
        LinearLayout buttonRow = new LinearLayout(this);
        buttonRow.setOrientation(LinearLayout.HORIZONTAL);
        buttonRow.setGravity(Gravity.CENTER);
        buttonRow.setPadding(0, 0, 0, 16);

        Button exportJson = new Button(this);
        exportJson.setText("Export JSON");
        exportJson.setOnClickListener(v -> exportFile("log.json", "application/json", true));
        buttonRow.addView(exportJson);

        Button exportCsv = new Button(this);
        exportCsv.setText("Export CSV");
        exportCsv.setOnClickListener(v -> exportFile("log.csv", "text/csv", false));
        buttonRow.addView(exportCsv);

        Button clear = new Button(this);
        clear.setText("Clear");
        clear.setOnClickListener(v -> {
            LogHelper.clearLog(this);
            recreate();
        });
        buttonRow.addView(clear);

        root.addView(buttonRow);

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
            tv.setBackgroundColor(0xFFEFEFEF);
            tv.setTextIsSelectable(true);

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
                    writer.write(String.format("\"%s\",\"%s\",\"%s\"\n",
                            entry.getString("time"),
                            entry.getString("type"),
                            entry.getJSONObject("data").toString().replace("\"", "'")));
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
