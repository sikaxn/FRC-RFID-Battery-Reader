package com.IronMaple.batterytagreader;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.core.content.FileProvider;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileWriter;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

import android.util.TypedValue;
import androidx.core.content.ContextCompat;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;


public class LogActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(16, 16, 16, 16); // your default
        ViewCompat.setOnApplyWindowInsetsListener(root, (v, insets) -> {
            Insets sysBars = insets.getInsets(WindowInsetsCompat.Type.systemBars());
            v.setPadding(16 + sysBars.left, 16 + sysBars.top,
                    16 + sysBars.right, 16 + sysBars.bottom);
            return insets;
        });

        setContentView(root);

        // ===== Row 1: Exit / Pin / Unpin =====
        LinearLayout row1 = new LinearLayout(this);
        row1.setOrientation(LinearLayout.HORIZONTAL);
        row1.setGravity(Gravity.CENTER);
        row1.setPadding(0, 0, 0, 16);

        LinearLayout.LayoutParams btnParams = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);

        Button exitBtn = new Button(this);
        exitBtn.setText(getString(R.string.btn_exit));
        exitBtn.setOnClickListener(v -> {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                stopLockTask();
            }
            finishAffinity(); // Optional: exit the app entirely
        });
        row1.addView(exitBtn, btnParams);

        Button pinBtn = new Button(this);
        pinBtn.setText(getString(R.string.btn_pin));
        pinBtn.setOnClickListener(v -> {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                startLockTask();
            }
        });
        row1.addView(pinBtn, btnParams);

        Button unpinBtn = new Button(this);
        unpinBtn.setText(getString(R.string.btn_unpin));
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
        exportJson.setText(getString(R.string.btn_export_json));
        exportJson.setOnClickListener(v -> exportFile("log.json", "application/json", true));
        row2.addView(exportJson, btnParams);

        Button exportCsv = new Button(this);
        exportCsv.setText(getString(R.string.btn_export_csv));
        exportCsv.setOnClickListener(v -> exportFile("log.csv", "text/csv", false));
        row2.addView(exportCsv, btnParams);

        Button clear = new Button(this);
        clear.setText(getString(R.string.btn_clear));
        clear.setOnClickListener(v -> showClearConfirm());
        row2.addView(clear, btnParams);

        root.addView(row2);

        // ===== Row 3: Demo / Privacy / Help =====
        LinearLayout row3 = new LinearLayout(this);
        row3.setOrientation(LinearLayout.HORIZONTAL);
        row3.setGravity(Gravity.CENTER);
        row3.setPadding(0, 0, 0, 16);

        Button demoBtn = new Button(this);
        demoBtn.setText(getString(R.string.btn_demo));
        demoBtn.setOnClickListener(v -> {
            String demoJson = LogHelper.generateDemoJson();
            Intent i = new Intent(this, MainActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra(MainActivity.EXTRA_DEMO_JSON, LogHelper.generateDemoJson())
                    .putExtra("IS_DEMO", true);   // marker so it won’t be logged
            startActivity(i);
        });
        row3.addView(demoBtn, btnParams);

        Button privacyBtn = new Button(this);
        privacyBtn.setText(getString(R.string.btn_privacy));
        privacyBtn.setOnClickListener(v -> {
            Uri u = Uri.parse("https://studenttechsupport.com/privacy");
            startActivity(new Intent(Intent.ACTION_VIEW, u));
        });
        row3.addView(privacyBtn, btnParams);

        Button helpBtn = new Button(this);
        helpBtn.setText(getString(R.string.btn_help));
        helpBtn.setOnClickListener(v -> {
            Uri u = Uri.parse("https://studenttechsupport.com/support");
            startActivity(new Intent(Intent.ACTION_VIEW, u));
        });
        row3.addView(helpBtn, btnParams);

        root.addView(row3);

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
            // Build the file in cache first
            File cacheFile = new File(getCacheDir(), filename);
            FileWriter writer = new FileWriter(cacheFile);

            JSONArray log = LogHelper.getLog(this);
            if (asJson) {
                writer.write(log.toString(2));
            } else {
                // Fixed CSV header (do NOT localize)
                writer.write("Time,Type,Data\n");
                for (int i = 0; i < log.length(); i++) {
                    JSONObject entry = log.getJSONObject(i);
                    String utcString = entry.optString("time", "");
                    String localTime = utcString;

                    try {
                        SimpleDateFormat utcFormat = new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US);
                        utcFormat.setTimeZone(TimeZone.getTimeZone("UTC"));

                        SimpleDateFormat localFormat = new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.ROOT);
                        localFormat.setTimeZone(TimeZone.getDefault());

                        Date parsedUtcDate = utcFormat.parse(utcString);
                        if (parsedUtcDate != null) {
                            localTime = localFormat.format(parsedUtcDate);
                        }
                    } catch (Exception e) {
                        e.printStackTrace();
                    }

                    String type = entry.optString("type", "");
                    String data = entry.optJSONObject("data").toString().replace("\"", "'");
                    writer.write(String.format(Locale.ROOT, "\"%s\",\"%s\",\"%s\"\n", localTime, type, data));
                }
            }
            writer.close();

            // 🔹 Ask user: Save to Downloads or Share
            new AlertDialog.Builder(this)
                    .setTitle(asJson ? "Export Log (JSON)" : "Export Log (CSV)")
                    .setMessage("Choose how you want to export the log file:")
                    .setPositiveButton("Share via apps", (dialog, which) -> {
                        shareFile(cacheFile, mime);
                    })
                    .setNegativeButton("Save to Downloads", (dialog, which) -> {
                        saveToDownloads(cacheFile, filename);
                    })
                    .setNeutralButton("Cancel", null)
                    .show();

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void shareFile(File file, String mime) {
        Uri uri = FileProvider.getUriForFile(
                this,
                getPackageName() + ".provider",
                file
        );

        Intent share = new Intent(Intent.ACTION_SEND);
        share.setType(mime);
        share.putExtra(Intent.EXTRA_STREAM, uri);
        share.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        startActivity(Intent.createChooser(share, getString(R.string.chooser_share_log_title)));
    }

    private void saveToDownloads(File source, String fileName) {
        try {
            File downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
            if (!downloads.exists()) downloads.mkdirs();

            // --- Determine file extension ---
            String extension = "";
            int dot = fileName.lastIndexOf('.');
            if (dot > 0) {
                extension = fileName.substring(dot);  // e.g. .json or .csv
            } else {
                extension = ".log"; // fallback
            }

            // --- Generate timestamped standardized filename ---
            String timeStamp = new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(new Date());
            String newName = "BatteryReader_" + timeStamp + ".log" + extension;

            File outFile = new File(downloads, newName);

            // --- Copy the file ---
            try (FileInputStream in = new FileInputStream(source);
                 FileOutputStream out = new FileOutputStream(outFile)) {
                byte[] buf = new byte[4096];
                int len;
                while ((len = in.read(buf)) > 0) out.write(buf, 0, len);
            }

            // --- Make visible in Files app immediately ---
            sendBroadcast(new Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE, Uri.fromFile(outFile)));

            Toast.makeText(this, "Saved to Downloads: " + outFile.getName(), Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            Toast.makeText(this, "Save failed: " + e.getMessage(), Toast.LENGTH_SHORT).show();
        }
    }



    private void showClearConfirm() {
        final AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle(R.string.dialog_clear_logs_title)
                .setMessage(R.string.dialog_clear_logs_message)
                .setPositiveButton(getString(R.string.dialog_yes_countdown, 3), null)
                .setNegativeButton(R.string.dialog_no, (d, w) -> d.dismiss())
                .create();

        dialog.setOnShowListener(dlg -> {
            final Button positive = dialog.getButton(AlertDialog.BUTTON_POSITIVE);
            positive.setEnabled(false);

            final Handler h = new Handler(Looper.getMainLooper());
            final int[] sec = {3};
            final Runnable tick = new Runnable() {
                @Override public void run() {
                    sec[0]--;
                    if (sec[0] <= 0) {
                        positive.setText(getString(R.string.dialog_yes));
                        positive.setEnabled(true);
                    } else {
                        positive.setText(getString(R.string.dialog_yes_countdown, sec[0]));
                        h.postDelayed(this, 1000);
                    }
                }
            };
            h.postDelayed(tick, 1000);

            positive.setOnClickListener(v -> {
                LogHelper.clearLog(this);
                Toast.makeText(this, R.string.toast_logs_cleared, Toast.LENGTH_SHORT).show();
                dialog.dismiss();
                recreate();
            });
        });

        dialog.show();
    }

    private String formatJsonPretty(JSONObject obj) {
        try {
            return obj.toString(2);
        } catch (Exception e) {
            return obj.toString();
        }
    }
}
