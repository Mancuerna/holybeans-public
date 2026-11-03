package com.caffeinateddev.holybeans

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** AES-GCM device credential, excluded from both Android and journal backups. */
class LoffeeKeyBridge(private val context: Context) {
    // Activity fields are created before Android attaches its base context.
    private val file by lazy { AtomicFile(File(context.noBackupFilesDir, "loffee-key.enc")) }
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val alias = "holybeans.loffee.key.v1"

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        executor.execute {
            try {
                val value = when (call.method) {
                    "read" -> read()
                    "save" -> {
                        val text = (call.arguments as? String)?.trim()
                            ?: throw IllegalArgumentException()
                        require(text.isNotEmpty() && text.length <= 512 && !text.contains('\n'))
                        save(text)
                        null
                    }
                    "delete" -> {
                        file.delete()
                        val store = store()
                        if (store.containsAlias(alias)) store.deleteEntry(alias)
                        null
                    }
                    else -> {
                        main.post { result.notImplemented() }
                        return@execute
                    }
                }
                main.post { result.success(value) }
            } catch (_: Exception) {
                // Never expose an exception's text, arguments or credential.
                main.post { result.error("credential_unavailable", "Could not access credential", null) }
            }
        }
    }

    private fun store() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun key(): SecretKey {
        val stored = store().getKey(alias, null) as? SecretKey
        if (stored != null) return stored
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build())
            generateKey()
        }
    }

    private fun read(): String? {
        if (!file.baseFile.exists()) return null
        val bytes = file.readFully()
        require(bytes.size > 28)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        return cipher.doFinal(bytes.copyOfRange(12, bytes.size)).toString(Charsets.UTF_8)
    }

    private fun save(value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val bytes = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val stream = file.startWrite()
        try {
            stream.write(bytes)
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
    }

    fun dispose() { executor.shutdown() }
}
