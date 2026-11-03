package com.caffeinateddev.holybeans

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Answers the "holybeans/backups" channel: picking a folder with the storage
 * access framework, keeping access to it, and saving daily copies there.
 * Only files named like a daily copy are ever replaced or deleted.
 */
class BackupFolderBridge(private val activity: Activity) {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null
    private val resolver get() = activity.contentResolver

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pick" -> pick(result)
            "isAvailable" -> background(result) { isAvailable(tree(call)) }
            "release" -> background(result) {
                val uri = tree(call)
                if (resolver.persistedUriPermissions.any { it.uri == uri }) {
                    resolver.releasePersistableUriPermission(uri, ACCESS)
                }
                null
            }
            "list" -> background(result) { children(tree(call)).map { it.second } }
            "write" -> background(result) {
                write(tree(call), dailyName(call.argument("name")), call.argument<String>("path")!!)
                null
            }
            "delete" -> background(result) {
                val uri = tree(call)
                val names = call.argument<List<String>>("names")!!.map(::dailyName).toSet()
                for ((id, name) in children(uri)) {
                    if (name in names) {
                        DocumentsContract.deleteDocument(
                            resolver,
                            DocumentsContract.buildDocumentUriUsingTree(uri, id),
                        )
                    }
                }
                null
            }
            else -> result.notImplemented()
        }
    }

    /** True when the result belonged to the folder picker. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_FOLDER) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        try {
            resolver.takePersistableUriPermission(uri, ACCESS)
            result.success(mapOf("uri" to uri.toString(), "name" to displayName(uri)))
        } catch (error: Exception) {
            result.error("denied", error.message, null)
        }
        return true
    }

    fun dispose() {
        io.shutdown()
    }

    private fun pick(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "A folder is already being picked", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            ACCESS or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
        )
        try {
            pendingPick = result
            activity.startActivityForResult(intent, PICK_FOLDER)
        } catch (error: ActivityNotFoundException) {
            pendingPick = null
            result.error("unavailable", error.message, null)
        }
    }

    private fun isAvailable(tree: Uri): Boolean {
        if (resolver.persistedUriPermissions.none { it.uri == tree && it.isWritePermission }) {
            return false
        }
        return try {
            resolver.query(folder(tree), arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)
                ?.use { it.moveToFirst() } ?: false
        } catch (error: Exception) {
            false
        }
    }

    /** Keeps the previous daily document until the new one is read back intact. */
    private fun write(tree: Uri, name: String, path: String) {
        val source = File(path)
        val expected = source.inputStream().use { digest(it) }
        val dayPrefix = name.removeSuffix(".zip")
        val previous = children(tree).filter { (_, existing) ->
            DAILY_COPY.matches(existing) &&
                (existing == name || existing.startsWith("$dayPrefix-"))
        }.map { (id, _) -> DocumentsContract.buildDocumentUriUsingTree(tree, id).toString() }
        val documents = object : BackupDocumentWriter.Documents {
            override fun create(name: String): String =
                (DocumentsContract.createDocument(resolver, folder(tree), "application/zip", name)
                    ?: error("Could not create the copy")).toString()

            override fun copy(id: String) = this@BackupFolderBridge.copy(source, Uri.parse(id))

            override fun verify(id: String) {
                val actual = (resolver.openInputStream(Uri.parse(id))
                    ?: error("Could not verify the copy")).use { digest(it) }
                check(expected.contentEquals(actual)) { "Backup verification failed" }
            }

            override fun rename(id: String, name: String): String? = try {
                DocumentsContract.renameDocument(resolver, Uri.parse(id), name)?.toString()
            } catch (_: UnsupportedOperationException) {
                null
            }

            override fun delete(id: String) {
                check(DocumentsContract.deleteDocument(resolver, Uri.parse(id))) {
                    "Could not remove the old copy"
                }
            }

            override fun cleanupFailed(error: Exception) {
                Log.w("HolyBeans", "Backup cleanup deferred", error)
            }
        }
        BackupDocumentWriter(documents).write(
            name, UUID.randomUUID().toString().replace("-", ""), previous,
        )
    }

    private fun digest(input: java.io.InputStream): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            digest.update(buffer, 0, count)
        }
        return digest.digest()
    }

    private fun copy(source: File, target: Uri) {
        val output = resolver.openOutputStream(target, "w") ?: error("Could not open the copy")
        output.use { out -> source.inputStream().use { it.copyTo(out) } }
    }

    /** Document ID and display name of every file directly in the folder. */
    private fun children(tree: Uri): List<Pair<String, String>> {
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        )
        val found = mutableListOf<Pair<String, String>>()
        resolver.query(uri, columns, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                found += cursor.getString(0) to (cursor.getString(1) ?: "")
            }
        }
        return found
    }

    private fun displayName(tree: Uri): String = try {
        resolver.query(
            folder(tree), arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null,
        )?.use { if (it.moveToFirst()) it.getString(0) else null } ?: ""
    } catch (error: Exception) {
        ""
    }

    private fun folder(tree: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))

    private fun tree(call: MethodCall): Uri = Uri.parse(call.argument<String>("uri")!!)

    private fun dailyName(name: String?): String {
        require(name != null && DAILY_COPY.matches(name)) { "Not a daily copy: $name" }
        return name
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (error: Exception) {
                main.post { result.error("failed", error.message, null) }
            }
        }
    }

    companion object {
        private const val PICK_FOLDER = 4107
        private const val ACCESS =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        private val DAILY_COPY = Regex("""^holybeans-backup-\d{4}-\d{2}-\d{2}(?:-[0-9a-f]{32})?\.zip$""")
    }
}
