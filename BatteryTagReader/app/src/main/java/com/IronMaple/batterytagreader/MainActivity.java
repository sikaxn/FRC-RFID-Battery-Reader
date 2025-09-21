package com.IronMaple.batterytagreader;

import android.app.Activity;
import android.app.ActivityManager;
import android.app.AlertDialog;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.nfc.NdefMessage;
import android.nfc.NdefRecord;
import android.nfc.NfcAdapter;
import android.nfc.Tag;
import android.nfc.tech.Ndef;
import android.os.Build;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.nio.charset.Charset;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.List;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.TimeZone;


public class MainActivity extends Activity {

    private NfcAdapter nfcAdapter;
    private LinearLayout resultLayout;
    private Tag lastTag = null;
    private JSONObject lastJson = null;
    private static final int MAX_RECORDS = 14;

    // === Added: extra key for demo JSON ===
    public static final String EXTRA_DEMO_JSON = "com.IronMaple.batterytagreader.EXTRA_DEMO_JSON";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        resultLayout = findViewById(R.id.resultLayout);

        showMessage("Hold battery to phone");

        nfcAdapter = NfcAdapter.getDefaultAdapter(this);
        if (nfcAdapter == null) {
            showMessage("NFC not supported on this device.");
        }

        Button btnCharged = findViewById(R.id.btnCharged);
        Button btnInit = findViewById(R.id.btnInit);
        Button btnStatus = findViewById(R.id.btnStatus);
        Button btnMockRobot = findViewById(R.id.btnMockRobot);
        Button btnViewLogs = findViewById(R.id.btnViewLogs);

        btnCharged.setOnClickListener(v -> writeChargerSession());
        btnInit.setOnClickListener(v -> promptForSerialNumber());
        btnStatus.setOnClickListener(v -> promptForNoteType());
        btnMockRobot.setOnClickListener(v -> writeRobotSession());

        btnViewLogs.setOnClickListener(v -> {
            Intent intent = new Intent(MainActivity.this, LogActivity.class);
            startActivity(intent);
        });

        // Handle a demo payload if we were launched with one
        handleIntentForDemo(getIntent());

