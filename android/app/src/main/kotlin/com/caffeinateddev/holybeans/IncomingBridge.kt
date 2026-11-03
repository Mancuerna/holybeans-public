package com.caffeinateddev.holybeans

import android.app.Activity
import android.content.Intent
import android.net.Uri
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Coffee cards that reach the app from outside, for the "holybeans/incoming"
 * channel: a `.holybeans` file opened from a chat or the files app, text
 * shared to HolyBeans (an AI's answer, say) and `holybeans://bean` links
 * from QR codes. Only reads what the user opened or shared; nothing is
 * fetched. Also scans a QR code with Google's scanner, which needs no
 * camera permission because Play services shows its own camera screen.
 */
class IncomingBridge(private val activity: Activity) {
    private var channel: MethodChannel? = null
    private var pending: String? = null

    fun attach(channel: MethodChannel) {
        this.channel = channel
    }

    /** Keeps what the app was opened with until Flutter asks for it. */
    fun onLaunch(intent: Intent?) {
        pending = read(intent)
    }

    /** Hands what arrives while the app runs straight to Flutter. */
    fun onNewIntent(intent: Intent) {
        val text = read(intent) ?: return
        channel?.invokeMethod("arrived", text) ?: run { pending = text }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "take" -> {
                result.success(pending)
                pending = null
            }
            "scan" -> scan(result)
            else -> result.notImplemented()
        }
    }

    private fun scan(result: MethodChannel.Result) {
        val options = GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build()
        GmsBarcodeScanning.getClient(activity, options)
            .startScan()
            .addOnSuccessListener { barcode -> result.success(barcode.rawValue) }
            .addOnCanceledListener { result.success(null) }
            .addOnFailureListener { error ->
                result.error("scan_failed", error.message, null)
            }
    }

    private fun read(intent: Intent?): String? {
        intent ?: return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.data?.let(::readUri)
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
                ?: streamOf(intent)?.let(::readUri)
            else -> null
        }
    }

    @Suppress("DEPRECATION")
    private fun streamOf(intent: Intent): Uri? =
        intent.getParcelableExtra(Intent.EXTRA_STREAM)

    private fun readUri(uri: Uri): String? = when (uri.scheme) {
        "holybeans" -> uri.toString()
        "content", "file" -> try {
            activity.contentResolver.openInputStream(uri)?.use { stream ->
                // A card is a few kilobytes; anything far bigger is not one.
                val out = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                var tooBig = false
                while (true) {
                    val count = stream.read(buffer)
                    if (count < 0) break
                    out.write(buffer, 0, count)
                    if (out.size() > MAX_BYTES) {
                        tooBig = true
                        break
                    }
                }
                if (tooBig) null else out.toString(Charsets.UTF_8.name())
            }
        } catch (_: Exception) {
            null
        }
        else -> null
    }

    private companion object {
        const val MAX_BYTES = 1024 * 1024
    }
}
