package com.caffeinateddev.holybeans

import android.content.Context

/**
 * Labels of what HolyBeans shows outside its own screens (launcher
 * shortcuts, home screen widget, the channel of the ongoing notice) in the
 * language chosen in the app, which may differ from the phone's. Flutter
 * sends them (channel "holybeans/device", method "setSurfaceLabels");
 * until it does, the Android resources in the phone's language stand in.
 */
object SurfaceLabels {
    private const val PREFS = "surface_labels"

    /** The labels the app understands, kept until the next ones. */
    private val keys = setOf(
        "shortcutBrew",
        "shortcutBrewLong",
        "shortcutRepeat",
        "shortcutRepeatLong",
        "shortcutScan",
        "shortcutScanLong",
        "widgetLabel",
        "widgetEmpty",
        "liveUpdateChannel",
    )

    fun save(context: Context, labels: Map<*, *>) {
        val editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        for ((key, value) in labels) {
            if (key is String && key in keys && value is String && value.isNotBlank()) {
                editor.putString(key, value)
            }
        }
        editor.apply()
    }

    /** The label for [key], or the resource [fallback] when none was sent. */
    fun get(context: Context, key: String, fallback: Int): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(key, null)
            ?: context.getString(fallback)
}
