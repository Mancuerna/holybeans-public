package com.caffeinateddev.holybeans

import android.app.Activity
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build

/**
 * The shortcuts a long press on the app icon offers: a new brew, the last
 * brew again and a coffee card from a QR code. Each opens the app with a
 * `holybeans://shortcut/<name>` link that [IncomingBridge] hands to Flutter.
 * Published at runtime so the intent targets whichever package this build
 * is (the Patrol and diagnostics builds have their own), and again when
 * the app sends its labels ([SurfaceLabels]).
 */
object AppShortcuts {
    fun publish(activity: Activity) {
        if (Build.VERSION.SDK_INT < 25) return
        val manager = activity.getSystemService(ShortcutManager::class.java) ?: return
        fun shortcut(id: String, link: String, label: String, long: String, icon: Int) =
            ShortcutInfo.Builder(activity, id)
                .setShortLabel(label)
                .setLongLabel(long)
                .setIcon(Icon.createWithResource(activity, icon))
                .setIntent(
                    Intent(activity, MainActivity::class.java)
                        .setAction(Intent.ACTION_VIEW)
                        .setData(Uri.parse("holybeans://shortcut/$link")),
                )
                .build()
        try {
            manager.dynamicShortcuts = listOf(
                shortcut(
                    "brew",
                    "brew",
                    SurfaceLabels.get(activity, "shortcutBrew", R.string.shortcut_brew),
                    SurfaceLabels.get(activity, "shortcutBrewLong", R.string.shortcut_brew_long),
                    R.drawable.ic_shortcut_brew,
                ),
                shortcut(
                    "repeat",
                    "repeat",
                    SurfaceLabels.get(activity, "shortcutRepeat", R.string.shortcut_repeat),
                    SurfaceLabels.get(activity, "shortcutRepeatLong", R.string.shortcut_repeat_long),
                    R.drawable.ic_shortcut_repeat,
                ),
                shortcut(
                    "scan-bean",
                    "scan-bean",
                    SurfaceLabels.get(activity, "shortcutScan", R.string.shortcut_scan),
                    SurfaceLabels.get(activity, "shortcutScanLong", R.string.shortcut_scan_long),
                    R.drawable.ic_shortcut_scan,
                ),
            )
        } catch (_: Exception) {
            // A launcher that refuses shortcuts must not stop the app.
        }
    }
}
