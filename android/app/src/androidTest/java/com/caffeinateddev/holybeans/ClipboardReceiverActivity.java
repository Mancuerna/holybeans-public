package com.caffeinateddev.holybeans;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.io.InputStream;

/** Separate test-APK UID: exercises Android's clipboard URI read grants. */
public class ClipboardReceiverActivity extends Activity {
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(24, 24, 24, 24);
        layout.setGravity(Gravity.CENTER_VERTICAL);
        TextView status = new TextView(this);
        status.setText("Clipboard receiver ready");
        Button paste = new Button(this);
        paste.setAllCaps(false);
        paste.setText("Paste test clipboard");
        paste.setOnClickListener(view -> {
            try {
                ClipboardManager manager = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
                ClipData clip = manager.getPrimaryClip();
                if (clip == null || clip.getItemCount() != 1) throw new IllegalStateException();
                ClipData.Item item = clip.getItemAt(0);
                if (clip.getDescription().hasMimeType("image/png")) {
                    if (item.getUri() == null || !"content".equals(item.getUri().getScheme())) {
                        throw new IllegalStateException();
                    }
                    try (InputStream input = getContentResolver().openInputStream(item.getUri())) {
                        Bitmap bitmap = BitmapFactory.decodeStream(input);
                        if (bitmap == null || bitmap.getWidth() < 100 || bitmap.getHeight() < 100) {
                            throw new IllegalStateException();
                        }
                        boolean alpha = Color.alpha(bitmap.getPixel(0, 0)) == 0;
                        status.setText(alpha ? "Clipboard PNG readable with transparency" : "Clipboard PNG readable");
                        bitmap.recycle();
                    }
                } else {
                    status.setText("Clipboard text: " + item.getText());
                }
            } catch (Exception error) {
                status.setText("Clipboard read failed: " + error.getClass().getSimpleName());
            }
        });
        layout.addView(paste);
        layout.addView(status);
        setContentView(layout);
    }
}
