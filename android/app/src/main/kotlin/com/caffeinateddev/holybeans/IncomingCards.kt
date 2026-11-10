package com.caffeinateddev.holybeans

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.concurrent.Executor

internal class IncomingCards(private val ownAuthorities: Set<String>) {
    fun text(value: String?): String? {
        value ?: return null
        if (value.length > MAX_BYTES) return null
        val limit = if (value.trimStart().startsWith("holybeans:", ignoreCase = true)) 8192 else MAX_BYTES
        return value.takeIf { it.length <= limit && it.toByteArray(Charsets.UTF_8).size <= limit }
    }

    fun read(scheme: String?, authority: String?, uri: String, open: () -> InputStream?): String? = try {
        when {
            scheme.equals("holybeans", ignoreCase = true) -> text(uri)
            scheme.equals("content", ignoreCase = true) && !authority.isNullOrEmpty() &&
                ownAuthorities.none { it.equals(authority.substringAfterLast('@'), ignoreCase = true) } ->
                open()?.use { stream ->
                    val out = ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val count = stream.read(buffer)
                        if (count < 0) break
                        if (out.size() + count > MAX_BYTES) return@use null
                        out.write(buffer, 0, count)
                    }
                    text(out.toString(Charsets.UTF_8.name()))
                }
            else -> null
        }
    } catch (_: Exception) { null }

    private companion object { const val MAX_BYTES = 1024 * 1024 }
}

/** All delivery state belongs to the UI thread; only reading runs on the worker. */
internal class IncomingDelivery(
    private val worker: Executor,
    private val ui: Executor,
    private val arrived: (String) -> Unit,
) {
    private var ready = false
    private var closed = false
    private var pending: String? = null
    fun receive(read: () -> String?) {
        if (closed) return
        worker.execute {
            val text = try { read() } catch (_: Exception) { null }
            ui.execute {
                if (!closed && text != null) {
                    if (ready) arrived(text) else pending = text
                }
            }
        }
    }
    fun take(): String? {
        ready = true
        return pending.also { pending = null }
    }
    fun close() { closed = true; pending = null }
}
