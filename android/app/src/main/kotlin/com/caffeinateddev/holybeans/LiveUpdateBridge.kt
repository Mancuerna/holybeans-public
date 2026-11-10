package com.caffeinateddev.holybeans

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The brew in progress as one ongoing notification ("holybeans/live-update").
 * On Android 16 a progress-style notification asking to be promoted to a
 * Live Update; on Android 8 through 15, an ongoing notification with a
 * chronometer and a progress bar. On Android 7 or without permission to
 * notify it does nothing.
 */
class LiveUpdateBridge(private val activity: Activity) {
    // Looked up on first use: the activity has no context yet while it is
    // being constructed, which is when this bridge is created.
    private val manager by lazy {
        activity.getSystemService(NotificationManager::class.java)
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "show" -> {
                show(call)
                result.success(null)
            }
            "clear" -> {
                manager.cancel(NOTIFICATION_ID)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun show(call: MethodCall) {
        if (Build.VERSION.SDK_INT < 26) return
        if (!allowed()) return
        ensureChannel()
        val title = call.argument<String>("title") ?: return
        val text = call.argument<String>("text") ?: ""
        val startedAt = call.argument<Number>("startedAtMs")?.toLong()
            ?: System.currentTimeMillis()
        val segments = call.argument<List<Int>>("segments") ?: emptyList()
        val progress = call.argument<Int>("progress") ?: 0
        val open = PendingIntent.getActivity(
            activity,
            0,
            Intent(activity, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = Notification.Builder(activity, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_holybeans)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_STOPWATCH)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setWhen(startedAt)
            .setShowWhen(true)
            .setUsesChronometer(true)
            // Gone by itself if the app dies before clearing it; the app
            // also clears it when it starts.
            .setTimeoutAfter(MAX_BREW_MS)
        val total = segments.sum()
        if (Build.VERSION.SDK_INT >= 36 && total > 0) {
            builder.setStyle(
                Notification.ProgressStyle()
                    .setProgressSegments(
                        segments.filter { it > 0 }.map { Notification.ProgressStyle.Segment(it) },
                    )
                    .setProgress(progress.coerceIn(0, total)),
            )
        } else if (total > 0) {
            builder.setProgress(total, progress.coerceIn(0, total), false)
        }
        // Android 16 shows it as a Live Update when the user allows it.
        builder.extras.putBoolean("android.requestPromotedOngoing", true)
        manager.notify(NOTIFICATION_ID, builder.build())
    }

    private fun allowed(): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            activity.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        // Creating it again only renames it, to the app's language; the
        // user's own settings for it stay.
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                SurfaceLabels.get(activity, "liveUpdateChannel", R.string.live_update_channel),
                NotificationManager.IMPORTANCE_LOW,
            ).apply { setShowBadge(false) },
        )
    }

    /** Renames the channel, once it exists, after the app sends its labels. */
    fun relabel() {
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(CHANNEL_ID) != null) {
            ensureChannel()
        }
    }

    companion object {
        private const val CHANNEL_ID = "brew_in_progress"
        private const val NOTIFICATION_ID = 7301

        /** Longer than any brew, cold brew aside. */
        private const val MAX_BREW_MS = 2L * 60 * 60 * 1000
    }
}
