package com.caffeinateddev.holybeans

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.Executor
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

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
    private val worker = ThreadPoolExecutor(
        1, 1, 0L, TimeUnit.MILLISECONDS, ArrayBlockingQueue(8),
        ThreadPoolExecutor.DiscardPolicy(),
    )
    private val delivery = IncomingDelivery(worker, Executor { activity.runOnUiThread(it) }) {
        channel?.invokeMethod("arrived", it)
    }
    private val cards by lazy {
        val providers = activity.packageManager.getPackageInfo(
            activity.packageName, PackageManager.GET_PROVIDERS,
        ).providers.orEmpty()
        IncomingCards(providers.flatMap { it.authority.orEmpty().split(';') }.toSet())
    }

    fun attach(channel: MethodChannel) {
        this.channel = channel
    }

    /** Keeps what the app was opened with until Flutter asks for it. */
    fun onLaunch(intent: Intent?) {
        if (intent != null) delivery.receive { read(intent) }
    }

    /** Hands what arrives while the app runs straight to Flutter. */
    fun onNewIntent(intent: Intent) {
        onLaunch(intent)
    }

    fun dispose() {
        delivery.close()
        worker.shutdownNow()
        channel = null
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "take" -> {
                result.success(delivery.take())
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
            .addOnSuccessListener { barcode -> result.success(cards.text(barcode.rawValue)) }
            .addOnCanceledListener { result.success(null) }
            .addOnFailureListener { error ->
                result.error("scan_failed", error.message, null)
            }
    }

    private fun read(intent: Intent?): String? {
        intent ?: return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.data?.let(::readUri)
            Intent.ACTION_SEND -> {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (text != null) cards.text(text) else streamOf(intent)?.let(::readUri)
            }
            else -> null
        }
    }

    @Suppress("DEPRECATION")
    private fun streamOf(intent: Intent): Uri? =
        intent.getParcelableExtra(Intent.EXTRA_STREAM)

    private fun readUri(uri: Uri): String? = cards.read(uri.scheme, uri.authority, uri.toString()) {
        activity.contentResolver.openInputStream(uri)
    }
}
