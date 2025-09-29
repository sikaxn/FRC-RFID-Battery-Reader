package com.IronMaple.batterytagreader;

import android.content.Context;
import android.media.AudioAttributes;
import android.media.SoundPool;
import android.os.Handler;
import android.os.Looper;

public final class SoundHelper {

    private static SoundPool soundPool;
    private static boolean loaded = false;

    private static int sNormal = 0;
    private static int sPractice = 0;
    private static int sScrap = 0;
    private static int sOther = 0;

    private SoundHelper() {}

    /** Call once (e.g., MainActivity.onCreate) */
    public static void init(Context ctx) {
        if (soundPool != null) return;

        AudioAttributes attrs = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build();

        soundPool = new SoundPool.Builder()
                .setMaxStreams(2)
                .setAudioAttributes(attrs)
                .build();

        // Load your 4 chime sounds from res/raw
        sNormal   = soundPool.load(ctx, R.raw.chime_normal,   1);
        sPractice = soundPool.load(ctx, R.raw.chime_practice, 1);
        sScrap    = soundPool.load(ctx, R.raw.chime_scrap,    1);
        sOther    = soundPool.load(ctx, R.raw.chime_other,    1);

        soundPool.setOnLoadCompleteListener((sp, sampleId, status) -> {
            if (status == 0) loaded = true;
        });
    }

    /** Play immediately for a given note type */
    public static void playForNote(int noteType) {
        if (!loaded || soundPool == null) return;

        int id;
        switch (noteType) {
            case 1:  id = sPractice; break;
            case 2:  id = sScrap;    break;
            case 3:  id = sOther;    break;
            case 0:
            default: id = sNormal;   break;
        }
        soundPool.play(id, 1f, 1f, 1, 0, 1f);
    }

    /** Play after a delay (e.g., to avoid overlapping system NFC beep) */
    public static void playForNoteDelayed(int noteType, long delayMs) {
        new Handler(Looper.getMainLooper()).postDelayed(
                () -> playForNote(noteType),
                delayMs
        );
    }

    // Convenience wrappers
    public static void playNormal()   { playForNote(0); }
    public static void playPractice() { playForNote(1); }
    public static void playScrap()    { playForNote(2); }
    public static void playOther()    { playForNote(3); }

    public static void release() {
        if (soundPool != null) {
            soundPool.release();
            soundPool = null;
            loaded = false;
        }
    }
}
