package com.caffeinateddev.holybeans

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

/**
 * Home screen widget with the last brew: its coffee and recipe,
 * Repeat and Brew. The app sends the text through [save] whenever it
 * changes (channel "holybeans/device", method "updateWidget"); the buttons
 * open the same `holybeans://shortcut/...` links as the launcher shortcuts.
 */
class NextBrewWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
    ) {
        render(context, manager, ids)
    }

    companion object {
        private const val PREFS = "next_brew_widget"

        /** Keeps the text and redraws every widget on the home screen. */
        fun save(context: Context, title: String?, recipe: String?) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("title", title)
                .putString("recipe", recipe)
                .apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, NextBrewWidget::class.java),
            )
            if (ids.isNotEmpty()) render(context, manager, ids)
        }

        /** Redraws every widget, after the app sends its labels. */
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, NextBrewWidget::class.java),
            )
            if (ids.isNotEmpty()) render(context, manager, ids)
        }

        private fun render(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val title = prefs.getString("title", null)
            val recipe = prefs.getString("recipe", null)
            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.next_brew_widget)
                views.setTextViewText(
                    R.id.widget_label,
                    SurfaceLabels.get(context, "widgetLabel", R.string.widget_label),
                )
                views.setTextViewText(
                    R.id.widget_title,
                    title ?: SurfaceLabels.get(context, "widgetEmpty", R.string.widget_empty),
                )
                views.setTextViewText(R.id.widget_recipe, recipe ?: "")
                views.setTextViewText(
                    R.id.widget_repeat,
                    SurfaceLabels.get(context, "shortcutRepeat", R.string.shortcut_repeat),
                )
                views.setTextViewText(
                    R.id.widget_brew,
                    SurfaceLabels.get(context, "shortcutBrew", R.string.shortcut_brew),
                )
                views.setOnClickPendingIntent(R.id.widget_repeat, link(context, "repeat", 1))
                views.setOnClickPendingIntent(R.id.widget_brew, link(context, "brew", 2))
                views.setOnClickPendingIntent(R.id.widget_root, link(context, "open", 3))
                manager.updateAppWidget(id, views)
            }
        }

        private fun link(context: Context, name: String, code: Int): PendingIntent =
            PendingIntent.getActivity(
                context,
                code,
                Intent(context, MainActivity::class.java)
                    .setAction(Intent.ACTION_VIEW)
                    .setData(Uri.parse("holybeans://shortcut/$name"))
                    .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
    }
}
