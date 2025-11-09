package com.IronMaple.batterytagreader;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.PendingIntent;
import android.content.Intent;
import android.net.Uri;
import android.nfc.NdefMessage;
import android.nfc.NdefRecord;
import android.nfc.NfcAdapter;
import android.nfc.Tag;
import android.nfc.tech.Ndef;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.view.Gravity;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.Toast;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.Charset;

public class ImportActivity extends Activity {

    private NfcAdapter nfcAdapter;
    private String loadedJson = "";
    private boolean writePending = false;
    private Button btnBackHome; // new fallback button

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        Log.d("ImportActivity", "onCreate called");

        // --- Simple layout container for fallback button ---
        FrameLayout layout = new FrameLayout(this);
        setContentView(layout);

        // --- Create hidden fallback button ---
        btnBackHome = new Button(this);
        btnBackHome.setText("Back to Home");
        btnBackHome.setVisibility(Button.GONE);
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
        );
        params.gravity = Gravity.CENTER;
        layout.addView(btnBackHome, params);

        btnBackHome.setOnClickListener(v -> {
            Intent intent = new Intent(ImportActivity.this, MainActivity.class);
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
            finish();
        });

        // --- Load JSON file from Intent ---
        try {
            Uri uri = getIntent().getData();
            if (uri != null) {
                InputStream input = getContentResolver().openInputStream(uri);
                BufferedReader reader = new BufferedReader(new InputStreamReader(input));
                StringBuilder sb = new StringBuilder();
                String line;
                while ((line = reader.readLine()) != null) sb.append(line);
                reader.close();

                loadedJson = sb.toString()
                        .replaceAll("[\\n\\r\\t]", "")
                        .replaceAll(" +", " ")
                        .trim();

                Log.d("ImportActivity", "Loaded JSON: " + loadedJson.substring(0, Math.min(80, loadedJson.length())));
            } else {
                Toast.makeText(this, "No file provided.", Toast.LENGTH_LONG).show();
                finish();
                return;
            }
        } catch (Exception e) {
            Log.e("ImportActivity", "Error reading file", e);
            Toast.makeText(this, "Error reading file: " + e.getMessage(), Toast.LENGTH_LONG).show();
            finish();
            return;
        }

        nfcAdapter = NfcAdapter.getDefaultAdapter(this);

        // --- Popup action dialog ---
        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("Import Battery JSON")
                .setMessage("Choose what to do with this file:")
                .setPositiveButton("View Content", (d, w) -> openInMain())
                .setNegativeButton("Write Tag", (d, w) -> beginWriteMode())
                .setNeutralButton("Cancel", (d, w) -> finish())
                .show();

        dialog.setCanceledOnTouchOutside(false);

        // Fallback: show "Back to Home" if dismissed unexpectedly
        dialog.setOnDismissListener(d -> {
            if (!isFinishing() && btnBackHome != null) {
                btnBackHome.setVisibility(Button.VISIBLE);
                Toast.makeText(this, "Import cancelled or no action selected.", Toast.LENGTH_SHORT).show();
            }
        });
    }

    private void beginWriteMode() {
        writePending = true;
        Toast.makeText(this, "Tap and hold tag to write...", Toast.LENGTH_LONG).show();

        if (nfcAdapter == null) {
            Toast.makeText(this, "NFC not available.", Toast.LENGTH_LONG).show();
            return;
        }

        Intent intent = new Intent(this, getClass()).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ? PendingIntent.FLAG_MUTABLE : 0
        );
        nfcAdapter.enableForegroundDispatch(this, pendingIntent, null, null);
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);

        if (!writePending) return;

        Tag tag = intent.getParcelableExtra(NfcAdapter.EXTRA_TAG);
        if (tag == null) {
            Toast.makeText(this, "No tag detected.", Toast.LENGTH_SHORT).show();
            return;
        }

        try {
            Ndef ndef = Ndef.get(tag);
            if (ndef != null && ndef.isWritable()) {
                ndef.connect();
                byte[] lang = "en".getBytes(Charset.forName("US-ASCII"));
                byte[] text = loadedJson.getBytes(Charset.forName("UTF-8"));
                byte[] payload = new byte[1 + lang.length + text.length];
                payload[0] = (byte) lang.length;
                System.arraycopy(lang, 0, payload, 1, lang.length);
                System.arraycopy(text, 0, payload, 1 + lang.length, text.length);
                NdefRecord record = new NdefRecord(
                        NdefRecord.TNF_WELL_KNOWN,
                        NdefRecord.RTD_TEXT,
                        new byte[0],
                        payload
                );
                ndef.writeNdefMessage(new NdefMessage(new NdefRecord[]{record}));
                ndef.close();

                Toast.makeText(this, "Write successful.", Toast.LENGTH_LONG).show();
                LogHelper.log(this, "import_write", new JSONObject(loadedJson));
                finish();
            } else {
                Toast.makeText(this, "Tag not writable or not NDEF.", Toast.LENGTH_SHORT).show();
            }
        } catch (Exception e) {
            Log.e("ImportActivity", "Write failed", e);
            Toast.makeText(this, "Write failed: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void openInMain() {
        try {
            Intent intent = new Intent(this, MainActivity.class);
            intent.putExtra(MainActivity.EXTRA_DEMO_JSON, loadedJson);
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            startActivity(intent);
        } catch (Exception e) {
            Log.e("ImportActivity", "Error launching MainActivity", e);
        }
        finish();
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (nfcAdapter != null) nfcAdapter.disableForegroundDispatch(this);
    }
}
