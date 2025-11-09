package com.IronMaple.batterytagreader;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.ActivityManager;
import android.app.AlertDialog;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.net.Uri;
import android.nfc.NdefMessage;
import android.nfc.NdefRecord;
import android.nfc.NfcAdapter;
import android.nfc.Tag;
import android.nfc.tech.Ndef;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.Spinner;
import android.widget.TextView;

import androidx.core.content.FileProvider;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.nio.charset.Charset;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.List;
import java.util.ArrayList;
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

        SoundHelper.init(this);

        WindowCompat.setDecorFitsSystemWindows(getWindow(), true);
        final View root = findViewById(android.R.id.content);
        ViewCompat.setOnApplyWindowInsetsListener(root, (v, insets) -> {
            Insets sys = insets.getInsets(
                    WindowInsetsCompat.Type.statusBars() | WindowInsetsCompat.Type.navigationBars()
            );
            v.setPadding(v.getPaddingLeft(), sys.top, v.getPaddingRight(), sys.bottom);
            return insets;
        });

        resultLayout = findViewById(R.id.resultLayout);

        showMessage(getString(R.string.msg_hold_battery));

        nfcAdapter = NfcAdapter.getDefaultAdapter(this);
        if (nfcAdapter == null) {
            showMessage(getString(R.string.msg_nfc_not_supported));
        }


        Button btnCharged = findViewById(R.id.btnCharged);
        Button btnInit = findViewById(R.id.btnInit);
        Button btnStatus = findViewById(R.id.btnStatus);
        Button btnMockRobot = findViewById(R.id.btnMockRobot);
        Button btnViewLogs = findViewById(R.id.btnViewLogs);
        Button btnExportJson = findViewById(R.id.btnExportJson);
        btnExportJson.setOnClickListener(v -> exportJson());


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
        IntentFilter filter = new IntentFilter("com.IronMaple.batterytagreader.LOAD_JSON");
        registerReceiver(new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                try {
                    String jsonStr = intent.getStringExtra("json");
                    if (jsonStr != null && !jsonStr.isEmpty()) {
                        parseAndDisplayJson(jsonStr);
                        LogHelper.log(MainActivity.this, "view_import", new JSONObject(jsonStr));
                    }
                } catch (Exception e) {
                    showMessage("Error loading imported JSON: " + e.getMessage());
                }
            }
        }, filter, RECEIVER_NOT_EXPORTED);

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

        // === 1. Handle incoming JSON from ImportActivity ===
        if (intent.hasExtra("WRITE_JSON_DIRECT")) {
            try {
                String jsonStr = intent.getStringExtra("WRITE_JSON_DIRECT");
                if (jsonStr != null && !jsonStr.isEmpty()) {
                    lastJson = new JSONObject(jsonStr);
                    // Direct NFC write
                    if (writeToTag(lastJson.toString())) {
                        LogHelper.log(this, "write", lastJson);
                    }
                } else {
                    showMessage("No JSON data provided.");
                }
            } catch (Exception e) {
                showMessage("Error writing JSON to tag: " + e.getMessage());
            }
            return;
        }

        // === 2. Handle JSON opened for viewing (demo import) ===
        if (handleIntentForDemo(intent)) {
            return;
        }

        // === 3. Handle NFC tag read as usual ===
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

            // Avoid logging duplicate reads (not user-visible; keep as-is)
            if (!obj.toString().equals(LogHelper.getLastLoggedRaw(this))) {
                LogHelper.log(this, "read", obj);
            }

            // Localized labels
            addLabel(getString(R.string.label_serial_number), obj.optString("sn"));
            addLabel(getString(R.string.label_first_use), formatDateTime(obj.optString("fu")));
            addLabel(getString(R.string.label_cycle_count), String.valueOf(obj.optInt("cc")));

            // Check for dark mode once
            int nightModeFlags = getResources().getConfiguration().uiMode
                    & android.content.res.Configuration.UI_MODE_NIGHT_MASK;
            boolean isDark = nightModeFlags == android.content.res.Configuration.UI_MODE_NIGHT_YES;

            // Note Type with background color (text localized via format string)
            int noteType = obj.optInt("n");
            SoundHelper.playForNoteDelayed(noteType, 50);

            TextView noteLabel = new TextView(this);
            noteLabel.setText(getString(R.string.label_note_type, noteTypeName(noteType)));
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

                addHeader(getString(R.string.header_usage_log));
                for (JSONObject entry : entries) {
                    int type = entry.optInt("d");
                    String info = getString(
                            R.string.usage_entry_format,
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
            showMessage(getString(R.string.error_invalid_json, rawJson));
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
        // === Load last selections from SharedPreferences ===
        SharedPreferences prefs = getSharedPreferences("initPrefs", MODE_PRIVATE);
        int lastMode = prefs.getInt("initMode", 0);         // 0 = Manual, 1 = BEST
        String lastTeam = prefs.getString("teamNumber", "");
        int lastType = prefs.getInt("batteryType", 0);      // 0 = New, 1 = Old, 2 = Special

        // === Build layout ===
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(40, 30, 40, 10);

        // --- Mode Selection ---
        TextView modeLabel = new TextView(this);
        modeLabel.setText("Select Mode:");
        layout.addView(modeLabel);

        Spinner modeSpinner = new Spinner(this);
        ArrayAdapter<String> modeAdapter = new ArrayAdapter<>(this,
                android.R.layout.simple_spinner_item,
                new String[]{"Manual Serial Input", "BEST Scheme"});
        modeAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        modeSpinner.setAdapter(modeAdapter);
        modeSpinner.setSelection(lastMode);
        layout.addView(modeSpinner);

        // --- Team Number ---
        TextView teamLabel = new TextView(this);
        teamLabel.setText("Team Number:");
        layout.addView(teamLabel);

        EditText teamInput = new EditText(this);
        teamInput.setHint("Enter team number (1–5 digits)");
        teamInput.setInputType(InputType.TYPE_CLASS_NUMBER);
        teamInput.setText(lastTeam);
        layout.addView(teamInput);

        // --- Battery Type ---
        TextView typeLabel = new TextView(this);
        typeLabel.setText("Battery Type:");
        layout.addView(typeLabel);

        Spinner typeSpinner = new Spinner(this);
        ArrayAdapter<String> typeAdapter = new ArrayAdapter<>(this,
                android.R.layout.simple_spinner_item,
                new String[]{"New Battery", "Old Battery", "Special Battery"});
        typeAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        typeSpinner.setAdapter(typeAdapter);
        typeSpinner.setSelection(lastType);
        layout.addView(typeSpinner);

        // --- Battery ID ---
        TextView idLabel = new TextView(this);
        idLabel.setText("Battery ID:");
        layout.addView(idLabel);

        EditText idInput = new EditText(this);
        idInput.setHint("Enter Battery ID");
        idInput.setInputType(InputType.TYPE_CLASS_NUMBER);
        layout.addView(idInput);

        // --- Manual Serial ---
        TextView manualLabel = new TextView(this);
        manualLabel.setText("Manual Serial:");
        layout.addView(manualLabel);

        EditText manualInput = new EditText(this);
        manualInput.setHint("ASCII ≤ 8 chars");
        manualInput.setInputType(InputType.TYPE_CLASS_TEXT);
        layout.addView(manualInput);

        // --- Preview ---
        TextView preview = new TextView(this);
        preview.setPadding(0, 20, 0, 10);
        preview.setTextColor(0xFF808080);
        preview.setText("Incomplete data — preview unavailable");
        layout.addView(preview);

        // === Prepare holders ===
        final String[] resultHolder = new String[1];

        // === Create dialog first ===
        AlertDialog alert = new AlertDialog.Builder(this)
                .setTitle("Initialize Battery")
                .setView(layout)
                .setPositiveButton("OK", null)
                .setNegativeButton("Cancel", null)
                .create();

        // === Update logic ===
        @SuppressLint({"SetTextI18n", "DefaultLocale"}) Runnable updatePreview = () -> {
            int mode = modeSpinner.getSelectedItemPosition();
            int type = typeSpinner.getSelectedItemPosition();
            String team = teamInput.getText().toString().trim();
            String idStr = idInput.getText().toString().trim();
            String manual = manualInput.getText().toString().trim();

            boolean isManual = (mode == 0);
            boolean isBest = (mode == 1);

            // === Control field visibility ===
            manualLabel.setVisibility(isManual ? View.VISIBLE : View.GONE);
            manualInput.setVisibility(isManual ? View.VISIBLE : View.GONE);

            teamLabel.setVisibility(isBest ? View.VISIBLE : View.GONE);
            teamInput.setVisibility(isBest ? View.VISIBLE : View.GONE);

            typeLabel.setVisibility(isBest ? View.VISIBLE : View.GONE);
            typeSpinner.setVisibility(isBest ? View.VISIBLE : View.GONE);

            boolean showId = isBest && type != 2;
            idLabel.setVisibility(showId ? View.VISIBLE : View.GONE);
            idInput.setVisibility(showId ? View.VISIBLE : View.GONE);

            // === Validation + Preview ===
            String result = null;
            boolean valid = true;

            if (mode == 0) {
                // Manual Serial Input mode
                if (manual.isEmpty() || manual.length() > 8) {
                    preview.setText("Incomplete or too long");
                    preview.setTextColor(0xFFFF0000);
                    valid = false;
                } else if (!manual.matches("\\A\\p{ASCII}+\\z")) {
                    preview.setText("Illegal input (non-ASCII)");
                    preview.setTextColor(0xFFFF0000);
                    valid = false;
                } else {
                    result = manual;
                    preview.setText("Preview: " + result);
                    preview.setTextColor(0xFF00AA00);
                }
            } else {
                // BEST Scheme mode
                if (team.isEmpty() || !team.matches("\\d{1,5}")) {
                    preview.setText("Incomplete team number");
                    preview.setTextColor(0xFFFF0000);
                    valid = false;
                } else {
                    while (team.length() < 5) team += "-";
                    int num = 0;
                    if (type != 2) {
                        if (idStr.isEmpty() || !idStr.matches("\\d+")) {
                            preview.setText("Incomplete ID");
                            preview.setTextColor(0xFFFF0000);
                            valid = false;
                        } else {
                            num = Integer.parseInt(idStr);
                        }
                    }

                    if (valid) {
                        switch (type) {
                            case 0:
                                if (num < 0 || num > 899) {
                                    preview.setText("Illegal ID (0–899)");
                                    preview.setTextColor(0xFFFF0000);
                                    valid = false;
                                } else {
                                    result = String.format("%s%03d", team, num);
                                }
                                break;
                            case 1:
                                if (num < 0 || num > 98) {
                                    preview.setText("Illegal ID (00–98)");
                                    preview.setTextColor(0xFFFF0000);
                                    valid = false;
                                } else {
                                    result = String.format("%s9%02d", team, num);
                                }
                                break;
                            case 2:
                                result = team + "999";
                                break;
                        }

                        if (valid) {
                            preview.setText("Preview: " + result);
                            preview.setTextColor(0xFF00AA00);
                        }
                    }
                }
            }

            resultHolder[0] = result;

            // Enable OK only if valid
            if (alert.isShowing()) {
                Button ok = alert.getButton(AlertDialog.BUTTON_POSITIVE);
                if (ok != null) ok.setEnabled(valid);
            }
        };

        // === Dialog event setup ===
        alert.setOnShowListener(d -> {
            Button okButton = alert.getButton(AlertDialog.BUTTON_POSITIVE);
            okButton.setEnabled(false);
            okButton.setOnClickListener(v -> {
                String sn = resultHolder[0];
                if (sn == null || sn.isEmpty()) return;
                try {
                    JSONObject json = new JSONObject();
                    json.put("sn", sn);
                    json.put("fu", currentTimestamp());
                    json.put("cc", 0);
                    json.put("n", 0);
                    json.put("u", new JSONArray());
                    lastJson = json;

                    if (writeToTag(lastJson.toString())) {
                        LogHelper.log(this, "write", lastJson);
                    }

                    prefs.edit()
                            .putInt("initMode", modeSpinner.getSelectedItemPosition())
                            .putString("teamNumber", teamInput.getText().toString().trim())
                            .putInt("batteryType", typeSpinner.getSelectedItemPosition())
                            .apply();

                    alert.dismiss();
                } catch (Exception e) {
                    showMessage("Error creating battery record.");
                }
            });

            // === Update listeners ===
            TextWatcher watcher = new SimpleTextWatcher(updatePreview);
            teamInput.addTextChangedListener(watcher);
            idInput.addTextChangedListener(watcher);
            manualInput.addTextChangedListener(watcher);
            modeSpinner.setOnItemSelectedListener(new SimpleItemListener(updatePreview));
            typeSpinner.setOnItemSelectedListener(new SimpleItemListener(updatePreview));

            updatePreview.run();
        });

        alert.show();
    }


    // === small helper classes ===
    private static class SimpleTextWatcher implements TextWatcher {
        private final Runnable callback;
        SimpleTextWatcher(Runnable cb) { this.callback = cb; }
        @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
        @Override public void onTextChanged(CharSequence s, int start, int before, int count) { callback.run(); }
        @Override public void afterTextChanged(Editable s) {}
    }

    private static class SimpleItemListener implements AdapterView.OnItemSelectedListener {
        private final Runnable callback;
        SimpleItemListener(Runnable cb) { this.callback = cb; }
        @Override public void onItemSelected(AdapterView<?> parent, View view, int pos, long id) { callback.run(); }
        @Override public void onNothingSelected(AdapterView<?> parent) {}
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
        //getWindow().getDecorView().setSystemUiVisibility(
         //       View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
         //               | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
         //               | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
         //               | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
          //              | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
          //              | View.SYSTEM_UI_FLAG_FULLSCREEN
        //);
    }

    private void exportJson() {
        if (lastJson == null) {
            showMessage("No battery data to export.");
            return;
        }

        // Get serial number field from JSON, or fallback if missing
        String serial = lastJson.optString("sn", "unknown");
        String fileName = serial + ".BEST.json";

        // Build JSON and write to cache for sharing
        File cacheFile = new File(getCacheDir(), fileName);
        try (FileWriter writer = new FileWriter(cacheFile)) {
            writer.write(lastJson.toString(2));
        } catch (IOException | JSONException e) {
            showMessage("Export failed: " + e.getMessage());
            return;
        }

        // --- Choice dialog with new Print option ---
        new AlertDialog.Builder(this)
                .setTitle("Export Battery JSON")
                .setMessage("Choose how you want to export the file:")
                .setPositiveButton("Share via apps", (dialog, which) -> shareJsonFile(cacheFile))
                .setNegativeButton("Save to Downloads", (dialog, which) -> saveToDownloads(fileName))
                .setNeutralButton("Print", (dialog, which) -> generateAndOpenPrintPage())
                .show();
    }
    private void generateAndOpenPrintPage() {
        try {
            // Convert JSON to HTML (mirrors battery_print.py structure)
            String html = BatteryReportHtmlGenerator.generateHtml(lastJson);

            // Save to a temp HTML file
            File outFile = new File(getCacheDir(), "BatteryReport_" +
                    new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(new Date()) + ".html");
            try (FileWriter writer = new FileWriter(outFile)) {
                writer.write(html);
            }

            // Open in browser
            Uri uri = FileProvider.getUriForFile(this, getPackageName() + ".provider", outFile);
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(uri, "text/html");
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            startActivity(intent);

        } catch (Exception e) {
            showMessage("Print generation failed: " + e.getMessage());
            e.printStackTrace();
        }
    }

    private void shareJsonFile(File file) {
        Uri uri = FileProvider.getUriForFile(
                this,
                getPackageName() + ".provider",
                file
        );

        Intent shareIntent = new Intent(Intent.ACTION_SEND);
        shareIntent.setType("*/*");
        shareIntent.putExtra(Intent.EXTRA_STREAM, uri);
        shareIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        startActivity(Intent.createChooser(shareIntent, "Share Battery JSON"));
    }

    private void saveToDownloads(String fileName) {
        try {
            File downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
            if (!downloads.exists()) downloads.mkdirs();

            // --- Split name and extension ---
            File outFile = new File(downloads, fileName);
            String baseName = fileName;
            String extension = "";

            int dot = fileName.lastIndexOf('.');
            if (dot > 0) {
                baseName = fileName.substring(0, dot);
                extension = fileName.substring(dot);
            }

            // --- Generate non-overwriting filename like "battery_1.BEST.json" ---
            int counter = 1;
            while (outFile.exists()) {
                String newName = baseName + "_" + counter + extension;
                outFile = new File(downloads, newName);
                counter++;
            }

            // --- Write JSON content ---
            try (FileWriter writer = new FileWriter(outFile)) {
                writer.write(lastJson.toString(2));
            }

            // --- Refresh in Files app immediately ---
            sendBroadcast(new Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE, Uri.fromFile(outFile)));

            showMessage("Saved to Downloads: " + outFile.getName());
        } catch (Exception e) {
            showMessage("Save failed: " + e.getMessage());
        }
    }




}