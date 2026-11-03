package com.caffeinateddev.holybeans

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class ShareClipboardBridge(private val context: Context) {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "copyImage") {
            result.notImplemented()
            return
        }
        val bytes = call.arguments as? ByteArray
        if (bytes == null) {
            result.error("clipboard_failed", "Could not copy image", null)
            return
        }
        executor.execute {
            var file: File? = null
            try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                require(bounds.outMimeType == "image/png" && bounds.outWidth > 0 && bounds.outHeight > 0)
                val directory = File(context.cacheDir, "clipboard-images")
                check(directory.isDirectory || directory.mkdirs())
                // Keep recent URIs valid for receiving apps and clipboard history.
                val cutoff = System.currentTimeMillis() - TimeUnit.DAYS.toMillis(7)
                directory.listFiles()?.filter { it.isFile && it.lastModified() < cutoff }
                    ?.forEach { it.delete() }
                val image = File.createTempFile("brew-", ".png", directory)
                file = image
                image.writeBytes(bytes)
                val uri = FileProvider.getUriForFile(context, "${context.packageName}.clipboard", image)
                main.post {
                    try {
                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        clipboard.setPrimaryClip(ClipData.newUri(context.contentResolver, "HolyBeans", uri))
                        result.success(null)
                    } catch (_: Exception) {
                        image.delete()
                        result.error("clipboard_failed", "Could not copy image", null)
                    }
                }
            } catch (_: Exception) {
                file?.delete()
                main.post { result.error("clipboard_failed", "Could not copy image", null) }
            }
        }
    }

    fun dispose() {
        executor.shutdown()
    }
}

class ClipboardImageProvider : FileProvider()