        //if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
        //    if (!isInLockTaskMode()) {
        //        startLockTask();
        //   }
        //}

    }

    @Override
    protected void onResume() {
        super.onResume();
        enableImmersiveMode();
        if (nfcAdapter != null) {
            Intent intent = new Intent(this, getClass()).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
            PendingIntent pendingIntent = PendingIntent.getActivity(
                    this,
                    0,
                    intent,
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ? PendingIntent.FLAG_MUTABLE : 0
            );
            nfcAdapter.enableForegroundDispatch(this, pendingIntent, null, null);
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (nfcAdapter != null) {
            nfcAdapter.disableForegroundDispatch(this);
        }
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);

        // === Added: if a demo JSON was delivered via intent, handle it first and return ===
        if (handleIntentForDemo(intent)) {
            return;
        }

        lastTag = intent.getParcelableExtra(NfcAdapter.EXTRA_TAG);
        if (lastTag == null) {
            showMessage("No tag detected.");
            return;
        }

        Ndef ndef = Ndef.get(lastTag);
        if (ndef != null) {
            try {
                ndef.connect();
                NdefMessage message = ndef.getNdefMessage();
                NdefRecord[] records = message.getRecords();

                if (records.length > 0) {
                    String raw = getTextFromPayload(records[0].getPayload());
                    parseAndDisplayJson(raw);
                } else {
                    showMessage("NDEF tag has no records.");
                }

                ndef.close();
            } catch (Exception e) {
                showMessage("Error reading NDEF: " + e.getMessage());
            }
        } else {
            showMessage("Tag is not NDEF formatted.");
        }
    }

    // === Added: central handler for demo payloads ===
    // Returns true if a demo JSON was found and handled.
    private boolean handleIntentForDemo(Intent intent) {
        if (intent == null) return false;
        String demo = intent.getStringExtra(EXTRA_DEMO_JSON);
        if (demo != null && !demo.isEmpty()) {
            try {
                parseAndDisplayJson(demo);
            } catch (Exception e) {
                showMessage("Failed to show demo data.");
            }
            // prevent re-processing if the intent is reused
            intent.removeExtra(EXTRA_DEMO_JSON);
            return true;
        }
        return false;
    }

    private void parseAndDisplayJson(String rawJson) {
        resultLayout.removeAllViews();

        try {
            JSONObject obj = new JSONObject(rawJson);
            lastJson = obj;

            // Avoid logging duplicate reads
            if (!obj.toString().equals(LogHelper.getLastLoggedRaw(this))) {
                LogHelper.log(this, "read", obj);
            }

            addLabel("Serial Number", obj.optString("sn"));
            addLabel("First Use", formatDateTime(obj.optString("fu")));
            addLabel("Cycle Count", String.valueOf(obj.optInt("cc")));

            // Check for dark mode once
            int nightModeFlags = getResources().getConfiguration().uiMode & android.content.res.Configuration.UI_MODE_NIGHT_MASK;
            boolean isDark = nightModeFlags == android.content.res.Configuration.UI_MODE_NIGHT_YES;

            // Note Type with background color
            int noteType = obj.optInt("n");
            TextView noteLabel = new TextView(this);
            noteLabel.setText("Note Type: " + noteTypeName(noteType));
            noteLabel.setTextSize(16f);
            noteLabel.setPadding(0, 12, 0, 4);

            switch (noteType) {
                case 1: // Practice Only (yellow)
                    noteLabel.setBackgroundColor(isDark ? 0xFFCCCC00 : 0xFFFFFF99);
                    noteLabel.setTextColor(0xFF000000);
                    break;
                case 2: // Scrap (red)
                    noteLabel.setBackgroundColor(isDark ? 0xFFCC3333 : 0xFFFF6666);
                    noteLabel.setTextColor(0xFFFFFFFF);
                    break;
                case 3: // Other (blue)
                    noteLabel.setBackgroundColor(isDark ? 0xFF3366AA : 0xFF99CCFF);
                    noteLabel.setTextColor(0xFFFFFFFF);
                    break;
                default: // Normal
                    noteLabel.setTextColor(isDark ? 0xFFFFFFFF : 0xFF000000);
                    break;
            }

            resultLayout.addView(noteLabel);

            JSONArray usage = obj.optJSONArray("u");
            if (usage != null && usage.length() > 0) {
                // Convert to list for sorting
                List<JSONObject> entries = new ArrayList<>();
                for (int i = 0; i < usage.length(); i++) {
                    entries.add(usage.getJSONObject(i));
                }

                // Sort descending by ID
                entries.sort((a, b) -> Integer.compare(b.optInt("i", 0), a.optInt("i", 0)));

                addHeader("Usage Log:");
                for (JSONObject entry : entries) {
                    int type = entry.optInt("d");
                    String info = String.format(
                            "#%d: %s\n• Device: %s\n• Energy: %dkJ, Voltage: %d",
                            entry.optInt("i"),
                            formatDateTime(entry.optString("t")),
                            deviceTypeName(type),
                            entry.optInt("e"),
                            entry.optInt("v")
                    );

                    TextView item = new TextView(this);
                    item.setText(info);
                    item.setTextSize(15f);
                    item.setPadding(24, 8, 0, 8);

                    if (type == 2) {  // Charger → green
                        item.setBackgroundColor(isDark ? 0xFF227733 : 0xFFAAFFAA);
                        item.setTextColor(isDark ? 0xFFFFFFFF : 0xFF000000);
                    } else if (type == 1) {  // Robot → blue
                        item.setBackgroundColor(isDark ? 0xFF224477 : 0xFFADD8E6);
                        item.setTextColor(isDark ? 0xFFFFFFFF : 0xFF000000);
                    }

                    resultLayout.addView(item);
                }
            }

        } catch (Exception e) {
            showMessage("Invalid JSON:\n" + rawJson);
        }
    }

    private void writeChargerSession() {
        if (lastJson == null) {
            showMessage("Scan a battery first.");
            return;
        }

        try {
            JSONArray u = lastJson.optJSONArray("u");
            if (u == null) u = new JSONArray();

            // Check last entry
            if (u.length() > 0) {
                JSONObject lastEntry = u.getJSONObject(u.length() - 1);
                int lastType = lastEntry.optInt("d", -1); // 2 = charger

                if (lastType == 2) {
                    new AlertDialog.Builder(this)
                            .setTitle("Duplicate Charger Entry")
                            .setMessage("The last log was already a charger. Add another anyway?")
                            .setPositiveButton("Yes", (dialog, which) -> doAddChargerEntry())
                            .setNegativeButton("No", null)
                            .show();
                    return;
                }
            }

            // Safe to proceed directly
            doAddChargerEntry();

        } catch (Exception e) {
            showMessage("Failed to update charger entry.");
        }
    }

    private void doAddChargerEntry() {
        try {
            JSONArray u = lastJson.optJSONArray("u");
            if (u == null) u = new JSONArray();

            // Determine max ID
            int maxId = 0;
            for (int i = 0; i < u.length(); i++) {
                JSONObject entry = u.getJSONObject(i);
                maxId = Math.max(maxId, entry.optInt("i", 0));
            }

            JSONObject entry = new JSONObject();
            entry.put("i", maxId + 1);
            entry.put("t", currentTimestamp());
            entry.put("d", 2); // charger
            entry.put("e", 0);
            entry.put("v", 0);
            u.put(entry);

            while (u.length() > MAX_RECORDS) u.remove(0); // MAX_RECORDS = 14
            lastJson.put("u", u);

            int cc = lastJson.optInt("cc", 0);
            lastJson.put("cc", cc + 1);

            if (writeToTag(lastJson.toString())) {
                LogHelper.log(this, "write", lastJson);
            }

        } catch (Exception e) {
            showMessage("Failed to write charger entry.");
        }
    }

    private void writeRobotSession() {
        if (lastJson == null) {
            showMessage("Scan a battery first.");
            return;
        }

        try {
            JSONArray u = lastJson.optJSONArray("u");
            if (u == null) u = new JSONArray();

            // Determine max ID
            int maxId = 0;
            for (int i = 0; i < u.length(); i++) {
                JSONObject entry = u.getJSONObject(i);
                maxId = Math.max(maxId, entry.optInt("i", 0));
            }

            JSONObject entry = new JSONObject();
            entry.put("i", maxId + 1);
            entry.put("t", currentTimestamp());
            entry.put("d", 1);  // robot
            entry.put("e", 0);
            entry.put("v", 0);
            u.put(entry);

            while (u.length() > MAX_RECORDS) u.remove(0);
            lastJson.put("u", u);

            if (writeToTag(lastJson.toString())) {
                LogHelper.log(this, "write", lastJson);
            }

        } catch (Exception e) {
            showMessage("Failed to mock robot session.");
        }
    }

    private void promptForSerialNumber() {
        EditText input = new EditText(this);
        input.setInputType(InputType.TYPE_CLASS_TEXT);
        new AlertDialog.Builder(this)
                .setTitle("Enter Serial Number")
                .setView(input)
                .setPositiveButton("OK", (dialog, which) -> {
                    try {
                        JSONObject json = new JSONObject();
                        json.put("sn", input.getText().toString());
                        json.put("fu", currentTimestamp());
                        json.put("cc", 0);
                        json.put("n", 0);
                        json.put("u", new JSONArray());
                        lastJson = json;

                        if (writeToTag(lastJson.toString())) {
                            LogHelper.log(this, "write", lastJson);
                        }

                    } catch (Exception e) {
                        showMessage("Error creating battery record.");
                    }
                }).setNegativeButton("Cancel", null).show();
    }

    private void promptForNoteType() {
        final String[] items = {"Normal", "Practice Only", "Scrap", "Other"};
        new AlertDialog.Builder(this)
                .setTitle("Set Note Type")
                .setItems(items, (dialog, which) -> {
                    try {
                        if (lastJson == null) {
                            showMessage("Scan a battery first.");
                            return;
                        }
                        lastJson.put("n", which);

                        if (writeToTag(lastJson.toString())) {
                            LogHelper.log(this, "write", lastJson);
                        }

                    } catch (Exception e) {
                        showMessage("Failed to set note.");
                    }
                }).show();
    }

    private boolean writeToTag(String data) {
        if (nfcAdapter == null || lastTag == null) {
            showMessage("No tag or NFC unavailable.");
            return false;
        }

        try {
            Ndef ndef = Ndef.get(lastTag);
            if (ndef != null && ndef.isWritable()) {
                ndef.connect();
                byte[] langBytes = "en".getBytes(Charset.forName("US-ASCII"));
                byte[] textBytes = data.getBytes(Charset.forName("UTF-8"));
                byte[] payload = new byte[1 + langBytes.length + textBytes.length];
                payload[0] = (byte) langBytes.length;
                System.arraycopy(langBytes, 0, payload, 1, langBytes.length);
                System.arraycopy(textBytes, 0, payload, 1 + langBytes.length, textBytes.length);

                NdefRecord record = new NdefRecord(
                        NdefRecord.TNF_WELL_KNOWN,
                        NdefRecord.RTD_TEXT,
                        new byte[0],
                        payload
                );

                ndef.writeNdefMessage(new NdefMessage(new NdefRecord[]{record}));
                ndef.close();

                showMessage("Write successful.");
                parseAndDisplayJson(data);  // Will log the read

                return true;
            } else {
                showMessage("Tag not writable.");
            }
        } catch (Exception e) {
            showMessage("Write error: " + e.getMessage());
        }

        return false;
    }

    private String currentTimestamp() {
        SimpleDateFormat utcFormat = new SimpleDateFormat("yyMMddHHmm", Locale.US);
        utcFormat.setTimeZone(TimeZone.getTimeZone("UTC"));
        return utcFormat.format(new Date());
    }

    private void showMessage(String message) {
        resultLayout.removeAllViews();
        TextView tv = new TextView(this);
        tv.setText(message);
        tv.setTextSize(18f);
        tv.setPadding(0, 16, 0, 16);
        tv.setGravity(Gravity.CENTER);
        resultLayout.addView(tv);
    }

    private void addLabel(String label, String value) {
        TextView tv = new TextView(this);
        tv.setText(label + ": " + value);
        tv.setTextSize(16f);
        tv.setPadding(0, 12, 0, 4);
        resultLayout.addView(tv);
    }

    private void addHeader(String text) {
        TextView tv = new TextView(this);
        tv.setText(text);
        tv.setTextSize(18f);
        tv.setPadding(0, 20, 0, 8);
        tv.setGravity(Gravity.START);
        resultLayout.addView(tv);
    }

    private void addListItem(String text) {
        TextView tv = new TextView(this);
        tv.setText(text);
        tv.setTextSize(15f);
        tv.setPadding(24, 8, 0, 8);
        resultLayout.addView(tv);
    }

    private String noteTypeName(int code) {
        switch (code) {
            case 1: return "Practice Only";
            case 2: return "Scrap";
            case 3: return "Other";
            default: return "Normal";
        }
    }

    private String deviceTypeName(int code) {
        return code == 2 ? "Charger" : "Robot";
    }

    private String formatDateTime(String raw) {
        // Guard nulls/whitespace first
        if (raw == null) return "Date not available";
        raw = raw.trim();

        // If the JSON date is all zeros (e.g., "0000000000" or even just "0"), show N/A
        if (raw.isEmpty() || raw.matches("^0+$")) {
            return "Date not available";
        }

        // Keep the current fallback for non-standard lengths
        if (raw.length() != 10) return raw;

        try {
            // Parse raw UTC timestamp encoded as "yyMMddHHmm"
            java.text.SimpleDateFormat utcFormat =
                    new java.text.SimpleDateFormat("yyMMddHHmm", java.util.Locale.US);
            utcFormat.setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
            java.util.Date date = utcFormat.parse(raw);

            // Format to local time
            java.text.SimpleDateFormat localFormat =
                    new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm", java.util.Locale.getDefault());
            localFormat.setTimeZone(java.util.TimeZone.getDefault());
            return localFormat.format(date);

        } catch (Exception e) {
            // If parsing fails for any other reason, fall back to the raw string
            return raw;
        }
    }

    private String getTextFromPayload(byte[] payload) {
        try {
            int langCodeLen = payload[0] & 0x3F;
            return new String(payload, langCodeLen + 1, payload.length - langCodeLen - 1, Charset.forName("UTF-8"));
        } catch (Exception e) {
            return "[Invalid Payload]";
        }
    }

    private boolean isInLockTaskMode() {
        ActivityManager am = (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            return am.getLockTaskModeState() != ActivityManager.LOCK_TASK_MODE_NONE;
        } else {
            return am.isInLockTaskMode();
        }
    }

    private void enableImmersiveMode() {
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                        | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                        | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_FULLSCREEN
        );
    }

}