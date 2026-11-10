package com.caffeinateddev.holybeans

import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.ToneGenerator
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the app and answers the "holybeans/device" channel: short beeps for
 * the pour assistant and keeping the screen on while it runs. Daily copies to
 * a chosen folder go through [BackupFolderBridge], reading another app's
 * export folder through [ExportFolderBridge], coffee cards opened,
 * shared or scanned into the app through [IncomingBridge], and the brew in
 * progress as an ongoing notification through [LiveUpdateBridge].
 */
class MainActivity : FlutterActivity() {
    private var tones: ToneGenerator? = null
    private var faaah: MediaPlayer? = null
    private val backupFolder = BackupFolderBridge(this)
    private val exportFolder = ExportFolderBridge(this)
    private val incoming = IncomingBridge(this)
    private val bleDiagnostics = BleDiagnosticBridge(this)
    private val loffeeKey = LoffeeKeyBridge(this)
    private val liveUpdate = LiveUpdateBridge(this)
    private val driveSync = DriveSyncBridge(this)
    private val shareClipboard = ShareClipboardBridge(this)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A restored activity already handed its launch card over.
        if (savedInstanceState == null) incoming.onLaunch(intent)
        AppShortcuts.publish(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        incoming.onNewIntent(intent)
    }

    override fun startActivityForResult(intent: Intent, requestCode: Int, options: Bundle?) {
        super.startActivityForResult(ShareTaskIntent.prepare(intent), requestCode, options)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "holybeans/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "beep" -> {
                        val long = call.argument<Boolean>("long") ?: false
                        val generator = tones
                            ?: ToneGenerator(AudioManager.STREAM_NOTIFICATION, 90)
                                .also { tones = it }
                        generator.startTone(
                            ToneGenerator.TONE_PROP_BEEP,
                            if (long) 600 else 150,
                        )
                        result.success(null)
                    }
                    "faaah" -> {
                        playFaaah()
                        result.success(null)
                    }
                    "keepScreenOn" -> {
                        if (call.argument<Boolean>("on") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "setSurfaceLabels" -> {
                        (call.arguments as? Map<*, *>)?.let { SurfaceLabels.save(this, it) }
                        AppShortcuts.publish(this)
                        NextBrewWidget.refresh(this)
                        liveUpdate.relabel()
                        result.success(null)
                    }
                    "updateWidget" -> {
                        NextBrewWidget.save(
                            this,
                            call.argument<String>("title"),
                            call.argument<String>("recipe"),
                        )
                        result.success(null)
                    }
                    "appVersion" -> {
                        // Read only: the installed version, for Settings.
                        val info = packageManager.getPackageInfo(packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            info.longVersionCode
                        } else {
                            @Suppress("DEPRECATION")
                            info.versionCode.toLong()
                        }
                        result.success("${info.versionName} ($code)")
                    }
                    "openBluetoothSettings" -> {
                        // Only opens the phone's own Bluetooth screen; the
                        // user turns it on there.
                        try {
                            startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                            result.success(true)
                        } catch (error: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "holybeans/backups")
            .setMethodCallHandler(backupFolder::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "holybeans/import-folder")
            .setMethodCallHandler(exportFolder::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "holybeans/incoming")
            .also(incoming::attach)
            .setMethodCallHandler(incoming::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "holybeans/ble-diagnostics")
            .setMethodCallHandler(bleDiagnostics::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "holybeans/live-update")
            .setMethodCallHandler(liveUpdate::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "holybeans/loffee-key")
            .setMethodCallHandler(loffeeKey::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "holybeans/drive-sync")
            .setMethodCallHandler(driveSync::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "holybeans/share-clipboard")
            .setMethodCallHandler(shareClipboard::handle)
    }

    /**
     * Brazil's easter egg; quiet when the phone is on silent or vibrate (and
     * with Do Not Disturb, which Samsung reports as not ringing).
     */
    private fun playFaaah() {
        val audio = getSystemService(AUDIO_SERVICE) as AudioManager
        if (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
        faaah?.release()
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        faaah = MediaPlayer.create(
            this,
            R.raw.brazil_faaah,
            attributes,
            audio.generateAudioSessionId(),
        )?.apply {
            setOnCompletionListener { player ->
                player.release()
                if (faaah === player) faaah = null
            }
            start()
        }
    }

    @Deprecated("Needed by the storage access framework folder picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!driveSync.onActivityResult(requestCode, resultCode, data) &&
            !bleDiagnostics.onActivityResult(requestCode, resultCode, data) &&
            !backupFolder.onActivityResult(requestCode, resultCode, data) &&
            !exportFolder.onActivityResult(requestCode, resultCode, data)
        ) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        tones?.release()
        tones = null
        faaah?.release()
        faaah = null
        backupFolder.dispose()
        exportFolder.dispose()
        loffeeKey.dispose()
        driveSync.dispose()
        shareClipboard.dispose()
        incoming.dispose()
        super.onDestroy()
    }
}
