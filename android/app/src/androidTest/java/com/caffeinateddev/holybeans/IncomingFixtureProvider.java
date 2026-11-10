package com.caffeinateddev.holybeans;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/** Read-only synthetic content; the slow read is released by the test UI. */
public class IncomingFixtureProvider extends ContentProvider {
    static final CountDownLatch release = new CountDownLatch(1);
    @Override public boolean onCreate() { return true; }
    @Override public String getType(Uri uri) { return "application/json"; }
    @Override public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if (!"r".equals(mode)) throw new FileNotFoundException("Read only");
        try {
            if ("/slow".equals(uri.getPath())) release.await(15, TimeUnit.SECONDS);
            File file = new File(getContext().getCacheDir(), "incoming-fixture.json");
            try (FileOutputStream out = new FileOutputStream(file)) {
                out.write("{\"name\":\"External\"}".getBytes(StandardCharsets.UTF_8));
            }
            return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
        } catch (Exception error) {
            throw new FileNotFoundException(error.toString());
        }
    }
    @Override public Cursor query(Uri u, String[] p, String s, String[] a, String o) { return null; }
    @Override public Uri insert(Uri u, ContentValues v) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri u, ContentValues v, String s, String[] a) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri u, String s, String[] a) { throw new UnsupportedOperationException(); }
}
