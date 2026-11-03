package com.caffeinateddev.holybeans

import android.content.Intent

/** Keeps the receiving app's navigation outside the HolyBeans task. */
object ShareTaskIntent {
    fun prepare(intent: Intent): Intent {
        if (intent.action != Intent.ACTION_CHOOSER) return intent
        @Suppress("DEPRECATION")
        val target = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return intent
        if (target.action != Intent.ACTION_SEND && target.action != Intent.ACTION_SEND_MULTIPLE) {
            return intent
        }
        // The chooser still belongs to HolyBeans and reports selection/cancellation.
        // Only its destination starts in the receiving app's task. Keep the payload,
        // temporary URI grants and chooser callback created by share_plus intact.
        return Intent(intent).apply {
            putExtra(Intent.EXTRA_INTENT, Intent(target).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}
