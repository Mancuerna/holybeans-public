package com.caffeinateddev.holybeans;

import android.content.ClipData;
import android.content.Intent;
import android.net.Uri;
import org.junit.Test;
import static org.junit.Assert.*;

public class ShareTaskIntentTest {
    @Test public void shareDestinationChangesTaskWithoutLosingPayloadOrGrants() {
        for (String action : new String[]{Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE}) {
            Uri uri = Uri.parse("content://test/image.png");
            Intent target = new Intent(action).setType("image/png")
                .putExtra(Intent.EXTRA_TEXT, "Caption")
                .putExtra(Intent.EXTRA_STREAM, uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            target.setClipData(ClipData.newRawUri("image", uri));
            Intent chooser = Intent.createChooser(target, "Share");
            Intent prepared = ShareTaskIntent.INSTANCE.prepare(chooser);
            Intent sent = prepared.getParcelableExtra(Intent.EXTRA_INTENT);
            assertNotSame(chooser, prepared);
            assertNotSame(target, sent);
            assertEquals(0, target.getFlags() & Intent.FLAG_ACTIVITY_NEW_TASK);
            assertEquals(Intent.FLAG_ACTIVITY_NEW_TASK, sent.getFlags() & Intent.FLAG_ACTIVITY_NEW_TASK);
            assertEquals(target.getFlags() | Intent.FLAG_ACTIVITY_NEW_TASK, sent.getFlags());
            assertEquals("Caption", sent.getStringExtra(Intent.EXTRA_TEXT));
            assertEquals(uri, sent.getParcelableExtra(Intent.EXTRA_STREAM));
            assertEquals(uri, sent.getClipData().getItemAt(0).getUri());
            assertEquals("Share", prepared.getCharSequenceExtra(Intent.EXTRA_TITLE));
            assertEquals(chooser.getFlags(), prepared.getFlags());
        }
    }
    @Test public void documentAndPhotoPickersAreUnchanged() {
        Intent document = new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("application/zip");
        assertSame(document, ShareTaskIntent.INSTANCE.prepare(document));
        Intent chooser = Intent.createChooser(document, "Restore");
        assertSame(chooser, ShareTaskIntent.INSTANCE.prepare(chooser));
        Intent empty = new Intent(Intent.ACTION_CHOOSER);
        assertSame(empty, ShareTaskIntent.INSTANCE.prepare(empty));
    }
}
