package com.caffeinateddev.holybeans;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.widget.TextView;
import java.io.InputStream;

/** Local-only receiver in the test APK: never sends or persists shared content. */
public class ShareReceiverActivity extends Activity {
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        String message = isTaskRoot() ? "Separate share task" : "Inside source task";
        message += "\n" + getIntent().getType();
        CharSequence text = getIntent().getCharSequenceExtra(Intent.EXTRA_TEXT);
        if (text != null && text.length() > 0) message += "\nText received";
        @SuppressWarnings("deprecation")
        Uri uri = getIntent().getParcelableExtra(Intent.EXTRA_STREAM);
        if (uri != null) {
            try (InputStream input = getContentResolver().openInputStream(uri)) {
                if (input.read(new byte[64]) > 0) message += "\nImage readable";
            } catch (Exception error) {
                message += "\nUnreadable image";
            }
        }
        android.widget.LinearLayout layout = new android.widget.LinearLayout(this);
        layout.setOrientation(android.widget.LinearLayout.VERTICAL);
        layout.setPadding(32, 100, 32, 32);
        for (String line : message.split("\n")) {
            TextView view = new TextView(this);
            view.setText(line);
            view.setTextSize(22);
            layout.addView(view);
        }
        setContentView(layout);
    }
}
