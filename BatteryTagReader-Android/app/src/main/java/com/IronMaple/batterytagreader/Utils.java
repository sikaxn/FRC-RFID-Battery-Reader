package com.IronMaple.batterytagreader;

import android.content.Context;
import android.net.Uri;
import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;

public class Utils {
    public static String readTextFromUri(Context context, Uri uri) throws Exception {
        StringBuilder sb = new StringBuilder();
        try (InputStream input = context.getContentResolver().openInputStream(uri);
             BufferedReader reader = new BufferedReader(new InputStreamReader(input))) {
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line);
            }
        }
        return sb.toString();
    }
}
