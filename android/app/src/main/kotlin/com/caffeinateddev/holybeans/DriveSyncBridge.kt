package com.caffeinateddev.holybeans

import android.app.Activity
import android.content.Intent
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.ClearTokenRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executors
import javax.net.ssl.HttpsURLConnection

/** Keeps OAuth credentials native and ephemeral. No generic host proxy, deletes,
 * token logging, redirects, or token persistence. Every request binds its account.
 */
class DriveSyncBridge(private val activity: Activity) {
    private companion object {
        const val REQUEST = 7020
        const val MAX_BYTES = 64 * 1024 * 1024
        val executor = Executors.newSingleThreadExecutor()
    }
    private var token: String? = null
    private var account: String? = null
    private var active: MethodChannel.Result? = null
    private var generation = 0L
    private var disposed = false

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) { result.error("cancelled", null, null); return }
        if (call.method == "cancel") {
            generation++
            token = null
            account = null
            fail("cancelled")
            result.success(null)
            return
        }
        if (active != null) { result.error("busy", null, null); return }
        when (call.method) {
            "package" -> result.success(activity.packageName)
            "connect" -> {
                active = result
                token = null
                account = null
                val operation = ++generation
                authorize(call.argument<Boolean>("interactive") == true, operation)
            }
            "disconnect" -> { token = null; account = null; result.success(null) }
            "request" -> {
                val credential = token
                if (credential == null || account != call.argument<String>("account")) {
                    result.error("not_connected", null, null); return
                }
                val url = call.argument<String>("url") ?: ""
                val method = call.argument<String>("method") ?: "GET"
                val body = call.argument<ByteArray>("body")
                val type = call.argument<String>("contentType") ?: "application/json"
                active = result
                executor.execute {
                    try {
                        val response = request(credential, url, method, body, type)
                        activity.runOnUiThread { finish(response) }
                    } catch (_: Exception) {
                        activity.runOnUiThread { fail("network") }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun authorize(interactive: Boolean, operation: Long) {
        val request = AuthorizationRequest.builder().setRequestedScopes(
            listOf(Scope("https://www.googleapis.com/auth/drive.appdata"))).build()
        Identity.getAuthorizationClient(activity).authorize(request)
            .addOnSuccessListener { result ->
                if (disposed || operation != generation) return@addOnSuccessListener
                if (result.hasResolution()) {
                    if (!interactive) { fail("authorization_required"); return@addOnSuccessListener }
                    try {
                        activity.startIntentSenderForResult(result.pendingIntent!!.intentSender,
                            REQUEST, null, 0, 0, 0)
                    } catch (_: Exception) { fail("authorization_failed") }
                } else authorized(result.accessToken, operation)
            }.addOnFailureListener {
                if (operation == generation) fail("authorization_failed")
            }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) return false
        if (active == null) return true
        if (resultCode != Activity.RESULT_OK) { fail("cancelled"); return true }
        val operation = generation
        try {
            authorized(Identity.getAuthorizationClient(activity)
                .getAuthorizationResultFromIntent(data).accessToken, operation)
        } catch (_: Exception) { fail("authorization_failed") }
        return true
    }

    private fun authorized(credential: String?, operation: Long) {
        if (disposed || operation != generation) return
        if (credential.isNullOrBlank()) { fail("authorization_failed"); return }
        executor.execute {
            try {
                val response = request(credential,
                    "https://www.googleapis.com/drive/v3/about?fields=user(permissionId)", "GET", null,
                    "application/json")
                check(response["status"] == 200)
                val id = JSONObject(String(response["body"] as ByteArray, Charsets.UTF_8))
                    .getJSONObject("user").getString("permissionId")
                check(id.isNotBlank())
                val key = MessageDigest.getInstance("SHA-256")
                    .digest(id.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
                activity.runOnUiThread {
                    if (!disposed && operation == generation) {
                        token = credential
                        account = key
                        finish(key)
                    }
                }
            } catch (_: Exception) {
                activity.runOnUiThread {
                    if (operation == generation) fail("authorization_failed")
                }
            }
        }
    }

    private fun request(credential: String, address: String, method: String,
                        body: ByteArray?, contentType: String): Map<String, Any?> {
        val url = URL(address)
        require(url.protocol == "https" && url.host == "www.googleapis.com" &&
            url.port == -1 && url.userInfo == null && url.ref == null &&
            (url.path.startsWith("/drive/v3/") || url.path.startsWith("/upload/drive/v3/")))
        require(method in setOf("GET", "POST", "PUT", "DELETE"))
        require(body == null || body.size <= MAX_BYTES)
        require(!contentType.contains('\r') && !contentType.contains('\n'))
        val connection = url.openConnection() as HttpsURLConnection
        try {
            connection.requestMethod = method
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 20000
            connection.readTimeout = 60000
            connection.setRequestProperty("Authorization", "Bearer $credential")
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", contentType)
                connection.setFixedLengthStreamingMode(body.size)
                connection.outputStream.use { it.write(body) }
            }
            val status = connection.responseCode
            val output = ByteArrayOutputStream()
            val input = if (status in 200..299) connection.inputStream else connection.errorStream
            input?.use {
                val buffer = ByteArray(32768)
                while (true) {
                    val count = it.read(buffer)
                    if (count < 0) break
                    check(output.size() + count <= MAX_BYTES)
                    output.write(buffer, 0, count)
                }
            }
            if (status == 401) activity.runOnUiThread {
                token = null; account = null
                Identity.getAuthorizationClient(activity).clearToken(
                    ClearTokenRequest.builder().setToken(credential).build())
            }
            return mapOf("status" to status, "body" to output.toByteArray(),
                "location" to connection.getHeaderField("Location"))
        } finally { connection.disconnect() }
    }

    private fun finish(value: Any?) { active?.success(value); active = null }
    private fun fail(code: String) { active?.error(code, null, null); active = null }
    fun dispose() { disposed = true; token = null; account = null; fail("cancelled") }
}
