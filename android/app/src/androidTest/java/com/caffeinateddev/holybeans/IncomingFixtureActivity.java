package com.caffeinateddev.holybeans;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.StrictMode;

/** Synthetic intents go only to the isolated Patrol application. */
public class IncomingFixtureActivity extends Activity {
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        Uri request = getIntent().getData();
        if ("release".equals(request.getHost())) {
            IncomingFixtureProvider.release.countDown();
        } else {
            // Exercise hostile file:// input without the sender rejecting it first.
            StrictMode.setVmPolicy(new StrictMode.VmPolicy.Builder().build());
            Intent target = new Intent(Intent.ACTION_VIEW,
                Uri.parse(request.getQueryParameter("uri")))
                .setClassName("com.caffeinateddev.holybeans.patrol",
                    "com.caffeinateddev.holybeans.MainActivity")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            startActivity(target);
        }
        finish();
    }
}
