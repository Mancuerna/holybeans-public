package com.caffeinateddev.holybeans

import android.app.Activity
import android.content.Intent
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Local environment and a user-selected JSONL export; no Bluetooth commands. */
class BleDiagnosticBridge(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private var bytes: ByteArray? = null
    private val requestCode = 9142

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "info" -> result.success(mapOf(
                "package" to activity.packageName,
                "manufacturer" to Build.MANUFACTURER,
                "model" to Build.MODEL,
                "androidRelease" to Build.VERSION.RELEASE,
                "androidSdk" to Build.VERSION.SDK_INT,
                "androidSecurityPatch" to Build.VERSION.SECURITY_PATCH,
            ))
            "save" -> {
                if (pending != null) {
                    result.error("BUSY", "An export is already open", null)
                    return
                }
                val content = call.argument<ByteArray>("bytes")
                if (content == null || content.size > 8 * 1024 * 1024) {
                    result.error("INVALID", "Missing or oversized diagnostic file", null)
                    return
                }
                pending = result
                bytes = content
                try {
                    activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
                    }, requestCode)
                } catch (e: Exception) {
                    pending = null
                    bytes = null
                    result.error("SAVE", e.toString(), null)
                }
            }
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != requestCode) return false
        val result = pending ?: return true
        val content = bytes
        pending = null
        bytes = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || content == null) {
            result.success(false)
            return true
        }
        Thread {
            try {
                val stream = activity.contentResolver.openOutputStream(uri, "wt")
                    ?: throw IllegalStateException("Cannot open export destination")
                stream.use { it.write(content) }
                activity.runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("SAVE", e.toString(), null) }
            }
        }.start()
        return true
    }
}
